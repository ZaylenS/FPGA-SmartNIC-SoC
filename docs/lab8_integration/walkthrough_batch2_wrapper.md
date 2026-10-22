# Batch 2 — NF2.1 Wrapper + PCI Register Interface Walkthrough

> **Updated 2026-07-14:** Stale walkthrough content was reconciled with the current RTL implementation by Codex (GPT-5).

**Files covered:** `include/lab8_reg_defines.vh` → `src/user_data_path.v` → `src/lab8_wrapper.v`

This batch wraps the convertible FIFO into the NF2.1 infrastructure, adding the PCI register ring that lets the host PC control the FIFO and access its BRAM. Batch 3 later adds the CPU into this same wrapper; Batch 4 adds the GPU + DMA; the current checkpoint also includes a GPU cycle counter register.

> **Document history.** Captured 2026-03-25 against the Lab 8 baseline (commit `44baf38`). **Reconciled 2026-07-14 against the current checkpoint RTL in `src/lab8_wrapper.v`.**
>
> | Date       | Commit    | Refinement                                                                                                                                                        | Sections affected |
> | ---------- | --------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------- |
> | 2026-04-13 | `b4648bd` | GPU cycle counter PCI register (`LAB8_GPU_CYCLE_COUNT = 0x30`); readback mux refactored into a dedicated `always @*` block to prevent XST from trimming it.       | §1.5 (new), §2.8, §2.13 (new) |
> | 2026-07-14 | current checkpoint | Reconciled the ARM register-alias window, CPU BRAM[0] ctrl preservation, and soft-reset auto-clear now present in the current RTL. | §2.4, §2.7-§2.12, Summary |
>
> The 2026-04-13 BCAST refactor inside the GPU core does **not** touch this wrapper -- see `docs/lab7_gpu/walkthrough_batch4_execute_stage.md`.

---

## 1. lab8_reg_defines.vh — Register Address Map

### 1.1 NF2 System Constants

```verilog
`ifndef _LAB8_REG_DEFINES_VH_
`define _LAB8_REG_DEFINES_VH_       // Include guard — prevents double-definition
```

```verilog
`ifndef UDP_REG_ADDR_WIDTH
`define UDP_REG_ADDR_WIDTH    23     // NF2 register address is 23 bits total
`endif

`ifndef CPCI_NF2_DATA_WIDTH
`define CPCI_NF2_DATA_WIDTH   32     // PCI data bus is 32 bits
`endif
```

These are normally defined by the NF2 build system. The `ifndef` guards let us provide defaults for standalone simulation (iverilog) while the generated `registers.v` takes priority during synthesis.

### 1.2 Block Address Anatomy

```verilog
`ifndef LAB8_REG_ADDR_WIDTH
`define LAB8_REG_ADDR_WIDTH   6      // 6-bit word offset → 64 register slots
`endif

`ifndef LAB8_BLOCK_ADDR
`define LAB8_BLOCK_ADDR       17'h00011  // Block base address in NF2 register space
`endif
```

**How NF2 register addressing works:**

The 23-bit register address is split into two parts:
```
reg_addr[22:0] = { BLOCK_ADDR[16:0], word_offset[5:0] }
                   ^^^^^^^^^^^^^^^^   ^^^^^^^^^^^^^^^^
                   Which module       Which register within module
                   (17 bits)          (6 bits → 64 slots)
```

The NF2 register generator assigns BLOCK_ADDR based on `project.xml` memalloc order. Our module gets `17'h00011` (after `in_arb` at `17'h00010`). The PCI byte address formula:

```
PCI_byte_addr = BAR2 + reg_addr * 4
              = BAR2 + (BLOCK_ADDR << 6 | word_offset) * 4
              = BAR2 + (0x00011 << 6 | offset) * 4
              = BAR2 + (0x000440 | offset) * 4
```

With BAR2 = `0x2000000`: base = `0x2001100`, so register N is at `0x2001100 + N*4`.

### 1.3 FIFO Register Offsets (0x00–0x0B)

```verilog
`define LAB8_CTRL             6'h00   // RW  bit[0]=soft_reset
`define LAB8_STATUS           6'h01   // RO  {pkt_word_cnt, head, tail, empty, full, pkt_ready}
`define LAB8_FIFO_MODE        6'h02   // RW  mode[1:0]: 0=FIFO, 1=CPU, 2=GPU
`define LAB8_FIFO_DRAIN       6'h03   // RW  bit[0]=drain_start (auto-clear strobe)
```

**Control registers** (RW = software-writable, host writes and hardware reads):
- **CTRL[0]:** Soft reset — resets the FIFO state machine but not the BRAM contents
- **FIFO_MODE:** Selects who drives Port B (FIFO drain vs processor access)
- **FIFO_DRAIN:** One-shot strobe — hardware auto-clears after one cycle

**Status register** (RO = hardware-writable, hardware writes and host reads):
- Packs 6 fields into one 32-bit read for efficiency

```verilog
`define LAB8_BRAM_ADDR        6'h04   // RW  BRAM address [7:0]
`define LAB8_BRAM_WD_LO       6'h05   // RW  write data [31:0]
`define LAB8_BRAM_WD_HI       6'h06   // RW  write data [63:32]
`define LAB8_BRAM_WCTRL       6'h07   // RW  write ctrl [7:0]
`define LAB8_BRAM_CMD         6'h08   // RW  bit[0]=write strobe (auto-clear)
`define LAB8_BRAM_RD_LO       6'h09   // RO  read data [31:0]
`define LAB8_BRAM_RD_HI       6'h0A   // RO  read data [63:32]
`define LAB8_BRAM_RCTRL       6'h0B   // RO  read ctrl [7:0]
```

**BRAM indirect access:** PCI registers are 32-bit but BRAM words are 72-bit. We use an indirect access pattern:
1. Write address to `BRAM_ADDR`
2. For writes: write data to `WD_LO`, `WD_HI`, `WCTRL`, then strobe `CMD`
3. For reads: just write address to `BRAM_ADDR`, then read `RD_LO`, `RD_HI`, `RCTRL`

### 1.4 CPU Register Offsets (0x0C–0x1A, added in Batch 3)

```verilog
`define LAB8_CPU_CTRL          6'h0C   // RW  bit[0]=start_stop, bit[1]=cpu_reset
`define LAB8_CPU_STATUS        6'h0D   // RO  {all_halted, cpsr, thread_id, running, ~reset}
`define LAB8_CPU_IMEM_ADDR     6'h0E   // RW  IMEM address [8:0]
// ... (IMEM, DMEM, Logic Analyzer registers through 0x1A)
```

The 15 CPU offsets include direct CTRL/STATUS registers plus separate indirect IMEM, DMEM, and logic-analyzer address/data/command groups. See Batch 3 for the exact access sequence.

### 1.5 GPU + DMA + Cycle Counter Offsets (0x20–0x30)

The GPU and DMA registers were added by Batch 4; the cycle counter was added 2026-04-13 as a Lab 10 refinement. Full map:

```verilog
// GPU registers (0x20-0x2B) -- added in Batch 4
`define LAB8_GPU_CTRL            6'h20   // RW  bit[0]=gpu_reset (1=hold)
`define LAB8_GPU_STATUS          6'h21   // RO  bit[0]=kernel_done, bit[1]=dma_busy
`define LAB8_GPU_IMEM_ADDR       6'h22   // RW  IMEM word address [9:0]
`define LAB8_GPU_IMEM_WDATA      6'h23   // RW  IMEM write data [31:0]
`define LAB8_GPU_IMEM_CMD        6'h24   // RW  bit[0]=write strobe (auto-clears)
`define LAB8_GPU_IMEM_RDATA      6'h25   // RO  IMEM read data
`define LAB8_GPU_DMEM_ADDR       6'h26   // RW  DMEM word address [9:0]
`define LAB8_GPU_DMEM_WDATA_LO   6'h27   // RW  low 32-bit write data
`define LAB8_GPU_DMEM_WDATA_HI   6'h28   // RW  high 32-bit write data
`define LAB8_GPU_DMEM_CMD        6'h29   // RW  bit[0]=write strobe (auto-clears)
`define LAB8_GPU_DMEM_RDATA_LO   6'h2A   // RO  low 32-bit read data
`define LAB8_GPU_DMEM_RDATA_HI   6'h2B   // RO  high 32-bit read data

// DMA registers (0x2C-0x2F) -- added in Batch 4
`define LAB8_DMA_CTRL            6'h2C   // RW  bit[0]=start (auto-clears), bit[1]=dir
`define LAB8_DMA_FIFO_ADDR       6'h2D   // RW  FIFO BRAM start address [7:0]
`define LAB8_DMA_GPU_ADDR        6'h2E   // RW  GPU DMEM start address [9:0]
`define LAB8_DMA_LENGTH          6'h2F   // RW  word count [7:0]

// GPU cycle counter (0x30) -- added 2026-04-13
`define LAB8_GPU_CYCLE_COUNT     6'h30   // RO  GPU cycles from reset-release to kernel_done
```

**Why a dedicated cycle counter register?** Host polling includes PCI-ring and software latency. This counter instead measures in the `core_clk` domain: asserted `gpu_reset` clears/re-arms it, and it increments while armed until it samples `kernel_done`. That gives cycle-level hardware measurement without attributing host polling delay to the kernel. Recorded BCAST/scalar results use this register, but the exact historical host-jitter figure is not established by the RTL.

**Note on 6-bit address width.** `LAB8_REG_ADDR_WIDTH = 6` (see §1.2), so the register space ends at 0x3F. Offsets 0x31..0x3F are currently unallocated.

**Generated-header consistency issue:** `include/lab8.xml` and `include/lab8_reg_defines.vh` include `GPU_CYCLE_COUNT`, but the checked-in generated `include/registers.v` stops this block at `DMA_LENGTH`. The guarded local definition keeps the current RTL compilable, but `registers.v` is stale relative to the XML and should not be used as evidence that offset 0x30 is absent.

---

## 2. lab8_wrapper.v — The Integrated NF2.1 Datapath Stage

`user_data_path.v` is the NF2 datapath top level. It instantiates `lab8_wrapper` between `output_port_lookup` and `output_queues`; the wrapper stage wires together:
- The convertible FIFO (Batch 1)
- The ARM processor (Batch 3)
- The GPU and bidirectional DMA engine (Batch 4)
- The PCI register ring (NF2.1 protocol)
- The GPU cycle counter

### 2.1 Module Parameters and Ports

```verilog
module lab8_wrapper
   #(
      parameter DATA_WIDTH = 64,              // NF2.1 data bus width
      parameter CTRL_WIDTH = DATA_WIDTH/8,    // 8 bytes → 8-bit ctrl
      parameter UDP_REG_SRC_WIDTH = 2         // Register ring source ID width
   )
   (
      // --- NF2.1 data path ---
      input  [DATA_WIDTH-1:0]             in_data,   // 64-bit packet data from upstream
      input  [CTRL_WIDTH-1:0]             in_ctrl,   // 8-bit control from upstream
      input                               in_wr,     // Write strobe from upstream
      output                              in_rdy,    // Backpressure to upstream
```

The data path ports connect directly to the NF2.1 pipeline. Our module sits between `output_port_lookup` and `output_queues`.

```verilog
      // --- Register ring (NF2.1 UDP) ---
      input                               reg_req_in,      // Request from upstream in ring
      input                               reg_ack_in,      // Acknowledgement from upstream
      input                               reg_rd_wr_L_in,  // 1=read, 0=write
      input  [`UDP_REG_ADDR_WIDTH-1:0]    reg_addr_in,     // 23-bit register address
      input  [`CPCI_NF2_DATA_WIDTH-1:0]   reg_data_in,     // 32-bit data
      input  [UDP_REG_SRC_WIDTH-1:0]      reg_src_in,      // Source module ID

      output                                  reg_req_out,   // Pass to downstream in ring
      output                                  reg_ack_out,
      output                                  reg_rd_wr_L_out,
      output [`UDP_REG_ADDR_WIDTH-1:0]        reg_addr_out,
      output [`CPCI_NF2_DATA_WIDTH-1:0]       reg_data_out,
      output [UDP_REG_SRC_WIDTH-1:0]          reg_src_out,
```

**NF2 register ring protocol:** Register requests travel around a ring of modules. Each module checks if the address matches its block. If yes, it handles the read/write and sets `ack`. If no, it passes the request to the next module unchanged.

### 2.2 Address Decode

```verilog
   wire block_match = (reg_addr_in[`UDP_REG_ADDR_WIDTH-1:`LAB8_REG_ADDR_WIDTH]
                        == `LAB8_BLOCK_ADDR);
```

Compare the upper 17 bits of the incoming address against our block address. If they match, this register request is for us.

```verilog
   wire [`LAB8_REG_ADDR_WIDTH-1:0] local_offset =
        reg_addr_in[`LAB8_REG_ADDR_WIDTH-1:0];
```

Extract the lower 6 bits as the register offset within our block.

### 2.3 Convertible FIFO Instantiation

```verilog
   // Soft reset: system reset OR register-controlled reset
   wire soft_reset;
```

```verilog
   convertible_fifo u_fifo (
      .clk           (clk),
      .reset         (soft_reset),        // System reset OR CTRL[0] soft reset
      // NF2.1 data path — direct pass-through
      .in_data       (in_data),           // From upstream → FIFO Port A
      .in_ctrl       (in_ctrl),
      .in_wr         (in_wr),
      .in_rdy        (in_rdy),            // FIFO → upstream (backpressure)
      .out_data      (out_data),          // FIFO → downstream
      .out_ctrl      (out_ctrl),
      .out_wr        (out_wr),
      .out_rdy       (out_rdy),           // From downstream (backpressure)
      // Processor access port — MUXed among PCI, CPU, and DMA
      .proc_addr     (fifo_proc_addr),    // ← set by proc port MUX
      .proc_din      (fifo_proc_din),     // ← set by proc port MUX
      .proc_we       (fifo_proc_we),      // ← set by proc port MUX
      .proc_dout     (fifo_proc_dout),    // → consumed by PCI, CPU, or DMA
      // Control — from wrapper registers (PCI or exposed ARM aliases)
      .mode          (fifo_mode),
      .drain_start   (fifo_drain_start),
      // Status — to wrapper status readback (PCI and ARM alias)
      .pkt_ready     (fifo_pkt_ready),
      .fifo_full     (fifo_full),
      .fifo_empty    (fifo_empty),
      .pkt_word_cnt  (fifo_pkt_word_cnt),
      // Head/tail — not used (tied off)
      .head_wr_val   (8'd0),
      .head_wr_en    (1'b0),
      .tail_wr_val   (8'd0),
      .tail_wr_en    (1'b0),
      .head_rd       (fifo_head_rd),
      .tail_rd       (fifo_tail_rd)
   );
```

### 2.4 Proc Port MUX — PCI vs CPU vs DMA

The wrapper first chooses one of three sources for the FIFO's `proc_*` bus: CPU, DMA, or PCI. `convertible_fifo.v` then applies a second mux: in mode 0, physical BRAM Port B ignores `proc_*` and is driven by the drain pointer; in modes 1 and 2, it uses the selected proc bus.

```verilog
   wire cpu_drives_proc = (reg_fifo_mode_r[1:0] == 2'd1) && cpu_running;
   wire dma_drives_proc = (reg_fifo_mode_r[1:0] == 2'd2) && dma_active;
```

**Who owns physical Port B?** Combining both muxes gives:

| Mode | CPU running? | DMA active? | Port B driver |
|------|--------------|-------------|---------------|
| 0 (FIFO) | -- | -- | FIFO drain pointer/FSM |
| 1 (CPU)  | Yes | -- | CPU MEM stage |
| 1 (CPU)  | No | -- | PCI indirect registers |
| 2 (GPU)  | -- | Yes | DMA engine |
| 2 (GPU)  | -- | No | PCI indirect registers |

The current wrapper derives a ctrl byte for ARM stores. FIFO BRAM index 0 receives `0xFF`, preserving the NF2.1 header marker when firmware rewrites the header; all other ARM-written words receive `0x00`.

```verilog
   reg [7:0] arm_bram_wctrl;
   always @(*) begin
      if (cpu_ext_mem_addr[6:0] == 7'h00)
         arm_bram_wctrl = 8'hFF;
      else
         arm_bram_wctrl = 8'h00;
   end

   always @(*) begin
      fifo_mode        = reg_fifo_mode_r[1:0];
      fifo_drain_start = reg_fifo_drain[0];

      if (cpu_drives_proc) begin
         fifo_proc_addr = cpu_ext_mem_addr;
         fifo_proc_din  = {arm_bram_wctrl, cpu_ext_mem_din};
         fifo_proc_we   = cpu_ext_mem_we;
      end else if (dma_drives_proc) begin
         // DMA path -- see batch 4 section 3.4 for the FSM
         // (FIFO->GPU vs GPU->FIFO direction handled in dma_dir branch)
         ...
      end else begin
         fifo_proc_addr = reg_bram_addr[7:0];
         fifo_proc_din  = {reg_bram_wctrl[7:0], reg_bram_wd_hi, reg_bram_wd_lo};
         fifo_proc_we   = bram_pci_wr_strobe;
      end
   end
```

**Why the ctrl byte matters.** The convertible FIFO stores 72-bit words = `{ctrl[7:0], data[63:0]}`. On drain, the FIFO emits `ctrl=0xFF` to mark the start-of-packet header and `ctrl=0x00` for subsequent data words; the downstream `output_queues` uses that ctrl byte for packet framing. The current ARM path reconstructs those two values from the FIFO index: index 0 gets `0xFF`, and every other index gets `0x00`. The DMA write path still prepends `8'h00`; the PCI indirect path can choose any ctrl byte through `reg_bram_wctrl`.

**Width adaptation for each path:**
- **CPU path:** CPU outputs 64-bit data -> wrapper prepends `arm_bram_wctrl` (`0xFF` at FIFO index 0, else `0x00`) -> 72-bit to BRAM. Reverse path: `cpu_ext_mem_dout = fifo_proc_dout[63:0]`.
- **DMA path:** DMA transfers only the 64-bit data half. FIFO-to-GPU discards `ctrl`; GPU-to-FIFO prepends `8'h00`. It neither preserves nor reconstructs packet framing.
- **PCI path:** PCI writes assemble `{wctrl, wd_hi, wd_lo}` from three 32-bit regs and use the registered `bram_pci_wr_strobe`; PCI reads split `proc_dout` into `RD_LO[31:0]`, `RD_HI[63:32]`, `RCTRL[7:0]`.

### 2.5 Software-Writable Registers

```verilog
   // FIFO registers
   reg [31:0] reg_ctrl;            // 0x00: bit[0]=soft_reset
   reg [31:0] reg_fifo_mode_r;     // 0x02: mode[1:0]
   reg [31:0] reg_fifo_drain;      // 0x03: bit[0]=drain_start
   reg [31:0] reg_bram_addr;       // 0x04: BRAM address
   reg [31:0] reg_bram_wd_lo;      // 0x05: write data low
   reg [31:0] reg_bram_wd_hi;      // 0x06: write data high
   reg [31:0] reg_bram_wctrl;      // 0x07: write ctrl
   reg [31:0] reg_bram_cmd;        // 0x08: bit[0]=write strobe

   // CPU registers (Batch 3)
   reg [31:0] reg_cpu_ctrl;        // 0x0C: bit[0]=start_stop, bit[1]=cpu_reset
   // ... (13 more CPU registers)
```

Each listed register is a 32-bit flip-flop writable by the PCI host. A defined subset is also writable by the ARM through the register-alias window described in §2.11.

### 2.6 Hardware-Readable (Status) Registers

```verilog
   wire [31:0] reg_status = {fifo_pkt_word_cnt,    // [31:24] word count
                             fifo_head_rd,          // [23:16] head pointer
                             fifo_tail_rd,          // [15:8]  tail pointer
                             5'd0,                  // [7:3]   reserved
                             fifo_empty,            // [2]
                             fifo_full,             // [1]
                             fifo_pkt_ready};       // [0]
```

Status is packed into a single 32-bit word so the host can read all status in one PCI access.

```verilog
   wire [31:0] reg_bram_rd_lo  = fifo_proc_dout[31:0];      // BRAM data bits [31:0]
   wire [31:0] reg_bram_rd_hi  = fifo_proc_dout[63:32];     // BRAM data bits [63:32]
   wire [31:0] reg_bram_rctrl  = {24'd0, fifo_proc_dout[71:64]};  // BRAM ctrl byte
```

BRAM readback splits the 72-bit `proc_dout` into three 32-bit registers. The host reads them separately.

### 2.7 Control Signal Wiring

```verilog
   assign soft_reset = reset | reg_ctrl[0];   // System reset OR soft reset register
```

Soft reset resets the FIFO state machine (pointers, state, `pkt_stored`) but not BRAM contents. `CTRL[0]` auto-clears, so either the host or ARM alias needs only write a one-cycle command value of `1`.

```verilog
   assign cpu_running = reg_cpu_ctrl[0];       // bit[0] = start_stop
   assign cpu_reset   = reset | reg_cpu_ctrl[1]; // bit[1] = cpu_reset
```

CPU control uses two bits of one register. Writing `0x2` asserts reset. Writing `0x1` releases reset AND starts the CPU atomically (critical for avoiding Bug #1).

### 2.8 Register Ring State Machine

> **Refined 2026-04-13 (commit `b4648bd`).** The 40+entry read-mux used to live *inside* the clocked write-path `always @(posedge clk)` block (an `else { case ... }` branch under `if (!reg_rd_wr_L_in) ... else ...`). When that block was synthesised on 2026-04-11, XST decided `reg_rd_data` was assigned only inside a deeply nested conditional and **trimmed the register**. Symptom: every PCI read returned `0xDEADBEEF`, every status check looked broken.
>
> The fix was to split the mux out into its own `always @*` (combinational) block, with a separate clocked flop that latches the muxed value when the wrapper recognises a read request. Functionally equivalent; structurally something XST can't dismiss. The clocked block below now only handles ring-pass-through and *write* dispatch.

#### Two-stage readback (combinational mux + clocked flop)

```verilog
   reg [`CPCI_NF2_DATA_WIDTH-1:0]   reg_rd_data;
   reg [`CPCI_NF2_DATA_WIDTH-1:0]   reg_rd_data_mux;

   // (1) Combinational mux -- one case arm per register
   always @* begin
      case (reg_addr_in[`LAB8_REG_ADDR_WIDTH-1:0])
         `LAB8_CTRL:              reg_rd_data_mux = reg_ctrl;
         `LAB8_STATUS:            reg_rd_data_mux = reg_status;
         `LAB8_FIFO_MODE:         reg_rd_data_mux = reg_fifo_mode_r;
         `LAB8_FIFO_DRAIN:        reg_rd_data_mux = reg_fifo_drain;
         // ... BRAM, CPU, GPU, DMA registers ...
         `LAB8_GPU_CYCLE_COUNT:   reg_rd_data_mux = reg_gpu_cycle_count;   // Added 2026-04-13
         default:                 reg_rd_data_mux = 32'hDEAD_BEEF;
      endcase
   end

   // (2) Dedicated sequential flop. When we own the request, latch the
   //     combinational mux output; otherwise pass through the upstream bus.
   always @(posedge clk) begin
      if (reset) begin
         reg_rd_data <= 32'd0;
      end
      else if (reg_req_in && !reg_ack_in && block_match && reg_rd_wr_L_in) begin
         reg_rd_data <= reg_rd_data_mux;
      end
      else begin
         reg_rd_data <= reg_data_in;
      end
   end
```

**`default: 32'hDEAD_BEEF`** is the canary. If you ever see `0xDEADBEEF` on a register that *should* exist, two possibilities: (a) wrong address, or (b) the register hasn't been added to the mux yet. The 2026-04-11 trimmed-mux bug made *every* read return this value -- which is how it got caught immediately.

**Why the read-request guard is so specific.** The combinational mux runs every cycle, but we only want to *capture* its output when the upstream NF2 ring is asking us for a read. The four conditions:
- `reg_req_in` -- there IS a pending request
- `!reg_ack_in` -- nobody upstream already handled it
- `block_match` -- the address is in our block (see §2.2)
- `reg_rd_wr_L_in` -- it's a read (not a write; writes are handled in the clocked block below)

If any of those is false, the flop captures `reg_data_in` instead -- which is whatever the upstream module already put on the ring. This is how requests pass through unchanged.

#### Clocked block: ring pass-through + write dispatch

```verilog
   always @(posedge clk) begin
      if (reset) begin
         // Reset wrapper registers (most to 0; GPU_CTRL resets to 1 to hold GPU reset)
         reg_ctrl         <= 32'd0;
         reg_fifo_mode_r  <= 32'd0;
         reg_gpu_ctrl     <= 32'h0000_0001;
         // ... remaining wrapper-owned registers reset to their documented defaults ...
         reg_req_held     <= 1'b0;
         reg_ack_held     <= 1'b0;
         reg_rd_wr_L_held <= 1'b0;
         reg_addr_held    <= {`UDP_REG_ADDR_WIDTH{1'b0}};
         reg_src_held     <= {UDP_REG_SRC_WIDTH{1'b0}};
      end
      else begin
         // --- Latch incoming request (1-cycle ring pipeline) ---
         reg_req_held     <= reg_req_in;
         reg_ack_held     <= reg_ack_in;
         reg_rd_wr_L_held <= reg_rd_wr_L_in;
         reg_addr_held    <= reg_addr_in;
         reg_src_held     <= reg_src_in;
         // NOTE: reg_rd_data is NOT assigned here -- see the dedicated flop above.

         if (reg_req_in && !reg_ack_in && block_match) begin
            reg_ack_held <= 1'b1;              // "I handled this request"

            if (!reg_rd_wr_L_in) begin
               // === WRITE === host data -> register flip-flop
               case (local_offset)
                  `LAB8_CTRL:              reg_ctrl           <= reg_data_in;
                  `LAB8_FIFO_MODE:         reg_fifo_mode_r    <= reg_data_in;
                  `LAB8_FIFO_DRAIN:        reg_fifo_drain     <= reg_data_in;
                  `LAB8_BRAM_ADDR:         reg_bram_addr      <= reg_data_in;
                  // ... BRAM_WD_LO/HI, BRAM_WCTRL, BRAM_CMD, CPU_*, GPU_*, DMA_* ...
                  default: ;               // Unknown offset -- ignore
               endcase
            end
            // Note: there is NO read-side branch here any more. Reads are
            // entirely handled by the combinational mux + dedicated flop above.
         end else if (cpu_reg_we) begin
            // ARM-side writes through DMEM addresses 0xF0..0xFF.
            // PCI has priority through the outer if branch above.
            case (cpu_reg_sel)
               4'h0: reg_dma_ctrl       <= cpu_reg_wdata[31:0];
               4'h1: reg_dma_fifo_addr  <= cpu_reg_wdata[31:0];
               4'h2: reg_dma_gpu_addr   <= cpu_reg_wdata[31:0];
               4'h3: reg_dma_length     <= cpu_reg_wdata[31:0];
               4'h4: reg_gpu_ctrl       <= cpu_reg_wdata[31:0];
               4'h7: reg_fifo_mode_r    <= cpu_reg_wdata[31:0];
               4'h8: reg_ctrl           <= cpu_reg_wdata[31:0];
               4'hA: reg_fifo_drain     <= cpu_reg_wdata[31:0];
               default: ;
            endcase
         end
```

The clocked block has two write sources. A matching PCI/NF2-ring request is handled first; only when that branch is inactive can `cpu_reg_we` update an ARM-exposed alias. Thus a simultaneous accepted PCI access has priority. Read-only and reserved ARM alias slots fall through `default` and ignore writes.

### 2.9 Auto-Clear Strobes

```verilog
         // --- Auto-clear strobes ---
         if (reg_fifo_drain[0])    reg_fifo_drain[0]    <= 1'b0;
         if (reg_bram_cmd[0])      reg_bram_cmd[0]      <= 1'b0;
         if (reg_cpu_imem_cmd[0])  reg_cpu_imem_cmd[0]  <= 1'b0;
         if (reg_cpu_dmem_cmd[0])  reg_cpu_dmem_cmd[0]  <= 1'b0;
         if (reg_gpu_imem_cmd[0])  reg_gpu_imem_cmd[0]  <= 1'b0;
         if (reg_gpu_dmem_cmd[0])  reg_gpu_dmem_cmd[0]  <= 1'b0;
         if (reg_dma_ctrl[0])      reg_dma_ctrl[0]      <= 1'b0;
         if (reg_ctrl[0])          reg_ctrl[0]          <= 1'b0;
```

**Why auto-clear?** Command registers (drain, write commands, DMA start, soft reset) should be active for exactly 1 cycle. The host or ARM writes `1`, hardware sees it for one clock, then auto-clears to `0`. Without auto-clear, software would need to follow every `1` with an immediate `0`.

The current wrapper therefore has eight auto-cleared command bits: FIFO drain, FIFO BRAM write, CPU IMEM/DMEM writes, GPU IMEM/DMEM writes, DMA start, and FIFO soft reset. This also makes ARM alias writes to DMA start, FIFO drain, and soft reset one-shot commands.

### 2.10 Ring Output

```verilog
   assign reg_req_out     = reg_req_held;
   assign reg_ack_out     = reg_ack_held;
   assign reg_rd_wr_L_out = reg_rd_wr_L_held;
   assign reg_addr_out    = reg_addr_held;
   assign reg_data_out    = reg_rd_data;     // ← May be our mux output (read) or pass-through
   assign reg_src_out     = reg_src_held;
```

All signals pass through the 1-cycle register pipeline. If we handled a read, `reg_data_out` contains the value from the §2.8 mux; otherwise it passes through the original data from upstream.

### 2.11 ARM Register-Alias Window

ARM DMEM addresses `0xF0..0xFF` are a third memory window. `data_mem.v` exports the low address nibble as `reg_alias_sel`, store data as `reg_alias_wdata`, and a gated write enable; `processor.v` passes that bundle to the wrapper:

```verilog
      .reg_alias_sel  (cpu_reg_sel),
      .reg_alias_wdata(cpu_reg_wdata),
      .reg_alias_we   (cpu_reg_we),
      .reg_alias_rdata(cpu_reg_rdata),
```

The current slot map is:

| ARM address | Slot | Wrapper register | Access |
|-------------|------|------------------|--------|
| `0xF0` | 0 | `DMA_CTRL` | RW |
| `0xF1` | 1 | `DMA_FIFO_ADDR` | RW |
| `0xF2` | 2 | `DMA_GPU_ADDR` | RW |
| `0xF3` | 3 | `DMA_LENGTH` | RW |
| `0xF4` | 4 | `GPU_CTRL` | RW |
| `0xF5` | 5 | `GPU_STATUS` | RO |
| `0xF6` | 6 | `FIFO_STATUS` | RO |
| `0xF7` | 7 | `FIFO_MODE` | RW |
| `0xF8` | 8 | `CTRL` (FIFO soft reset) | RW |
| `0xF9` | 9 | `GPU_CYCLE_COUNT` | RO |
| `0xFA` | A | `FIFO_DRAIN` | RW |
| `0xFB..0xFF` | B..F | Reserved (reads zero; writes ignored) | -- |

Readback is a combinational two-level mux in `lab8_wrapper.v`; `data_mem.v` captures that value so it aligns with the one-cycle MEM read path. Each implemented value is zero-extended from 32 to 64 bits.

### 2.12 Register Access Ownership

The PCI/NF2 register ring can access the complete register map. The ARM alias exposes only the eleven slots listed above, which are sufficient for firmware to configure/start DMA, release or reset the GPU, poll GPU/FIFO status, select FIFO mode, read the cycle count, soft-reset the FIFO, and trigger drain. PCI writes take priority if a PCI access and `cpu_reg_we` coincide. Alias writes to the RO status/counter slots or reserved slots are silently ignored.


### 2.13 GPU Cycle Counter (added 2026-04-13)

```verilog
   reg [31:0] gpu_cycle_count;
   reg        gpu_count_armed;

   always @(posedge clk) begin
      if (reset || gpu_reset) begin
         gpu_cycle_count <= 32'd0;
         gpu_count_armed <= 1'b1;
      end else if (gpu_count_armed) begin
         gpu_cycle_count <= gpu_cycle_count + 32'd1;
         if (gpu_kernel_done)
            gpu_count_armed <= 1'b0;
      end
   end

   wire [31:0] reg_gpu_cycle_count = gpu_cycle_count;
```

**Three-state counter:**
1. **Reset.** Either `reset` (system) or asserted `gpu_reset` clears the count and re-arms it.
2. **Counting.** While `gpu_count_armed`, every `core_clk` cycle adds 1.
3. **Frozen.** On the edge that samples `gpu_kernel_done` while armed, the nonblocking counter increment still occurs and `gpu_count_armed` clears. Subsequent cycles do not increment.

The result is read at register `0x30` (`LAB8_GPU_CYCLE_COUNT`). It counts armed clock edges after GPU reset is released, whether by PCI or the ARM alias, through the edge that samples `kernel_done`. Comparisons to a testbench counter require using the same edge convention.

**Use case.** The BCAST vs scalar IDS speedup: scalar kernel = 2402 cycles; BCAST kernel = 732 cycles. Reading `0x30` after each run lets the host print "732 / 2402 = 3.28×" without instrumenting either kernel.

---

## 3. PCI Access Pattern — How the Host Reads/Writes BRAM

These recipes require physical BRAM Port B to select the proc bus: use mode 1 with the CPU stopped, or mode 2 with DMA idle. In mode 0, the FIFO drain pointer owns Port B and the PCI-selected `proc_*` address/data are ignored.

### 3.1 Write one 72-bit BRAM word

```
Host sends 5 PCI writes in sequence:
  regwrite(BRAM_ADDR,  addr)        → reg_bram_addr = addr
  regwrite(BRAM_WD_LO, lo32)        → reg_bram_wd_lo = lo32
  regwrite(BRAM_WD_HI, hi32)        → reg_bram_wd_hi = hi32
  regwrite(BRAM_WCTRL, ctrl8)       → reg_bram_wctrl = ctrl8
  regwrite(BRAM_CMD,   0x1)         → reg_bram_cmd[0] = 1 (auto-clears next cycle)
```

When the host writes `BRAM_CMD=1`, the wrapper captures that PCI write into `bram_pci_wr_strobe`. On the strobe cycle, assuming PCI owns the proc port, `fifo_proc_we` goes HIGH and the BRAM writes `{ctrl8, hi32, lo32}` at address `addr`.

### 3.2 Read one 72-bit BRAM word

```
Host sends 1 write + 3 reads:
  regwrite(BRAM_ADDR, addr)          → reg_bram_addr = addr (BRAM starts reading)
  regread(BRAM_ADDR)                 → bus turnaround (ensures BRAM latency elapsed)
  regread(BRAM_RD_LO)               → returns fifo_proc_dout[31:0]
  regread(BRAM_RD_HI)               → returns fifo_proc_dout[63:32]
  regread(BRAM_RCTRL)               → returns fifo_proc_dout[71:64]
```

The dummy `regread(BRAM_ADDR)` ensures the BRAM's 1-cycle read latency has elapsed before reading the output registers.

---

## Summary - What Batch 2 Establishes (current as of 2026-07-14)

1. **lab8_reg_defines.vh** - the address map: 44 implemented registers across FIFO (0x00-0x0B), CPU (0x0C-0x1A), GPU (0x20-0x2B), DMA (0x2C-0x2F), and the cycle counter (0x30). `lab8.xml` allocates 49 slots because offsets 0x1B-0x1F are reserved.
2. **lab8_wrapper.v** - the NF2.1 integration:
   - Register ring state machine: 1-cycle pipeline, `block_match` decode, two-stage readback (combinational mux + dedicated flop) -- refactored 2026-04-13 to survive XST.
   - Nested Port B ownership: the wrapper selects CPU/DMA/PCI for `proc_*`, while `convertible_fifo` selects its drain pointer in mode 0 and the proc bus in modes 1/2. ARM writes use `ctrl=0xFF` at FIFO index 0 and `0x00` elsewhere; DMA writes prepend `8'h00`; PCI writes choose the ctrl byte through `BRAM_WCTRL`.
   - Eight auto-clear command bits: drain, BRAM/CPU/GPU write commands, DMA start, and `CTRL[0]` FIFO soft reset.
   - 72-bit <-> 32-bit width adaptation for PCI indirect access.
   - Soft reset, CPU control signal wiring.
   - **GPU cycle counter** (`0x30`) -- 32-bit counter from `gpu_reset` deassertion until `kernel_done` (added 2026-04-13).
   - ARM register aliases at CPU addresses `0xF0..0xFA`, including RO GPU/FIFO status and cycle count plus RW DMA/GPU/FIFO controls; PCI retains priority on coincident accesses.

**Refinement timeline for this file:**
- **2026-03-25** baseline -- FIFO + register ring + soft reset (Batch 2 originally).
- **Later batches at the same time** -- Batch 3 added CPU integration; Batch 4 added GPU + DMA + extended proc-port mux to 3-way.
- **2026-04-13 (commit `b4648bd`)** -- GPU cycle counter + readback mux refactor.
- **2026-07-14 reconciliation** -- restored the current ARM register-alias window, CPU BRAM[0] ctrl preservation, and soft-reset auto-clear descriptions from the checked-in RTL.

**Next batch:** ARM CPU integration (`processor.v`, `data_mem.v`, `IF_stage.v`).
