# ARM CPU Walkthrough -- 5-Stage Quad-Thread Pipeline

> **Updated 2026-07-14:** Stale walkthrough content was reconciled with the current RTL implementation by Codex (GPT-5).

Reviewed and updated where necessary on 2026-07-11 by GPT-5.6 Sol Ultra.

**Files covered:** `processor.v` -> `IF_stage.v` -> `inst_mem.v` -> `ifid_reg.v` -> `ID.v` -> `idex_reg.v` -> `EX.v` -> `alu64.v` -> `addsub64.v` -> `logic64.v` -> `exmem_reg.v` -> `data_mem.v` -> `memwb_reg.v` -> `logic_analyzer.v`

This walkthrough covers the ARM-compatible CPU used in Lab 8. The CPU is a 5-stage pipelined processor with Fine-Grained Multithreading (FGMT) -- 4 hardware threads share the pipeline, eliminating data hazards and branch penalties. Each thread has its own PC, register set, and CPSR flags. The CPU accesses local DMEM, FIFO BRAM, and wrapper control-register aliases through a MEM-stage address-space split.

> **Document history.** Originally captured 2026-03-25 against the Lab 8 baseline RTL (commit `44baf38`). **Audited 2026-07-14 against the current checkpoint RTL in `src/arm/` and its ARM-facing integration in `src/lab8_wrapper.v`.**
>
> The current checkpoint includes the ARM register-alias/orchestrator port set. In addition to IMEM Port B, internal DMEM Port B, the FIFO-BRAM `ext_mem_*` port, logic-analyzer readback, and debug/status ports, `processor.v` exposes `reg_alias_*` signals. `data_mem.v` has three MEM-stage address windows: `0x00..0x7F` is internal DMEM, `0x80..0xEF` maps to FIFO BRAM, and `0xF0..0xFF` maps to wrapper control-register aliases.
>
> Sections 1.1, 1.5, and 12 were revised in this audit to match the current RTL. Sections 2-11 and 13-14 remain aligned with the Lab 8 CPU baseline and the H1/H2/C1 fixes captured in [docs/lab8_integration/walkthrough_batch3_cpu_integration.md](../lab8_integration/walkthrough_batch3_cpu_integration.md).
>
> **How to read this walkthrough.** Assume you have never seen this CPU before. Each module section starts with a short *purpose* line, lists the ports, then walks the logic. Where the implementation collapses into a familiar pattern (mux, decoder, counter), the text calls that out so you can recognise the shape rather than re-deriving it from the cases.

---

## Architecture Overview

### Pipeline Stages

The 5 stages are the classic ARM pipeline:

```
IF  ->  ID  ->  EX  ->  MEM  ->  WB
```

| Stage | Module(s)         | Function |
|-------|-------------------|----------|
| IF    | IF_stage, inst_mem | Fetch instruction from IMEM, advance PC |
| ID    | ID                | Decode instruction, read register file, evaluate condition, generate control signals |
| EX    | EX_stage, alu64   | Barrel shift, ALU operation, flag generation |
| MEM   | data_mem          | Load/store to DMEM, external FIFO BRAM, or wrapper register aliases |
| WB    | WB (memwb_reg.v)  | Select ALU result or memory data, write back to register file |

### Fine-Grained Multithreading (FGMT)

Instead of forwarding and stall logic, this CPU uses 4 hardware threads scheduled round-robin. Each thread occupies a different pipeline stage each cycle:

```
Cycle:  0    1    2    3    4    5    6    7    8
IF:     T0   T1   T2   T3   T0   T1   T2   T3   T0
ID:          T0   T1   T2   T3   T0   T1   T2   T3
EX:               T0   T1   T2   T3   T0   T1   T2
MEM:                    T0   T1   T2   T3   T0   T1
WB:                          T0   T1   T2   T3   T0
```

Thread 0's second instruction enters IF at cycle 4 -- by then, its first instruction is completing MEM, so WB writes back before the second instruction needs to read in ID (cycle 5). This guarantees no RAW hazards between same-thread instructions.

### Why FGMT?

**Eliminates three major hazards at zero cost:**
- **Data hazards** -- same-thread instructions are 4 stages apart, so writeback always completes before the next read.
- **Branch penalties** -- a branch resolved in ID (cycle N) redirects that thread's PC for cycle N+4. No bubble, no flush.
- **Pipeline stalls** -- no forwarding MUXes or hazard detection needed, saving both area and timing.

The tradeoff is throughput: each thread runs at 1/4 clock rate. But for our packet-processing use case, single-thread IPC is not critical -- we need 4 threads to run short programs on packet data concurrently.

### Memory Architecture

| Memory | Width | Depth | Access |
|--------|-------|-------|--------|
| IMEM   | 32-bit | 512 words | Port A: CPU fetch, Port B: PCI program loading |
| DMEM | 64-bit | 256-word local array; CPU Port A exposes 128 local words, a 112-word external window, and 16 wrapper-register aliases | Port A: CPU load/store/alias access, Port B: host access to all 256 local words |
| LA     | 64-bit | 2048 words | Port A: trace capture, Port B: PCI readback |

The instruction encoding is ARM-like and 32 bits wide, but the implemented register file, shifter, ALU, load/store path, and DMEM data are genuinely 64 bits wide. Only particular sources, such as data-processing immediates and PC-derived values, are zero-extended. A loaded word can have nonzero upper bits, and the N/C/V flags consequently have 64-bit rather than ARM32 arithmetic semantics.

**The MEM-stage address space has three windows muxed onto one CPU port** (see §12):

| CPU address | Physical target | Notes |
|-------------|----------------|-------|
| `0x00..0x7F` (0-127)   | Local DMEM array | CPU-visible local half, shared by all 4 threads. |
| `0x80..0xEF` (128-239) | External FIFO BRAM (mapped to FIFO indices `0x00..0x6F`) | The window the wrapper exposes to packet data. |
| `0xF0..0xFF` (240-255) | Wrapper control-register aliases (slots `0x0..0xF`) | Lets ARM firmware control DMA, GPU, FIFO mode/drain, and selected wrapper functions. |

The external window is selected by `addr[7] && addr[7:4] != 4'hF`; the alias window is selected by `addr[7:4] == 4'hF`. This is a CPU Port A view: the HDL still declares a 256-word local array, and host Port B can access its entries `0x00..0xFF`. At the integration boundary, the ARM `ext_mem_*` signals reach FIFO BRAM only while `lab8_wrapper.v` is in CPU mode and `cpu_running` is asserted. The separate alias bus reads wrapper registers combinationally and sends ARM writes to the wrapper's register-update logic, where an active PCI transaction has priority.

### Per-Thread Resources

Each thread has:
- Its own PC (11 bits, confined to a 128-word IMEM region)
- Its own register file partition (16 registers out of 64 total)
- Its own CPSR flags (4 bits: N, Z, C, V)
- Its own halted flag

All threads share: IMEM, local DMEM, FIFO BRAM, and the wrapper register-alias window.

---

## 1. processor.v -- Top-Level Pipeline

**Purpose:** Top-level module that instantiates and wires all 5 pipeline stages, manages the global thread counter, per-thread CPSR flags, halt detection, and the logic analyzer.

### 1.1 Port List

```verilog
module processor(
    input clk,                     // System clock (125 MHz on NetFPGA)
    input rst,                     // Synchronous reset
    input         start_stop,      // 1=running, 0=paused (thread counter frozen)

    // IMEM Port B: PCI register interface (host loads program)
    input         intf_wen_imem,   // Write enable for IMEM programming
    input  [8:0]  intf_addr_imem,  // 9-bit word address (512 words total)
    input  [31:0] intf_data_imem,  // 32-bit instruction to store
    output [31:0] intf_dout_imem,  // Read-back data for verification

    // DMEM Port B: PCI register interface (host debug access)
    input         web,             // Write enable
    input  [63:0] dinb,            // 64-bit write data
    input  [7:0]  addrb,           // 8-bit address (256 words)
    output [63:0] doutb,           // Read-back data

    // External memory port (FIFO BRAM access from MEM stage)
    output [7:0]  ext_mem_addr,    // FIFO-window address (0-111 when active)
    output [63:0] ext_mem_din,     // Write data to FIFO BRAM
    output        ext_mem_we,      // Write enable to FIFO BRAM
    input  [63:0] ext_mem_dout,    // Read data from FIFO BRAM

    // Register-alias window (ARM-orchestrated pipeline)
    output [3:0]  reg_alias_sel,   // Wrapper register slot (0x0-0xF)
    output [63:0] reg_alias_wdata, // Store data for an alias write
    output        reg_alias_we,    // Alias-window write enable
    input  [63:0] reg_alias_rdata, // Wrapper register read data

    // Logic Analyzer read port (PCI readback)
    input  [10:0] la_rd_addr,      // 11-bit address (2048 entries)
    output [63:0] la_rd_data,      // 64-bit trace entry

    // Debug outputs
    output [3:0]  dbg_cpsr_0,      // Thread 0 {N, Z, C, V}
    output [3:0]  dbg_cpsr_1,      // Thread 1
    output [3:0]  dbg_cpsr_2,      // Thread 2
    output [3:0]  dbg_cpsr_3,      // Thread 3
    output [1:0]  dbg_thread_id,   // Current global thread_id
    output        all_halted       // 1 when all threads have hit HALT
);
```

**Four external datapath/programming interfaces:**
- **IMEM Port B** -- host loads the program before execution
- **DMEM Port B** -- host reads/writes internal DMEM for debugging
- **ext_mem** -- CPU's MEM stage reads/writes FIFO BRAM through the wrapper's proc port MUX
- **reg_alias** -- CPU's `0xF0..0xFF` MEM-stage window reads/writes selected wrapper control and status registers

### 1.2 Global Thread Counter

```verilog
reg [1:0] thread_id;

always @(posedge clk) begin
    if (rst)
        thread_id <= 2'd0;         // Reset to thread 0
    else if (start_stop)
        thread_id <= thread_id + 2'd1;  // Wraps: 0->1->2->3->0->...
end

assign dbg_thread_id = thread_id;
```

**The thread counter is the heartbeat of the FGMT pipeline.** It cycles 0->1->2->3->0... on every clock edge while `start_stop=1`. Each pipeline stage uses the thread ID (propagated through pipeline registers) to select the correct PC, register partition, and CPSR.

**Why gate by `start_stop`?** When the host pauses the CPU (`start_stop=0`), the thread counter freezes. However, note that the pipeline itself does NOT freeze -- IF_stage still uses whatever `thread_id` is latched. This is the root cause of Bug #1 (see Batch 3 walkthrough): if `rst=0` and `start_stop=0`, the counter sticks at 0 but IF_stage keeps advancing T0's PC every cycle. The software workaround is to never enter this state -- always transition directly from reset to running.

### 1.3 Halt Detection

```verilog
reg [3:0] halted;                  // One flag per thread
assign all_halted = &halted;       // AND-reduce: 1 when ALL 4 threads halted
wire halt_detected;                // From ID stage: current instruction is HALT

always @(posedge clk) begin
    if (rst)
        halted <= 4'b0000;         // No threads halted on reset
    else if (halt_detected)
        halted[id_thread_id] <= 1'b1;  // Set flag for the halting thread
end
```

`halt_detected` comes from the ID stage -- it fires when the decoded instruction is `0xFFFFFFFF` (our HALT encoding). The `halted` vector is wired to IF_stage to gate PC advancement (H1 fix). This freezes that thread's PC, but it does not disable IMEM: the synchronous fetch path continues rereading and decoding the frozen post-HALT address whenever the thread's slot recurs. A safe instruction must therefore remain at that address; the fix prevents PC progression and eventual program re-entry rather than stopping the pipeline slot itself.

**Why AND-reduce?** The host polls `all_halted` (exposed as `CPU_STATUS[31]`) to know when the program is done. Individual thread halt flags are not exposed -- either all threads are done, or the CPU is still running.

### 1.4 Per-Thread CPSR Flags

```verilog
reg [3:0] cpsr_0, cpsr_1, cpsr_2, cpsr_3;   // {N, Z, C, V} per thread

// CPSR update: happens at MEM stage (flags computed in EX, registered in EX/MEM)
always @(posedge clk) begin
    if (rst) begin
        cpsr_0 <= 4'd0;
        cpsr_1 <= 4'd0;
        cpsr_2 <= 4'd0;
        cpsr_3 <= 4'd0;
    end else if (mem_set_flags) begin
        case (mem_thread_id)
            2'd0: cpsr_0 <= {mem_N, mem_Z, mem_C, mem_V};
            2'd1: cpsr_1 <= {mem_N, mem_Z, mem_C, mem_V};
            2'd2: cpsr_2 <= {mem_N, mem_Z, mem_C, mem_V};
            2'd3: cpsr_3 <= {mem_N, mem_Z, mem_C, mem_V};
        endcase
    end
end
```

The sequential CPSR-update `case` above has no `default` branch in the current RTL. The two-bit thread ID covers all binary values, so this does not change ordinary behavior, but it violates this project's rule that every `case` include an explicit `default` and should be treated as an outstanding RTL-quality issue.

**Why separate registers instead of `reg [3:0] cpsr [0:3]`?** Project history attributes this style to avoiding an ISE 10.1 dynamic-array-bit synthesis problem. The current repository contains no paired failing/passing synthesis artifact for that claim; what the RTL proves is that explicit registers make each thread's update/select path unambiguous.

**CPSR timing:** Flags are computed in EX, registered through EX/MEM, then written to the CPSR in the MEM stage. The ID stage reads the CPSR for condition evaluation. Since FGMT guarantees 4 stages of separation, the CPSR is always up-to-date when the same thread reaches ID again.

```verilog
// Select the correct thread's CPSR for the ID stage condition evaluator
reg [3:0] cpsr_selected;
always @(*) begin
    case (ifid_thread_id)              // Thread ID from the IF/ID register
        2'd0: cpsr_selected = cpsr_0;
        2'd1: cpsr_selected = cpsr_1;
        2'd2: cpsr_selected = cpsr_2;
        2'd3: cpsr_selected = cpsr_3;
        default: cpsr_selected = 4'd0;
    endcase
end

wire cpsr_N_id = cpsr_selected[3];     // Individual flags for ID stage
wire cpsr_Z_id = cpsr_selected[2];
wire cpsr_C_id = cpsr_selected[1];
wire cpsr_V_id = cpsr_selected[0];
```

The mux uses `ifid_thread_id` (the thread currently in ID stage), not `thread_id` (the thread currently in IF stage). This is critical -- condition evaluation must use the flags belonging to the instruction being decoded.

### 1.5 Pipeline Instantiation

The pipeline is wired linearly:

```
IF_stage --> ifid_reg --> ID --> idex_reg --> EX_stage --> exmem_reg --> data_mem --> WB
   ^                      |                                              |           |
   |                      |                                              v           |
   +---- branch_addr -----+                                         CPSR update      |
   +---- halted -----------+---- halt_detected                                        |
                           ^                                                          |
                           +---------- wb_data, wb_waddr, wb_wen, wb_thread_id -------+
```

Key cross-stage connections:
- **Branch (ID -> IF):** `ctrl_branch`, `branch_addr`, `id_thread_id` feed back to IF_stage to redirect PCs
- **Writeback (WB -> ID):** `wb_data`, `wb_waddr`, `wb_wen`, `wb_thread_id` write the register file in ID
- **CPSR (MEM -> processor -> ID):** Flags from EX/MEM register are written to per-thread CPSR in processor.v, then muxed and sent to ID
- **Halt (ID -> processor -> IF):** `halt_detected` sets `halted[]` in processor.v, which gates IF_stage PCs
- **External I/O (MEM -> wrapper):** The MEM stage exposes `ext_mem_*` for FIFO BRAM access and `reg_alias_*` for wrapper-register access; `processor.v` forwards both buses to the wrapper. The logic analyzer is a separate trace-memory path inside `processor.v`.

```verilog
wire flush = 1'b0;   // Branch flush disabled -- FGMT eliminates control hazards
```

**Why flush is always 0:** In a single-thread pipeline, a taken branch requires flushing the incorrectly-fetched instruction. With FGMT, the branch is resolved in ID (cycle N) and takes effect at the branching thread's next IF (cycle N+4). No wrong-path instruction is ever fetched.

### 1.6 Logic Analyzer

```verilog
localparam LA_AW = 11;                              // 2^11 = 2048 entries

reg [LA_AW-1:0] la_wr_ptr;                          // Circular write pointer
wire la_event = wb_wen | mem_WMemEn | mem_RMemEn;   // Any visible event
wire la_we    = start_stop & la_event;               // Record only when running

always @(posedge clk) begin
    if (rst)
        la_wr_ptr <= {LA_AW{1'b0}};
    else if (la_we)
        la_wr_ptr <= la_wr_ptr + 1;                 // Advance (wraps at 2048)
end
```

**Event selection:** Only records when something "interesting" happens -- a register write, a memory store, or a memory load. NOP cycles and pure-compute cycles that do not produce a visible result are skipped. This makes the trace much denser and more useful for debugging.

```verilog
// Trace format (64-bit packed word):
wire [63:0] la_din = {
    3'b0,                    // [63:61] reserved
    mem_thread_id,           // [60:59] which thread is in MEM stage
    MEM_pc_idx,              // [58:54] low 5 instruction-index bits (modulo 32)
    wb_thread_id,            // [53:52] which thread is in WB stage
    WB_pc_idx,               // [51:47] low 5 instruction-index bits (modulo 32)
    mem_WMemEn,              // [46]    1 = store in progress
    mem_RMemEn,              // [45]    1 = load in progress
    wb_wen,                  // [44]    1 = register writeback in progress
    wb_waddr,                // [43:40] destination register number
    mem_alu_result[7:0],     // [39:32] memory address (low byte)
    mem_write_data[15:0],    // [31:16] store data (low 16 bits)
    wb_data[15:0]            // [15:0]  writeback data (low 16 bits)
};
```

**Why capture both MEM and WB simultaneously?** Under normal continuous round-robin issue, they hold adjacent issued instructions and therefore belong to different threads. A single trace entry shows what two different threads are doing at the same instant -- invaluable for diagnosing cross-thread memory conflicts.

The LA instantiation connects to a simple dual-port BRAM (see Section 14).

---

## 2. IF_stage.v -- Instruction Fetch

**Purpose:** Manages 4 independent PCs, fetches instructions from IMEM, and gates PC advancement for halted threads.

### 2.1 Port List

```verilog
module IF_stage(
    input         clk,
    input         rst,

    // Port B: PCI register interface (host loads program into IMEM)
    input         intf_wen_imem,     // Write enable
    input  [8:0]  intf_addr_imem,    // 9-bit word address (0-511)
    input  [31:0] intf_data_imem,    // 32-bit instruction data
    output [31:0] intf_dout_imem,    // Read-back for verification

    // CPU datapath output (aligned with BRAM output, 1 cycle after fetch)
    output [31:0] data_out,          // Fetched instruction
    output reg [10:0] pc_plus4_out,  // Next PC (used in branch-target computation)
    output reg [1:0]  thread_id_out, // Thread that owns data_out
    output reg [4:0]  pc_idx_out,    // Low 5 instruction-index bits (for LA)

    // Thread control
    input  [1:0]  thread_id,         // Current cycle's thread (from global counter)

    // Branch control (from ID stage, targets a specific thread)
    input         ctrl_branch,       // 1 = branch taken
    input  [63:0] branch_addr,       // Branch target address
    input  [1:0]  branch_thread_id,  // Which thread is branching

    // Halt flags (from processor.v, per-thread)
    input  [3:0]  halted             // H1 fix: gate PC advance per-thread
);
```

### 2.2 Per-Thread PCs and Region Confinement

```verilog
reg [10:0] pc [0:3];                 // 4 independent PCs, 11 bits each
```

Each PC has the format `{thread_id[1:0], byte_offset[8:0]}`. The upper 2 bits permanently identify the thread's IMEM region, and the lower 9 bits are the byte offset within that 512-byte (128-word) region.

```
IMEM layout (512 words total, 32-bit each):
  Thread 0: IMEM[  0..127]   PC range 0x000-0x1FF
  Thread 1: IMEM[128..255]   PC range 0x200-0x3FF
  Thread 2: IMEM[256..383]   PC range 0x400-0x5FF
  Thread 3: IMEM[384..511]   PC range 0x600-0x7FF
```

```verilog
wire [10:0] current_pc   = pc[thread_id];         // PC of the fetching thread
wire [8:0]  current_off  = current_pc[8:0];        // Byte offset within region
wire [8:0]  next_off     = current_off + 9'd4;     // +4 bytes = next instruction
wire [10:0] next_pc_seq  = {thread_id, next_off};  // Force region base bits
```

**Region confinement:** `next_pc_seq` always reconstructs the full PC from `{thread_id, next_off}`. Even if `next_off` wraps past 0x1FF, the upper 2 bits are forced to `thread_id`. This prevents one thread from accidentally executing another thread's code -- the offset wraps within the 128-word region boundary.

```verilog
// Branch target: also confined to branch_thread_id's region
wire [10:0] next_pc_br = {branch_thread_id, branch_addr[8:0]};
```

Branch targets are similarly confined. Only the low 9 bits of the branch address are used; the upper bits are replaced with the branching thread's ID.

### Why Confinement?

Without confinement, a thread that progressed beyond its region could enter another thread's code and corrupt shared state. Supporting history attributes discovery to a bubble-sort simulation, but the raw run is not present in this checkpoint; the cross-region failure mechanism itself follows directly from an unconstrained shared IMEM address.

### 2.3 PC Update Logic

```verilog
always @(posedge clk) begin
    if (rst) begin
        pc[0] <= 11'h000;       // Thread 0 starts at word 0
        pc[1] <= 11'h200;       // Thread 1 starts at word 128
        pc[2] <= 11'h400;       // Thread 2 starts at word 256
        pc[3] <= 11'h600;       // Thread 3 starts at word 384
        pc_plus4_out  <= 11'd0;
        thread_id_out <= 2'd0;
        pc_idx_out    <= 5'd0;
    end else begin
        // Advance fetching thread's PC (only if not halted -- H1 fix)
        if (!halted[thread_id])
            pc[thread_id] <= next_pc_seq;

        // Branch override (from ID stage, also confined to thread's region)
        if (ctrl_branch)
            pc[branch_thread_id] <= next_pc_br;

        // Pipeline metadata (delayed 1 cycle to match BRAM read latency)
        pc_plus4_out  <= next_pc_seq;
        thread_id_out <= thread_id;
        pc_idx_out    <= current_pc[6:2];  // Low 5 word-index bits (index modulo 32)
    end
end
```

**H1 fix (halt gating):** `halted[thread_id]` gates the PC advance. Before this fix, a halted thread's PC kept advancing, wrapping through its region and re-executing the program indefinitely. The workaround was filling unused IMEM with `B .` instructions (`0xEAFFFFFE`). With the H1 fix, halted threads' PCs freeze permanently.

**Branch priority:** The branch write (`pc[branch_thread_id] <= next_pc_br`) comes after the sequential advance. If both target the same thread on the same cycle, Verilog's "last-write-wins" rule ensures the branch takes priority. In practice, this race cannot happen -- the branching thread (in ID) is 2 stages ahead of the fetching thread (in IF), so `branch_thread_id != thread_id`.

**Delayed outputs:** `pc_plus4_out`, `thread_id_out`, and `pc_idx_out` are registered (1-cycle delay) to align with the BRAM's 1-cycle read latency. When IF presents `current_pc` to IMEM in cycle N, the instruction appears on `data_out` in cycle N+1. The metadata must arrive at the IF/ID register in the same cycle N+1, so it's also registered.

### 2.4 IMEM Instantiation

```verilog
inst_mem m_imem (
    .clk   (clk),
    .addra (current_pc[10:2]),     // Word index: drop 2 LSBs (byte -> word)
    .dina  (32'd0),                // Port A never writes during execution
    .wea   (1'b0),                 // Write enable tied low
    .douta (data_out),             // Fetched instruction -> IF/ID register
    .addrb (intf_addr_imem),       // Port B: PCI programming interface
    .dinb  (intf_data_imem),
    .web   (intf_wen_imem),
    .doutb (intf_dout_imem)        // Port B: PCI read-back
);
```

**Address conversion:** ARM PCs are byte addresses. IMEM stores 32-bit words. Dropping the 2 LSBs (`[10:2]`) converts the 11-bit byte address to a 9-bit word address (0-511).

**Dual-port usage:** Port A fetches instructions every cycle (read-only). Port B is used by the host to load the program before execution (read/write). Both ports can operate simultaneously without conflict.

---

## 3. inst_mem.v -- IMEM BRAM

**Purpose:** 512x32-bit true dual-port BRAM for instruction storage.

### 3.1 Module Interface

```verilog
module inst_mem(
    input         clk,

    // Port A: CPU datapath (read-only during execution)
    input  [8:0]  addra,           // 9-bit word address (0-511)
    input  [31:0] dina,            // Write data (unused; tied to 0)
    input         wea,             // Write enable (tied low during execution)
    output reg [31:0] douta,       // Fetched instruction (1-cycle latency)

    // Port B: PCI register interface (read/write for program loading)
    input  [8:0]  addrb,           // Word address from PCI
    input  [31:0] dinb,            // Instruction to store
    input         web,             // Write enable (high during loading)
    output reg [31:0] doutb        // Read-back data (for PCI verification)
);
```

### 3.2 Memory Array

```verilog
reg [31:0] mem [0:511];            // 512 x 32-bit memory array

// Port A: registered read, optional write
always @(posedge clk) begin
    if (wea)
        mem[addra] <= dina;        // Write (unused during execution)
    douta <= mem[addra];           // Read: always reads, 1-cycle latency
end

// Port B: registered read, optional write
always @(posedge clk) begin
    if (web)
        mem[addrb] <= dinb;        // Write (PCI loads program)
    doutb <= mem[addrb];           // Read: PCI verification read-back
end
```

This is the standard Xilinx BRAM inference pattern. XST recognizes this coding style and maps it to Block RAM primitives on the VP50. Key properties:

- **Synchronous read:** `douta` is a register, not a wire. The value appears 1 clock cycle after the address is presented. This latency is accounted for by IF_stage's delayed metadata outputs.
- **Read-during-write:** The `douta <= mem[addra]` read happens in the same `always` block as the write. In Xilinx BRAM, this produces "read-first" behavior -- the old value is read, then the new value is written.
- **No initialization block:** IMEM starts with undefined contents. The host must load the program via Port B before starting the CPU.

### Why 512 Words?

512 = 4 threads x 128 words each. Each thread gets 128 instructions, which is sufficient for our packet-processing kernels (typically 5-20 instructions). The 9-bit word address maps naturally to BRAM primitives (VP50 Block RAMs are 18Kbit = 512x36 in the widest configuration, so one BRAM holds the full IMEM).

---

## 4. ifid_reg.v -- IF/ID Pipeline Register

**Purpose:** Latches the fetched instruction and associated metadata between the IF and ID stages.

### 4.1 Module Interface

```verilog
module ifid_reg(
    input clk,
    input rst,
    input flush,                   // Branch flush (tied to 0 in FGMT)

    input  [31:0] i_inst,          // Fetched instruction from IMEM
    output reg [31:0] o_inst,      // -> ID stage

    input  [10:0] i_pc,            // PC+4 from IF_stage
    output reg [10:0] o_pc,        // -> ID stage (for branch offset computation)

    input  [1:0] i_thread_id,      // Thread that fetched this instruction
    output reg [1:0] o_thread_id,  // -> ID stage (selects register partition + CPSR)

    input  [4:0] i_pc_idx,         // Instruction index (for LA trace)
    output reg [4:0] o_pc_idx      // -> ID stage -> further pipeline registers -> LA
);
```

### 4.2 Register Logic

```verilog
always @(posedge clk) begin
    if (rst) begin
        o_inst      <= 32'b0;      // NOP on reset
        o_pc        <= 11'd0;
        o_thread_id <= 2'd0;
        o_pc_idx    <= 5'd0;
    end
    else if (flush) begin
        o_inst      <= 32'b0;      // NOP on flush (same as reset)
        o_pc        <= 11'd0;
        o_thread_id <= 2'd0;
        o_pc_idx    <= 5'd0;
    end
    else begin
        o_inst      <= i_inst;     // Normal pipeline advance
        o_pc        <= i_pc;
        o_thread_id <= i_thread_id;
        o_pc_idx    <= i_pc_idx;
    end
end
```

**Flush path:** Although `flush` is always 0 in FGMT (no branch penalties), the logic is retained for completeness and reset behavior. If `flush` were asserted, it would insert a NOP (all zeros) into the ID stage, preventing any instruction from executing.

**Thread ID propagation:** `o_thread_id` is the key signal that tells ID which register partition to read, which CPSR to evaluate, and which thread to attribute halt detection to. It travels with the instruction through every pipeline register until WB.

---

## 5. ID.v -- Instruction Decode

**Purpose:** Decodes the ARM instruction, reads the register file, evaluates the condition code, generates all control signals, and computes branch targets. This is the most complex stage.

### 5.1 Port List

```verilog
module ID(
    input             clk,
    input             rst,
    input      [31:0] i_inst,           // 32-bit ARM instruction from IF/ID

    // Writeback from WB stage (writes register file)
    input      [3:0]  waddr,            // Destination register number (4-bit)
    input      [63:0] wdata,            // Data to write
    input             i_WRegEn,         // Write enable
    input      [1:0]  wb_thread_id,     // Which thread's registers to write

    // PC from IF/ID register
    input      [10:0] ifid_pc,          // For branch offset computation

    // Thread ID from IF/ID pipeline register
    input      [1:0]  thread_id,        // Current thread in decode stage

    // Register read outputs
    output     [63:0] r0data,           // Rn value (source 1 / base address)
    output     [63:0] r1data,           // Rm value (source 2) or Rd value (STR)
    output     [63:0] o_sign_extended,  // Immediate / offset value

    // Control signals
    output     [3:0]  o_WReg1,          // Destination register (Rd)
    output reg        o_WRegEn,         // Register write enable
    output reg        o_WMemEn,         // Memory write enable (STR)
    output reg        o_RMemEn,         // Memory read enable (LDR)
    output reg        ctrl_branch,      // Branch taken
    output reg        ctrl_mem2reg,     // 1=load data -> reg, 0=ALU result -> reg
    output     [63:0] branch_addr,      // Branch target address
    output reg        alusrc,           // 0=shifted register, 1=immediate
    output reg [3:0]  ALU_op,           // ARM opcode passed to ALU
    output reg        o_set_flags,      // 1=update CPSR flags

    // Barrel shifter control
    output     [4:0]  o_shift_amt,      // Shift amount (inst[11:7])
    output     [1:0]  o_shift_type,     // Shift type (inst[6:5])

    // Halt detection
    output            is_halt,          // 1 when instruction is 0xFFFFFFFF

    // Per-thread CPSR flags (pre-selected by processor.v)
    input             cpsr_N,           // Negative
    input             cpsr_Z,           // Zero
    input             cpsr_C,           // Carry
    input             cpsr_V            // Overflow
);
```

### 5.2 Register File (64 Entries)

```verilog
reg [63:0] register_file [0:63];       // 64 entries x 64-bit
integer i;

always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < 64; i = i + 1)
            register_file[i] <= 64'd0;  // Zero all registers on reset
    end else begin
        if (i_WRegEn)
            register_file[{wb_thread_id, waddr}] <= wdata;  // Write to correct thread
    end
end
```

**Thread-qualified addressing:** The 6-bit register address is `{thread_id[1:0], reg_number[3:0]}`. Thread 0's r5 is at index `{2'b00, 4'd5}` = 5; Thread 2's r5 is at `{2'b10, 4'd5}` = 37. This partitions the 64-entry file into 4 independent banks of 16 registers each.

**Write port:** `wb_thread_id` comes from the WB stage (4 cycles behind ID). A thread's WB write completes before that thread's next ID read, so there are no conflicts. The `i_WRegEn` signal is the final gated write enable from the WB module.

### Why 64-bit Registers?

The 32-bit ARM-like encoding controls a genuinely 64-bit register datapath. Register operands and loaded words retain all 64 bits; only explicitly constructed 32-bit sources such as DP immediates are zero-extended. This width matches the DMEM and FIFO data bus but gives arithmetic, shifts, and flags 64-bit semantics.

### 5.3 ARM Instruction Field Extraction

```verilog
wire [3:0]  cond       = i_inst[31:28];   // Condition code (EQ, NE, AL, etc.)
wire [1:0]  op_class   = i_inst[27:26];   // 00=DP, 01=LDR/STR
wire        I_bit      = i_inst[25];       // DP: 1=immediate, 0=register operand
wire [3:0]  opcode     = i_inst[24:21];   // DP: ARM ALU operation
wire        U_bit      = i_inst[23];       // LDR/STR: 1=add offset, 0=subtract
wire        S_bit      = i_inst[20];       // DP: 1=update flags
wire        L_bit      = i_inst[20];       // LDR/STR: 1=load, 0=store (same bit)
wire [3:0]  Rn         = i_inst[19:16];   // Source register 1 / base address
wire [3:0]  Rd         = i_inst[15:12];   // Destination register
wire [3:0]  Rm         = i_inst[3:0];      // Source register 2 (DP register mode)
wire [4:0]  shift_amt  = i_inst[11:7];    // Barrel shifter amount
wire [1:0]  shift_type = i_inst[6:5];     // 00=LSL, 01=LSR, 10=ASR, 11=ROR
wire [3:0]  rotate     = i_inst[11:8];    // DP immediate: rotation amount
wire [7:0]  imm8       = i_inst[7:0];     // DP immediate: 8-bit value
wire [11:0] offset12   = i_inst[11:0];    // LDR/STR: 12-bit unsigned offset
```

These wires are direct slices of the instruction -- no logic, just naming. The ARM encoding uses positional fields, so decoding is mostly just selecting bit ranges.

### 5.4 Immediate Computation (DP)

```verilog
reg  [31:0] imm32;
wire [4:0]  rot_amt   = {rotate, 1'b0};   // Rotation amount = rotate * 2
wire [31:0] imm32_raw = {24'b0, imm8};    // Zero-extend 8-bit immediate

always @(*) begin
    if (rotate == 4'd0)
        imm32 = imm32_raw;                // No rotation
    else
        imm32 = (imm32_raw >> rot_amt) | (imm32_raw << (6'd32 - {1'b0, rot_amt}));
end
```

ARM data-processing immediates are encoded as an 8-bit value rotated right by `rotate*2` positions within a 32-bit field. For example, `MOV r1, #128` encodes `imm8=0x80, rotate=0`, giving `imm32=0x80=128`. Larger constants use non-zero rotations: `imm8=0xFF, rotate=9` rotates `0x000000FF` right by 18 positions to produce `0x003FC000`.

### 5.5 Instruction Class Detection

```verilog
wire is_nop        = (i_inst == 32'd0);                     // All-zero = NOP
assign is_halt     = (i_inst == 32'hFFFFFFFF);              // All-ones = HALT
wire is_bx         = !is_nop && (i_inst[27:20] == 8'b00010010)
                              && (i_inst[7:4]   == 4'b0001); // BX (branch-exchange)
wire is_dp         = (op_class == 2'b00) && !is_nop && !is_bx; // Data processing
wire is_load_store = (op_class == 2'b01);                    // LDR or STR
wire is_load       = is_load_store &  L_bit;                 // LDR (L=1)
wire is_store      = is_load_store & ~L_bit;                 // STR (L=0)
wire is_test_op    = (opcode[3:2] == 2'b10);                 // TST/TEQ/CMP/CMN
wire is_branch     = (i_inst[27:25] == 3'b101) && !is_nop;  // B or BL-class encoding
```

**NOP exclusion:** `is_dp` explicitly excludes `is_nop` because an all-zero instruction happens to have `op_class=00` (data processing), but we want it to produce no side effects. Similarly, BX has `op_class=00` but is not a normal DP instruction.

**HALT encoding:** `0xFFFFFFFF` is a reserved (undefined) ARM instruction. We repurpose it as HALT. When decoded, it sets the thread's `halted` flag via the `is_halt` output.

**Test operations:** TST, TEQ, CMP, CMN (opcode[3:2]=10) update flags but do NOT write a result to Rd. The `is_test_op` signal gates `o_WRegEn` off for these instructions.

**BL limitation:** The branch-class detector also accepts encodings with the link bit set, but no logic writes the return address to r14. In this implementation, a BL encoding therefore behaves as B rather than implementing a subroutine call.

### 5.6 Condition Evaluator (C1 Fix)

```verilog
reg cond_pass;
always @(*) begin
    case (cond)
        4'b0000: cond_pass = cpsr_Z;                    // EQ: equal (Z=1)
        4'b0001: cond_pass = ~cpsr_Z;                   // NE: not equal (Z=0)
        4'b0010: cond_pass = cpsr_C;                    // CS: carry set
        4'b0011: cond_pass = ~cpsr_C;                   // CC: carry clear
        4'b0100: cond_pass = cpsr_N;                    // MI: negative
        4'b0101: cond_pass = ~cpsr_N;                   // PL: positive or zero
        4'b0110: cond_pass = cpsr_V;                    // VS: overflow set
        4'b0111: cond_pass = ~cpsr_V;                   // VC: overflow clear
        4'b1000: cond_pass = cpsr_C & ~cpsr_Z;          // HI: unsigned higher
        4'b1001: cond_pass = ~cpsr_C | cpsr_Z;          // LS: unsigned lower or same
        4'b1010: cond_pass = (cpsr_N == cpsr_V);         // GE: signed >=
        4'b1011: cond_pass = (cpsr_N != cpsr_V);         // LT: signed <
        4'b1100: cond_pass = ~cpsr_Z & (cpsr_N == cpsr_V); // GT: signed >
        4'b1101: cond_pass = cpsr_Z | (cpsr_N != cpsr_V);  // LE: signed <=
        4'b1110: cond_pass = 1'b1;                       // AL: always execute
        4'b1111: cond_pass = 1'b0;                       // NV: never execute
        default: cond_pass = 1'b1;
    endcase
end
```

All 15 ARM condition codes are implemented. The evaluator reads the per-thread CPSR flags (`cpsr_N/Z/C/V` are pre-selected by processor.v based on `ifid_thread_id`).

**C1 fix:** In the original Lab 6 design, `cond_pass` only gated `ctrl_branch`. All other control signals (WRegEn, WMemEn, RMemEn, set_flags) were unconditional -- a `ADDNE r1, r2, r3` would write r1 even if the NE condition failed. The fix (applied in the control unit below) gates ALL write enables by `cond_pass`:

```
o_WRegEn    = !is_test_op & cond_pass;   // DP: only write if condition passes
o_set_flags = (S_bit | is_test_op) & cond_pass;  // Only update flags if passes
o_RMemEn    = cond_pass;                  // LDR: only load if passes
o_WMemEn    = cond_pass;                  // STR: only store if passes
```

### 5.7 Branch Target Computation

```verilog
wire [23:0] branch_imm24    = i_inst[23:0];                        // 24-bit signed offset
wire [63:0] branch_offset64 = {{38{branch_imm24[23]}}, branch_imm24, 2'b00}; // Sign-extend + <<2
wire [63:0] branch_target_b = {53'd0, ifid_pc} + 64'd4 + branch_offset64;

// BX target: read register[Rm] directly from register file
wire [3:0]  bx_rm            = i_inst[3:0];
wire [63:0] branch_target_bx = register_file[{thread_id, bx_rm}];

assign branch_addr = is_bx ? branch_target_bx : branch_target_b;
```

**B and BL-class branch:** The 24-bit signed offset is sign-extended to 64 bits and shifted left by 2 (byte alignment). The target is `PC + 8 + offset` in ARM convention, which equals `ifid_pc + 4 + offset` because `ifid_pc` already represents `PC+4`. As noted above, the link bit is ignored and LR is not written.

**BX branch:** The target is read directly from register `Rm` in the register file. This is an asynchronous read using the thread-qualified address `{thread_id, bx_rm}`.

### 5.8 Immediate/Offset MUX

```verilog
wire [63:0] dp_imm      = {32'd0, imm32};       // Zero-extend 32-bit DP immediate to 64
wire [63:0] ls_offset   = {52'd0, offset12};     // Zero-extend 12-bit LDR/STR offset to 64
wire [63:0] imm_extended = is_load_store ? ls_offset : dp_imm;
```

The `o_sign_extended` output carries either the DP immediate (rotated 8-bit) or the LDR/STR offset (12-bit unsigned), depending on the instruction class. The EX stage uses this when `alusrc=1`.

### 5.9 Register Read Ports

```verilog
wire [3:0] r0addr = Rn;                        // Source register 1 = Rn
wire [3:0] r1addr = is_store ? Rd : Rm;        // Source register 2: Rd for STR, Rm for DP

wire        rn_is_pc    = (Rn == 4'd15);        // Rn=r15 -> substitute PC value
wire [63:0] arm_pc_value = {53'd0, ifid_pc} + 64'd4;  // ARM PC = ifid_pc + 4

assign r0data = rn_is_pc ? arm_pc_value : register_file[{thread_id, r0addr}];
assign r1data = register_file[{thread_id, r1addr}];
```

**Store data path:** For STR, the register file's second read port reads Rd (the data to store), not Rm. For DP instructions, it reads Rm (the second operand). This mux eliminates the need for a separate store-data read port.

**PC substitution:** When Rn=r15 (the program counter), the register file value is overridden with `ifid_pc + 4`. This implements PC-relative addressing (e.g., `LDR r0, [PC, #offset]`). The `+4` accounts for the ARM convention that the PC register reads as `current_instruction_address + 8`, and `ifid_pc` is already `address + 4`.

This is the only architectural-PC substitution in the current decoder. Reading r15 through the second read port uses its ordinary stored register-file slot, and writing Rd=r15 does not redirect fetch. General ARM r15 read/write and write-to-PC semantics are therefore not implemented.

### 5.10 Control Unit

```verilog
always @(*) begin
    // Defaults: NOP behavior (no writes, no memory access)
    o_WRegEn     = 1'b0;
    o_WMemEn     = 1'b0;
    o_RMemEn     = 1'b0;
    ctrl_mem2reg = 1'b0;
    ctrl_branch  = 1'b0;
    alusrc       = 1'b0;
    ALU_op       = 4'b0100;        // Default: ADD (safe for address calculation)
    o_set_flags  = 1'b0;

    if (is_branch) begin
        ctrl_branch = cond_pass;   // Branch only if condition passes
    end
    else if (is_bx) begin
        ctrl_branch = cond_pass;   // BX: branch to register, conditional
    end
    else if (is_dp) begin
        ALU_op      = opcode;                       // Pass ARM opcode directly to ALU
        alusrc      = I_bit;                         // 1=immediate operand, 0=register
        o_WRegEn    = !is_test_op & cond_pass;       // Write result (not for TST/CMP) if cond
        o_set_flags = (S_bit | is_test_op) & cond_pass; // Update flags if S=1 or test op
    end
    else if (is_load) begin
        alusrc       = 1'b1;                         // Offset is always immediate
        ALU_op       = U_bit ? 4'b0100 : 4'b0010;   // U=1: base+offset, U=0: base-offset
        o_RMemEn     = cond_pass;                    // Read memory if condition passes
        o_WRegEn     = cond_pass;                    // Write loaded value to Rd
        ctrl_mem2reg = 1'b1;                         // Select memory data (not ALU result)
    end
    else if (is_store) begin
        alusrc       = 1'b1;                         // Offset is always immediate
        ALU_op       = U_bit ? 4'b0100 : 4'b0010;   // U=1: base+offset, U=0: base-offset
        o_WMemEn     = cond_pass;                    // Write memory if condition passes
    end
end
```

**Key control signals explained:**
- `alusrc` -- 0: ALU operand B = shifted register (Rm); 1: ALU operand B = immediate/offset
- `ALU_op` -- Directly passes the ARM opcode[24:21] to the ALU for DP; for LDR/STR, set to ADD (U=1) or SUB (U=0) for address calculation
- `ctrl_mem2reg` -- 0: WB writes ALU result to register; 1: WB writes memory read data to register
- `o_set_flags` -- 1: CPSR flags are updated from ALU output (for S-bit DP instructions and test ops)

The implemented LDR/STR subset is narrower than the full ARM class-01 encoding: it uses `Rn +/- imm12`, transfers one full 64-bit word, and treats the low address bits as a word index. It does not implement byte access, register offsets, pre/post-index selection, or base-register writeback; those encoding bits are ignored rather than rejected. Incrementing the address by one therefore selects the next 64-bit word, not the next byte.

**Why default ALU_op = ADD?** NOP and unrecognized instruction classes retain the no-side-effect defaults. Unsupported data-processing opcodes are different: `is_dp` accepts the whole class, so opcodes such as ADC, RSB, SBC, and RSC fall through the ALU mux as ADD and can write that result. Software must not treat unsupported DP encodings as NOPs.

### 5.11 Output Assignments

```verilog
assign o_WReg1         = Rd;              // Destination register
assign o_sign_extended = imm_extended;     // Immediate/offset value
assign o_shift_amt     = shift_amt;        // Barrel shifter control
assign o_shift_type    = shift_type;       // Barrel shifter type
assign branch_addr     = is_bx ? branch_target_bx : branch_target_b;
```

These are simple pass-throughs. The branch address selects between B/BL-class (PC-relative) and BX (register-indirect) targets.

---

## 6. idex_reg.v -- ID/EX Pipeline Register

**Purpose:** Latches all ID stage outputs between the ID and EX stages. This is the widest pipeline register in the design.

### 6.1 Signals Carried

```verilog
module idex_reg(
    input clk,
    input rst,

    // Data path (64-bit each)
    input      [63:0] i_R1,              // Rn value
    input      [63:0] i_R2,              // Rm/Rd value
    input      [63:0] i_sign_extended,   // Immediate/offset
    output reg [63:0] o_R1,
    output reg [63:0] o_R2,
    output reg [63:0] o_sign_extended,

    // MEM/WB control (pass-through to later stages)
    input      [3:0]  i_WReg1,           // Destination register
    input              i_WRegEn,          // Register write enable
    input              i_WMemEn,          // Memory write enable
    input              i_RMemEn,          // Memory read enable
    input              i_ctrl_mem2reg,    // Memory-to-register select
    output reg [3:0]  o_WReg1,
    output reg        o_WRegEn,
    output reg        o_WMemEn,
    output reg        o_RMemEn,
    output reg        o_ctrl_mem2reg,

    // EX control
    input              i_alusrc,          // ALU source select
    input      [3:0]  i_ALU_op,           // ALU operation
    input      [4:0]  i_shift_amt,        // Barrel shifter amount
    input      [1:0]  i_shift_type,       // Barrel shifter type
    input              i_set_flags,        // Update CPSR enable
    output reg        o_alusrc,
    output reg [3:0]  o_ALU_op,
    output reg [4:0]  o_shift_amt,
    output reg [1:0]  o_shift_type,
    output reg        o_set_flags,

    // Thread ID
    input      [1:0]  i_thread_id,
    output reg [1:0]  o_thread_id,

    // PC index for LA trace
    input      [4:0]  i_pc_idx,
    output reg [4:0]  o_pc_idx
);
```

### 6.2 Register Logic

```verilog
always @(posedge clk) begin
    if (rst) begin
        // Zero all outputs on reset (prevents spurious writes/stores)
        o_R1            <= 64'd0;
        o_R2            <= 64'd0;
        o_sign_extended <= 64'd0;
        o_WReg1         <= 4'd0;
        o_WRegEn        <= 1'b0;
        o_WMemEn        <= 1'b0;
        o_RMemEn        <= 1'b0;
        o_ctrl_mem2reg  <= 1'b0;
        o_alusrc        <= 1'b0;
        o_ALU_op        <= 4'd0;
        o_shift_amt     <= 5'd0;
        o_shift_type    <= 2'd0;
        o_set_flags     <= 1'b0;
        o_thread_id     <= 2'd0;
        o_pc_idx        <= 5'd0;
    end else begin
        // Normal pipeline advance: latch all signals
        o_R1            <= i_R1;
        o_R2            <= i_R2;
        o_sign_extended <= i_sign_extended;
        o_WReg1         <= i_WReg1;
        o_WRegEn        <= i_WRegEn;
        o_WMemEn        <= i_WMemEn;
        o_RMemEn        <= i_RMemEn;
        o_ctrl_mem2reg  <= i_ctrl_mem2reg;
        o_alusrc        <= i_alusrc;
        o_ALU_op        <= i_ALU_op;
        o_shift_amt     <= i_shift_amt;
        o_shift_type    <= i_shift_type;
        o_set_flags     <= i_set_flags;
        o_thread_id     <= i_thread_id;
        o_pc_idx        <= i_pc_idx;
    end
end
```

This is a straightforward D-flip-flop bank. Every control signal is cleanly zeroed on reset. The total width is approximately 64+64+64+4+1+1+1+1+1+4+5+2+1+2+5 = 220 bits -- a significant register, but necessary to carry all ID outputs to EX.

### Why No Stall Signal?

In a single-thread pipeline, the ID/EX register might have a stall input for load-use hazards. With FGMT, there are no data hazards, so no stall logic is needed. The register always advances on every clock edge.

---

## 7. EX.v (EX_stage) -- Execute Stage

**Purpose:** Performs the barrel shift, selects the ALU operand, and instantiates the combinational ALU hierarchy. Entirely combinational -- no clock.

### 7.1 Port List

```verilog
module EX_stage(
    // Operands from ID/EX register
    input  [63:0] R1,              // Rn value (first ALU operand)
    input  [63:0] R2,              // Rm value (or store data for STR)
    input  [63:0] sign_extended,   // Immediate / offset

    // Control from ID/EX register
    input         alu_src,         // 0=shifted register, 1=immediate
    input  [3:0]  ALU_op,          // ARM opcode [24:21]
    input  [4:0]  shift_amt,       // Barrel shifter amount (0-31)
    input  [1:0]  shift_type,      // 00=LSL, 01=LSR, 10=ASR, 11=ROR

    // Outputs (combinational -- latched by exmem_reg)
    output [63:0] alu_result,      // ALU computation result
    output [63:0] write_data,      // R2 pass-through for STR
    output        flag_N,          // Negative flag
    output        flag_Z,          // Zero flag
    output        flag_C,          // Carry flag
    output        flag_V           // Overflow flag
);
```

### 7.2 Barrel Shifter

```verilog
reg [63:0] shifted_R2;

always @(*) begin
    case (shift_type)
        2'b00:   shifted_R2 = R2 << shift_amt;                                // LSL
        2'b01:   shifted_R2 = R2 >> shift_amt;                                // LSR
        2'b10:   shifted_R2 = $signed(R2) >>> shift_amt;                      // ASR
        2'b11:   shifted_R2 = (R2 >> shift_amt) | (R2 << (64 - shift_amt));  // ROR
        default: shifted_R2 = R2;
    endcase
end
```

Four 64-bit shift functions are implemented:
- **LSL (Logical Shift Left):** Fills vacated bits with 0
- **LSR (Logical Shift Right):** Fills vacated bits with 0
- **ASR (Arithmetic Shift Right):** Fills vacated bits with the sign bit (preserves signed values)
- **ROR (Rotate Right):** Bits shifted out the right re-enter from the left

The barrel shifter operates on the full 64-bit value, using only the five-bit immediate shift field. It does not implement register-specified shifts, ARM's special zero-shift cases (including RRX), or a shifter carry-out; logic and move operations consequently drive C to zero when flags are updated. This is an ARM-like subset, not the full ARM Operand2 shifter semantics.

### 7.3 Operand2 MUX

```verilog
wire [63:0] operand2 = alu_src ? sign_extended : shifted_R2;
```

- `alu_src=0` (register mode): Operand2 is the barrel-shifted Rm value
- `alu_src=1` (immediate mode): Operand2 is the sign-extended immediate or LDR/STR offset

### 7.4 ALU Instantiation

```verilog
alu64 u_alu (
    .A(R1),                // First operand: Rn value
    .B(operand2),          // Second operand: shifted Rm or immediate
    .alu_ctrl(ALU_op),     // ARM opcode [24:21]
    .Z(alu_result),        // 64-bit result
    .N_flag(flag_N),       // Negative
    .Z_flag(flag_Z),       // Zero
    .C_flag(flag_C),       // Carry
    .V_flag(flag_V)        // Overflow
);
```

### 7.5 Store Data Pass-Through

```verilog
assign write_data = R2;   // Unshifted R2 -> STR data
```

For STR instructions, the data to store is R2 (read from Rd in the register file). Note that `write_data` carries the UNSHIFTED R2 -- the barrel shifter only applies to the ALU operand, not the store data. This matches ARM architecture: `STR Rd, [Rn, #offset]` stores the raw value of Rd.

### Why is EX_stage Combinational?

All outputs are combinational functions of the ID/EX register outputs. The results are captured by the EX/MEM register (`exmem_reg`) on the next clock edge. Making EX purely combinational simplifies the stage -- no clock, no reset, no state.

---

## 8. alu64.v -- 64-bit ALU

**Purpose:** Implements the supported ARM-like data-processing operations using behavioral arithmetic and logic sub-modules, with an output MUX and CPSR flag generation.

### 8.1 Port List

```verilog
module alu64 (
    input  [63:0] A,          // First operand (Rn)
    input  [63:0] B,          // Second operand (already shifted or immediate)
    input  [3:0]  alu_ctrl,   // ARM opcode [24:21]
    output [63:0] Z,          // ALU result
    output        N_flag,     // Negative  (Z[63])
    output        Z_flag,     // Zero      (Z == 0)
    output        C_flag,     // Carry out
    output        V_flag      // Signed overflow
);
```

### 8.2 Arithmetic Unit

```verilog
wire is_sub = (alu_ctrl == 4'b0010) ||   // SUB
              (alu_ctrl == 4'b1010);      // CMP

wire [63:0] arith_result;
wire        arith_cout;                   // Carry-out from MSB

addsub64 u_addsub (
    .A(A),
    .B(B),
    .sub_mode(is_sub),
    .S(arith_result),
    .overflow(arith_cout)                 // Carry-out, NOT signed overflow
);
```

The `addsub64` computes `A + B` (when `is_sub=0`) or `A - B` (when `is_sub=1`). Only SUB and CMP trigger subtraction mode.

**Signed overflow computation:**

```verilog
wire b_eff_msb = B[63] ^ is_sub;         // Effective MSB of B after 2's complement inversion
wire arith_V   = (~(A[63] ^ b_eff_msb)) & (arith_result[63] ^ A[63]);
```

V flag = 1 when the operands have the same effective sign but the result has a different sign. This detects signed overflow for both addition and subtraction.

### 8.3 Logic Unit

```verilog
wire [63:0] and_out, or_out, xnor_out;

logic64 u_logic (
    .A(A),
    .B(B),
    .AND_out(and_out),
    .OR_out(or_out),
    .XNOR_out(xnor_out)
);

// Additional logic ops (behavioral)
wire [63:0] eor_out = A ^ B;          // EOR (0001): exclusive OR
wire [63:0] bic_out = A & (~B);       // BIC (1110): bit clear
wire [63:0] mvn_out = ~B;             // MVN (1111): bitwise NOT
```

The structural `logic64` provides AND, OR, and XNOR. EOR, BIC, and MVN are implemented behaviorally as single-line assigns. XNOR is computed structurally but not used by any current instruction -- it was part of the original Lab 2 schematic design.

### 8.4 Output MUX

```verilog
reg [63:0] mux_Z;
reg        mux_C;

always @(*) begin
    mux_Z = arith_result;               // Safe default: ADD
    mux_C = arith_cout;

    case (alu_ctrl)
        // Arithmetic (structural addsub64)
        4'b0100: begin mux_Z = arith_result; mux_C = arith_cout; end  // ADD
        4'b0010: begin mux_Z = arith_result; mux_C = arith_cout; end  // SUB
        4'b1010: begin mux_Z = arith_result; mux_C = arith_cout; end  // CMP

        // Logic (structural + behavioral)
        4'b0000: begin mux_Z = and_out;  mux_C = 1'b0; end  // AND
        4'b0001: begin mux_Z = eor_out;  mux_C = 1'b0; end  // EOR
        4'b1000: begin mux_Z = and_out;  mux_C = 1'b0; end  // TST (= AND, flags only)
        4'b1001: begin mux_Z = eor_out;  mux_C = 1'b0; end  // TEQ (= EOR, flags only)
        4'b1100: begin mux_Z = or_out;   mux_C = 1'b0; end  // ORR
        4'b1110: begin mux_Z = bic_out;  mux_C = 1'b0; end  // BIC
        4'b1111: begin mux_Z = mvn_out;  mux_C = 1'b0; end  // MVN

        // Move
        4'b1101: begin mux_Z = B;        mux_C = 1'b0; end  // MOV (pass-through B)

        // Unsupported DP opcodes (ADC, SBC, RSB, RSC) default to ADD.
        // CMN also takes this ADD result intentionally; ID suppresses Rd write and sets flags.
        default: begin mux_Z = arith_result; mux_C = arith_cout; end
    endcase
end
```

**Why default to ADD?** LDR/STR address calculations (`base + offset` or `base - offset`) pass through this MUX with `alu_ctrl=0100` (ADD) or `0010` (SUB). Any unrecognized opcode also defaults to ADD, ensuring address calculations always produce a valid result.

### 8.5 Flag Generation

```verilog
assign Z      = mux_Z;
assign N_flag  = mux_Z[63];                // MSB of result
assign Z_flag  = (mux_Z == 64'd0);         // Result is zero
assign C_flag  = mux_C;                    // Carry (arithmetic) or 0 (logic)

wire is_arith = (alu_ctrl == 4'b0100) ||   // ADD
                (alu_ctrl == 4'b0010) ||   // SUB
                (alu_ctrl == 4'b1010) ||   // CMP
                (alu_ctrl == 4'b1011);     // CMN
assign V_flag  = is_arith ? arith_V : 1'b0;
```

**N flag:** Bit 63 of the 64-bit result. A value with only bit 31 set is negative in ARM32 but positive to this ALU, so MI/PL and signed GE/LT/GT/LE follow signed-64-bit semantics. Programs that rely on ARM32 signed comparisons must explicitly construct or load correctly sign-extended 64-bit operands.

**C/V on logic operations:** Logic, move, and test operations still request a full CPSR update when their S/test behavior is selected, but this ALU forces C and V to zero rather than preserving V or using an ARM shifter carry-out.

### Supported ARM Opcodes Summary

| Opcode | Name | Operation | Flags |
|--------|------|-----------|-------|
| 0000 | AND | A & B | N,Z; C=V=0 |
| 0001 | EOR | A ^ B | N,Z; C=V=0 |
| 0010 | SUB | A - B | N,Z,C,V |
| 0100 | ADD | A + B | N,Z,C,V |
| 1000 | TST | A & B (flags only) | N,Z; C=V=0 |
| 1001 | TEQ | A ^ B (flags only) | N,Z; C=V=0 |
| 1010 | CMP | A - B (flags only) | N,Z,C,V |
| 1011 | CMN | A + B (flags only) | N,Z,C,V |
| 1100 | ORR | A \| B | N,Z; C=V=0 |
| 1101 | MOV | B (pass-through) | N,Z; C=V=0 |
| 1110 | BIC | A & ~B | N,Z; C=V=0 |
| 1111 | MVN | ~B | N,Z; C=V=0 |

---

## 9. addsub64.v -- 64-bit Adder/Subtractor

**Purpose:** Behavioral 64-bit add/subtract unit. Computes `A + B` or `A - B` with carry-out.

### 9.1 Implementation

```verilog
module addsub64 (
    input  [63:0] A,
    input  [63:0] B,
    input         sub_mode,      // 0 = Add, 1 = Subtract
    output [63:0] S,             // Sum/difference result
    output        overflow       // Carry-out from MSB (NOT signed overflow)
);

    wire [63:0] B_eff = B ^ {64{sub_mode}};  // XOR invert B for subtraction
    wire [64:0] sum   = {1'b0, A} + {1'b0, B_eff} + {64'd0, sub_mode};

    assign S        = sum[63:0];
    assign overflow = sum[64];               // Carry-out from bit 63
endmodule
```

**Subtraction via 2's complement:** `A - B = A + (~B) + 1`. When `sub_mode=1`:
- `B_eff = B ^ 0xFFFF...F = ~B` (bitwise inversion)
- The `+ sub_mode` adds 1, completing the 2's complement

When `sub_mode=0`:
- `B_eff = B ^ 0x0000...0 = B` (unchanged)
- The `+ sub_mode` adds 0, giving simple addition

### Why Behavioral Arithmetic?

The current `addsub64.v` directly expresses 64-bit addition/subtraction so synthesis can infer the FPGA carry structure. Earlier structural-adder ancestry is mentioned in historical project material, but the claimed `full_adder.v` and `adder8_comb.v` files are not present in this checkpoint or its cited baseline and are not part of the audited RTL; exact comparative area/timing claims cannot be verified from this repository.

---

## 10. logic64.v -- 64-bit Logic Unit

**Purpose:** Computes AND, OR, and XNOR of two 64-bit operands.

### 10.1 Implementation

```verilog
module logic64 (
    input  [63:0] A,
    input  [63:0] B,
    output [63:0] AND_out,
    output [63:0] OR_out,
    output [63:0] XNOR_out
);

    assign AND_out  = A & B;
    assign OR_out   = A | B;
    assign XNOR_out = ~(A ^ B);
endmodule
```

Like `addsub64`, this is a behavioral replacement for the original gate-level design (which would have instantiated 192 individual gate primitives -- 64 AND2 + 64 OR2 + 64 XNOR2). The behavioral version lets XST freely optimize for the target architecture.

### Why Keep a Separate Module?

The ALU's design is "structural" in the sense that it instantiates sub-modules for arithmetic (`addsub64`) and logic (`logic64`) rather than doing everything inline. This mirrors the Lab 2 schematic hierarchy. The separate module also makes the ALU's architecture clear -- arithmetic and logic are independent parallel datapaths, with the output MUX selecting between them.

---

## 11. exmem_reg.v -- EX/MEM Pipeline Register

**Purpose:** Latches EX stage results and control signals between EX and MEM stages. Also carries CPSR flags for processor.v to update the per-thread CPSR.

### 11.1 Signals Carried

```verilog
module exmem_reg(
    input         clk,
    input         rst,

    // Data from EX stage
    input  [63:0] i_alu_result,       // ALU computation result
    input  [63:0] i_write_data,       // Store data (R2 pass-through)
    output reg [63:0] o_alu_result,
    output reg [63:0] o_write_data,

    // CPSR flags from EX stage (combinational ALU outputs)
    input         i_set_flags,         // 1 = update CPSR this cycle
    input         i_N, i_Z, i_C, i_V, // ALU flag outputs
    output reg    o_set_flags,
    output reg    o_N, o_Z, o_C, o_V,

    // MEM/WB control (pass-through to data_mem and beyond)
    input  [3:0]  i_WReg1,            // Destination register
    input         i_WRegEn,           // Register write enable
    input         i_WMemEn,           // Memory write enable (STR)
    input         i_RMemEn,           // Memory read enable (LDR)
    input         i_ctrl_mem2reg,     // Memory-to-register select
    output reg [3:0]  o_WReg1,
    output reg        o_WRegEn,
    output reg        o_WMemEn,
    output reg        o_RMemEn,
    output reg        o_ctrl_mem2reg,

    // Thread ID
    input  [1:0]  i_thread_id,
    output reg [1:0] o_thread_id,

    // PC index for LA trace
    input  [4:0]  i_pc_idx,
    output reg [4:0] o_pc_idx
);
```

### 11.2 Register Logic

```verilog
always @(posedge clk) begin
    if (rst) begin
        o_alu_result   <= 64'd0;
        o_write_data   <= 64'd0;
        o_set_flags    <= 1'b0;   // No CPSR update on reset
        o_N <= 1'b0; o_Z <= 1'b0; o_C <= 1'b0; o_V <= 1'b0;
        o_WReg1        <= 4'd0;
        o_WRegEn       <= 1'b0;   // No register write on reset
        o_WMemEn       <= 1'b0;   // No memory write on reset
        o_RMemEn       <= 1'b0;   // No memory read on reset
        o_ctrl_mem2reg <= 1'b0;
        o_thread_id    <= 2'd0;
        o_pc_idx       <= 5'd0;
    end else begin
        o_alu_result   <= i_alu_result;
        o_write_data   <= i_write_data;
        o_set_flags    <= i_set_flags;
        o_N <= i_N; o_Z <= i_Z; o_C <= i_C; o_V <= i_V;
        o_WReg1        <= i_WReg1;
        o_WRegEn       <= i_WRegEn;
        o_WMemEn       <= i_WMemEn;
        o_RMemEn       <= i_RMemEn;
        o_ctrl_mem2reg <= i_ctrl_mem2reg;
        o_thread_id    <= i_thread_id;
        o_pc_idx       <= i_pc_idx;
    end
end
```

**CPSR flag path:** `o_set_flags`, `o_N/Z/C/V`, and `o_thread_id` are read by processor.v at the MEM stage to update the per-thread CPSR registers. This means flag updates happen one cycle after the ALU computes them. With FGMT, the same thread's next instruction reaches ID 3 cycles later (at which point CPSR has been stable for 2 cycles), so the flags are always ready.

---

## 12. data_mem.v -- MEM Stage + DMEM + FIFO/Alias Windows

**Purpose:** Implements the MEM pipeline stage. Contains the on-chip 256x64-bit data memory array, and decodes `addr[7:0]` to route CPU loads/stores among internal DMEM, the external FIFO BRAM window, and wrapper control-register aliases:

| CPU address      | Where it goes                  | Read latency |
|------------------|--------------------------------|--------------|
| `0x00..0x7F`     | Internal DMEM (this module)    | 1 cycle (sync BRAM read)  |
| `0x80..0xEF`     | FIFO BRAM (in wrapper)         | 1 cycle (sync BRAM read)  |
| `0xF0..0xFF`     | Wrapper control-register aliases | 1 cycle (captured wrapper read mux) |

Also folds the MEM/WB pipeline register into the same module so its control signals stay aligned with the registered DMEM read output.

> **Current checkpoint note (2026-07-14).** This section matches `src/arm/data_mem.v`, including its `0xF0..0xFF` register-alias window, `reg_alias_*` port bundle, delayed `was_reg` selector, and registered alias read data.

### 12.1 Port List

```verilog
module data_mem(
    input         clk,
    input         reset,              // Resets delayed window selectors/read data

    // Port A: CPU datapath
    input  [63:0] addr,              // ALU result = memory address (full 64-bit)
    input  [63:0] dina,              // Register data for STR
    input         WMemEn,            // Store enable
    output reg [63:0] douta,         // Load result (one of three sources, muxed)
    output reg [63:0] skip_mem,      // ALU result pass-through (for non-load ops)

    // MEM/WB pipeline register: control signals
    input         i_WRegEn,          // Register write enable (from EX/MEM)
    input  [3:0]  i_WReg1,           // Destination register
    input         i_ctrl_mem2reg,    // 1=select memory data, 0=select ALU result
    output reg    o_MRegEn,          // -> WB stage
    output reg [3:0] o_WReg1,
    output reg    o_ctrl_mem2reg,

    // Thread ID and PC pass-through
    input  [1:0]  i_thread_id,
    output reg [1:0] o_thread_id,
    input  [4:0]  i_pc_idx,
    output reg [4:0] o_pc_idx,

    // Port B: host interface to the local 256-word DMEM array
    input         web,
    input  [63:0] dinb,
    input  [7:0]  addrb,
    output reg [63:0] doutb,

    // Window 2: External FIFO BRAM (active for addra 0x80-0xEF)
    output [7:0]  ext_mem_addr,
    output [63:0] ext_mem_din,
    output        ext_mem_we,
    input  [63:0] ext_mem_dout,

    // Window 3: Wrapper register aliases (active for addra 0xF0-0xFF)
    output [3:0]  reg_alias_sel,
    output [63:0] reg_alias_wdata,
    output        reg_alias_we,
    input  [63:0] reg_alias_rdata
);
```

### 12.2 Address Decode -- Three Windows

```verilog
wire [7:0] addra = addr[7:0];              // Only low 8 bits matter

// 0xF0-0xFF carves the alias window out of the former FIFO range
wire addr_is_reg = (addra[7:4] == 4'hF);
wire addr_is_ext = addra[7] & ~addr_is_reg;
// Implicit internal decode: !addr_is_ext && !addr_is_reg
```

If `addra[7]=0`, Port A writes go to the local `mem[]` array and reads return `dmem_rd`. Addresses with `addra[7]=1` go to FIFO BRAM except for top-nibble `0xF`, which selects the wrapper register-alias port.

```
Address map:
  0x00..0x7F (0-127)    Internal DMEM                  (128 slots)
  0x80..0xEF (128-239)  FIFO BRAM (-> ext_mem_addr 0x00..0x6F)  (112 slots)
  0xF0..0xFF (240-255)  Wrapper register aliases       (16 slots)
```

### 12.3 Per-Window Output Drivers

```verilog
// Window 2: FIFO BRAM port
assign ext_mem_addr = {1'b0, addra[6:0]};      // CPU 0x80-0xEF -> FIFO 0x00-0x6F
assign ext_mem_din  = dina;
assign ext_mem_we   = WMemEn & addr_is_ext;    // Write only when in this window

// Window 3: Wrapper register-alias port
assign reg_alias_sel   = addra[3:0];
assign reg_alias_wdata = dina;
assign reg_alias_we    = WMemEn & addr_is_reg;
```

**Slicing strategy:** FIFO BRAM gets `addra[6:0]`, so CPU address `0x80` maps to FIFO index 0 and CPU address `0xEF` maps to FIFO index 111 (`0x6F`). Alias slot selection uses `addra[3:0]`, so `0xF0` selects slot 0 and `0xFF` selects slot 15. Both write enables are gated by their mutually exclusive decodes.

### 12.4 Read-Latency Alignment -- `was_ext`, `was_reg`, and Alias Capture

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

Internal DMEM and FIFO BRAM have 1-cycle synchronous reads. The decode happens in cycle N (when the load address is presented); the data appears in cycle N+1. The output mux therefore chooses with the cycle-N decode delayed in `was_ext` and `was_reg`.

The wrapper's `reg_alias_rdata` is instead a combinational mux keyed by `reg_alias_sel`. `reg_alias_rdata_r` captures that value on the same edge that captures `was_reg`, preserving the addressed alias value for the next-cycle load result even after the CPU address changes.

**H2 fix (extended by the alias window):** Explicit reset clears both delayed selectors and the registered alias data. Without those resets, the first MEM-stage read could select stale or unknown external/alias data.

The wrapper alias map is:

| CPU address | Slot | Wrapper register | Access |
|-------------|------|------------------|--------|
| `0xF0` | `0` | `DMA_CTRL` | Read/write |
| `0xF1` | `1` | `DMA_FIFO_ADDR` | Read/write |
| `0xF2` | `2` | `DMA_GPU_ADDR` | Read/write |
| `0xF3` | `3` | `DMA_LENGTH` | Read/write |
| `0xF4` | `4` | `GPU_CTRL` | Read/write |
| `0xF5` | `5` | `GPU_STATUS` | Read-only |
| `0xF6` | `6` | `FIFO_STATUS` | Read-only |
| `0xF7` | `7` | `FIFO_MODE` | Read/write |
| `0xF8` | `8` | `CTRL` (soft-reset control) | Read/write |
| `0xF9` | `9` | `GPU_CYCLE_COUNT` | Read-only |
| `0xFA` | `A` | `FIFO_DRAIN` | Read/write |
| `0xFB..0xFF` | `B..F` | Reserved | Reads return zero; writes are dropped |

Wrapper values are zero-extended from 32 to 64 bits on reads, and alias stores use `reg_alias_wdata[31:0]`. Read-only/reserved writes are dropped. If an ARM alias write and an accepted PCI register request coincide, the wrapper's `if ... else if` update logic gives PCI priority.

### 12.5 Internal DMEM -- Always-Read, Gated-Write

```verilog
reg [63:0] mem [0:255];                                // 256 x 64-bit (logical)
reg [63:0] dmem_rd;

// Port A: CPU writes only land in internal DMEM (0x00..0x7F).
always @(posedge clk) begin
    if (WMemEn && !addr_is_ext && !addr_is_reg)
        mem[addra] <= dina;
    dmem_rd <= mem[addra];                              // Always read
end
```

DMEM is **always read** -- the synchronous BRAM read pattern requires this for XST to infer block RAM. The output mux discards `dmem_rd` when the access was actually to a different window.

**Write gating:** A store needs `WMemEn` and neither nonlocal decode to write local DMEM. External-window stores assert `ext_mem_we`; alias-window stores assert `reg_alias_we`. The three decodes ensure exactly one window sees a write request (the wrapper can still discard writes to read-only or reserved alias slots).

For CPU Port A, addresses `0x80..0xEF` are routed to FIFO BRAM and `0xF0..0xFF` to register aliases, so the simultaneous local-array read is discarded and CPU stores do not update the local upper half. The array itself is nevertheless a real 256-word local memory: independent host Port B can read and write entries `0x80..0xFF`. Those entries are neither FIFO/alias storage nor dead silicon; they are simply hidden from CPU Port A by the address-window mux.

### 12.6 Output MUX -- 3:1

```verilog
always @(*) douta = was_reg ? reg_alias_rdata_r
                  : (was_ext ? ext_mem_dout : dmem_rd);
```

A 3:1 mux selects the registered alias value, FIFO BRAM read result, or local DMEM read result. `was_reg` and `was_ext` are delayed by one cycle so the selection lines up with the corresponding read data. The decodes are mutually exclusive; alias-first ordering is the explicit RTL priority.

This `douta` value feeds directly into the WB stage's memory/ALU mux.

### 12.7 Port B (PCI Debug)

```verilog
always @(posedge clk) begin
    if (web)
        mem[addrb] <= dinb;        // PCI write (always internal DMEM)
    doutb <= mem[addrb];           // PCI read (always internal DMEM)
end
```

Port B always accesses the local 256-word DMEM array, including local entries `0x80..0xFF`. PCI cannot directly access external FIFO BRAM through the CPU's DMEM interface -- FIFO BRAM has its own indirect registers in the wrapper, and that path requires a nonzero mode in which the CPU/DMA owner is idle.

### 12.8 ALU Result Pass-Through

```verilog
always @(posedge clk) begin
    skip_mem <= addr;              // Register the ALU result (= address = ALU output)
end
```

For non-load instructions (DP, branch), the ALU result needs to pass through to WB. `skip_mem` registers the ALU result with the same 1-cycle latency as the DMEM read, so both arrive at the WB mux simultaneously.

### 12.9 Integrated MEM/WB Pipeline Register

```verilog
always @(posedge clk) begin
    o_WReg1        <= i_WReg1;
    o_MRegEn       <= i_WRegEn;     // Note: renamed from WRegEn to MRegEn
    o_ctrl_mem2reg <= i_ctrl_mem2reg;
    o_thread_id    <= i_thread_id;
    o_pc_idx       <= i_pc_idx;
end
```

The control signals are registered in the same module rather than a separate `memwb_reg` module. This keeps their intended alignment with the DMEM read latency visually explicit. The current RTL resets `was_ext`, `was_reg`, and `reg_alias_rdata_r`; `skip_mem`, `dmem_rd`, `doutb`, and the MEM/WB control/metadata registers have no explicit reset. Upstream reset eventually clears propagated enables, but immediately after reset these registers can still be unknown. This is a current implementation limitation and conflicts with the project's explicit-reset coding rule.

### Why Integrate the MEM/WB Register Here?

The DMEM read (`dmem_rd`) is inherently registered (synchronous BRAM read). Keeping the associated controls here is an organizational choice; a separate module could preserve identical latency by capturing the same inputs on the same edge. Only adding another register after the already-registered memory output would add a cycle.

---

## 13. memwb_reg.v (WB module) -- Writeback Stage

**Purpose:** Selects between memory data and ALU result, then outputs the final writeback value and control signals to the register file in ID.

### 13.1 Module Interface

```verilog
module WB(
    input  [63:0] i_mem_data,      // Data from DMEM/FIFO/alias window (load result)
    input  [63:0] i_skip_mem,      // ALU result (pass-through for non-load ops)
    output [63:0] dout,            // Final writeback value -> register file

    // Control signals
    input         i_WRegEn,        // 1 = write register file
    input  [3:0]  i_WReg1,         // Destination register number
    input         i_ctrl_mem2reg,  // 1 = use memory data, 0 = use ALU result
    output        o_ctrl_mem2reg,  // Pass-through (unused downstream)
    output        o_WRegEn,        // -> ID register file write enable
    output [3:0]  o_WReg1,         // -> ID register file write address

    // Thread ID
    input  [1:0]  i_thread_id,     // Which thread this writeback belongs to
    output [1:0]  o_thread_id      // -> ID register file write thread
);
```

### 13.2 Writeback Logic

```verilog
assign o_WRegEn       = i_WRegEn;
assign o_WReg1        = i_WReg1;
assign o_ctrl_mem2reg = i_ctrl_mem2reg;
assign o_thread_id    = i_thread_id;

assign dout = (o_ctrl_mem2reg) ? i_mem_data : i_skip_mem;
```

The entire WB stage is combinational -- just a 2:1 MUX and pass-throughs:
- `ctrl_mem2reg=1` (LDR): writeback data is the memory read result
- `ctrl_mem2reg=0` (DP/MOV): writeback data is the ALU result

The outputs (`dout`, `o_WRegEn`, `o_WReg1`, `o_thread_id`) feed directly into the ID module's register file write port. The write happens on the next clock edge inside ID's `always @(posedge clk)` block.

### Why a Separate Module for Combinational Logic?

The WB module could be inlined into `processor.v`. Keeping it as a separate module preserves the Lab 6 design hierarchy and makes the 5-stage pipeline structure explicit: each stage (IF, ID, EX, MEM, WB) is its own module or clearly labeled section.

---

## 14. logic_analyzer.v -- 2048x64 Trace Buffer

**Purpose:** Dual-port BRAM that records CPU pipeline events during execution. The write port captures traces; the read port allows PCI readback for post-mortem debugging.

### 14.1 Module Interface

```verilog
module logic_analyzer(
    input         clk,
    // Port A: write (trace capture from processor.v)
    input  [10:0] addra,           // 11-bit write address (0-2047)
    input  [63:0] dina,            // 64-bit trace entry (packed fields)
    input         wea,             // Write enable (1 when event occurs)
    // Port B: read (PCI readback for host debugging)
    input  [10:0] addrb,           // 11-bit read address from PCI
    output reg [63:0] doutb        // 64-bit trace entry read data
);
```

### 14.2 Implementation

```verilog
reg [63:0] mem [0:2047];           // 2048 x 64-bit trace buffer

// Port A: write-only (trace capture)
always @(posedge clk) begin
    if (wea)
        mem[addra] <= dina;        // Store trace entry when event fires
end

// Port B: read-only (PCI readback, synchronous)
always @(posedge clk) begin
    doutb <= mem[addrb];           // 1-cycle read latency
end
```

This is a minimal dual-port BRAM with asymmetric access: Port A only writes (trace capture), Port B only reads (PCI readback). The recorded mapped build uses eight RAMB16 instances for the 2048 x 64-bit (128-Kibit) logical buffer.

### How the LA is Used

The host reads LA entries sequentially via PCI after stopping the CPU. Each 64-bit entry contains a snapshot of both MEM and WB stage activity at the moment the event was recorded. The RAM is not initialized, so unwritten entries are undefined. The write pointer/event count is also not exposed; after the circular buffer wraps, software cannot identify the chronological first entry without outside knowledge of the run.

The circular buffer (write pointer wraps at 2048) means only the last 2048 events are retained. A straight-line run with at most 20 event-producing instructions per thread would generate at most about 80 entries, but loops can generate arbitrarily more and overwrite older history.

### Trace Entry Format (from processor.v)

```
[63:61]  reserved (3 bits)
[60:59]  mem_thread_id       -- which thread is in MEM stage
[58:54]  MEM_pc_idx           -- low 5 instruction-index bits (modulo 32)
[53:52]  wb_thread_id        -- which thread is in WB stage
[51:47]  WB_pc_idx            -- low 5 instruction-index bits (modulo 32)
[46]     mem_WMemEn           -- 1 = store in progress
[45]     mem_RMemEn           -- 1 = load in progress
[44]     wb_wen               -- 1 = register writeback in progress
[43:40]  wb_waddr             -- destination register number
[39:32]  mem_alu_result[7:0]  -- memory address (low byte)
[31:16]  mem_write_data[15:0] -- store data (low 16 bits)
[15:0]   wb_data[15:0]        -- writeback data (low 16 bits)
```

---

## Historical Structural-Adder References

Some older project material refers to `full_adder.v` and `adder8_comb.v`. Neither file exists in the current repository or the cited Lab 8 baseline, and current RTL does not instantiate them. The auditable implementation is the behavioral `src/arm/addsub64.v`; the unavailable modules' exact hierarchy, primitive use, and resource comparison cannot be verified here.

---

## Summary -- What the ARM CPU Provides

1. **processor.v** -- Top-level pipeline wiring, global round-robin thread counter (`thread_id` cycles 0-3), per-thread CPSR flag storage (4 explicit registers to avoid ISE array bugs), halt detection (AND-reduce of 4-bit `halted` vector), and logic analyzer trace capture (event-triggered, 64-bit packed format)
2. **IF_stage.v** -- 4 independent PCs with per-thread IMEM region confinement (`{thread_id, offset[8:0]}`), halt gating (H1 fix: `!halted[thread_id]` stops PC advance), branch target override from ID stage, and IMEM instantiation with byte-to-word address conversion
3. **inst_mem.v** -- 512x32-bit true dual-port BRAM: Port A for CPU fetch (read-only), Port B for PCI program loading (read/write); standard Xilinx inference pattern
4. **ifid_reg.v** -- IF/ID pipeline register carrying instruction, PC+4, thread ID, and PC index; flush input retained but always 0 in FGMT (no branch penalties)
5. **ID.v** -- 64-entry register file (4 threads x 16 registers, thread-qualified addressing), ARM field extraction, rotated immediate computation, full 15-condition evaluator with C1 fix (cond_pass gates ALL write enables), control unit for DP/LDR/STR/B/BX, branch target computation (PC-relative and register-indirect), halt detection (`inst == 0xFFFFFFFF`)
6. **idex_reg.v** -- ID/EX pipeline register carrying data operands (3x64-bit), ALU control, shifter control, all MEM/WB control signals, thread ID, and PC index (~220 bits total)
7. **EX.v** -- Combinational execute stage: four 64-bit immediate shift functions (LSL/LSR/ASR/ROR), operand2 mux (register vs immediate), ALU instantiation, store data pass-through
8. **alu64.v** -- 64-bit ALU with behavioral arithmetic (`addsub64`) and logic (`logic64`) sub-modules, output mux for 12 supported opcodes (AND/EOR/SUB/ADD/TST/TEQ/CMP/CMN/ORR/MOV/BIC/MVN), and 64-bit CPSR flag generation
9. **addsub64.v** -- Behavioral 64-bit adder/subtractor using XOR inversion for 2's-complement subtraction and synthesis-inferred carry logic
10. **logic64.v** -- Behavioral 64-bit AND/OR/XNOR; replaces 192-gate structural design for synthesis optimization
11. **exmem_reg.v** -- EX/MEM pipeline register carrying ALU result, store data, CPSR flags (for processor.v update), and all MEM/WB control signals
12. **data_mem.v** -- DMEM stage with **three CPU Port A address windows**. Window 1 (`0x00..0x7F`) is the local DMEM array; Window 2 (`0x80..0xEF`) is the FIFO BRAM external port; Window 3 (`0xF0..0xFF`) aliases selected wrapper registers. `was_ext`, `was_reg`, and `reg_alias_rdata_r` align the 3:1 output mux with the 1-cycle read latency. The local array remains 256 words and host Port B can access all of it. The integrated MEM/WB registers, `skip_mem`, `dmem_rd`, and `doutb` still lack explicit reset in the current RTL.
13. **memwb_reg.v (WB)** -- Purely combinational writeback mux: `ctrl_mem2reg` selects between memory data (LDR) and ALU result (DP); outputs feed directly to ID register file write port with thread-qualified addressing
14. **logic_analyzer.v** -- 2048x64-bit dual-port BRAM trace buffer: Port A captures events (register writes, loads, stores) with packed MEM/WB stage metadata; Port B provides PCI readback for post-mortem debugging
