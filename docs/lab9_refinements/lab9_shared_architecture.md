# Lab 9 -- Shared Architecture & Interface Specification

Shared document for merging CPU subgroup and GPU subgroup designs into a
unified network processor on the NetFPGA V2 (Virtex-II Pro XC2VP50).

---

## 1. System Overview

```
         NetFPGA V2 (125 MHz core clock)
         reference_nic base project

  NF2.1 data path chain:
    input_arbiter -> output_port_lookup -> [lab8_wrapper] -> output_queues

  Inside lab8_wrapper:
    +-----------------------------------------------------------------+
    | Convertible FIFO (256x72 dual-port BRAM)                        |
    |   Port A: network in/out (NF2.1 pipeline)                       |
    |   Port B: processor access (muxed: PCI / CPU / DMA)             |
    +-----------------------------------------------------------------+
    |   ARM CPU (4-thread barrel)  <--FIFO BRAM-->  GPU (4-lane SIMD) |
    |   5-stage pipeline                            6-stage pipeline   |
    |   32-bit ARM instructions                     32-bit custom ISA  |
    |   64-bit data path                            64-bit data path   |
    +-----------------------------------------------------------------+
    |   DMA Engine: FIFO BRAM <-> GPU DMEM, 1 word/cycle              |
    +-----------------------------------------------------------------+
    |   PCI Register Ring (NF2.1 UDP protocol)                        |
    |   48 registers, 6-bit word-addressed                            |
    +-----------------------------------------------------------------+
```

**Top-level file:** `src/lab8_wrapper.v` (649 lines)
**Data path glue:** `src/user_data_path.v` (490 lines)

---

## 2. Operating Modes

Controlled by PCI register `LAB8_FIFO_MODE` (offset 0x02), bits [1:0]:

| Mode | Value | FIFO Port B driver | Port A behavior |
|------|-------|--------------------|-----------------|
| FIFO | 0 | FIFO drain FSM (rd_ptr) | Accepts network packets |
| CPU  | 1 | ARM CPU ext_mem port | Blocked (in_rdy=0) |
| GPU  | 2 | DMA engine or PCI | Blocked (in_rdy=0) |

Mode transitions are software-controlled via PCI writes. No hardware interlock
-- software must stop CPU/GPU before changing mode.

---

## 3. Convertible FIFO

**File:** `src/fifo/convertible_fifo.v`
**BRAM:** `src/fifo/fifo_bram.v` -- 256 x 72-bit true dual-port

### 3.1 Port Interface

```
module convertible_fifo (
    input         clk, reset,
    // NF2.1 input
    input  [63:0] in_data,
    input  [7:0]  in_ctrl,
    input         in_wr,
    output        in_rdy,
    // NF2.1 output
    output [63:0] out_data,
    output [7:0]  out_ctrl,
    output        out_wr,
    input         out_rdy,
    // Processor access port (Port B)
    input  [7:0]  proc_addr,    // 8-bit: 0-255
    input  [71:0] proc_din,     // {ctrl[7:0], data[63:0]}
    input         proc_we,
    output [71:0] proc_dout,
    // Control
    input  [1:0]  mode,         // 0=FIFO, 1=CPU, 2=GPU
    input         drain_start,
    // Status
    output        pkt_ready, fifo_full, fifo_empty,
    output [7:0]  pkt_word_cnt,
    // Head/tail (unused in current design)
    input  [7:0]  head_wr_val, input head_wr_en,
    input  [7:0]  tail_wr_val, input tail_wr_en,
    output [7:0]  head_rd, tail_rd
);
```

### 3.2 FSM States

```
S_IDLE(0) -> S_RECEIVING(1) -> S_PKT_BUFFERED(2)
                                     |
                              drain_start
                                     v
                            S_DRAIN_WAIT1(3) -> S_DRAIN_WAIT2(4) -> S_DRAINING(5)
                                                                          |
                                                                     last word
                                                                          v
                                                                      S_IDLE
```

- Buffers exactly 1 packet. Packet length from NF2.1 header data[39:32].
- BRAM has 1-cycle read latency, hence 2 drain-wait states.

### 3.3 BRAM Word Format (72 bits)

```
[71:64] = ctrl (0xFF for header, 0x00 for data)
[63:0]  = data
```

### 3.4 NF2.1 Packet Header (first word, ctrl=0xFF)

```
data[63:48] = dst_port[15:0]   (one-hot: 0x01=MAC0, 0x02=CPU0, etc.)
data[47:32] = word_length[15:0] (total words including header)
data[31:16] = src_port[15:0]
data[15:0]  = byte_length[15:0]
```

---

## 4. ARM CPU

**Files:** `src/arm/processor.v` (top), `IF_stage.v`, `ID.v`, `EX.v`,
`data_mem.v`, `memwb_reg.v` (WB stage), pipeline regs (`ifid_reg.v`,
`idex_reg.v`, `exmem_reg.v`), `alu64.v`, `addsub64.v`, `logic64.v`,
`inst_mem.v`, `logic_analyzer.v`

### 4.1 Top-Level Interface

```
module processor (
    input         clk, rst,
    input         start_stop,       // 1=running, 0=paused
    // IMEM Port B (PCI)
    input         intf_wen_imem,
    input  [8:0]  intf_addr_imem,   // 512-word IMEM
    input  [31:0] intf_data_imem,
    output [31:0] intf_dout_imem,
    // DMEM Port B (PCI)
    input         web,
    input  [63:0] dinb,
    input  [7:0]  addrb,            // 256-entry DMEM
    output [63:0] doutb,
    // External memory (FIFO BRAM via MEM stage)
    output [7:0]  ext_mem_addr,
    output [63:0] ext_mem_din,
    output        ext_mem_we,
    input  [63:0] ext_mem_dout,
    // Logic analyzer
    input  [10:0] la_rd_addr,
    output [63:0] la_rd_data,
    // Debug
    output [3:0]  dbg_cpsr_0..3,
    output [1:0]  dbg_thread_id,
    output        all_halted
);
```

### 4.2 Pipeline: 5 stages, 4-thread barrel

```
IF -> ID -> EX -> MEM -> WB
```

- **IF**: 4 independent PCs. Thread N starts at IMEM word N*128. PC confined to 128-word region per thread.
- **ID**: 64-entry register file (4 threads x 16 regs x 64-bit). Condition evaluator. Branch resolution.
- **EX**: ALU (64-bit) + barrel shifter. Combinational.
- **MEM**: 256-entry DMEM (64-bit). addr[7]=0 -> internal DMEM. addr[7]=1 -> ext_mem (FIFO BRAM 0-127).
- **WB**: Mux between ALU result and memory read.

No data forwarding. No hazard detection. Fine-grained multithreading (4 threads) eliminates same-thread data hazards (4-cycle separation).

### 4.3 ISA Subset (ARM-compatible, 64-bit data)

**Supported:**
- DP: AND, EOR, SUB, ADD, TST, TEQ, CMP, ORR, MOV, BIC, MVN
- Memory: LDR, STR (immediate offset, U-bit for +/-)
- Branch: B, BL (not link-save), BX
- Special: NOP (0x00000000), HALT (0xFFFFFFFF)
- Condition codes: all 16 ARM conditions (but only gate branches currently)
- S-bit: set flags (N, Z, C, V per-thread)

**Not implemented:** ADC, SBC, RSB, RSC, CMN, multiply, coprocessor, thumb

### 4.4 IMEM Layout (512 x 32-bit)

```
Word 0-127:   Thread 0
Word 128-255: Thread 1
Word 256-383: Thread 2
Word 384-511: Thread 3
```

PCI loads via 9-bit address (0-511). All 4 threads share the same program
image (replicated at each base) for CUDA-style parallelism.

### 4.5 DMEM Layout (256 x 64-bit)

```
Address 0-127:   Internal DMEM (CPU addr[7]=0)
Address 128-255: Maps to FIFO BRAM 0-127 (CPU addr[7]=1)
```

PCI can access all 256 entries. CPU only uses 0-127 directly (internal) or
128-255 (FIFO BRAM pass-through).

### 4.6 Logic Analyzer

2048 x 64-bit circular trace buffer. Records MEM/WB events (store, load,
writeback). Read via PCI. No wrap indicator.

---

## 5. GPU (SIMD Coprocessor)

**Files:** `src/gpu/gpu_top.v` (top), `core_top.v`, `fetch_stage.v`,
`decode_stage.v`, `instruction_decoder.v`, `register_file.v`,
`execute_stage.v`, `simd_alu.v`, `int16_alu.v`, `bf16_alu.v`,
`bf16_fma_unit.v`, `hazard_unit.v`, `writeback_stage.v`,
pipeline regs (`pipeline_reg_idex.v`, `pipeline_reg_ex.v`,
`pipeline_reg_exwb.v`), `instruction_memory.v`, `data_memory.v`,
`program_counter.v`

**Params:** `include/gpu_params.vh`

### 5.1 Top-Level Interface

```
module gpu_top (
    input         clk, rst,
    input  [31:0] thread_id,     // hardwired 0 in lab8
    input  [31:0] block_id,      // hardwired 0
    input  [31:0] block_dim,     // hardwired 1
    output        kernel_done,
    // IMEM ext port (PCI only)
    input  [9:0]  ext_imem_addr,
    input         ext_imem_wr_en,
    input  [31:0] ext_imem_wr_data,
    output [31:0] ext_imem_rd_data,
    // DMEM ext port (PCI or DMA)
    input  [9:0]  ext_dmem_addr,
    input         ext_dmem_wr_en,
    input  [63:0] ext_dmem_wr_data,
    output [63:0] ext_dmem_rd_data
);
```

### 5.2 Pipeline: 6 stages, single thread

```
FETCH -> DECODE -> EX1 -> EX2 -> EX3 -> WB
```

- EX1/EX2/EX3 split to meet timing for BF16 FMA multiply-accumulate.
- Hazard unit inserts stalls for RAW hazards.
- Branch resolved in DECODE (1-cycle penalty).

### 5.3 ISA (Custom 32-bit, SIMD)

```
R-type: [31:27]opcode [26:23]rd [22:19]rs1 [18:15]rs2 [14:12]dtype [11:0]func
I-type: [31:27]opcode [26:23]rd [22:19]rs1 [18:0]imm19
M-type: [31:27]opcode [26:23]rd [22:19]rbase [14:12]dtype [11:0]offset12
F-type: [31:27]opcode [26:23]rd [22:19]rs1 [18:15]rs2 [14:12]dtype [11:8]rs3
B-type: [31:27]opcode [26:23]rs1 [22:19]rs2 [18:0]offset19
```

**Opcodes:**

| Op | Encoding | Description |
|----|----------|-------------|
| NOP  | 0x00 | No operation |
| ADD  | 0x01 | SIMD add (4-lane int16 or bf16) |
| SUB  | 0x02 | SIMD subtract |
| MUL  | 0x03 | SIMD multiply |
| FMA  | 0x04 | Fused multiply-add (tensor core op) |
| MAX  | 0x05 | SIMD max |
| MOV  | 0x0C | Register move |
| ADDI | 0x0E | Add immediate (scalar) |
| LD   | 0x10 | Load from DMEM |
| ST   | 0x11 | Store to DMEM |
| BLT  | 0x16 | Branch if less than (signed 64-bit compare) |
| BGE  | 0x17 | Branch if greater or equal |
| RELU | 0x18 | Activation function (clamp negative to 0) |
| MOVI | 0x1B | Move immediate |
| HALT | 0x1F | Stop execution |

**Data types (dtype field):** S16(000), U16(001), S32(010), BF16(100)

**Special registers:** R0=zero, R13=threadIdx.x, R14=blockIdx.x, R15=blockDim.x

### 5.4 Memories

- **IMEM:** 1024 x 32-bit dual-port BRAM. Port A = core fetch. Port B = PCI load.
- **DMEM:** 1024 x 64-bit dual-port BRAM. Port A = core LD/ST. Port B = PCI or DMA.

### 5.5 Register File

16 registers x 64-bit. R0 hardwired to 0. SIMD operations treat each 64-bit
register as 4 x 16-bit lanes: `{lane3[63:48], lane2[47:32], lane1[31:16], lane0[15:0]}`.

---

## 6. DMA Engine

**Location:** `src/lab8_wrapper.v` lines 220-278

### 6.1 Interface (internal to lab8_wrapper)

Controlled by 4 PCI registers:
- `DMA_CTRL` (0x2C): bit[0]=start (auto-clear), bit[1]=direction
- `DMA_FIFO_ADDR` (0x2D): FIFO BRAM start address [7:0]
- `DMA_GPU_ADDR` (0x2E): GPU DMEM start address [9:0]
- `DMA_LENGTH` (0x2F): word count [7:0]

### 6.2 FSM

```
DMA_IDLE -> DMA_READ -> DMA_COPY -> ... -> DMA_IDLE
```

- 1-cycle setup (DMA_READ), then 1 word/cycle (DMA_COPY).
- Direction: 0 = FIFO BRAM -> GPU DMEM, 1 = GPU DMEM -> FIFO BRAM.
- Only starts when mode=2 and length != 0.
- Read pointer leads write pointer by 1 (pipeline latency).

### 6.3 Port Mux Priority

FIFO BRAM proc port (Port B):
```
1. CPU ext_mem     (when mode=1 and cpu_running)
2. DMA engine      (when mode=2 and dma_active)
3. PCI registers   (default)
```

GPU DMEM ext port (Port B):
```
1. DMA engine      (when dma_active)
2. PCI registers   (default)
```

---

## 7. PCI Register Map

Block address: `LAB8_BLOCK_ADDR = 17'h00011`
Register width: 32-bit. Word-addressed (6-bit offset).
PCI byte address = `0x2001100 + offset * 4`.

### 7.1 FIFO Registers (0x00 - 0x0B)

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x00 | CTRL | RW | bit[0] = soft_reset |
| 0x01 | STATUS | RO | {pkt_word_cnt[7:0], head[7:0], tail[7:0], 5'b0, empty, full, pkt_ready} |
| 0x02 | FIFO_MODE | RW | mode[1:0]: 0=FIFO, 1=CPU, 2=GPU |
| 0x03 | FIFO_DRAIN | RW | bit[0] = drain_start (auto-clear) |
| 0x04 | BRAM_ADDR | RW | BRAM address [7:0] |
| 0x05 | BRAM_WD_LO | RW | Write data [31:0] |
| 0x06 | BRAM_WD_HI | RW | Write data [63:32] |
| 0x07 | BRAM_WCTRL | RW | Write ctrl [7:0] |
| 0x08 | BRAM_CMD | RW | bit[0] = write strobe (auto-clear) |
| 0x09 | BRAM_RD_LO | RO | Read data [31:0] |
| 0x0A | BRAM_RD_HI | RO | Read data [63:32] |
| 0x0B | BRAM_RCTRL | RO | Read ctrl [7:0] |

### 7.2 CPU Registers (0x0C - 0x1A)

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x0C | CPU_CTRL | RW | bit[0]=start_stop, bit[1]=cpu_reset |
| 0x0D | CPU_STATUS | RO | {all_halted[31], 3'b0, cpsr_3[27:24], cpsr_2[23:20], cpsr_1[19:16], cpsr_0[15:12], thread_id[11:10], 6'b0, 2'b0, running[1], ~reset[0]} |
| 0x0E | CPU_IMEM_ADDR | RW | IMEM address [8:0] |
| 0x0F | CPU_IMEM_WDATA | RW | IMEM write data [31:0] |
| 0x10 | CPU_IMEM_CMD | RW | bit[0] = write strobe (auto-clear) |
| 0x11 | CPU_IMEM_RDATA | RO | IMEM readback [31:0] |
| 0x12 | CPU_DMEM_ADDR | RW | DMEM address [7:0] |
| 0x13 | CPU_DMEM_WDATA_LO | RW | DMEM write data [31:0] |
| 0x14 | CPU_DMEM_WDATA_HI | RW | DMEM write data [63:32] |
| 0x15 | CPU_DMEM_CMD | RW | bit[0] = write strobe (auto-clear) |
| 0x16 | CPU_DMEM_RDATA_LO | RO | DMEM readback [31:0] |
| 0x17 | CPU_DMEM_RDATA_HI | RO | DMEM readback [63:32] |
| 0x18 | CPU_LA_ADDR | RW | Logic analyzer address [10:0] |
| 0x19 | CPU_LA_RDATA_LO | RO | LA readback [31:0] |
| 0x1A | CPU_LA_RDATA_HI | RO | LA readback [63:32] |

### 7.3 GPU Registers (0x20 - 0x2B)

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x20 | GPU_CTRL | RW | bit[0] = gpu_reset (1=hold in reset) |
| 0x21 | GPU_STATUS | RO | {30'b0, dma_active[1], kernel_done[0]} |
| 0x22 | GPU_IMEM_ADDR | RW | IMEM address [9:0] |
| 0x23 | GPU_IMEM_WDATA | RW | IMEM write data [31:0] |
| 0x24 | GPU_IMEM_CMD | RW | bit[0] = write strobe (auto-clear) |
| 0x25 | GPU_IMEM_RDATA | RO | IMEM readback [31:0] |
| 0x26 | GPU_DMEM_ADDR | RW | DMEM address [9:0] |
| 0x27 | GPU_DMEM_WDATA_LO | RW | DMEM write data [31:0] |
| 0x28 | GPU_DMEM_WDATA_HI | RW | DMEM write data [63:32] |
| 0x29 | GPU_DMEM_CMD | RW | bit[0] = write strobe (auto-clear) |
| 0x2A | GPU_DMEM_RDATA_LO | RO | DMEM readback [31:0] |
| 0x2B | GPU_DMEM_RDATA_HI | RO | DMEM readback [63:32] |

### 7.4 DMA Registers (0x2C - 0x2F)

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x2C | DMA_CTRL | RW | bit[0]=start (auto-clear), bit[1]=dir (0=FIFO->GPU, 1=GPU->FIFO) |
| 0x2D | DMA_FIFO_ADDR | RW | FIFO BRAM start address [7:0] |
| 0x2E | DMA_GPU_ADDR | RW | GPU DMEM start address [9:0] |
| 0x2F | DMA_LENGTH | RW | Word count [7:0] |

### 7.5 Auto-Clear Strobes

These register bits auto-clear to 0 one cycle after being written to 1:
- FIFO_DRAIN[0], BRAM_CMD[0]
- CPU_IMEM_CMD[0], CPU_DMEM_CMD[0]
- GPU_IMEM_CMD[0], GPU_DMEM_CMD[0]
- DMA_CTRL[0]

Additionally, `bram_pci_wr_strobe` and `gpu_dmem_pci_wr_strobe` are
registered strobes that bypass the combinational mux for reliable writes at
125 MHz (Bug #4 fix).

---

## 8. NF2.1 Register Ring Protocol

```
udp_reg_master -> input_arbiter -> output_port_lookup -> lab8_wrapper -> output_queues -> (back)
```

Each module in the ring:
1. Latches incoming request (1-cycle pipeline)
2. If `reg_req_in && !reg_ack_in && block_match`: claim request, set `reg_ack_out=1`
3. Write: store `reg_data_in` to addressed register
4. Read: place register value in `reg_data_out`
5. Pass everything downstream

lab8_wrapper register defines: `include/lab8_reg_defines.vh`
NF2 XML: `include/lab8.xml` (48 registers, 5 padding slots between CPU and GPU)

---

## 9. Software Control Flow (lab8reg Perl script)

**File:** `sw/lab8reg` (host-side PCI register access via `regwrite`/`regread`)

### 9.1 CUDA-style Execution Sequence

```
1. Wait for packet:    poll STATUS until pkt_ready=1
2. Set mode=1 (CPU):   write FIFO_MODE=1
3. Load CPU program:   for each word: IMEM_ADDR=addr, IMEM_WDATA=data, IMEM_CMD=1
4. Start CPU:          write CPU_CTRL=0x01 (start=1, reset=0)
5. Poll CPU done:      read CPU_STATUS until all_halted=1 (or timeout)
6. Stop CPU:           write CPU_CTRL=0x00
7. Set mode=2 (GPU):   write FIFO_MODE=2
8. DMA FIFO->GPU:      set DMA_FIFO_ADDR, DMA_GPU_ADDR, DMA_LENGTH, DMA_CTRL=0x01
9. Poll DMA done:      read GPU_STATUS until dma_active=0
10. Release GPU reset:  write GPU_CTRL=0x00
11. Load GPU kernel:    for each word: IMEM_ADDR, IMEM_WDATA, IMEM_CMD=1
12. Start GPU:          (GPU runs on reset release with program loaded)
13. Poll GPU done:      read GPU_STATUS until kernel_done=1
14. Hold GPU reset:     write GPU_CTRL=0x01
15. DMA GPU->FIFO:      set addresses/length, DMA_CTRL=0x03 (start=1, dir=1)
16. Set mode=0 (FIFO):  write FIFO_MODE=0
17. Drain packet:       write FIFO_DRAIN=1
```

### 9.2 Host Software Commands (sw/lab8reg)

**FIFO:** status, fifo_reset, fifo_read, bram_write_full, packet_echo
**CPU:** cpu_reset, cpu_start, cpu_stop, cpu_status, cpu_load_imem, cpu_read_imem, cpu_read_dmem, cpu_write_dmem, cpu_la_read, cpu_test
**GPU:** gpu_reset, gpu_start, gpu_stop, gpu_status, gpu_load_imem, gpu_read_imem, gpu_read_dmem, gpu_write_dmem
**DMA:** dma_fifo_to_gpu, dma_gpu_to_fifo
**Integration:** gpu_test (full pipeline: reset -> check pkt -> DMA -> kernel -> DMA -> drain)

---

## 10. Data Flow for Dot Product (Lab 9 Test Case)

Lab 9 requires a CUDA program for dot product of two large vectors.

### 10.1 Network Packet Format

Host node sends two packets, each containing vector data:
```
Packet 1 (Vector A):  [NF2 header][A0,A1,A2,A3][A4,A5,A6,A7]...
Packet 2 (Vector B):  [NF2 header][B0,B1,B2,B3][B4,B5,B6,B7]...
```

Each 64-bit data word holds 4 x int16 elements (SIMD-aligned).

### 10.2 Processing Pipeline

```
1. FIFO captures Packet 1 (Vector A)
2. CPU mode: ARM copies relevant BRAM words to DMEM (or just set pointers)
3. GPU mode: DMA vector A from FIFO BRAM -> GPU DMEM[0..N]
4. FIFO drains/resets, captures Packet 2 (Vector B)
5. GPU mode: DMA vector B from FIFO BRAM -> GPU DMEM[N..2N]
6. GPU kernel: SIMD multiply A*B, accumulate partial sums, store result
7. DMA result back to FIFO BRAM
8. Drain result packet to network
```

### 10.3 GPU Kernel Pseudocode (dot product)

```
MOVI  r1, #addr_A          ; start of vector A in DMEM
MOVI  r2, #addr_B          ; start of vector B in DMEM
MOVI  r3, #0               ; accumulator (4 lanes)
MOVI  r4, #vector_length   ; loop count
MOVI  r5, #0               ; loop index
loop:
  LD    r6, [r1, r5]       ; load A[i] (4 x int16)
  LD    r7, [r2, r5]       ; load B[i] (4 x int16)
  MUL   r8, r6, r7, S16    ; r8 = A[i] * B[i] (4-lane SIMD)
  ADD   r3, r3, r8, S16    ; accumulate partial products
  ADDI  r5, r5, #1
  BLT   r5, r4, loop
  ST    r3, [r1, #0]       ; store result
  HALT
```

CPU kernel: ARM program sums the 4 lanes of the final SIMD result into a
scalar, or manages packet header rewriting for output.

---

## 11. File Inventory

### 11.1 Synthesizable RTL (src/)

| Path | Description | Lines |
|------|-------------|-------|
| `src/lab8_wrapper.v` | Top-level: FIFO + CPU + GPU + DMA + registers | 649 |
| `src/user_data_path.v` | NF2.1 data path chain | 490 |
| `src/fifo/fifo_bram.v` | 256x72 true dual-port BRAM | 40 |
| `src/fifo/convertible_fifo.v` | Packet FIFO with proc access, 6-state FSM | 281 |
| `src/arm/processor.v` | ARM top: 5-stage pipeline, 4-thread barrel | 491 |
| `src/arm/IF_stage.v` | Instruction fetch, 4 per-thread PCs | 100 |
| `src/arm/ID.v` | Decode, 64-entry register file, condition eval | 248 |
| `src/arm/EX.v` | Execute: barrel shifter + ALU | 73 |
| `src/arm/alu64.v` | 64-bit ALU (AND/EOR/SUB/ADD/CMP/ORR/MOV/BIC/MVN) | 162 |
| `src/arm/addsub64.v` | 64-bit adder/subtractor | ~30 |
| `src/arm/logic64.v` | AND/OR/XNOR gate-level | ~30 |
| `src/arm/data_mem.v` | MEM stage: DMEM + ext_mem mux + MEM/WB reg | 104 |
| `src/arm/memwb_reg.v` | WB stage (mux ALU/mem) | ~30 |
| `src/arm/ifid_reg.v` | IF/ID pipeline register | ~40 |
| `src/arm/idex_reg.v` | ID/EX pipeline register | ~60 |
| `src/arm/exmem_reg.v` | EX/MEM pipeline register | ~60 |
| `src/arm/inst_mem.v` | 512x32 dual-port IMEM BRAM | ~30 |
| `src/arm/logic_analyzer.v` | 2048x64 trace buffer | 33 |
| `src/arm/adder8_comb.v` | **Dead code** (unused) | ~30 |
| `src/arm/full_adder.v` | **Dead code** (unused) | ~20 |
| `src/gpu/gpu_top.v` | GPU top: core + IMEM + DMEM | 103 |
| `src/gpu/core_top.v` | GPU core: 6-stage pipeline | ~150 |
| `src/gpu/fetch_stage.v` | GPU fetch + PC | ~50 |
| `src/gpu/decode_stage.v` | GPU decode + branch | ~120 |
| `src/gpu/instruction_decoder.v` | Opcode -> control signals | ~100 |
| `src/gpu/register_file.v` | 16x64 GPU registers | ~50 |
| `src/gpu/execute_stage.v` | GPU EX1 stage | ~80 |
| `src/gpu/simd_alu.v` | SIMD dispatch (int16/bf16) | ~80 |
| `src/gpu/int16_alu.v` | 4-lane int16 ALU | ~80 |
| `src/gpu/bf16_alu.v` | 4-lane BFloat16 ALU | ~150 |
| `src/gpu/bf16_fma_unit.v` | BF16 fused multiply-add | ~200 |
| `src/gpu/hazard_unit.v` | RAW hazard detection + stall | ~60 |
| `src/gpu/writeback_stage.v` | GPU WB | ~40 |
| `src/gpu/pipeline_reg_idex.v` | GPU ID/EX pipeline reg | ~60 |
| `src/gpu/pipeline_reg_ex.v` | GPU EX1/EX2, EX2/EX3 regs | ~60 |
| `src/gpu/pipeline_reg_exwb.v` | GPU EX3/WB pipeline reg | ~50 |
| `src/gpu/instruction_memory.v` | 1024x32 dual-port IMEM | ~30 |
| `src/gpu/data_memory.v` | 1024x64 dual-port DMEM | ~30 |
| `src/gpu/program_counter.v` | GPU PC with branch/stall | ~40 |

### 11.2 Configuration / Include

| Path | Description |
|------|-------------|
| `include/lab8_reg_defines.vh` | Register offset defines (simulation) |
| `include/gpu_params.vh` | GPU ISA encoding, sizing, BF16 constants |
| `include/lab8.xml` | NF2 register generator XML (48 registers) |

### 11.3 Testbenches (tb/)

| Path | Description |
|------|-------------|
| `tb/tb_lab8_wrapper.v` | PCI register + FIFO test |
| `tb/tb_cpu_fifo.v` | CPU-FIFO integration test |
| `tb/tb_gpu_integration.v` | GPU + DMA round-trip test |
| `tb/sim_primitives.v` | Gate models for iverilog |

### 11.4 Software (sw/)

| Path | Description |
|------|-------------|
| `sw/lab8reg` | Perl script: PCI register access + all test commands |

---

## 12. Synthesis Constraints

- **Target:** XC2VP50, ISE 10.1, reference_nic base
- **Clock:** 125 MHz (8 ns) core_clk_int
- **Known timing violations:** 4816 on core_clk_int (GPU DECODE path, worst 16.67 ns)
- **Workaround:** `export XIL_TIMING_ALLOW_IMPOSSIBLE=1`
- **Build:** `cd /root/netfpga/projects/lab8/synth && make`
- **NF2 auto-build:** compiles all .v files in src/ subdirectories

---

## 13. Known Issues (for Lab 9 merge)

1. **CPU conditional execution incomplete** -- cond_pass only gates branches, not DP/LDR/STR. Programs must use cond=0xE (always) or risk silent wrong results.
2. **GPU timing violations** -- DECODE path exceeds 8 ns budget. Works due to stall cycles but marginal.
3. **Drain stall** -- out_rdy from output_queues stays LOW. Drain FSM stalls. Tests use PCI readback instead.
4. **all_halted unreliable** -- CPU PC keeps advancing after HALT. Software uses timeout fallback.
5. **Single-packet FIFO** -- only 1 packet buffered. For dot product with 2 vectors, must process/reset between packets.
6. **No CPU-GPU shared memory** -- GPU has separate DMEM. Data moves through DMA via FIFO BRAM.

---

## 14. Merging Checklist (for teammate integration)

- [ ] Agree on register map offsets (current: FIFO 0x00-0x0B, CPU 0x0C-0x1A, GPU 0x20-0x2B, DMA 0x2C-0x2F)
- [ ] Verify teammate's CPU/GPU module port names match Section 4.1 / 5.1
- [ ] Reconcile IMEM/DMEM sizes if different
- [ ] Ensure teammate's modules use Verilog-2001 (no SystemVerilog)
- [ ] Check for naming conflicts in src/ (NF2 auto-compiles all .v files)
- [ ] Update lab8.xml if register count changes
- [ ] Test with iverilog before synthesis (build commands in MEMORY.md)
- [ ] Verify PCI base address ($BASE = 0x2001100) matches on target NetFPGA
