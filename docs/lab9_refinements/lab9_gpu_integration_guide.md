# Lab 9 -- GPU Subgroup Integration Guide

Everything you need to know to explain to the other subgroup how the GPU
integrates with their ARM CPU + Convertible FIFO on the NetFPGA V2.

We (GPU subgroup) contribute: GPU coprocessor + DMA engine + GPU/DMA registers.
They (CPU subgroup) contribute: ARM CPU + Convertible FIFO + FIFO/CPU registers.
Together: a shared wrapper module instantiates all three around a dual-port BRAM.

---

## 1. What the Network Processor Does

The system sits inside the NF2.1 data path on the NetFPGA V2 (Virtex-II Pro
XC2VP50, 125 MHz core clock). It intercepts network packets, lets the CPU
and/or GPU process them, then forwards the (possibly modified) packet.

```
NF2.1 pipeline:
  input_arbiter -> output_port_lookup -> [our wrapper] -> output_queues

Inside our wrapper:
  +---------------------------------------------------------------+
  |  Convertible FIFO (256 x 72-bit dual-port BRAM)               |
  |    Port A: network in/out (NF2.1 pipeline)                    |
  |    Port B: processor access (muxed: PCI / CPU / DMA)          |
  +---------------------------------------------------------------+
  |   ARM CPU          3-way MUX           GPU (SIMD)             |
  |   (their code)    (PCI/CPU/DMA)       (our code)              |
  |   ext_mem port ---> Port B <--- DMA engine                    |
  |                                  FIFO BRAM <-> GPU DMEM       |
  +---------------------------------------------------------------+
  |   PCI Register Ring (NF2.1 UDP protocol)                      |
  |   Host software reads/writes control registers                |
  +---------------------------------------------------------------+
```

A network packet arrives on Port A, the FIFO buffers it, software switches
the mode to CPU or GPU, the processor does its work via Port B, then software
switches back to FIFO mode and drains the packet out.

---

## 2. The Convertible FIFO (Their Code, Our Interface)

The FIFO is a 256 x 72-bit dual-port BRAM with a control FSM. Each word is
72 bits = 8-bit ctrl + 64-bit data, matching the NF2.1 word format.

### 2.1 FIFO Port Interface

**Port A -- Network side** (always connected to NF2.1 pipeline):
```
input  [63:0] in_data       // packet data from upstream
input  [7:0]  in_ctrl       // packet ctrl (0xFF = header, 0x00 = data)
input         in_wr         // write strobe
output        in_rdy        // backpressure (0 = don't send)

output [63:0] out_data      // packet data to downstream
output [7:0]  out_ctrl      // packet ctrl
output        out_wr        // output valid
input         out_rdy       // downstream ready
```

**Port B -- Processor side** (our integration point):
```
input  [7:0]  proc_addr     // BRAM address (0-255)
input  [71:0] proc_din      // write data {ctrl[7:0], data[63:0]}
input         proc_we       // write enable
output [71:0] proc_dout     // read data {ctrl[7:0], data[63:0]}
```

**Control signals:**
```
input  [1:0]  mode          // 0=FIFO, 1=CPU, 2=GPU
input         drain_start   // pulse to begin draining packet
output        pkt_ready     // 1 = packet fully buffered
output        fifo_full     // 1 = one packet stored
output        fifo_empty    // 1 = FIFO is empty
output [7:0]  pkt_word_cnt  // number of words in buffered packet
```

### 2.2 Critical: in_rdy Mode Gating

```verilog
assign in_rdy = (mode == 2'd0)
             && (state == S_IDLE || state == S_RECEIVING)
             && !pkt_stored;
```

When mode != 0, `in_rdy` is forced LOW. This prevents network packets from
writing Port A while a processor uses Port B. Without this, incoming broadcast
packets (like ARP) corrupt BRAM contents during slow PCI operations. This was
Bug #2 in Lab 8 -- make sure the CPU subgroup's FIFO has this check.

### 2.3 FIFO FSM States

```
S_IDLE -> S_RECEIVING -> S_PKT_BUFFERED -> S_DRAIN_WAIT1 -> S_DRAIN_WAIT2 -> S_DRAINING -> S_IDLE
```

- **S_IDLE**: Waiting for packet. First word with `ctrl != 0` starts capture.
- **S_RECEIVING**: Counting data words using `word_length` from NF2.1 header.
- **S_PKT_BUFFERED**: Packet complete. Processor can access via Port B.
- **S_DRAIN_***: Reads BRAM and outputs to downstream (1-cycle read latency).

Packet header format (data[63:0]):
```
{dst_port[15:0], word_length[15:0], src_port[15:0], byte_length[15:0]}
```

### 2.4 BRAM Synchronous Read Latency

All dual-port BRAMs have **1-cycle read latency**. Address presented at cycle N,
data available at cycle N+1. This affects:
- DMA engine (needs a READ state before COPY)
- FIFO drain (needs WAIT states before output)
- CPU data_mem (needs `was_ext` register to align output mux)

---

## 3. The Mode System

Software controls which device drives FIFO BRAM Port B via the `FIFO_MODE`
PCI register.

| Mode | Value | Port B Driver | Port A (in_rdy) | When to Use |
|------|-------|---------------|------------------|-------------|
| FIFO | 0 | FIFO drain FSM | Active (accepts packets) | Normal packet capture & drain |
| CPU | 1 | ARM ext_mem port | Blocked | CPU reads/modifies packet data |
| GPU | 2 | DMA engine or PCI | Blocked | DMA copies between FIFO and GPU DMEM |

**Mode transitions are software-controlled** (PCI register write). No hardware
interlock -- software must stop CPU/GPU before changing mode.

**Typical sequence:**
1. Mode 0: Packet arrives, FIFO captures it
2. Software reads `STATUS.pkt_ready = 1`
3. Software writes `FIFO_MODE = 1` (CPU mode)
4. CPU processes packet, software polls `CPU_STATUS.all_halted`
5. Software writes `FIFO_MODE = 2` (GPU mode)
6. DMA copies data to GPU, kernel runs, DMA copies results back
7. Software writes `FIFO_MODE = 0` (FIFO mode)
8. Software writes `FIFO_DRAIN = 1` to forward modified packet

---

## 4. The GPU (Our Code)

### 4.1 gpu_top.v -- Top-Level Interface

This is the single module that the wrapper instantiates:

```verilog
module gpu_top (
    input         clk,
    input         rst,              // active high, hold in reset until ready
    input  [31:0] thread_id,       // hardwire to 32'd0
    input  [31:0] block_id,        // hardwire to 32'd0
    input  [31:0] block_dim,       // hardwire to 32'd1
    output        kernel_done,     // 1 when HALT completes (registered)

    // Instruction Memory Port B (PCI loads programs here)
    input  [9:0]  ext_imem_addr,
    input         ext_imem_wr_en,
    input  [31:0] ext_imem_wr_data,
    output [31:0] ext_imem_rd_data,

    // Data Memory Port B (DMA or PCI accesses data here)
    input  [9:0]  ext_dmem_addr,
    input         ext_dmem_wr_en,
    input  [63:0] ext_dmem_wr_data,
    output [63:0] ext_dmem_rd_data
);
```

### 4.2 GPU Architecture Summary

6-stage pipelined SIMD processor:
```
FETCH -> DECODE -> EX1 -> EX2 -> EX3 -> WRITEBACK
```

Key specs:
- **Data width**: 64-bit (4 x 16-bit SIMD lanes)
- **Instruction width**: 32-bit
- **Register file**: 16 x 64-bit (R0 hardwired to 0)
- **IMEM**: 1024 x 32-bit (10-bit address)
- **DMEM**: 1024 x 64-bit (10-bit address)
- **Hazard resolution**: Stall-only (no forwarding)
- **Branch**: Resolved in EX1 (2-cycle penalty)
- **Data types**: int16 (signed/unsigned), BFloat16

### 4.3 GPU Instruction Set

| Opcode | Mnemonic | Description |
|--------|----------|-------------|
| 0x00 | NOP | No operation |
| 0x01 | ADD | 4-lane SIMD add |
| 0x02 | SUB | 4-lane SIMD subtract |
| 0x03 | MUL | 4-lane BF16 multiply |
| 0x04 | FMA | 4-lane BF16 fused multiply-add |
| 0x05 | MAX | 4-lane max |
| 0x10 | LD | Load 64-bit word from DMEM |
| 0x11 | ST | Store 64-bit word to DMEM |
| 0x18 | RELU | 4-lane ReLU (max(0, x)) |
| 0x1F | HALT | Stop execution, assert kernel_done |

### 4.4 HALT and kernel_done

```verilog
// In core_top.v:
reg halted_r;
always @(posedge clk) begin
    if (rst)           halted_r <= 1'b0;
    else if (exwb_is_halt) halted_r <= 1'b1;
end
assign halted = halted_r;    // REGISTERED ONLY (no combinational bypass)
```

`kernel_done` = `halted` = 1 one cycle after HALT reaches writeback.
DMEM writes are gated: `dmem_wr_en = dmem_wr_en_raw && !halted`.

**Critical**: The `halted` signal MUST be registered-only. A combinational
version (`halted_r || exwb_is_halt`) creates a timing path that fails at
125 MHz, causing ST instructions to silently not write. This was Bug #5 in
Lab 8.

### 4.5 GPU Memory Layout

Programs (IMEM) and data (DMEM) are separate. For packet processing:

```
IMEM: kernel program loaded via PCI before execution
  [0..N]  kernel instructions (e.g., 14 instructions for ANN inference)

DMEM: data loaded via DMA from FIFO BRAM
  [0..6]  packet payload (input data / weights)
  [7]     output (kernel writes result here)
  [8+]    available for larger programs
```

The kernel operates on DMEM via LD/ST instructions. It never touches FIFO BRAM
directly -- DMA copies data in and results out.

### 4.6 GPU Source Files

All in `src/gpu/`:
```
gpu_top.v              Top-level (instantiate this)
core_top.v             6-stage pipeline + halt detection
program_counter.v      PC with stall/branch/halt gating
fetch_stage.v          IF/ID valid tracking
decode_stage.v         Instruction decoder + register file
instruction_decoder.v  Opcode -> control signals
register_file.v        16 x 64-bit, R0=0, R13-15=thread params
pipeline_reg_idex.v    ID/EX pipeline register (stall/flush)
pipeline_reg_ex.v      EX1/EX2 and EX2/EX3 pipeline registers
pipeline_reg_exwb.v    EX3/WB pipeline register
execute_stage.v        3-stage EX with SIMD ALU + BF16 FMA
simd_alu.v             2-cycle int16/bf16 ALU
int16_alu.v            Signed/unsigned 16-bit lane operations
bf16_alu.v             BFloat16 multiply/add (unsigned arithmetic)
bf16_fma_unit.v        3-cycle fused multiply-add per lane
hazard_unit.v          RAW hazard detection (stall-only, 4-stage check)
writeback_stage.v      WB mux (ALU result or DMEM load)
instruction_memory.v   1024 x 32-bit dual-port BRAM
data_memory.v          1024 x 64-bit dual-port BRAM
```

Include file: `include/gpu_params.vh` (widths, depths, opcodes, register addresses).

---

## 5. The DMA Engine (Our Code, Lives in the Wrapper)

The DMA engine copies 64-bit words between FIFO BRAM and GPU DMEM. It sits
in the wrapper module alongside the port muxes.

### 5.1 DMA Registers

| Offset | Name | Description |
|--------|------|-------------|
| 0x2C | DMA_CTRL | bit[0]=start (auto-clear), bit[1]=direction |
| 0x2D | DMA_FIFO_ADDR | FIFO BRAM start address [7:0] |
| 0x2E | DMA_GPU_ADDR | GPU DMEM start address [9:0] |
| 0x2F | DMA_LENGTH | Word count [7:0] |

**Direction**: 0 = FIFO->GPU, 1 = GPU->FIFO.

### 5.2 DMA FSM

```
DMA_IDLE ---(start && mode==2 && length!=0)---> DMA_READ ---> DMA_COPY ---> DMA_IDLE
                                                 (1 cycle)     (N cycles)
```

- **DMA_IDLE**: Latches direction, addresses, length from registers.
- **DMA_READ**: Presents first read address. Waits 1 cycle for BRAM read latency.
- **DMA_COPY**: Pipelined: `rd_ptr` leads `wr_ptr` by 1. Copies 1 word/cycle.

### 5.3 DMA Data Flow

**FIFO->GPU (direction=0):**
```
FIFO BRAM Port B (read) -> fifo_proc_dout[63:0] -> gpu_dmem_wr_data -> GPU DMEM Port B (write)
```
DMA drives FIFO BRAM `proc_addr` with `dma_fifo_base + dma_rd_ptr`.
DMA drives GPU DMEM `ext_dmem_addr` with `dma_gpu_base + dma_wr_ptr`.

**GPU->FIFO (direction=1):**
```
GPU DMEM Port B (read) -> gpu_dmem_rd_data -> fifo_proc_din[63:0] -> FIFO BRAM Port B (write)
```
DMA drives GPU DMEM `ext_dmem_addr` with `dma_gpu_base + dma_rd_ptr`.
DMA drives FIFO BRAM `proc_addr` with `dma_fifo_base + dma_wr_ptr`.

**Note**: FIFO BRAM is 72 bits but GPU data is 64 bits. When writing FIFO BRAM
from GPU, the DMA pads `ctrl = 8'h00` (data word). When reading FIFO BRAM to
GPU, only `data[63:0]` is passed (ctrl byte stripped).

### 5.4 DMA Software Sequence

```
1. Set mode = 2 (GPU mode)
2. Write DMA_FIFO_ADDR = 1      (skip header, start at first data word)
3. Write DMA_GPU_ADDR = 0       (GPU DMEM destination)
4. Write DMA_LENGTH = 7         (7 data words)
5. Write DMA_CTRL = 0x01        (start, direction=FIFO->GPU)
6. Poll GPU_STATUS[1] (dma_active) until 0
7. [Run GPU kernel]
8. Write DMA_CTRL = 0x03        (start, direction=GPU->FIFO)
9. Poll GPU_STATUS[1] until 0
```

---

## 6. The 3-Way Port MUX (In the Wrapper)

This is the most critical piece of integration logic. Three devices compete
for FIFO BRAM Port B access.

### 6.1 FIFO Proc Port MUX

```verilog
wire cpu_drives_proc = (mode == 2'd1) && cpu_running;
wire dma_drives_proc = (mode == 2'd2) && dma_active;

always @(*) begin
    if (cpu_drives_proc) begin
        // CPU MEM stage drives Port B
        fifo_proc_addr = cpu_ext_mem_addr;
        fifo_proc_din  = {8'h00, cpu_ext_mem_din};  // pad ctrl=0x00
        fifo_proc_we   = cpu_ext_mem_we;
    end else if (dma_drives_proc) begin
        // DMA engine drives Port B (read or write depending on direction)
        fifo_proc_addr = dma_fifo_addr;
        fifo_proc_din  = {8'h00, gpu_dmem_rd_data};  // GPU->FIFO: GPU data
        fifo_proc_we   = dma_fifo_we;
    end else begin
        // PCI registers drive Port B (default)
        fifo_proc_addr = reg_bram_addr[7:0];
        fifo_proc_din  = {reg_bram_wctrl[7:0], reg_bram_wd_hi, reg_bram_wd_lo};
        fifo_proc_we   = bram_pci_wr_strobe;  // REGISTERED strobe, not cmd[0]
    end
end
```

### 6.2 GPU DMEM Ext Port MUX

```verilog
always @(*) begin
    if (dma_active) begin
        // DMA drives GPU DMEM Port B
        gpu_dmem_addr    = dma_gpu_addr;
        gpu_dmem_wr_en   = dma_gpu_we;
        gpu_dmem_wr_data = fifo_proc_dout[63:0];  // FIFO->GPU: FIFO data
    end else begin
        // PCI drives GPU DMEM Port B
        gpu_dmem_addr    = reg_gpu_dmem_addr[9:0];
        gpu_dmem_wr_en   = gpu_dmem_pci_wr_strobe;  // REGISTERED strobe
        gpu_dmem_wr_data = {reg_gpu_dmem_wd_hi, reg_gpu_dmem_wd_lo};
    end
end
```

### 6.3 Registered PCI Write Strobes

PCI writes through combinational muxes fail timing at 125 MHz. Use registered
strobes instead:

```verilog
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

These produce clean 1-cycle pulses one clock after the PCI write. Direct paths
(CPU IMEM, CPU DMEM, GPU IMEM) don't need strobes because they don't go through
muxes. Only FIFO BRAM and GPU DMEM (which go through 3-way and 2-way muxes
respectively) need registered strobes.

---

## 7. PCI Register Map

48 total registers, 6-bit word-addressed. The wrapper implements a NF2.1
register ring: incoming requests are checked against block address, claimed
if matching, or passed downstream.

### 7.1 Register Partition

| Range | Owner | Purpose |
|-------|-------|---------|
| 0x00-0x0B | CPU subgroup (FIFO) | FIFO control, status, BRAM access |
| 0x0C-0x1A | CPU subgroup (CPU) | CPU control, IMEM/DMEM, logic analyzer |
| 0x1B-0x1F | (padding) | 5 reserved registers for alignment |
| 0x20-0x2B | GPU subgroup (GPU) | GPU control, IMEM/DMEM |
| 0x2C-0x2F | GPU subgroup (DMA) | DMA control, addresses, length |

### 7.2 GPU Registers (Our Responsibility)

```
0x20  GPU_CTRL        [RW]  bit[0]=gpu_reset (1=hold in reset, default=1)
0x21  GPU_STATUS      [RO]  bit[0]=kernel_done, bit[1]=dma_active
0x22  GPU_IMEM_ADDR   [RW]  IMEM address [9:0]
0x23  GPU_IMEM_WDATA  [RW]  IMEM write data [31:0]
0x24  GPU_IMEM_CMD    [RW]  bit[0]=write strobe (auto-clear)
0x25  GPU_IMEM_RDATA  [RO]  IMEM readback [31:0]
0x26  GPU_DMEM_ADDR   [RW]  DMEM address [9:0]
0x27  GPU_DMEM_WD_LO  [RW]  DMEM write data [31:0]
0x28  GPU_DMEM_WD_HI  [RW]  DMEM write data [63:32]
0x29  GPU_DMEM_CMD    [RW]  bit[0]=write strobe (auto-clear)
0x2A  GPU_DMEM_RD_LO  [RO]  DMEM readback [31:0]
0x2B  GPU_DMEM_RD_HI  [RO]  DMEM readback [63:32]
0x2C  DMA_CTRL        [RW]  bit[0]=start (auto-clear), bit[1]=direction
0x2D  DMA_FIFO_ADDR   [RW]  FIFO BRAM start [7:0]
0x2E  DMA_GPU_ADDR    [RW]  GPU DMEM start [9:0]
0x2F  DMA_LENGTH      [RW]  word count [7:0]
```

### 7.3 FIFO + CPU Registers (Their Responsibility)

```
0x00  CTRL            [RW]  bit[0]=soft_reset
0x01  STATUS          [RO]  {pkt_word_cnt, head, tail, empty, full, pkt_ready}
0x02  FIFO_MODE       [RW]  mode[1:0] (0=FIFO, 1=CPU, 2=GPU)
0x03  FIFO_DRAIN      [RW]  bit[0]=drain_start (auto-clear)
0x04  BRAM_ADDR       [RW]  BRAM address [7:0]
0x05  BRAM_WD_LO      [RW]  write data [31:0]
0x06  BRAM_WD_HI      [RW]  write data [63:32]
0x07  BRAM_WCTRL      [RW]  write ctrl [7:0]
0x08  BRAM_CMD        [RW]  bit[0]=write strobe (auto-clear)
0x09  BRAM_RD_LO      [RO]  read data [31:0]
0x0A  BRAM_RD_HI      [RO]  read data [63:32]
0x0B  BRAM_RCTRL      [RO]  read ctrl [7:0]
0x0C  CPU_CTRL        [RW]  bit[0]=start_stop, bit[1]=cpu_reset
0x0D  CPU_STATUS      [RO]  {all_halted, cpsr, thread_id, running, ~reset}
0x0E-0x1A  CPU IMEM/DMEM/LA registers
```

---

## 8. What to Tell the Other Subgroup

### 8.1 What We Provide

1. **GPU source files** -- all 18 .v files in `src/gpu/` plus `include/gpu_params.vh`
2. **DMA engine RTL** -- extract from `lab8_wrapper.v` (lines ~220-280 in Lab 8)
3. **Port mux logic** -- the 3-way FIFO proc mux and 2-way GPU DMEM mux
4. **GPU + DMA register definitions** -- offsets 0x20-0x2F
5. **Registered PCI write strobe logic** -- for BRAM and GPU DMEM paths
6. **Test scripts** -- `lab8reg.py` with 5 kernel tests + 2 ANN inference tests
7. **Hex programs** -- 5 kernel .hex files + ANN kernel + data files

### 8.2 What We Need From Them

1. **FIFO proc port interface** -- exact signal names and widths for Port B
   (must be: addr[7:0], din[71:0], we, dout[71:0], plus mode[1:0] input)
2. **CPU ext_mem interface** -- exact signal names
   (must be: addr[7:0], din[63:0], we, dout[63:0])
3. **FIFO status signals** -- pkt_ready, fifo_empty, pkt_word_cnt
4. **CPU status signals** -- all_halted, cpu_running (for `cpu_drives_proc`)
5. **Confirmation of in_rdy mode gating** -- their FIFO MUST gate in_rdy by mode==0
6. **Their register addresses** -- offsets 0x00-0x1A (we take 0x20-0x2F)
7. **NF2 XML file** -- their portion of the register declarations

### 8.3 Interface Agreement Checklist

Before writing wrapper code, agree on:

- [ ] FIFO BRAM width: 72 bits (8 ctrl + 64 data)?
- [ ] FIFO BRAM depth: 256 entries (8-bit address)?
- [ ] CPU ext_mem data width: 64 bits?
- [ ] Mode register at offset 0x02, values 0/1/2?
- [ ] `in_rdy` gated by `mode == 0` in FIFO?
- [ ] CPU ext_mem_dout carries only data[63:0] (ctrl stripped)?
- [ ] GPU IMEM: 1024 x 32-bit, DMEM: 1024 x 64-bit?
- [ ] Register partition: FIFO(0x00-0x0B), CPU(0x0C-0x1A), GPU(0x20-0x2B), DMA(0x2C-0x2F)?
- [ ] Padding registers (0x1B-0x1F) in XML to align GPU at 0x20?
- [ ] Verilog-2001 only (no SystemVerilog)?
- [ ] Every `case` has `default`, every flip-flop has reset?

---

## 9. Operational Sequences (What to Demo)

### 9.1 Capture + CPU Modify + Drain

```
1. Wait for packet:       poll STATUS.pkt_ready == 1
2. Switch to CPU mode:    FIFO_MODE = 1
3. Start CPU:             CPU_CTRL = 0x01  (atomic: release reset + start)
4. Wait for completion:   poll CPU_STATUS.all_halted == 1
5. Stop CPU:              CPU_CTRL = 0x02  (re-assert reset)
6. Verify:                read BRAM via PCI (BRAM_ADDR + BRAM_RD_LO/HI)
7. Return to FIFO mode:  FIFO_MODE = 0
8. Drain:                 FIFO_DRAIN = 1
```

### 9.2 Capture + GPU Process + Drain

```
1. Wait for packet:       poll STATUS.pkt_ready == 1
2. Switch to GPU mode:    FIFO_MODE = 2
3. Load GPU IMEM:         GPU_CTRL = 0x01 (hold reset)
                          for each instruction: set ADDR, WDATA, CMD=1
4. DMA FIFO->GPU:         DMA_FIFO_ADDR=1, DMA_GPU_ADDR=0, DMA_LENGTH=7
                          DMA_CTRL = 0x01 (start, dir=FIFO->GPU)
                          poll GPU_STATUS.dma_active == 0
5. Run kernel:            GPU_CTRL = 0x00 (release reset)
                          poll GPU_STATUS.kernel_done == 1
6. Stop GPU:              GPU_CTRL = 0x01 (re-assert reset)
7. DMA GPU->FIFO:         DMA_FIFO_ADDR=1, DMA_GPU_ADDR=0, DMA_LENGTH=8
                          DMA_CTRL = 0x03 (start, dir=GPU->FIFO)
                          poll GPU_STATUS.dma_active == 0
8. Verify:                read BRAM via PCI
9. Return to FIFO mode:   FIFO_MODE = 0
10. Drain:                FIFO_DRAIN = 1
```

### 9.3 CPU + GPU Sequential

Same packet processed by CPU first (mode=1), then GPU (mode=2), then drained
(mode=0). Just chain sequences 9.1 and 9.2, skip the initial capture and
final drain in the middle.

---

## 10. Bugs We Hit in Lab 8 (Avoid in Lab 9)

| Bug | Symptom | Fix | Who Owns |
|-----|---------|-----|----------|
| #1 CPU atomic start | CPU executes stale code when rst=0, start_stop=0 | Write CPU_CTRL=0x01 atomically | SW |
| #2 in_rdy not gated | Network packets corrupt BRAM during CPU/GPU mode | Gate in_rdy by mode==0 | CPU subgroup (FIFO) |
| #3 PC wrap after HALT | Program re-executes after HALT | Gate PC advance by halted flag | CPU subgroup (IF_stage) |
| #4 PCI BRAM write timing | Combinational mux path too long at 125 MHz | Use registered PCI write strobes | Wrapper |
| #5 GPU HALT gating | Combinational halted signal suppresses ST writes | Use registered-only halted | GPU subgroup (core_top) |

---

## 11. Verilog Coding Rules (ISE 10.1)

Both subgroups must follow:

1. **Verilog-2001 only** -- `reg`/`wire` not `logic`, `always @(posedge clk)` not `always_ff`
2. **Every `case` must have `default`** -- prevents latch inference
3. **Every flip-flop needs explicit reset** -- VP50 has no global reset
4. **BRAM inference pattern:**
   ```verilog
   reg [width] mem [0:depth-1];
   always @(posedge clk) begin
       if (wr_en) mem[addr] <= wr_data;
       rd_data <= mem[addr];  // synchronous read
   end
   ```
5. **No `$display` or `$readmemh`** in synthesizable RTL
6. **Multiplier inference**: `assign product = a * b;` with operands <= 18 bits

---

## 12. File Organization for Lab 9

```
src/
  fifo/
    fifo_bram.v              (their code)
    convertible_fifo.v       (their code)
  arm/
    processor.v              (their code)
    IF_stage.v               (their code)
    ID.v                     (their code)
    ... (other pipeline stages)
  gpu/
    gpu_top.v                (our code)
    core_top.v               (our code)
    ... (17 other GPU files)
  lab9_wrapper.v             (joint: instantiates all three + DMA + registers)
  user_data_path.v           (NF2 glue: data path chain)
include/
  lab9_reg_defines.vh        (joint: register offsets)
  gpu_params.vh              (our code)
  lab9.xml                   (joint: NF2 register declarations)
tb/
  sim_primitives.v           (XOR2/AND2/OR3 stubs for iverilog)
  tb_lab9_*.v                (joint testbenches)
sw/
  lab9reg.py                 (joint: Python test script)
  kernels/                   (GPU kernel hex files)
```

The wrapper (`lab9_wrapper.v`) is the main integration point. It can be
written by either subgroup, or jointly. It contains:
- Convertible FIFO instantiation
- ARM CPU instantiation
- GPU instantiation
- DMA engine
- 3-way proc port mux
- 2-way GPU DMEM ext port mux
- PCI register ring (NF2.1 UDP protocol)
- Registered PCI write strobes

---

## 13. Quick Reference: GPU Instantiation Template

```verilog
// GPU instantiation in wrapper
gpu_top u_gpu (
    .clk             (clk),
    .rst             (gpu_reset),           // reset | reg_gpu_ctrl[0]
    .thread_id       (32'd0),
    .block_id        (32'd0),
    .block_dim       (32'd1),
    .kernel_done     (gpu_kernel_done),
    // IMEM Port B (PCI-only)
    .ext_imem_addr   (reg_gpu_imem_addr[9:0]),
    .ext_imem_wr_en  (gpu_imem_wr_strobe),
    .ext_imem_wr_data(reg_gpu_imem_wdata[31:0]),
    .ext_imem_rd_data(gpu_imem_rd_data),
    // DMEM Port B (muxed: PCI or DMA)
    .ext_dmem_addr   (gpu_dmem_addr),       // from 2-way mux
    .ext_dmem_wr_en  (gpu_dmem_wr_en),      // from 2-way mux
    .ext_dmem_wr_data(gpu_dmem_wr_data),    // from 2-way mux
    .ext_dmem_rd_data(gpu_dmem_rd_data)     // to DMA + PCI readback
);

// GPU reset: held in reset by default (reg_gpu_ctrl resets to 0x1)
assign gpu_reset = reset | reg_gpu_ctrl[0];
```

---

## 14. Verified Test Results (Lab 8, March 20 2026)

All tests pass on NetFPGA hardware (nf5.usc.edu) with the refined bitfile:

| Test | Type | Result |
|------|------|--------|
| cpu_test (all_halted=1) | CPU-FIFO | PASS |
| vec_add_i16 | GPU standalone | PASS |
| vec_sub_i16 | GPU standalone | PASS |
| bf16_mul | GPU standalone | PASS |
| bf16_fma | GPU standalone | PASS |
| relu_i16 | GPU standalone | PASS |
| ANN handcrafted (BF16) | GPU standalone | PASS |
| ANN trained (BF16) | GPU standalone | PASS |
| ANN handcrafted integrated | FIFO->DMA->GPU->DMA->FIFO | PASS |
| ANN trained integrated | FIFO->DMA->GPU->DMA->FIFO | PASS |
| **Total** | | **9/9 + cpu_test** |
