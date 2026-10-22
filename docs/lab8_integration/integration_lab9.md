# Lab 9 Integration Guide -- How We Connected ARM + GPU to the Convertible FIFO

This document explains exactly how Lab 8 integrated the ARM CPU and GPU coprocessor
with the convertible FIFO inside the NF2.1 data path wrapper. It was originally
written as a reference for the Lab 9 subgroup handoff; it now also serves as the
top-down architecture summary for the Lab 10 final-project state.

> **Refreshed 2026-05-17 to reflect every refinement since the Lab 9 handoff.** The §1-§10 narrative still matches the design's *spine* — the FIFO + 3-way Port B mux + ARM + GPU + DMA. Two later refinement bundles bolted features onto that spine without altering it:
>
> | Date       | Commit    | Refinement                                                                                                             | Sections updated below |
> | ---------- | --------- | ---------------------------------------------------------------------------------------------------------------------- | ----------------------- |
> | 2026-04-13 | `b4648bd` | GPU cycle counter PCI register (`0x30`); readback mux refactor to survive XST                                          | §8 |
> | 2026-04-13 | `e14d012` | BCAST cross-lane SIMD instruction + simd_alu pipeline restructure (GPU-core internal; integration interface unchanged) | §5.2 (note only)        |
> | 2026-05-10 | `942decf` | ARM register-alias window (16 slots at DMEM `0xF0..0xFF`); Fix B (BRAM[0] ctrl=0xFF); soft-reset auto-clear            | §4.2, §4.3, §7.1, §8 (new §8.X) |

All code references are from the current (`HEAD`) Lab 10 codebase. The key files are:

| File | Role |
|------|------|
| `src/lab8_wrapper.v` | Top-level integration wrapper (instantiates everything) |
| `src/fifo/convertible_fifo.v` | Packet-buffering FIFO with processor access port |
| `src/fifo/fifo_bram.v` | 256x72 true dual-port BRAM |
| `src/arm/processor.v` | ARM CPU top-level (5-stage pipeline, quad-thread) -- gained `reg_alias_*` ports 2026-05-10 |
| `src/arm/data_mem.v` | CPU MEM stage with FIFO BRAM and register-alias windows -- refined 2026-05-10 |
| `src/gpu/gpu_top.v` | GPU top-level (SIMD core + IMEM + DMEM) -- interface unchanged since Lab 8 |
| `include/lab8_reg_defines.vh` | PCI register address map -- added `0x30` 2026-04-13 |
| `include/gpu_params.vh` | GPU sizing parameters -- added `OP_BCAST`, `ALU_BCAST` 2026-04-13 |

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [The Convertible FIFO](#2-the-convertible-fifo)
3. [Mode System (0=FIFO, 1=CPU, 2=GPU)](#3-mode-system)
4. [CPU-FIFO Integration (Mode 1)](#4-cpu-fifo-integration-mode-1)
5. [GPU-FIFO Integration (Mode 2)](#5-gpu-fifo-integration-mode-2)
6. [The DMA Engine](#6-the-dma-engine)
7. [Port Muxes in the Wrapper](#7-port-muxes-in-the-wrapper)
8. [PCI Register Interface](#8-pci-register-interface)
9. [Operational Sequences](#9-operational-sequences)
10. [Lessons Learned / Pitfalls](#10-lessons-learned--pitfalls)
11. [What to Adapt for Lab 9](#11-what-to-adapt-for-lab-9)

---

## 1. Architecture Overview

The wrapper sits in the NF2.1 pipeline between `output_port_lookup` and
`output_queues`. It intercepts network packets, lets the CPU and/or GPU
process them, then drains the (possibly modified) packet downstream.

```
                    lab8_wrapper.v
  8-byte   +--------------------------------------------------+   8-byte
  data in  |  Convertible FIFO (256x72 dual-port BRAM)        |   data out
 --------->|    Port A: network write (packet capture)         |---------->
  ctrl in  |    Port B: processor access (muxed)               |   ctrl out
 --------->|                                                   |---------->
           |  +----------+                  +----------------+ |
           |  | ARM CPU  |--- ext_mem ----->|  3-way MUX     | |
           |  | (Lab 6)  |                  |  (PCI/CPU/DMA) |-|---> Port B
           |  +----------+                  +-------|--------+ |
           |                                        |          |
           |  +----------+     DMA engine           |          |
           |  | GPU SIMD |<--- FIFO<->GPU --------->|          |
           |  | (Lab 7)  |    copy engine           |          |
           |  +----------+                          |          |
           |                                        |          |
           |  PCI registers <--- NF2 register ring  |          |
           +--------------------------------------------------+
```

Key idea: the FIFO BRAM has two ports. Port A is always owned by the FIFO
state machine (network input/output). Port B is shared via a 3-way mux
among PCI register access, CPU ext_mem, and DMA engine. The `mode` register
selects who gets Port B.

---

## 2. The Convertible FIFO

**File:** `src/fifo/convertible_fifo.v`

The FIFO buffers exactly one NF2.1 network packet in a 256x72-bit dual-port
BRAM. Each word is 72 bits: 8-bit ctrl + 64-bit data (matching the NF2.1 bus
width).

### 2.1 Port Interface

```verilog
// src/fifo/convertible_fifo.v lines 16-55
module convertible_fifo (
    input         clk,
    input         reset,

    // NF2.1 input (from upstream module)
    input  [63:0] in_data,
    input  [7:0]  in_ctrl,
    input         in_wr,
    output        in_rdy,

    // NF2.1 output (to downstream module)
    output [63:0] out_data,
    output [7:0]  out_ctrl,
    output        out_wr,
    input         out_rdy,

    // Processor access port (directly from CPU MEM stage or GPU)
    input  [7:0]  proc_addr,
    input  [71:0] proc_din,
    input         proc_we,
    output [71:0] proc_dout,

    // Control
    input  [1:0]  mode,         // 0=FIFO, 1=CPU, 2=GPU
    input         drain_start,  // strobe: begin draining buffered packet

    // Status
    output        pkt_ready,    // one packet fully buffered
    output        fifo_full,    // cannot accept more input
    output        fifo_empty,
    output [7:0]  pkt_word_cnt, // words in buffered packet

    // Head/tail register access (for processor)
    input  [7:0]  head_wr_val,
    input         head_wr_en,
    input  [7:0]  tail_wr_val,
    input         tail_wr_en,
    output [7:0]  head_rd,
    output [7:0]  tail_rd
);
```

### 2.2 State Machine

```
  IDLE --> RECEIVING --> PKT_BUFFERED --> DRAIN_WAIT1 --> DRAIN_WAIT2 --> DRAINING --> IDLE
   ^                         |                                              |
   |                   (CPU/GPU works                                       |
   |                    on BRAM here)                                       |
   +------------------------------------------------------------------------+
```

- **S_IDLE (0):** Waiting for a packet. When `in_wr && in_ctrl != 0` (header
  word arrives), captures `word_length` from `in_data[39:32]`, starts writing
  to BRAM at wr_ptr=0.
- **S_RECEIVING (1):** Counts down `words_remaining`. Each `in_wr` writes
  the next word to BRAM via Port A.
- **S_PKT_BUFFERED (2):** Packet fully stored. **This is where CPU/GPU
  access happens.** The FIFO holds the packet in BRAM and waits for
  `drain_start` to be pulsed.
- **S_DRAIN_WAIT1 (3):** BRAM read pipeline stage 1 (address presented).
- **S_DRAIN_WAIT2 (4):** BRAM read pipeline stage 2 (data latched).
- **S_DRAINING (5):** Outputs words to the downstream NF2.1 module via
  `out_data/out_ctrl/out_wr`, with backpressure support via `out_rdy`.

### 2.3 Port A: Network Side (Always FIFO-Owned)

Port A is dedicated to writing incoming packet words. It is only active
during S_IDLE and S_RECEIVING:

```verilog
// src/fifo/convertible_fifo.v lines 123-135
wire fifo_wr_active = in_wr && in_rdy;

always @(*) begin
    if (fifo_wr_active) begin
        bram_addr_a = wr_ptr;
        bram_din_a  = {in_ctrl, in_data};
        bram_we_a   = 1'b1;
    end else begin
        bram_addr_a = 8'd0;
        bram_din_a  = 72'd0;
        bram_we_a   = 1'b0;
    end
end
```

### 2.4 Port B: Processor Side (Mode-Dependent)

Port B is muxed between FIFO drain reads and processor access. When
mode=1 or mode=2, the external `proc_*` signals drive Port B:

```verilog
// src/fifo/convertible_fifo.v lines 140-155
always @(*) begin
    case (mode)
        2'd1, 2'd2: begin
            // CPU or GPU mode: processor drives Port B
            bram_addr_b = proc_addr;
            bram_din_b  = proc_din;
            bram_we_b   = proc_we;
        end
        default: begin
            // FIFO mode: read side drives Port B
            bram_addr_b = rd_ptr;
            bram_din_b  = 72'd0;
            bram_we_b   = 1'b0;
        end
    endcase
end

// Processor read output (always wired to Port B output)
assign proc_dout = bram_dout_b;
```

### 2.5 in_rdy Gating (Bug #2 Fix)

Critical: `in_rdy` is gated by `mode == 0` so that network packets cannot
write Port A while CPU/GPU is using Port B. Without this, incoming packets
would corrupt BRAM contents during processing:

```verilog
// src/fifo/convertible_fifo.v lines 88-90
assign in_rdy = (mode == 2'd0)
             && (state == S_IDLE || state == S_RECEIVING)
             && !pkt_stored;
```

### 2.6 BRAM (fifo_bram.v)

Simple true dual-port BRAM with synchronous reads (1-cycle read latency):

```verilog
// src/fifo/fifo_bram.v (complete module)
module fifo_bram (
    input         clk,
    input  [7:0]  addr_a, input  [71:0] din_a, input  we_a, output reg [71:0] dout_a,
    input  [7:0]  addr_b, input  [71:0] din_b, input  we_b, output reg [71:0] dout_b
);
    reg [71:0] mem [0:255];

    always @(posedge clk) begin
        if (we_a) mem[addr_a] <= din_a;
        dout_a <= mem[addr_a];
    end

    always @(posedge clk) begin
        if (we_b) mem[addr_b] <= din_b;
        dout_b <= mem[addr_b];
    end
endmodule
```

---

## 3. Mode System

The `mode` register (`reg_fifo_mode_r[1:0]`, PCI offset 0x02) controls who
owns FIFO BRAM Port B and what `in_rdy` does:

| mode | Name | Port B driven by | in_rdy | Use case |
|------|------|-----------------|--------|----------|
| 0 | FIFO | FIFO drain logic (rd_ptr) | Active (accepts packets) | Normal packet flow |
| 1 | CPU | ARM CPU ext_mem port | Blocked | CPU reads/writes BRAM |
| 2 | GPU | DMA engine (or PCI if DMA idle) | Blocked | DMA copies FIFO<->GPU |

Mode switching sequence:
1. Wait for packet to arrive (poll `STATUS.pkt_ready`)
2. Write mode=1 or mode=2 to FIFO_MODE register
3. Do processing (CPU run, or DMA + GPU kernel)
4. Write mode=0 to FIFO_MODE register
5. Pulse drain_start to forward the packet downstream

---

## 4. CPU-FIFO Integration (Mode 1)

### 4.1 How the CPU Accesses FIFO BRAM

The ARM CPU has a standard 5-stage pipeline (IF-ID-EX-MEM-WB). To let the
CPU read/write FIFO BRAM contents, we added an **external memory port** to
the MEM stage (`data_mem.v`).

The CPU uses **address bit [7]** to distinguish internal DMEM from external
FIFO BRAM:

| CPU addr range | Target | Routes via |
|----------------|--------|-----------|
| `0x00..0x7F` (0-127) | Internal DMEM (128 x 64) | `mem[]` in `data_mem.v` |
| `0x80..0xEF` (128-239) | FIFO BRAM (mapped to FIFO `0x00..0x6F`) | `ext_mem_*` port -> wrapper proc mux |
| `0xF0..0xFF` (240-255) | Wrapper control registers (16 slots) -- **added 2026-05-10** | `reg_alias_*` port -> wrapper 16:1 mux |

So from the ARM program's perspective:
- `LDR r2, [r1, #0]` with r1=0x80 reads FIFO BRAM word 0 (the packet header)
- `STR r2, [r1, #1]` with r1=0x80 writes FIFO BRAM word 1
- `STR r3, [r1, #4]` with r1=0xF0 writes wrapper alias slot 4 = `reg_gpu_ctrl` (kicks the GPU)

The third window (register-alias) is what powers the Milestone 4 ARM orchestrator: an ARM thread can drive `GPU_CTRL`, `DMA_*`, `FIFO_DRAIN`, `LAB8_CTRL` (soft-reset), and read `GPU_STATUS`, `GPU_CYCLE_COUNT`, `FIFO_STATUS` -- all from inside the running program, no host involvement.

### 4.2 data_mem.v External + Alias Memory Ports

```verilog
// src/arm/data_mem.v -- two external bus groups (Window 2 + Window 3)
// Window 2: External FIFO BRAM (active when addra[7]=1 && addra[7:4]!=4'hF)
output [7:0]  ext_mem_addr,
output [63:0] ext_mem_din,
output        ext_mem_we,
input  [63:0] ext_mem_dout,

// Window 3: Register-alias (active when addra[7:4]==4'hF) -- added 2026-05-10
output [3:0]  reg_alias_sel,     // Slot index = addra[3:0]
output [63:0] reg_alias_wdata,
output        reg_alias_we,
input  [63:0] reg_alias_rdata
```

Address decode -- a 4-bit comparator + AND gate:

```verilog
// src/arm/data_mem.v
wire [7:0] addra = addr[7:0];
wire addr_is_reg = (addra[7:4] == 4'hF);     // 0xF0..0xFF
wire addr_is_ext = addra[7] & ~addr_is_reg;  // 0x80..0xEF

// Window 2: FIFO BRAM port
assign ext_mem_addr = {1'b0, addra[6:0]};
assign ext_mem_din  = dina;
assign ext_mem_we   = WMemEn & addr_is_ext;

// Window 3: Register-alias port (added 2026-05-10)
assign reg_alias_sel   = addra[3:0];
assign reg_alias_wdata = dina;
assign reg_alias_we    = WMemEn & addr_is_reg;
```

Read alignment -- two `was_*` flags + a captured alias rdata flop (the alias bus is combinational, so we register it locally to keep `douta` valid for one full cycle):

```verilog
reg was_ext, was_reg;
reg [63:0] reg_alias_rdata_r;
always @(posedge clk) begin
    if (reset) {was_ext, was_reg, reg_alias_rdata_r} <= 0;
    else begin
        was_ext           <= addr_is_ext;
        was_reg           <= addr_is_reg;
        reg_alias_rdata_r <= reg_alias_rdata;
    end
end

// 3:1 output mux (alias > FIFO > internal)
always @(*) douta = was_reg ? reg_alias_rdata_r
                  : (was_ext ? ext_mem_dout : dmem_rd);
```

See `walkthrough_batch3_cpu_integration.md §3` for the full design rationale of each window and why `reg_alias_rdata` needs the local register.

### 4.3 processor.v Ports

The CPU top-level exposes both `ext_mem_*` and `reg_alias_*` signals (the latter added 2026-05-10):

```verilog
// src/arm/processor.v
output [7:0]  ext_mem_addr,
output [63:0] ext_mem_din,
output        ext_mem_we,
input  [63:0] ext_mem_dout,
// Register-alias window (Milestone 4: ARM-orchestrated IDS pipeline)
output [3:0]  reg_alias_sel,
output [63:0] reg_alias_wdata,
output        reg_alias_we,
input  [63:0] reg_alias_rdata,
```

Both groups are just plumbed straight through `processor.v` to `data_mem.v` -- no logic in `processor.v` touches them.

### 4.4 Wrapper Instantiation

In `lab8_wrapper.v`, the CPU is instantiated and its ext_mem wired:

```verilog
// src/lab8_wrapper.v lines 131-134
wire [7:0]  cpu_ext_mem_addr;
wire [63:0] cpu_ext_mem_din;
wire        cpu_ext_mem_we;
wire [63:0] cpu_ext_mem_dout;
```

```verilog
// src/lab8_wrapper.v lines 153-177
processor u_cpu (
    .clk            (clk),
    .rst            (cpu_reset),
    .start_stop     (cpu_running),
    .intf_wen_imem  (cpu_imem_wen),
    .intf_addr_imem (cpu_imem_addr),
    .intf_data_imem (cpu_imem_wdata),
    .intf_dout_imem (cpu_imem_rdata),
    .web            (cpu_dmem_wen),
    .dinb           (cpu_dmem_wdata),
    .addrb          (cpu_dmem_addr),
    .doutb          (cpu_dmem_rdata),
    .ext_mem_addr   (cpu_ext_mem_addr),
    .ext_mem_din    (cpu_ext_mem_din),
    .ext_mem_we     (cpu_ext_mem_we),
    .ext_mem_dout   (cpu_ext_mem_dout),
    .la_rd_addr     (cpu_la_addr),
    .la_rd_data     (cpu_la_data),
    .dbg_cpsr_0     (cpu_cpsr_0),
    .dbg_cpsr_1     (cpu_cpsr_1),
    .dbg_cpsr_2     (cpu_cpsr_2),
    .dbg_cpsr_3     (cpu_cpsr_3),
    .dbg_thread_id  (cpu_thread_id),
    .all_halted     (cpu_all_halted)
);

assign cpu_ext_mem_dout = fifo_proc_dout[63:0];
```

Note: `fifo_proc_dout` is 72 bits (8 ctrl + 64 data). The CPU only sees the
lower 64 data bits. The ctrl byte is stripped.

### 4.5 CPU Control Signals

```verilog
// src/lab8_wrapper.v lines 348-349
assign cpu_running = reg_cpu_ctrl[0];       // bit 0 = start_stop
assign cpu_reset   = reset | reg_cpu_ctrl[1]; // bit 1 = cpu_reset
```

CPU has additional PCI-accessible ports:
- **IMEM Port B:** For loading programs (intf_wen_imem, intf_addr_imem, etc.)
- **DMEM Port B:** For PCI read/write of internal data memory
- **Logic Analyzer:** 2048x64 trace buffer for debug

### 4.6 CPU Data Width Consideration

The ARM CPU is a **32-bit** processor. Its registers are 64 bits wide in this
implementation, but ARM instructions operate on the lower 32 bits. When the
CPU writes to FIFO BRAM (64-bit words), only the lower 32 bits are typically
meaningful from the ARM program's perspective. The upper 32 bits pass through
unchanged on a read-modify-write.

---

## 5. GPU-FIFO Integration (Mode 2)

### 5.1 Why DMA (Not Direct Access)

Unlike the CPU, the GPU does **not** have a direct external memory port to
the FIFO BRAM. The GPU has its own separate IMEM (1024x32) and DMEM
(1024x64). To process packet data, we use a DMA engine to copy words between
FIFO BRAM and GPU DMEM.

This design choice was made to avoid modifying GPU RTL. The GPU's DMEM already
has an external port (Port B) for PCI access -- we simply reuse that port for
DMA as well.

### 5.2 gpu_top.v Port Interface

```verilog
// src/gpu/gpu_top.v
module gpu_top (
    input         clk,
    input         rst,

    // Thread parameters (hardwired for Lab 8)
    input  [31:0] thread_id,     // = 0
    input  [31:0] block_id,      // = 0
    input  [31:0] block_dim,     // = 1

    output        kernel_done,

    // External IMEM interface (Port B, PCI-driven only)
    input  [9:0]  ext_imem_addr,
    input         ext_imem_wr_en,
    input  [31:0] ext_imem_wr_data,
    output [31:0] ext_imem_rd_data,

    // External DMEM interface (Port B, muxed: DMA or PCI)
    input  [9:0]  ext_dmem_addr,
    input         ext_dmem_wr_en,
    input  [63:0] ext_dmem_wr_data,
    output [63:0] ext_dmem_rd_data
);
```

> **Note (2026-05-17):** `gpu_top.v` ports are bit-identical to the original Lab 7 / Lab 8 baseline. The 2026-04-13 BCAST refactor (commit `e14d012`) restructured the GPU core internals -- new opcode, new cross-lane mux in `simd_alu`, INT16 scalarised, simd_alu input pipeline register -- but **none** of that crosses this interface. The wrapper's GPU instantiation is unchanged. For the GPU-core deep dive, see `../lab7_gpu/walkthrough_batch4_execute_stage.md`.

### 5.3 GPU Sizing (from gpu_params.vh)

| Parameter | Value | Description |
|-----------|-------|-------------|
| `DATA_WIDTH` | 64 | DMEM word width (same as FIFO data width) |
| `INSTR_WIDTH` | 32 | Instruction width |
| `IMEM_ADDR_W` | 10 | IMEM address bits (1024 entries) |
| `DMEM_ADDR_W` | 10 | DMEM address bits (1024 entries) |
| `SIMD_LANES` | 4 | 4-lane SIMD (4x int16 or 4x bf16 per 64-bit word) |

### 5.4 Wrapper Instantiation

```verilog
// src/lab8_wrapper.v lines 200-215
gpu_top u_gpu (
    .clk             (clk),
    .rst             (gpu_reset),
    .thread_id       (32'd0),
    .block_id        (32'd0),
    .block_dim       (32'd1),
    .kernel_done     (gpu_kernel_done),
    .ext_imem_addr   (gpu_imem_addr),
    .ext_imem_wr_en  (gpu_imem_wr_en),
    .ext_imem_wr_data(gpu_imem_wr_data),
    .ext_imem_rd_data(gpu_imem_rd_data),
    .ext_dmem_addr   (gpu_dmem_addr),
    .ext_dmem_wr_en  (gpu_dmem_wr_en),
    .ext_dmem_wr_data(gpu_dmem_wr_data),
    .ext_dmem_rd_data(gpu_dmem_rd_data)
);
```

### 5.5 GPU Control Signals

```verilog
// src/lab8_wrapper.v line 350
assign gpu_reset = reset | reg_gpu_ctrl[0];  // bit 0 = gpu_reset (active high)
```

GPU starts in reset (`reg_gpu_ctrl` resets to `32'h1`). Software must write
`GPU_CTRL = 0` to release reset before starting a kernel.

---

## 6. The DMA Engine

**File:** `src/lab8_wrapper.v` lines 220-279

The DMA engine copies 64-bit words between FIFO BRAM and GPU DMEM. It
operates only in mode=2 and is controlled by 4 PCI registers.

### 6.1 DMA Registers

| Register | Offset | Description |
|----------|--------|-------------|
| `DMA_CTRL` | 0x2C | bit[0]=start (auto-clear), bit[1]=direction |
| `DMA_FIFO_ADDR` | 0x2D | FIFO BRAM start address [7:0] |
| `DMA_GPU_ADDR` | 0x2E | GPU DMEM start address [9:0] |
| `DMA_LENGTH` | 0x2F | Word count [7:0] |

Direction bit: 0 = FIFO->GPU, 1 = GPU->FIFO.

### 6.2 Start Condition

DMA only starts when all three conditions are met:

```verilog
// src/lab8_wrapper.v lines 371-373
assign dma_start = reg_dma_ctrl[0]
                && (reg_fifo_mode_r[1:0] == 2'd2)
                && (reg_dma_length[7:0] != 8'd0);
```

### 6.3 FSM

```
  IDLE ---(dma_start)---> READ ---(1 cycle)---> COPY ---(N cycles)---> IDLE
```

- **DMA_IDLE (0):** Waiting for start. Latches direction, addresses, and
  length from registers.
- **DMA_READ (1):** Presents the first read address to BRAM/DMEM. Waits
  1 cycle for synchronous read latency.
- **DMA_COPY (2):** Reads one address ahead of writes (pipelined).
  `dma_rd_ptr` leads `dma_wr_ptr` by 1. Each cycle copies one 64-bit word.
  Completes when `dma_wr_ptr + 1 == dma_len`.

```verilog
// src/lab8_wrapper.v lines 243-279
always @(posedge clk) begin
    if (reset) begin
        dma_state     <= DMA_IDLE;
        dma_dir       <= 1'b0;
        dma_fifo_base <= 8'd0;
        dma_gpu_base  <= 10'd0;
        dma_len       <= 8'd0;
        dma_rd_ptr    <= 8'd0;
        dma_wr_ptr    <= 8'd0;
    end else begin
        case (dma_state)
            DMA_IDLE: begin
                if (dma_start) begin
                    dma_dir       <= reg_dma_ctrl[1];
                    dma_fifo_base <= reg_dma_fifo_addr[7:0];
                    dma_gpu_base  <= reg_dma_gpu_addr[9:0];
                    dma_len       <= reg_dma_length[7:0];
                    dma_rd_ptr    <= 8'd0;
                    dma_wr_ptr    <= 8'd0;
                    dma_state     <= DMA_READ;
                end
            end
            DMA_READ: begin
                // First read address presented combinationally; wait 1 cycle
                dma_rd_ptr <= 8'd1;
                dma_state  <= DMA_COPY;
            end
            DMA_COPY: begin
                dma_wr_ptr <= dma_wr_ptr + 8'd1;
                dma_rd_ptr <= dma_rd_ptr + 8'd1;
                if (dma_wr_ptr + 8'd1 == dma_len)
                    dma_state <= DMA_IDLE;
            end
            default: dma_state <= DMA_IDLE;
        endcase
    end
end
```

### 6.4 DMA Timing

For N words: 1 cycle (IDLE->READ) + 1 cycle (READ->COPY) + N cycles (COPY)
= N+2 total cycles. At 125 MHz, copying 7 words takes 72 ns.

---

## 7. Port Muxes in the Wrapper

This is the most critical part of the integration. The wrapper has two muxes
that route signals to the FIFO proc port and GPU DMEM ext port.

### 7.1 FIFO Proc Port Mux (3-way: PCI / CPU / DMA)

```verilog
// src/lab8_wrapper.v lines 379-408
wire cpu_drives_proc = (reg_fifo_mode_r[1:0] == 2'd1) && cpu_running;
wire dma_drives_proc = (reg_fifo_mode_r[1:0] == 2'd2) && dma_active;

always @(*) begin
    fifo_mode        = reg_fifo_mode_r[1:0];
    fifo_drain_start = reg_fifo_drain[0];

    if (cpu_drives_proc) begin
        // Mode 1: CPU ext_mem drives FIFO BRAM Port B
        // Fix B (2026-04-20): preserve ctrl=0xFF on writes to BRAM[0] so the
        // outgoing NF2.1 header marker survives drain.
        fifo_proc_addr = cpu_ext_mem_addr;
        fifo_proc_din  = {arm_bram_wctrl, cpu_ext_mem_din};
        fifo_proc_we   = cpu_ext_mem_we;
    end else if (dma_drives_proc) begin
        if (!dma_dir) begin
            // FIFO->GPU: read from FIFO BRAM
            fifo_proc_addr = dma_fifo_base + dma_rd_ptr;
            fifo_proc_din  = 72'd0;
            fifo_proc_we   = 1'b0;
        end else begin
            // GPU->FIFO: write to FIFO BRAM
            fifo_proc_addr = dma_fifo_base + dma_wr_ptr;
            fifo_proc_din  = {8'h00, gpu_dmem_rd_data};
            fifo_proc_we   = (dma_state == DMA_COPY);
        end
    end else begin
        // Default: PCI register access
        fifo_proc_addr = reg_bram_addr[7:0];
        fifo_proc_din  = {reg_bram_wctrl[7:0], reg_bram_wd_hi, reg_bram_wd_lo};
        fifo_proc_we   = bram_pci_wr_strobe;
    end
end
```

Important details:
- CPU data is 64 bits, padded by a small 2:1 mux (`arm_bram_wctrl`) -- `0xFF` for BRAM[0] (Fix B, 2026-04-20) and `0x00` for every other slot.
- DMA GPU->FIFO always pads with `0x00` ctrl. The header word is now written by the ARM orchestrator instead (which goes through the CPU path above and benefits from Fix B's ctrl=0xFF for BRAM[0]).
- PCI access includes the full 72-bit width (ctrl via `reg_bram_wctrl`).

### 7.2 GPU DMEM Ext Port Mux (2-way: PCI / DMA)

```verilog
// src/lab8_wrapper.v lines 410-429
always @(*) begin
    if (dma_active) begin
        if (!dma_dir) begin
            // FIFO->GPU: write to GPU DMEM
            gpu_dmem_addr    = dma_gpu_base + {2'b0, dma_wr_ptr};
            gpu_dmem_wr_en   = (dma_state == DMA_COPY);
            gpu_dmem_wr_data = fifo_proc_dout[63:0];  // from FIFO BRAM read
        end else begin
            // GPU->FIFO: read from GPU DMEM
            gpu_dmem_addr    = dma_gpu_base + {2'b0, dma_rd_ptr};
            gpu_dmem_wr_en   = 1'b0;
            gpu_dmem_wr_data = 64'd0;
        end
    end else begin
        // Default: PCI register access
        gpu_dmem_addr    = reg_gpu_dmem_addr[9:0];
        gpu_dmem_wr_en   = gpu_dmem_pci_wr_strobe;
        gpu_dmem_wr_data = {reg_gpu_dmem_wd_hi, reg_gpu_dmem_wd_lo};
    end
end
```

### 7.3 PCI Write Strobes

At 125 MHz, using `reg_bram_cmd[0]` directly through the combinational mux
creates timing failures. We use registered strobes instead:

```verilog
// src/lab8_wrapper.v lines 290-307
wire pci_wr_hit = reg_req_in && !reg_ack_in && block_match && !reg_rd_wr_L_in;

reg bram_pci_wr_strobe;
reg gpu_dmem_pci_wr_strobe;

always @(posedge clk) begin
    if (reset) begin
        bram_pci_wr_strobe     <= 1'b0;
        gpu_dmem_pci_wr_strobe <= 1'b0;
    end else begin
        bram_pci_wr_strobe     <= pci_wr_hit
                                && (local_offset == `LAB8_BRAM_CMD)
                                && reg_data_in[0];
        gpu_dmem_pci_wr_strobe <= pci_wr_hit
                                && (local_offset == `LAB8_GPU_DMEM_CMD)
                                && reg_data_in[0];
    end
end
```

---

## 8. PCI Register Interface

### 8.1 Register Map (all word-indexed, 6-bit offsets)

```
FIFO Registers (0x00-0x0B):
  0x00  CTRL           RW  bit[0]=soft_reset
  0x01  STATUS         RO  {pkt_word_cnt[7:0], head[7:0], tail[7:0],
                             5'b0, empty, full, pkt_ready}
  0x02  FIFO_MODE      RW  mode[1:0] (0=FIFO, 1=CPU, 2=GPU)
  0x03  FIFO_DRAIN     RW  bit[0]=drain_start (auto-clear strobe)
  0x04  BRAM_ADDR      RW  BRAM address [7:0]
  0x05  BRAM_WD_LO     RW  write data [31:0]
  0x06  BRAM_WD_HI     RW  write data [63:32]
  0x07  BRAM_WCTRL     RW  write ctrl [7:0]
  0x08  BRAM_CMD       RW  bit[0]=write strobe (auto-clear)
  0x09  BRAM_RD_LO     RO  read data [31:0]
  0x0A  BRAM_RD_HI     RO  read data [63:32]
  0x0B  BRAM_RCTRL     RO  read ctrl [7:0]

CPU Registers (0x0C-0x1A):
  0x0C  CPU_CTRL       RW  bit[0]=start_stop, bit[1]=cpu_reset
  0x0D  CPU_STATUS     RO  {all_halted, 3'b0, cpsr3, cpsr2, cpsr1, cpsr0,
                             thread_id[1:0], 6'b0, 2'b0, running, ~reset}
  0x0E  CPU_IMEM_ADDR  RW  IMEM address [8:0]
  0x0F  CPU_IMEM_WDATA RW  IMEM write data [31:0]
  0x10  CPU_IMEM_CMD   RW  bit[0]=write strobe (auto-clear)
  0x11  CPU_IMEM_RDATA RO  IMEM readback [31:0]
  0x12  CPU_DMEM_ADDR  RW  DMEM address [7:0]
  0x13  CPU_DMEM_WD_LO RW  DMEM write data [31:0]
  0x14  CPU_DMEM_WD_HI RW  DMEM write data [63:32]
  0x15  CPU_DMEM_CMD   RW  bit[0]=write strobe (auto-clear)
  0x16  CPU_DMEM_RD_LO RO  DMEM readback [31:0]
  0x17  CPU_DMEM_RD_HI RO  DMEM readback [63:32]
  0x18  CPU_LA_ADDR    RW  Logic analyzer address [10:0]
  0x19  CPU_LA_RD_LO   RO  LA readback [31:0]
  0x1A  CPU_LA_RD_HI   RO  LA readback [63:32]

(0x1B-0x1F: padding/reserved to align GPU at 0x20)

GPU Registers (0x20-0x2B):
  0x20  GPU_CTRL       RW  bit[0]=gpu_reset (1=hold in reset)
  0x21  GPU_STATUS     RO  bit[0]=kernel_done, bit[1]=dma_busy
  0x22  GPU_IMEM_ADDR  RW  IMEM address [9:0]
  0x23  GPU_IMEM_WDATA RW  IMEM write data [31:0]
  0x24  GPU_IMEM_CMD   RW  bit[0]=write strobe (auto-clear)
  0x25  GPU_IMEM_RDATA RO  IMEM readback [31:0]
  0x26  GPU_DMEM_ADDR  RW  DMEM address [9:0]
  0x27  GPU_DMEM_WD_LO RW  DMEM write data [31:0]
  0x28  GPU_DMEM_WD_HI RW  DMEM write data [63:32]
  0x29  GPU_DMEM_CMD   RW  bit[0]=write strobe (auto-clear)
  0x2A  GPU_DMEM_RD_LO RO  DMEM readback [31:0]
  0x2B  GPU_DMEM_RD_HI RO  DMEM readback [63:32]

DMA Registers (0x2C-0x2F):
  0x2C  DMA_CTRL       RW  bit[0]=start (auto-clear), bit[1]=dir
  0x2D  DMA_FIFO_ADDR  RW  FIFO BRAM start address [7:0]
  0x2E  DMA_GPU_ADDR   RW  GPU DMEM start address [9:0]
  0x2F  DMA_LENGTH     RW  word count [7:0]

Performance Counter (0x30) -- added 2026-04-13:
  0x30  GPU_CYCLE_COUNT RO  32-bit count of core_clk cycles from gpu_reset
                            deassertion until kernel_done first asserts.
                            Frozen at the kernel_done cycle. Reset on gpu_reset.
                            Matches the testbench cycle_count value exactly.
```

### 8.2 NF2 Register Ring

The wrapper sits on the NF2.1 UDP register ring. It checks incoming requests
against its block address and either handles them (read/write) or passes
them through to the next module:

```verilog
wire block_match = (reg_addr_in[`UDP_REG_ADDR_WIDTH-1:`LAB8_REG_ADDR_WIDTH]
                    == `LAB8_BLOCK_ADDR);

wire [`LAB8_REG_ADDR_WIDTH-1:0] local_offset =
     reg_addr_in[`LAB8_REG_ADDR_WIDTH-1:0];
```

The register state machine latches incoming requests with a 1-cycle pipeline
delay. On a matching write, it updates the target register. On a matching
read, the **combinational readback mux** picks the right register value and
a separate dedicated flop captures it — that combinational-mux + dedicated-flop
split was the fix for Bug #6 (2026-04-13), where XST trimmed `reg_rd_data`
when the read case was buried inside the clocked write block. Auto-clear
strobes (drain, BRAM cmd, IMEM/DMEM cmd, DMA ctrl, soft-reset) clear bit[0]
one cycle after being written; soft-reset (`reg_ctrl[0]`) was added to the
auto-clear list 2026-05-10 so the ARM orchestrator can issue it as a single
store. See `walkthrough_batch5_synthesis_hw.md §7` for the trim-bug root
cause and `walkthrough_batch2_wrapper.md §2.8` for the current code.

### 8.3 ARM Register-Alias Window (added 2026-05-10)

Beyond the PCI ring, the ARM CPU can read/write a 16-slot subset of these
registers directly from a thread program by accessing DMEM addresses
`0xF0..0xFF`. Slot map (full list in `walkthrough_batch2_wrapper.md §2.11`):

```
ARM DMEM     Slot   Maps to
0xF0         0x0    DMA_CTRL
0xF1         0x1    DMA_FIFO_ADDR
0xF2         0x2    DMA_GPU_ADDR
0xF3         0x3    DMA_LENGTH
0xF4         0x4    GPU_CTRL
0xF5         0x5    GPU_STATUS         (RO)
0xF6         0x6    FIFO STATUS        (RO)
0xF7         0x7    FIFO_MODE
0xF8         0x8    LAB8_CTRL (soft-reset)
0xF9         0x9    GPU_CYCLE_COUNT    (RO)
0xFA         0xA    FIFO_DRAIN
0xFB..0xFF   reserved
```

This is what makes the Milestone 4 orchestrator possible -- one ARM thread
sequences `wait for packet -> DMA in -> start GPU -> poll done -> read cycle
count -> DMA out -> drain` without any host involvement. The host's only job
is to load the IMEM/DMEM programs once at startup.

---

## 9. Operational Sequences

### 9.1 CPU Processing a Packet (Mode 1)

```
Step  PCI Register Write              What Happens
----  ----------------------------    ----------------------------------
1.    CTRL = 1                        Reset FIFO (clears state)
2.    CTRL = 0                        Release reset
3.    (wait)                          Packet arrives from network
4.    Read STATUS                     Poll until pkt_ready (bit 0) = 1
5.    FIFO_MODE = 1                   Switch to CPU mode (blocks in_rdy)
6.    CPU_CTRL = 0x02                 Hold CPU in reset
7.    Load IMEM via CPU_IMEM_*        Write program instructions
8.    CPU_CTRL = 0x01                 Release reset + start (atomic)
9.    Read CPU_STATUS                 Poll until all_halted (bit 31) = 1
10.   CPU_CTRL = 0x00                 Stop CPU
11.   FIFO_MODE = 0                   Back to FIFO mode
12.   FIFO_DRAIN = 1                  Start draining modified packet
```

Example ARM program (adds 42 to BRAM[1]):
```
MOV r1, #128      ; base address for ext mem (bit[7]=1)
LDR r2, [r1, #1]  ; read FIFO BRAM word 1
ADD r2, r2, #42   ; modify
STR r2, [r1, #1]  ; write back
HALT               ; stop execution
```

### 9.2 GPU Processing a Packet (Mode 2)

```
Step  PCI Register Write              What Happens
----  ----------------------------    ----------------------------------
1-4.  (same as CPU: reset, wait for packet)
5.    FIFO_MODE = 2                   Switch to GPU mode
6.    GPU_CTRL = 0                    Release GPU from reset
7.    Load GPU IMEM via GPU_IMEM_*    Write kernel instructions
8.    DMA_FIFO_ADDR = 1              FIFO BRAM start (skip header)
      DMA_GPU_ADDR  = 0              GPU DMEM start
      DMA_LENGTH    = 7              7 data words
      DMA_CTRL      = 0x01           Start DMA: FIFO -> GPU (dir=0)
9.    Read GPU_STATUS                 Poll until dma_busy (bit 1) = 0
10.   GPU_CTRL = 0 (release reset)   Start GPU kernel
      (GPU was already out of reset;
       or: gpu_start if using a
       start/stop model)
11.   Read GPU_STATUS                 Poll until kernel_done (bit 0) = 1
12.   GPU_CTRL = 1                    Hold GPU in reset (stop)
13.   DMA_FIFO_ADDR = 1              Same addresses
      DMA_GPU_ADDR  = 0
      DMA_LENGTH    = 7
      DMA_CTRL      = 0x03           Start DMA: GPU -> FIFO (dir=1)
14.   Read GPU_STATUS                 Poll until dma_busy = 0
15.   FIFO_MODE = 0                   Back to FIFO mode
16.   FIFO_DRAIN = 1                  Drain modified packet
```

### 9.3 Combined CPU + GPU (Mode 1 then Mode 2)

Run steps 5-10 from CPU sequence (mode 1), then steps 5-14 from GPU
sequence (mode 2), then drain. The packet data passes through both
processors sequentially.

### 9.4 ARM-Orchestrated CPU + GPU (added 2026-05-10)

The Milestone 4 orchestrator replaces steps 8-16 of the GPU sequence with
a single ARM kernel running on one of the four threads. The host's only job
becomes step 1 (one-time IMEM/DMEM program load); from then on the ARM
thread sequences everything:

```
ARM orchestrator loop (one packet per iteration, in pseudo-ASM):

  poll_pkt:
    LDR  r2, [r6, #0xF6]      ; read FIFO STATUS via alias (slot 6)
    AND  r3, r2, #1            ; pkt_ready bit
    BEQ  poll_pkt

    STR  r4, [r6, #0xF7]      ; FIFO_MODE = 2 (GPU)
    MOV  r3, #0x01
    STR  r3, [r6, #0xF0]      ; DMA_CTRL = start, dir=0 (FIFO->GPU)

  poll_dma1:
    LDR  r2, [r6, #0xF5]      ; read GPU_STATUS
    AND  r3, r2, #2            ; dma_busy bit
    BNE  poll_dma1

    STR  r0, [r6, #0xF4]      ; GPU_CTRL = 0 (release reset)

  poll_done:
    LDR  r2, [r6, #0xF5]      ; read GPU_STATUS
    AND  r3, r2, #1            ; kernel_done bit
    BEQ  poll_done

    LDR  r2, [r6, #0xF9]      ; (optional) read GPU_CYCLE_COUNT
    STR  r2, [r5, #0]         ; write packet response header (Fix B keeps ctrl=0xFF)

    MOV  r3, #0x03
    STR  r3, [r6, #0xF0]      ; DMA_CTRL = start, dir=1 (GPU->FIFO)
    ...
    MOV  r3, #0
    STR  r3, [r6, #0xF7]      ; FIFO_MODE = 0 (FIFO)
    MOV  r3, #1
    STR  r3, [r6, #0xFA]      ; FIFO_DRAIN = 1 (auto-clears)
    B    poll_pkt
```

The `r6` base register is set once at startup to `0x780` (= `0xF0 * 8`, the
ARM-side byte address of slot 0); each slot is offset by 8 bytes since the
DMEM array is 64-bit word-addressed. See `docs/arm_orchestrator.md` for the
real assembly and a per-instruction commentary.

---

## 10. Lessons Learned / Pitfalls

### 10.1 Timing: Registered Write Strobes Required

Using `reg_bram_cmd[0]` directly through the 3-way combinational proc port
mux creates a timing path that fails at 125 MHz. Solution: use a dedicated
registered strobe (`bram_pci_wr_strobe`) that fires one cycle after the PCI
write. Same applies to GPU DMEM PCI writes. See Section 7.3.

### 10.2 in_rdy Must Be Gated by Mode

If `in_rdy` is not gated by `mode==0`, incoming network packets will write
to BRAM Port A while the CPU/GPU is using Port B, corrupting data. This was
our Bug #2 -- packets arriving during IMEM load overwrote BRAM contents.

### 10.3 CPU Atomic Start

The CPU must be started atomically: write `CPU_CTRL = 0x01` to simultaneously
release reset (bit[1]=0) and assert start_stop (bit[0]=1). If you release
reset first and then start, the CPU may fetch stale instructions during the
gap.

### 10.4 GPU Default State

The GPU starts in reset (`reg_gpu_ctrl` resets to `32'h1`). This prevents
the GPU from running its pipeline on garbage IMEM contents at power-up.
Software must explicitly write `GPU_CTRL = 0` to release reset.

### 10.5 BRAM Read Latency

The FIFO BRAM (and GPU DMEM) have 1-cycle synchronous read latency. This
affects:
- DMA engine: needs DMA_READ state to prime the read pipeline
- CPU: uses `was_ext` registered flag to mux output correctly
- FIFO drain: needs DRAIN_WAIT1 + DRAIN_WAIT2 states before DRAINING

### 10.6 Data Width Alignment

| Component | Data Width | Notes |
|-----------|-----------|-------|
| FIFO BRAM word | 72 bits | 8-bit ctrl + 64-bit data |
| NF2.1 bus | 64+8 bits | Separate data and ctrl signals |
| CPU registers | 64 bits | ARM operates on lower 32 |
| GPU DMEM word | 64 bits | 4x int16 SIMD lanes |
| DMA transfer unit | 64 bits | Strips/pads ctrl byte |

### 10.7 NF2.1 Packet Format

The first word of every packet has `ctrl != 0` (typically `ctrl = 0xFF`).
Its data field contains:
```
data[63:48] = dst_port[15:0]    (one-hot port encoding)
data[47:32] = word_length[15:0] (total words including header)
data[31:16] = src_port[15:0]
data[15:0]  = byte_length[15:0]
```
All subsequent words have `ctrl = 0x00`.

### 10.8 Resource Usage (XC2VP50, Lab 8 Batch 5)

| Resource | Used | Available | % |
|----------|------|-----------|---|
| Slices | 20,711 | 23,616 | 87% |
| Slice FFs | 20,846 | 47,232 | 44% |
| 4-input LUTs | 32,050 | 47,232 | 67% |
| BRAM (RAMB16) | 108 | 232 | 46% |
| MULT18X18 | 12 | 232 | 5% |
| DCMs | 6 | 8 | 75% |

Slices are the bottleneck at 87%. The GPU's decode stage is the critical
timing path (16.67 ns vs 8 ns target at 125 MHz). 4816 timing violations
exist but do not affect functional correctness.

---

## 11. What to Adapt for Lab 9

### 11.1 What the Other Subgroup Provides

They contribute:
- Convertible FIFO (their version of `convertible_fifo.v` + `fifo_bram.v`)
- ARM processor (their version of `processor.v` + pipeline stages)

You need to understand their interfaces to connect the GPU.

### 11.2 What We Provide

- GPU (`gpu_top.v` and all submodules)
- GPU parameters (`gpu_params.vh`)

### 11.3 Integration Checklist

1. **Understand their FIFO proc port interface.** It should have signals
   equivalent to our `proc_addr`, `proc_din`, `proc_we`, `proc_dout`. Check:
   - Address width (ours: 8 bits = 256 entries)
   - Data width (ours: 72 bits = 8 ctrl + 64 data)
   - Whether they expose a `mode` input

2. **Understand their CPU ext_mem interface.** Check if their CPU has an
   external memory port like our `ext_mem_addr/din/we/dout`. If not, the
   CPU-FIFO integration approach may differ.

3. **Write the wrapper.** The wrapper needs:
   - FIFO instantiation (their code)
   - CPU instantiation (their code)
   - GPU instantiation (our code)
   - DMA engine (copy from our `lab8_wrapper.v` lines 220-279)
   - Port muxes (adapt from our lines 379-429)
   - PCI register ring (adapt from our lines 469-647)
   - Register defines (adapt from our `lab8_reg_defines.vh`)

4. **DMA engine reuse.** The DMA engine is generic -- it just copies 64-bit
   words between two address spaces using address+data+we signals. It should
   work with any FIFO that has a similar proc port interface.

5. **GPU ports are fixed.** The GPU's external interface does not change:
   - IMEM: 10-bit addr, 32-bit data, wr_en, rd_data
   - DMEM: 10-bit addr, 64-bit data, wr_en, rd_data
   - Control: rst (active high), kernel_done output
   - Parameters: thread_id=0, block_id=0, block_dim=1

6. **Register map negotiation.** Decide with the other subgroup how to
   partition the register space. Our Lab 8 layout:
   - 0x00-0x0B: FIFO (12 registers) -- their responsibility
   - 0x0C-0x1A: CPU (15 registers) -- their responsibility
   - 0x20-0x2F: GPU + DMA (16 registers) -- our responsibility

7. **Test incrementally.** Suggested order:
   - First: FIFO standalone (mode=0, packet in/out)
   - Second: CPU + FIFO (mode=1, CPU modifies packet)
   - Third: GPU + FIFO (mode=2, DMA + kernel)
   - Last: Combined CPU + GPU

### 11.4 Key Interface Summary for the Other Subgroup

Tell them we need the following from the FIFO for GPU integration:

```
// Minimum FIFO proc port interface needed for GPU DMA:
input  [7:0]  proc_addr,     // BRAM address (8-bit for 256 entries)
input  [71:0] proc_din,      // write data (72-bit: 8 ctrl + 64 data)
input         proc_we,       // write enable
output [71:0] proc_dout,     // read data (72-bit, 1-cycle latency)
input  [1:0]  mode,          // 0=FIFO, 1=CPU, 2=GPU
```

And from the FIFO status:
```
output        pkt_ready,     // packet fully buffered
input         drain_start,   // strobe to begin draining
```

If their FIFO data width differs (e.g., 64 bits without ctrl), the DMA
engine and mux logic need minor width adjustments.
