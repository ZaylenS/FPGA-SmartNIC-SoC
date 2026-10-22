# Batch 3 — ARM CPU Integration Walkthrough

> **Updated 2026-07-14:** Stale walkthrough content was reconciled with the current RTL implementation by Codex (GPT-5).

**Files covered:** `IF_stage.v` (modified) → `data_mem.v` (modified) → `processor.v` (modified) → `lab8_wrapper.v` (CPU additions) → hardware bugs and fixes

This batch integrates the Lab 6 ARM CPU into the Lab 8 wrapper so the CPU can directly read and modify packet data in the FIFO BRAM. The CPU accesses BRAM through its MEM stage — no PCI round-trip needed.

> **Document history.** Captured 2026-03-25 against the Lab 8 baseline (commit `44baf38`). **Reconciled 2026-07-14 against the current checkpoint RTL in `src/arm/` and `src/lab8_wrapper.v`.**
>
> Current RTL status:
> - The CPU integration is a **3-way** address-space split.
> - `data_mem.v` routes `0x00..0x7F` to internal DMEM, `0x80..0xEF` to the FIFO BRAM `ext_mem_*` port, and `0xF0..0xFF` to the wrapper `reg_alias_*` port.
> - `processor.v` passes the register-alias bundle through to `lab8_wrapper.v`, which exposes DMA/GPU/FIFO control and status slots.
> - CPU writes into FIFO BRAM use `ctrl=0xFF` at FIFO index 0 and `ctrl=0x00` elsewhere.
>

---

## 1. The Integration Problem

The ARM CPU from Lab 6 has a 64-bit DMEM (256×64, dual-port). Packets live in the FIFO BRAM (256×72, dual-port). We need the CPU to read/write FIFO BRAM as if it were memory, while keeping its own DMEM for local variables and stack.

**Solution: 3-window address-space split.** The CPU's 8-bit memory address decoder uses the high address bits to select:
```
0x00..0x7F  ->  Internal DMEM - local variables, stack
0x80..0xEF  ->  FIFO BRAM indices 0x00..0x6F - packet data
0xF0..0xFF  ->  Wrapper register aliases 0x0..0xF - orchestration controls/status
```

This means:
- `LDR r2, [r1, #1]` with `r1 = 0x80` reads FIFO BRAM address 1 -- the first data word of the buffered packet.
- `STR r3, [r1, #1]` writes back to FIFO BRAM address 1.


---

## 2. IF_stage.v — Per-Thread PC Confinement

### 2.1 Threading Model

The ARM uses **fine-grained 4-thread barrel multithreading**. Each cycle, a different thread fetches. Thread scheduling is round-robin: T0, T1, T2, T3, T0, T1, ...

```verilog
module IF_stage(
    input         clk,
    input         rst,
    // Port B: PCI register interface (host loads program)
    input         intf_wen_imem,
    input  [8:0]  intf_addr_imem,   // 9-bit = 512 words total
    input  [31:0] intf_data_imem,
    output [31:0] intf_dout_imem,
    // CPU datapath output
    output [31:0] data_out,          // Fetched instruction
    output reg [10:0] pc_plus4_out,  // Next PC (used for branch-target computation)
    output reg [1:0]  thread_id_out, // Which thread owns this instruction
    output reg [4:0]  pc_idx_out,    // Low 5 instruction-index bits (for LA trace)
    // Thread control
    input  [1:0]  thread_id,         // Current cycle's thread from global counter
    // Branch control (from ID stage)
    input         ctrl_branch,
    input  [63:0] branch_addr,
    input  [1:0]  branch_thread_id,
    // Halt flags (H1 fix: gate PC advance per-thread)
    input  [3:0]  halted
);
```

### 2.2 Per-Thread PCs

```verilog
    reg [10:0] pc [0:3];             // 4 independent PCs, 11 bits each
```

Each PC is 11 bits: `{thread_id[1:0], offset[8:0]}`. The upper 2 bits select the thread's IMEM region, and the lower 9 bits are the byte offset within that region.

```verilog
    wire [10:0] current_pc   = pc[thread_id];           // PC of the fetching thread
    wire [8:0]  current_off  = current_pc[8:0];         // Byte offset within region
    wire [8:0]  next_off     = current_off + 9'd4;      // +4 bytes = next instruction
    wire [10:0] next_pc_seq  = {thread_id, next_off};   // Force region base bits
```

**Region confinement:** `next_pc_seq` always has `thread_id` as the upper 2 bits. The 9-bit offset wraps within 512 bytes (128 words). This prevents one thread from accidentally fetching another thread's code.

```
IMEM layout (512 words, 32-bit each):
  Thread 0: IMEM[  0..127]   PC region 0x000–0x1FF
  Thread 1: IMEM[128..255]   PC region 0x200–0x3FF
  Thread 2: IMEM[256..383]   PC region 0x400–0x5FF
  Thread 3: IMEM[384..511]   PC region 0x600–0x7FF
```

### 2.3 PC Update

```verilog
    always @(posedge clk) begin
        if (rst) begin
            pc[0] <= 11'h000;   // Thread 0 starts at word 0
            pc[1] <= 11'h200;   // Thread 1 starts at word 128
            pc[2] <= 11'h400;   // Thread 2 starts at word 256
            pc[3] <= 11'h600;   // Thread 3 starts at word 384
            pc_plus4_out  <= 11'd0;
            thread_id_out <= 2'd0;
            pc_idx_out    <= 5'd0;
        end else begin
            // Sequential advance — only if thread is not halted (H1 fix)
            if (!halted[thread_id])
                pc[thread_id] <= next_pc_seq;

            // Branch override — from ID stage, targets specific thread
            if (ctrl_branch)
                pc[branch_thread_id] <= next_pc_br;

            // Pipeline metadata (1 cycle behind fetch)
            pc_plus4_out  <= next_pc_seq;
            thread_id_out <= thread_id;
            pc_idx_out    <= current_pc[6:2];  // Low 5 word-index bits (modulo 32)
        end
    end
```

**H1 fix (PC halt gating):** `halted[thread_id]` now gates sequential PC advance. Because the PC advanced when HALT was fetched and the flag is set later in ID, the frozen address is a post-HALT slot, not the HALT itself. IMEM has no read enable and the round-robin slot continues, so that frozen instruction can be fetched and executed repeatedly. The slot must be a harmless NOP, repeated HALT, or self-branch; H1 removes the need to fill the entire remaining region but not the need for one safe post-HALT instruction.

**Historical note (Bug #3):** In the original Batch 3 code, the PC advanced unconditionally (`pc[thread_id] <= next_pc_seq` with no halted check). After HALT, the PC would wrap around the 128-word IMEM region and re-execute the program. Filling all unused IMEM with `B .` (`0xEAFFFFFE`) prevented that wraparound. With H1, one safe post-HALT slot is sufficient; larger existing padding remains harmless.

### 2.4 IMEM Instantiation

```verilog
    inst_mem m_imem (
        .clk   (clk),
        .addra (current_pc[10:2]),  // Word index: drop 2 LSBs (byte→word)
        .dina  (32'd0),             // Port A never writes
        .wea   (1'b0),
        .douta (data_out),          // Fetched instruction → pipeline
        .addrb (intf_addr_imem),    // Port B: PCI writes program
        .dinb  (intf_data_imem),
        .web   (intf_wen_imem),
        .doutb (intf_dout_imem)     // Port B: PCI reads back for verification
    );
```

True dual-port: Port A fetches instructions (every cycle), Port B loads the program from PCI (before execution).

---

## 3. data_mem.v — Three Memory Windows on One Port

This is the key modification that enables CPU-to-FIFO BRAM communication.

### 3.1 Original Design (Lab 6)

Lab 6's `data_mem` had a simple 256×64 BRAM accessed by the CPU's MEM stage (Port A) and PCI debug (Port B). All 256 addresses were internal DMEM.

### 3.2 Current Checkpoint (3 windows)

The current checkpoint keeps the original `addr[7]` internal/external split, then carves `0xF0..0xFF` out of the upper half for wrapper register aliases. Addresses `0x80..0xEF` reach FIFO BRAM; addresses `0xF0..0xFF` do not.

### 3.3 Current Design

There are three windows:

| Window | CPU address | Routed to | Read latency | Notes |
|--------|-------------|-----------|--------------|-------|
| 1 (Internal DMEM) | `0x00..0x7F` | this module's `mem[]` array | 1 cycle (sync BRAM) | Local variables, stack |
| 2 (External FIFO BRAM) | `0x80..0xEF` | `ext_mem_*` port -> wrapper proc-port mux | 1 cycle (sync BRAM) | FIFO indices `0x00..0x6F` |
| 3 (Register aliases) | `0xF0..0xFF` | `reg_alias_*` port -> wrapper register mux/decode | 1 cycle (captured mux readback) | DMA/GPU/FIFO orchestration |

Module interface:

```verilog
module data_mem(
    input         clk,
    input         reset,           // Explicit reset for delayed read-path state

    // Port A: CPU datapath (one port, three windows)
    input  [63:0] addr,
    input  [63:0] dina,
    input         WMemEn,
    output reg [63:0] douta,
    output reg [63:0] skip_mem,

    // MEM/WB pipeline register (control signals)
    input         i_WRegEn,
    input  [3:0]  i_WReg1,
    input         i_ctrl_mem2reg,
    output reg    o_MRegEn,
    output reg [3:0] o_WReg1,
    output reg    o_ctrl_mem2reg,
    input  [1:0]  i_thread_id,
    output reg [1:0] o_thread_id,
    input  [4:0]  i_pc_idx,
    output reg [4:0] o_pc_idx,

    // Port B: host access to the local 256-word DMEM array
    input         web,
    input  [63:0] dinb,
    input  [7:0]  addrb,
    output reg [63:0] doutb,

    // Window 2: External FIFO BRAM
    output [7:0]  ext_mem_addr,
    output [63:0] ext_mem_din,
    output        ext_mem_we,
    input  [63:0] ext_mem_dout,

    // Window 3: Wrapper register aliases
    output [3:0]  reg_alias_sel,
    output [63:0] reg_alias_wdata,
    output        reg_alias_we,
    input  [63:0] reg_alias_rdata
);
```

### 3.4 Address Decode

```verilog
    wire [7:0] addra = addr[7:0];

    // 0xF0-0xFF carves a register window out of the former FIFO window
    wire addr_is_reg = (addra[7:4] == 4'hF);
    wire addr_is_ext = addra[7] & ~addr_is_reg;
```

Reading the three cases:

1. If `addra[7:4]==4'hF` (`0xF0..0xFF`) -> register alias. `addr_is_reg=1` and `addr_is_ext=0`.
2. Else if `addra[7]=1` (`0x80..0xEF`) -> FIFO BRAM. `addr_is_ext=1`.
3. Otherwise (`0x00..0x7F`) -> internal DMEM. The always-on DMEM read is the default at the output mux (see §3.7).

Only the upper nibble and high bit participate in target selection; there is no full 8-bit equality decoder for every address.

### 3.5 Per-Window Output Drivers

```verilog
    // Window 2: FIFO BRAM port
    assign ext_mem_addr = {1'b0, addra[6:0]};      // CPU 0x80 -> FIFO 0x00, ...
    assign ext_mem_din  = dina;
    assign ext_mem_we   = WMemEn & addr_is_ext;    // Write only when in this window

    // Window 3: wrapper register aliases
    assign reg_alias_sel   = addra[3:0];
    assign reg_alias_wdata = dina;
    assign reg_alias_we    = WMemEn & addr_is_reg;
```

**Slicing strategy:** FIFO gets `addra[6:0]`, so CPU address `0x80` maps to FIFO index 0 and `0xEF` maps to FIFO index `0x6F`. The alias window uses `addra[3:0]` as its slot selector. The two write strobes are separately gated, so one store cannot target FIFO BRAM and a wrapper register simultaneously.

### 3.6 Read-Latency Alignment -- `was_ext` and `was_reg`

```verilog
    reg was_ext;
    reg was_reg;
    always @(posedge clk) begin
        if (reset) begin
            was_ext <= 1'b0;
            was_reg <= 1'b0;
        end else begin
            was_ext <= addr_is_ext;
            was_reg <= addr_is_reg;
        end
    end

    reg [63:0] reg_alias_rdata_r;
    always @(posedge clk) begin
        if (reset) reg_alias_rdata_r <= 64'd0;
        else       reg_alias_rdata_r <= reg_alias_rdata;
    end
```

**Why the delayed selects exist:** Internal DMEM and FIFO BRAM have 1-cycle synchronous reads. The decode happens in cycle N, and the corresponding result is selected in cycle N+1, so `was_ext` and `was_reg` retain the access type. Wrapper alias readback is combinational, so `reg_alias_rdata_r` captures the selected slot on the same edge; otherwise the next instruction's alias selector could change the value before writeback.

**Reset behavior:** `was_ext`, `was_reg`, and `reg_alias_rdata_r` are explicitly cleared. This prevents the first MEM-stage result from selecting stale external or alias data.

### 3.7 Internal DMEM -- Always-Read, Gated-Write

```verilog
    reg [63:0] mem [0:255];                                // 256 x 64-bit (logical)
    reg [63:0] dmem_rd;

    // Port A: CPU writes ONLY land in window 1 (0x00..0x7F).
    always @(posedge clk) begin
        if (WMemEn && !addr_is_ext && !addr_is_reg)
            mem[addra] <= dina;
        dmem_rd <= mem[addra];                              // Always read
    end
```

DMEM is **always read** -- the synchronous BRAM read pattern requires this for XST to infer block RAM. The output mux discards `dmem_rd` when the access was actually to a different window.

**Write gating:** An internal store requires `WMemEn` with neither external decode asserted. FIFO stores use `ext_mem_we`; register stores use `reg_alias_we`; exactly one target accepts any valid store.

Port B always accesses the local DMEM array, independently of the CPU Port A window mux:

```verilog
    always @(posedge clk) begin
        if (web)
            mem[addrb] <= dinb;
        doutb <= mem[addrb];
    end
```

### 3.8 Output MUX (3:1)

```verilog
    always @(*) douta = was_reg ? reg_alias_rdata_r
                      : (was_ext ? ext_mem_dout : dmem_rd);
```

A priority 3:1 mux selects registered alias readback, FIFO BRAM data, or local DMEM data. The delayed access-type bits align the selection with the corresponding one-cycle result.

This `douta` feeds directly into the WB stage's memory/ALU mux.

---

## 4. processor.v — Top-Level Pipeline + External/alias Ports

### 4.1 Thread Counter

```verilog
reg [1:0] thread_id;

always @(posedge clk) begin
    if (rst)
        thread_id <= 2'd0;
    else if (start_stop)              // ONLY advances when running
        thread_id <= thread_id + 2'd1;
end
```

The HDL array is 256 words, and Port B can read/write all entries `0x00..0xFF`. CPU Port A instead interprets `0x80..0xEF` as FIFO BRAM and `0xF0..0xFF` as wrapper aliases; the corresponding upper-half local entries are distinct storage hidden from the CPU path.

**Bug #1 root cause:** When `rst=0` and `start_stop=0`, the thread counter freezes at 0 but the pipeline keeps executing. Thread 0 is then issued every cycle, violating the four-cycle FGMT spacing on which the no-forwarding design depends; this is not a valid "4× speed" mode and can produce hazards or unintended execution. The recorded host procedure avoids this state by atomically transitioning from reset to running.

### 4.2 Halt Detection

```verilog
reg [3:0] halted;
assign all_halted = &halted;           // AND-reduce: 1 only when ALL threads halted
wire halt_detected;                     // From ID stage: current instruction is HALT

always @(posedge clk) begin
    if (rst)
        halted <= 4'b0000;
    else if (halt_detected)
        halted[id_thread_id] <= 1'b1;  // Set flag for the halting thread
end
```

`halted` is a 4-bit vector, one flag per thread. Each flag is set when that thread's HALT instruction reaches the ID stage. `all_halted` goes HIGH when all four sticky flags have been set. With H1, `halted` gates only sequential PC advancement; it does not disable IMEM reads or the thread's pipeline slot, so a safe frozen post-HALT instruction remains required.

### 4.3 Pipeline Stages

The full pipeline: IF → ID → EX → MEM → WB. With 4-thread interleaving, same-thread instructions are always 4 cycles apart, so no data hazards or branch flush needed (unlike the GPU's single-thread pipeline).

```
Cycle:  0    1    2    3    4    5    6    7    8
IF:     T0   T1   T2   T3   T0   T1   T2   T3   T0
ID:          T0   T1   T2   T3   T0   T1   T2   T3
EX:               T0   T1   T2   T3   T0   T1   T2
MEM:                    T0   T1   T2   T3   T0   T1
WB:                          T0   T1   T2   T3   T0
```

Thread 0's next instruction enters IF at cycle 4, when the previous instruction is in MEM. By the time the new instruction reaches EX (cycle 6), the old one has completed WB (cycle 4). No conflict.

### 4.4 External Memory and Alias Port Pass-Through

```verilog
data_mem u_mem(
    // Port A: CPU datapath
    .addr(mem_alu_result),        // ALU result = memory address
    .dina(mem_write_data),         // Store data from register file
    .WMemEn(mem_WMemEn),           // Store enable from pipeline
    .douta(mem_data_out),          // Load data → WB stage
    // ...

    // Window 2: External FIFO BRAM
    .ext_mem_addr(ext_mem_addr),   // → lab8_wrapper → fifo_proc_addr
    .ext_mem_din(ext_mem_din),     // → lab8_wrapper → fifo_proc_din[63:0]
    .ext_mem_we(ext_mem_we),       // → lab8_wrapper → fifo_proc_we
    .ext_mem_dout(ext_mem_dout),   // ← lab8_wrapper ← fifo_proc_dout[63:0]
    // Window 3: wrapper register aliases
    .reg_alias_sel(reg_alias_sel),
    .reg_alias_wdata(reg_alias_wdata),
    .reg_alias_we(reg_alias_we),
    .reg_alias_rdata(reg_alias_rdata)
);
```

Both bundles flow straight through `processor.v`: `ext_mem_*` connects packet memory to the FIFO proc-port mux, while `reg_alias_*` connects CPU addresses `0xF0..0xFF` to the wrapper register read/write logic.

### 4.5 Logic Analyzer

```verilog
localparam LA_AW = 11;                 // 2^11 = 2048 trace entries

reg [LA_AW-1:0] la_wr_ptr;            // Write pointer (circular buffer)
wire la_event = wb_wen | mem_WMemEn | mem_RMemEn;  // Any visible event
wire la_we    = start_stop & la_event; // Only record when CPU is running
```

Records a trace entry whenever the CPU does something visible: register writeback (`wb_wen`), memory store (`mem_WMemEn`), or memory load (`mem_RMemEn`). The trace captures both MEM and WB stage signals simultaneously, since they're from DIFFERENT threads (4 cycles apart).

```verilog
wire [63:0] la_din = {
    3'b0,                    // [63:61] reserved
    mem_thread_id,           // [60:59] which thread is in MEM
    MEM_pc_idx,              // [58:54] MEM instruction index
    wb_thread_id,            // [53:52] which thread is in WB
    WB_pc_idx,               // [51:47] WB instruction index
    mem_WMemEn,              // [46]    is MEM doing a store?
    mem_RMemEn,              // [45]    is MEM doing a load?
    wb_wen,                  // [44]    is WB writing a register?
    wb_waddr,                // [43:40] WB destination register
    mem_alu_result[7:0],     // [39:32] MEM address (low byte)
    mem_write_data[15:0],    // [31:16] MEM store data (low 16 bits)
    wb_data[15:0]            // [15:0]  WB data (low 16 bits)
};
```

This format was critical for debugging. From a single LA entry, you can determine:
- Which thread is doing what in MEM and WB
- Whether loads/stores are happening
- Memory addresses and data values (low bits)
- Which register is being written and with what value

---

## 5. lab8_wrapper.v — CPU Wiring (Batch 3 additions, current checkpoint)

### 5.1 CPU Instantiation

```verilog
processor u_cpu (
    .clk            (clk),
    .rst            (cpu_reset),          // reset | reg_cpu_ctrl[1]
    .start_stop     (cpu_running),        // reg_cpu_ctrl[0]
    // IMEM Port B (PCI loads program)
    .intf_wen_imem  (cpu_imem_wen),       // From CPU_IMEM_CMD[0]
    .intf_addr_imem (cpu_imem_addr),      // From CPU_IMEM_ADDR[8:0]
    .intf_data_imem (cpu_imem_wdata),     // From CPU_IMEM_WDATA
    .intf_dout_imem (cpu_imem_rdata),     // → CPU_IMEM_RDATA
    // DMEM Port B (PCI debug access)
    .web            (cpu_dmem_wen),
    .dinb           (cpu_dmem_wdata),
    .addrb          (cpu_dmem_addr),
    .doutb          (cpu_dmem_rdata),
    // External memory port (FIFO BRAM, window 2 of the CPU's DMEM space)
    .ext_mem_addr   (cpu_ext_mem_addr),   // → proc port MUX → FIFO BRAM
    .ext_mem_din    (cpu_ext_mem_din),     // → proc port MUX → FIFO BRAM
    .ext_mem_we     (cpu_ext_mem_we),      // → proc port MUX → FIFO BRAM
    .ext_mem_dout   (cpu_ext_mem_dout),    // ← proc port MUX ← FIFO BRAM
    // Register aliases (window 3 of the CPU's DMEM space)
    .reg_alias_sel  (cpu_reg_sel),
    .reg_alias_wdata(cpu_reg_wdata),
    .reg_alias_we   (cpu_reg_we),
    .reg_alias_rdata(cpu_reg_rdata),
    // Logic Analyzer
    .la_rd_addr     (cpu_la_addr),
    .la_rd_data     (cpu_la_data),
    // Debug
    .dbg_cpsr_0     (cpu_cpsr_0),         // → CPU_STATUS[15:12]
    .all_halted     (cpu_all_halted)       // → CPU_STATUS[31]
);
```

The ARM CPU modifies buffered packet data through `ext_mem_*` and can orchestrate DMA, GPU, FIFO mode/reset/drain, and status polling through the alias bundle. The PCI register ring remains available and takes priority over a coincident ARM alias write. The exact alias slot map is in `walkthrough_batch2_wrapper.md §2.11`.

### 5.2 CPU Read Path (FIFO BRAM → CPU)

```verilog
assign cpu_ext_mem_dout = fifo_proc_dout[63:0];
```

The FIFO BRAM outputs 72 bits (`{ctrl[7:0], data[63:0]}`). CPU loads see only the 64-bit data; the ctrl byte is not readable through this path. On stores, the wrapper reconstructs the ctrl value from the FIFO index as described next.

### 5.3 CPU Write Path (CPU → FIFO BRAM)

In the proc port MUX, a named ctrl-byte helper preserves the NF2.1 header marker when firmware rewrites FIFO index 0:
```verilog
if (cpu_ext_mem_addr[6:0] == 7'h00)
    arm_bram_wctrl = 8'hFF;
else
    arm_bram_wctrl = 8'h00;

fifo_proc_din = {arm_bram_wctrl, cpu_ext_mem_din};
```

The FIFO stores 72-bit words = `{ctrl, data}`. ARM stores to FIFO index 0 write `ctrl=0xFF`; stores to every other accessible FIFO index write `ctrl=0x00`. This supports on-chip response-header rewriting but does not preserve arbitrary pre-existing ctrl values. PCI writes remain able to choose an arbitrary ctrl byte through `BRAM_WCTRL`.

See `walkthrough_batch2_wrapper.md §2.4` for the broader proc-port mux (CPU vs DMA vs PCI).

### 5.4 CPU_STATUS Register

```verilog
wire [31:0] reg_cpu_status = {
   cpu_all_halted,    // [31]    1 = all 4 threads have hit HALT
   3'd0,              // [30:28] reserved
   cpu_cpsr_3,        // [27:24] thread 3 flags {N,Z,C,V}
   cpu_cpsr_2,        // [23:20] thread 2 flags
   cpu_cpsr_1,        // [19:16] thread 1 flags
   cpu_cpsr_0,        // [15:12] thread 0 flags
   cpu_thread_id,     // [11:10] current thread being fetched
   6'd0,              // [9:4]   reserved
   2'd0,              // [3:2]   reserved
   cpu_running,       // [1]     start_stop status
   ~cpu_reset         // [0]     1 = not in reset
};
```

The host polls `CPU_STATUS[31]` (all_halted) to know when the program is done. The CPSR fields are useful for debugging conditional execution.

---

## 6. Hardware Bugs and Fixes

### Bug #1: Pipeline Runs Wild (start_stop=0, rst=0)

**Symptom:** After `cpu_load_imem`, BRAM[1] had wrong value.

**Historical root cause:** the thread counter advanced only when `start_stop=1`:
```verilog
else if (start_stop)
    thread_id <= thread_id + 2'd1;
```
The counter only advances when `start_stop=1`. The historical IF path advanced the selected PC whenever reset was inactive:
```verilog
pc[thread_id] <= next_pc_seq;  // runs whenever !rst
```
With `rst=0, start_stop=0`, the thread counter was frozen at 0 while T0's PC advanced every cycle. That collapsed the intended four-thread spacing and allowed unintended, hazard-prone execution before the host was ready. Current `IF_stage.v` additionally gates advancement with `!halted[thread_id]`, but it still does not make this paused state safe for an active, non-halted thread.

**Fix (lab8reg):** Never allow `rst=0, start_stop=0`:
```
cpu_load_imem:  CPU_CTRL=0x2 → load IMEM → keep CPU_CTRL=0x2 (in reset)
cpu_start:      CPU_CTRL=0x1 (release reset + start atomically)
cpu_stop:       CPU_CTRL=0x2 (re-assert reset, not 0x0)
```

### Bug #2: FIFO Port A Race (Network Corruption)

**Symptom:** BRAM[1] read as 0xe65e instead of 0x1000.

**Root cause:** Old `convertible_fifo.v`:
```verilog
assign in_rdy = (state == S_IDLE || state == S_RECEIVING) && !pkt_stored;
```
Missing `mode == 0` check. During 30-second IMEM loading, FIFO is in IDLE with `in_rdy=1`. Network broadcast packets arrive on Port A and overwrite BRAM via Port A while CPU will later read via Port B.

**Fix (RTL, subsequently synthesized and hardware-tested as recorded in Batch 5):**
```verilog
assign in_rdy = (mode == 2'd0) && (state == S_IDLE || ...) && !pkt_stored;
```

**Fix (SW workaround):** Reorder: load IMEM first (slow), then write BRAM + start CPU immediately (fast, minimal window for corruption).

### Bug #3: PC Wrap (Program Loops) -- NOW FIXED IN RTL (H1)

**Symptom:** BRAM[1] accumulated +42 per iteration instead of one-shot +42.

**Original root cause:** `IF_stage.v` -- PC advanced unconditionally. `halted` flag did NOT stop IF. After HALT at IMEM[4], PC continued through IMEM[5..127], then wrapped to IMEM[0] and re-executed.

**RTL fix (H1):** `IF_stage.v` now gates PC advance with `!halted[thread_id]`. This prevents eventual wrap and program re-entry. `all_halted` asserts when all four sticky HALT flags have been set; the recorded hardware status test no longer timed out. The fix does not flush or disable the frozen thread slot.

**Original program workaround (`test_4t_v2.hex`):** HALT at position 4 plus `B .` (self-branch `0xEAFFFFFE`) at positions 5-127. Full-region padding is no longer necessary, but the first post-HALT slot must remain safe because it is the address that freezes.

---

## 7. End-to-End Data Flow: CPU Modifies a Packet Word

```
1. Network packet arrives → FIFO captures it (Port A writes to BRAM)
   BRAM[0] = {0xFF, header}   BRAM[1] = {0x00, data_word_1}   ...

2. Host sets mode=CPU via PCI → Port B switches to proc port
   FIFO in_rdy drops (mode≠0), no more network input accepted

3. Host starts CPU → CPU_CTRL=0x1 (rst=0, start_stop=1)
   Thread counter starts: T0, T1, T2, T3, T0, ...
   cpu_drives_proc = (mode==1) && cpu_running = 1

4. CPU Thread 0 executes:
   MOV r1, #128              → r1 = 0x80
   LDR r2, [r1, #1]          → addr = 129 = 0x81
                                addr[7]=1 → external
                                ext_mem_addr = 0x01 → FIFO BRAM[1]
                                r2 = BRAM[1].data[63:0]
   ADD r2, r2, #42           → r2 = r2 + 42
   STR r2, [r1, #1]          → ext_mem_we=1, ext_mem_addr=0x01
                                BRAM[1].data = r2 (ctrl stays 0x00)
   HALT                      → halted[0] = 1
   B .                       → safe frozen post-HALT slot for Thread 0

5. Host reads CPU_STATUS[31] = 1 (all_halted)
   Host stops CPU → CPU_CTRL=0x2

6. Host sets mode=FIFO, triggers drain → FIFO reads BRAM[0..N] via Port B.
   This is the intended downstream path, but current drain prefetch is not safe if
   `out_rdy` stalls mid-packet; recorded Lab 8 evidence verified the modified BRAM
   contents, not successful wire-side response delivery.
```

---

## 8. Test Program (test_4t_v2.hex)

The following listing is present as `programs/arm/test_4t_v2.hex` in the current checkpoint; its 512 lines match the four 128-word thread regions summarized below.

```
IMEM layout (512 lines):
  Thread 0 region (lines 0–127):
    [0] E3A01080  MOV r1, #128       ; FIFO base address
    [1] E5912001  LDR r2, [r1, #1]   ; load packet word 1
    [2] E282202A  ADD r2, r2, #42    ; modify it
    [3] E5812001  STR r2, [r1, #1]   ; store back
    [4] FFFFFFFF  HALT               ; signal completion
    [5] EAFFFFFE  B .                ; trap PC (prevent re-execution)
    [6..127] EAFFFFFE               ; safety: all self-branch

  Thread 1 region (lines 128–255):
    [128] FFFFFFFF  HALT             ; immediately halt
    [129] EAFFFFFE  B .              ; trap PC
    [130..255] EAFFFFFE

  Thread 2 region (lines 256–383): same as Thread 1
  Thread 3 region (lines 384–511): same as Thread 1
```

**Verified result on hardware:** BRAM[1] = 0x0000102A (0x1000 + 42).

---

## Summary — What Batch 3 Establishes

1. **data_mem.v three-window decode** -- `0x00..0x7F` selects internal DMEM, `0x80..0xEF` selects FIFO BRAM, and `0xF0..0xFF` selects wrapper aliases; delayed selects align all three read paths
2. **processor.v pass-through** -- both `ext_mem_*` and `reg_alias_*` signals flow from data_mem through processor to `lab8_wrapper`; `halted` is wired to IF_stage (H1 fix)
3. **lab8_wrapper.v CPU integration** -- `cpu_drives_proc = (mode==1) && cpu_running` selects CPU vs PCI; width adaptation handles 64-bit<->72-bit, and ARM stores use `ctrl=0xFF` at FIFO index 0
4. **IF_stage.v confinement + halt gating** -- per-thread PCs wrap within 128-word regions; H1 prevents post-HALT wrap/re-entry, while one safe frozen post-HALT slot remains necessary
5. **ID.v conditional execution** -- `cond_pass` gates all write enables (C1 fix), not just branches; see the Lab 6 ARM walkthrough for the decoder details
6. **Three hardware bugs found** -- Bug #1 (SW fix: atomic start), Bug #2 (RTL fix: in_rdy mode gating), Bug #3 (RTL fix: H1 PC halt gating)
7. **Register control** -- host PCI can access the full map, while ARM addresses `0xF0..0xFA` expose the DMA/GPU/FIFO controls and status needed for on-chip orchestration

**Next batch:** GPU integration (Batch 4) — DMA copy between GPU DMEM and FIFO BRAM, tensor operation on packet data
