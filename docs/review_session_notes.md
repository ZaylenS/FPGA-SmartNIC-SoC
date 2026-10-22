# Quiz Review Session Notes (2026-04-07)

Comprehensive review of the Group 12 Network Processor architecture, GPU microarchitecture, data flow, and IDS inference pipeline.

---

## 1. Network Processor Architecture

```
                         NF2.1 Pipeline (NetFPGA datapath)
                        ====================================
                         in_data/ctrl              out_data/ctrl
                             |                         ^
                             v                         |
                     +-------------------------------------------+
                     |          Convertible FIFO                 |
                     |  +-------------------------------------+  |
                     |  |      FIFO BRAM (256 x 72-bit)       |  |
                     |  |         Dual-Port BRAM               |  |
                     |  |                                      |  |
                     |  |   Port A              Port B         |  |
                     |  |   (NF2.1              (muxed by      |  |
                     |  |    pipeline)           mode reg)     |  |
                     |  +-------+------------------+----------+  |
                     |          |                   |             |
                     |    wr_ptr/rd_ptr        +----+----+       |
                     |    (FIFO ctrl)          | Port B  |       |
                     |                         |  MUX    |       |
                     +-------------------------+         +-------+
                                               +--+-+-+--+
                                  Mode 0 ---------+ | +--------- Mode 1
                                  (PCI direct)  Mode 2           (CPU)
                                      |          (DMA)              |
                                      |            |                |
 +--------------------------------------------------------------------------+
 |                      PCI Register Interface                              |
 |  +----------+  +----------+  +----------+  +------------------+         |
 |  | FIFO Regs|  | CPU Regs |  | GPU Regs |  |    DMA Regs      |         |
 |  |0x00-0x0B |  |0x0C-0x1A |  |0x20-0x2B |  | CTRL  FIFO_ADDR |         |
 |  |          |  |          |  |          |  | GPU_ADDR LENGTH  |         |
 |  | MODE_REG |  | CTRL     |  | CTRL     |  | 0x2C-0x2F       |         |
 |  | BRAM_ADDR|  | STATUS   |  | STATUS   |  +--------+---------+         |
 |  | BRAM_WD  |  | IMEM     |  | IMEM     |           |                   |
 |  | BRAM_CMD |  | DMEM     |  | DMEM     |           |                   |
 |  +----------+  +----+-----+  +----+-----+           |                   |
 +------------------------+----------+------------------+-------------------+
                          |          |                  |
           +--------------+    +-----+         +--------+
           |                   |               |
           v                   v (Port B)      v
 +------------------+  +-------------------+  +-------------+
 |    ARM CPU       |  |       GPU         |  | DMA Engine  |
 |   (4-thread)     |  |   (4-lane SIMD)   |  | (3-state    |
 |                  |  |                   |  |  FSM)        |
 | +-------------+  |  | +---------------+ |  |             |
 | | IMEM        |  |  | | IMEM          | |  | IDLE        |
 | | 512x32 BRAM |  |  | | 1024x32 BRAM  | |  |  |          |
 | | A:fetch     |  |  | | A:fetch       | |  |  v          |
 | | B:PCI load  |  |  | | B:PCI load    | |  | READ (1cy)  |
 | +-------------+  |  | +---------------+ |  |  |          |
 |                  |  |                   |  |  v          |
 | +-------------+  |  | +---------------+ |  | COPY (N cy) |
 | | DMEM        |  |  | | DMEM          |<+--+  1 word/cy  |
 | | 128x32 BRAM |  |  | | 1024x64 BRAM  | |  |             |
 | | (internal)  |  |  | | A:pipeline    | |  | dir=0: FIFO |
 | +-------------+  |  | | B:PCI / DMA   |<+--+       ->GPU |
 |                  |  | +---------------+ |  | dir=1: GPU  |
 | addr[7]=1 ------+--+-- FIFO BRAM       |  |       ->FIFO |
 | (ext mem access) |  |  (via Port B,     |  +-------------+
 |                  |  |   Mode 1 only)    |
 | 5-stage pipeline |  | 6-stage pipeline  |
 | IF ID EX MEM WB  |  | IF ID EX1 EX2    |
 | (+ thread switch)|  |         EX3 WB    |
 +------------------+  +-------------------+

 Host PC (nf6) controls everything via PCI regread/regwrite
```

### FIFO Modes and Port B Ownership

| Mode | Port B Owner | Purpose | Use Case |
|------|-------------|---------|----------|
| 0 | PCI (direct register access) | Normal FIFO forwarding | Packet passthrough, debug reads |
| 1 | ARM CPU | CPU drives Port B | CPU reads/writes packet data |
| 2 | DMA engine (when active) / PCI (when idle) | GPU DMA transfers | IDS inference data movement |

### All BRAM Memories in the Design

| Memory | Size | Width | Port A | Port B |
|--------|------|-------|--------|--------|
| FIFO BRAM | 256 deep | 72-bit | NF2.1 pipeline (network) | CPU/DMA/PCI (muxed by mode) |
| GPU IMEM | 1024 deep | 32-bit | Core pipeline (fetch) | PCI host (load programs) |
| GPU DMEM | 1024 deep | 64-bit | Core pipeline (LD/ST) | PCI/DMA (muxed) |
| ARM IMEM | 512 deep | 32-bit | CPU fetch | PCI host (load programs) |
| ARM DMEM | 128 deep | 32-bit | CPU LD/ST | (internal only) |

All use the same pattern: `reg [W-1:0] mem [0:DEPTH-1]` with synchronous read/write. ISE 10.1 infers Virtex-II Pro Block RAMs. Dual-port allows pipeline and PCI/DMA to access simultaneously without contention.

---

## 2. End-to-End IDS Inference Data Flow

### Setup (one-time, before any packets arrive)
1. Host loads GPU kernel (211 instructions) into GPU IMEM via PCI register writes
2. Host loads weights + biases (372 words) into GPU DMEM via PCI register writes
3. GPU is held in reset (GPU_CTRL bit[0] = 1)

### Per-Packet Inference
1. **Packet arrival**: UDP packet from nf7 -> nf6 ethernet -> NF2.1 pipeline -> Port A -> FIFO BRAM (autonomous, no software involvement)
2. **Mode switch**: Host sets FIFO mode = 2 (GPU mode) via PCI
3. **DMA setup**: Host writes DMA_FIFO_ADDR=1 (skip header), DMA_GPU_ADDR=0, DMA_LENGTH=11 (features), DMA_CTRL=0x1 (start, dir=0 for FIFO->GPU)
4. **DMA transfer**: FSM runs IDLE -> READ (1 cycle) -> COPY (11 cycles) -> IDLE. Features land in GPU DMEM[0..10]
5. **Poll DMA**: Host polls GPU_STATUS bit[1] (dma_busy) until 0
6. **GPU execute**: Host releases GPU reset (GPU_CTRL = 0). Kernel runs ~2402 cycles (~19.2 us at 125 MHz)
7. **Poll completion**: Host polls GPU_STATUS bit[0] (kernel_done) until 1
8. **Read results**: Host reads GPU DMEM[381..382] via PCI (two 64-bit words = 2 logits)
9. **Classify**: Host does argmax(logits) -> NORMAL or ATTACK

**Key insight**: The host PC software orchestrates every step via PCI register writes. The hardware blocks don't act autonomously (except FIFO packet capture).

**ARM CPU is NOT involved** in the IDS inference flow at all. It could be, but currently isn't needed.

### DMA FSM Detail

Three states:
- **IDLE**: Waits for `dma_start` signal (DMA_CTRL bit[0] AND mode==2 AND length!=0)
- **READ**: 1-cycle pipeline fill. Issues first BRAM read address. No write yet (BRAM has 1-cycle read latency).
- **COPY**: Each cycle writes data read last cycle + issues next read address. Runs for `length` cycles. Pipelined at 1 word/cycle throughput.

Direction bit (DMA_CTRL bit[1]): dir=0 FIFO->GPU, dir=1 GPU->FIFO.

---

## 3. GPU Pipeline Microarchitecture

### 6-Stage Pipeline Overview

```
  IF -> ID -> EX1 -> EX2 -> EX3 -> WB
```

- **IF (Fetch)**: Program counter drives IMEM read. PC increments each cycle unless stall/branch. Branch resolved in EX1 causes flush of IF and ID.
- **ID (Decode)**: Instruction decoder extracts opcode, register addresses, immediates. Register file read (3 read ports). Branch-aware address muxing.
- **EX1/EX2/EX3 (Execute)**: Two parallel compute paths (see below). DMEM address computed in EX1, stored through pipeline, used in EX3.
- **WB (Writeback)**: Combinational MUX selects ALU result or DMEM load data. Writes back to register file.

### Hazard Unit

Stall-only (no forwarding). Checks RAW hazards across 4 pipeline stages (EX1, EX2, EX3, WB). If any destination register in flight matches a source register in decode, the pipeline stalls. FMA gets special treatment since it has 3 source registers (rs1, rs2, rs3).

This is why the kernel uses 2-neuron interleaving: the LD->FMA stall is ~2-3 cycles, and interleaving fills those stall slots with useful work.

### Execute Stage: SIMD ALU + FMA Side by Side

```
        From Decode Stage
        +----------------------------------+
        | rs1_data  rs2_data  rs3_data     |
        | (64-bit)  (64-bit)  (64-bit)     |
        | alu_op, is_fma, use_imm, dtype   |
        +---+----------+----------+--------+
            |          |          |
            |    +-----+-----+   |
            |    | op_b MUX  |   |
            |    | imm / rs2 |   |
            |    +-----+-----+   |
            |          |         |
            v          v         v
     +----------------------+  +-----------------------------+
     |     SIMD ALU         |  |        FMA Unit             |
     |  4x int16_alu        |  |    4x bf16_fma_unit         |
     |  4x bf16_alu         |  |                             |
     |                      |  |  Computes: a * b + c        |
     |  2 inputs: a, op_b   |  |  3 inputs: rs1, rs2, rs3   |
     |                      |  |                             |
     | EX1: compute start   |  | EX1: multiply + exp math   |
     |      ---reg---       |  |      ---reg---              |
     | EX2: result ready    |  | EX2: barrel shift + add     |
     |      ---reg---       |  |      ---reg---              |
     | EX3: HELD (waiting)  |  | EX3: LZC + normalize       |
     +----------+-----------+  +-------------+---------------+
                |                            |
                v                            v
           +--------------------------------------+
           |        EX3 Result MUX                |
           | is_fma ? fma_result : simd_result_r  |
           +------------------+-------------------+
                              |
                              v
                        To Writeback
```

**Both paths compute every cycle.** Only one result is selected by `is_fma` flag. The other is discarded.

**Why 3 EX stages**: SIMD ALU takes 2 cycles, FMA takes 3 cycles. SIMD result is held in an extra register (`simd_result_r`) in EX3 to align with FMA's 3-cycle latency. This gives a uniform pipeline depth for all instructions.

### SIMD ALU Internals

4 independent lanes, no cross-lane communication:
```
operand_a[63:0]:  | Lane3 [63:48] | Lane2 [47:32] | Lane1 [31:16] | Lane0 [15:0] |
operand_b[63:0]:  | Lane3 [63:48] | Lane2 [47:32] | Lane1 [31:16] | Lane0 [15:0] |
                       |                |                |               |
                   int16_alu[3]    int16_alu[2]    int16_alu[1]    int16_alu[0]
                   bf16_alu[3]     bf16_alu[2]     bf16_alu[1]     bf16_alu[0]
                       |                |                |               |
result[63:0]:     | Lane3 [63:48] | Lane2 [47:32] | Lane1 [31:16] | Lane0 [15:0] |
```

Each `bf16_alu` handles: ADD, SUB, MUL, MAX, MOV, RELU (2-cycle pipelined).
Each `int16_alu` handles: same ops but combinational (1 cycle), then registered to align.
`dtype` field selects BF16 vs INT16 result.

### FMA Unit (bf16_fma_unit) — Per Lane

Each lane computes `result = a * b + c` in 3 pipeline stages:

**Cycle 1 (EX1)**: Mantissa multiply (8x8 -> 16-bit, infers MULT18X18), exponent sum, magnitude comparison between product and addend c, sort into large/small operands.

**Cycle 2 (EX2)**: Barrel shift smaller mantissa to align exponents, add or subtract aligned mantissas (19-bit result).

**Cycle 3 (EX3)**: Leading-zero count (casez on 18 bits), normalize mantissa, adjust exponent, special case handling (NaN, Inf, zero, denorm).

**This is NOT a tensor core.** It's 4 independent scalar FMA units. No cross-lane interaction. NVIDIA tensor cores compute matrix multiply-accumulate (e.g., 4x4 matmul in one op with full cross-lane dot products).

---

## 4. Scalar SIMD Workaround for MLP Inference

### The Problem

The GPU has 4 SIMD lanes, but MLP inference is inherently scalar (one value per neuron, sequential layer dependencies). The ISA has a critical constraint:

**MOVI** broadcasts to all 4 lanes: `imm_ext = {4{instruction[15:0]}}`
- `MOVI R9, 0` -> R9 = {0, 0, 0, 0}

**ADDI** sign-extends to 64 bits (NOT replication): `imm_ext = {{45{sign}}, imm19}`
- `ADDI R9, R9, 1` -> adds {0, 0, 0, 1} -> R9 = {0, 0, 0, 1} -- LANES DIVERGED

### Why Diverged Lanes Break Everything

Pointers live in registers. If pointer R9 = {0, 0, 0, 1} after ADDI, the lanes are no longer computing the same thing. When the accumulator is eventually ST'd to DMEM, lanes 1-3 have wrong values. The next layer LD's all 4 lanes back -> garbage propagates.

### The Workaround

```
MOVI R7, 1          # R7 = {1, 1, 1, 1}  <- MOVI broadcasts!
...
ADD  R9, R9, R7     # All 4 lanes: +1    <- register-register ADD is per-lane
```

All DMEM values are replicated 4x: {v, v, v, v}. All 4 lanes compute the same thing in lockstep. R7 is permanently dedicated as the `{1,1,1,1}` increment constant.

**Consequence**: Only using 25% of SIMD compute capacity. The other 3 lanes are wasted on redundant computation.

### What Would Fix It

- **BCAST instruction** (copy lane 0 to all lanes): Could use ADDI freely for pointers, then BCAST the result at layer boundaries before ST. Would also enable computing 4 neurons in parallel for up to 4x speedup.
- **Scalar registers**: Separate pointer registers from SIMD data registers.
- Both require RTL changes, and at 96% slice utilization there's no room.

---

## 5. IDS Kernel Structure (ann_ids_11_16_8_2.asm)

### Network: 3-layer MLP (11 -> 16 -> 8 -> 2)

- Layer 1: 11 inputs -> 16 neurons, ReLU activation
- Layer 2: 16 inputs -> 8 neurons, ReLU activation
- Layer 3: 8 inputs -> 2 outputs, no activation (raw logits for classification)

### DMEM Layout (383 words total)

| Address | Content | Size |
|---------|---------|------|
| 0..10 | Input features x[0..10] | 11 words |
| 11..186 | L1 weights (neuron-major) | 176 words (16 neurons x 11 weights) |
| 187..202 | L1 biases | 16 words |
| 203..218 | L1 output = L2 input | 16 words |
| 219..346 | L2 weights | 128 words (8 neurons x 16 weights) |
| 347..354 | L2 biases | 8 words |
| 355..362 | L2 output = L3 input | 8 words |
| 363..378 | L3 weights | 16 words (2 neurons x 8 weights) |
| 379..380 | L3 biases | 2 words |
| 381..382 | Final output (logits) | 2 words |

**The kernel has hardcoded addresses matching this layout.** No runtime configuration. Software must place data at the exact right addresses before execution.

### Per-Neuron Computation

```
acc = bias[n]                          // LD Rd, bias_addr(R0)
for i = 0 to num_inputs-1:
    w = weights[n][i]                  // LD from weight pointer
    x = input[i]                       // LD from input pointer
    acc = acc + w * x                  // FMA Rd, Rw, Rx, Rd
output[n] = ReLU(acc)                  // RELU Rd, Rd
                                       // ST Rd, output_addr(R0)
```

### 2-Neuron Interleaving Optimization

Computes 2 neurons (A and B) simultaneously per inner loop to hide LD->FMA pipeline stalls (~2-3 cycle stall due to hazard unit). Neuron A uses R1 (accumulator), R2 (weight). Neuron B uses R5 (accumulator), R4 (weight). R3 (input) is shared.

Weight pointers offset by stride (e.g., stride=11 for L1) to access adjacent neuron weights.

### Layer Chaining

Layer outputs are stored in DMEM at addresses where the next layer expects its inputs:
- L1 ST -> DMEM[203..218] -> L2 LD reads from DMEM[203]
- L2 ST -> DMEM[355..362] -> L3 LD reads from DMEM[355]

No explicit data movement between layers -- just address arithmetic.

---

## 6. Key Numbers

| Metric | Value |
|--------|-------|
| FPGA | Virtex-II Pro XC2VP50 |
| Clock | 125 MHz (8 ns period) |
| Slice utilization | 96% |
| Timing violations | 4816 (worst in GPU DECODE, 11 ns vs 8 ns budget) |
| IDS kernel cycles | ~2402 |
| Inference latency | ~19.2 us |
| DMA throughput | 1 word/cycle (8 ns/word) |
| Current accuracy | 75% |
| Kernel instructions | 211 |
| DMEM words used | 383 |

---

## 7. Potential Quiz Topics (Priority Order)

1. **Trace end-to-end packet data flow** for IDS inference (most likely follow-up to architecture diagram quiz)
2. **Draw architecture block diagram** with Port A/B, mode mux, all BRAMs labeled
3. **Explain FIFO modes** and Port B ownership
4. **DMA FSM** states and operation
5. **List all BRAM memories** with sizes, widths, port assignments
6. **Register write sequence** for loading GPU program and running inference
7. **NF2.1 packet format** (header word, one-hot port encoding)
8. **GPU 6-stage pipeline** and why EX has 3 stages
9. **Timing violations** root cause and critical path
10. **ARM CPU FIFO access** mechanism (addr[7] bit)
11. **IDS DMEM layout** and layer chaining
