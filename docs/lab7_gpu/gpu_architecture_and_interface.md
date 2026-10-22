# GPU Architecture & Integration Interface

Concise reference for explaining the design and integrating with ARM + FIFO (Labs 8/9/10).

> **Document refreshed 2026-05-17** to match `HEAD` RTL. Two batches of refinements have landed since the original Lab 8 baseline (`44baf38`, 2026-03-25):
>
> | Date       | Commit    | Scope                                                                       | Sections affected here |
> | ---------- | --------- | --------------------------------------------------------------------------- | ---------------------- |
> | 2026-04-13 | `e14d012` | BCAST cross-lane SIMD instruction; simd_alu input pipeline register; INT16 scalarised | §1, §2, §3 |
> | 2026-04-13 | `b4648bd` | Wrapper GPU cycle counter (`LAB8_GPU_CYCLE_COUNT = 0x30`); readback mux refactor | §5.5 |
> | 2026-05-10 | `942decf` | ARM register-alias window (orchestrator); ARM-side only -- no GPU-core changes | §5.5, §6 |
>
> The `gpu_top.v` external interface (§4) is **unchanged** since 2026-03-25. Per-batch deep dives live in `walkthrough_batch{1..5}_*.md`; per-fix change logs live in `gpu_update_notes.md` and `timing_fix_refine_lab8.md`.

---

## 1. Pipeline Overview

```
         IF          ID           EX1          EX2          EX3          WB
      +--------+  +--------+  +----------+  +----------+  +----------+  +--------+
      | Fetch  |->| Decode |->| Execute1 |->| Execute2 |->| Execute3 |->|Writeback|
      | IMEM   |  | Decoder|  | MUL/FMA  |  | Shift+   |  | LZC+     |  | RegFile |
      | read   |  | RegFile|  | start    |  | Add      |  | Normalize|  | or DMEM |
      |        |  | read   |  |          |  |          |  | DMEM wr  |  | write   |
      +--------+  +--------+  +----------+  +----------+  +----------+  +--------+
          |            |            |             |             |             |
        IF/ID        ID/EX       EX1/EX2       EX2/EX3       EX3/WB
       (BRAM out)  (pipeline    (pipeline     (pipeline     (pipeline
                    register)    _reg_ex)      _reg_ex)      _reg_exwb)
```

**Key details:**
- 6 stages, 125 MHz clock target (8ns), stall-only hazard handling (no forwarding)
- Branch resolved in **EX1** (2-cycle penalty: flushes IF/ID + ID/EX)
- SIMD ALU: **3-cycle (EX1→EX2→EX3) -- refined 2026-04-13.** Input pipeline register lives inside simd_alu; integer + BF16 paths both land in EX3. End-to-end SIMD latency is the same as before the refactor; the register moved from `execute_stage.v` to inside `simd_alu.v` to break a 15.26 ns critical path through the BCAST mux.
- BF16 FMA: 3-cycle (EX1→EX2→EX3), all 4 lanes independent
- DMEM write: active in EX3 (address doubly-registered through EX1→EX2→EX3)
- DMEM read: address in EX3, data available in WB (synchronous BRAM)
- Worst-case RAW stall: 4 cycles (hazard unit checks EX1, EX2, EX3, WB destinations)

---

## 2. Module Hierarchy

```
gpu_top
├── core_top                        ← Pipeline orchestration
│   ├── program_counter             ← PC: rst > branch > stall > increment
│   ├── fetch_stage                 ← IF/ID valid tracking
│   ├── decode_stage                ← Decoder + register file (no branch comparator)
│   │   ├── instruction_decoder     ← Combinational instruction cracker
│   │   └── register_file           ← 16x64 FF-based, 3 read + 1 write port
│   ├── pipeline_reg_idex           ← ID/EX register (stall=hold, flush=NOP)
│   ├── execute_stage               ← ALU + FMA dispatch, DMEM address calc
│   │   ├── simd_alu                ← 4-lane dispatch + BCAST mux + input pipeline reg (refined 2026-04-13)
│   │   │   ├── int16_alu ×1        ← Combinational, lane-0 only (replicated to 4 outputs) -- scalarised 2026-04-13
│   │   │   └── bf16_alu  ×4        ← 2-cycle pipelined BF16 ALU
│   │   └── bf16_fma_unit ×4        ← 3-cycle pipelined FMA
│   ├── pipeline_reg_ex ×2          ← EX1/EX2 and EX2/EX3 control registers
│   ├── pipeline_reg_exwb           ← EX3/WB register
│   ├── writeback_stage             ← Result MUX (ALU result vs DMEM read)
│   └── hazard_unit                 ← RAW stall detection (4-stage check)
├── instruction_memory              ← 1024×32 true dual-port BRAM
│   Port A: core fetch (read-only)
│   Port B: external load/readback
└── data_memory                     ← 1024×64 true dual-port BRAM
    Port A: core LD/ST
    Port B: external load/readback (DMA or PCI)
```

---

## 3. ISA Quick Reference

**32-bit instructions, 64-bit data, 4-lane SIMD (int16 + BFloat16)**

| Opcode | Mnemonic | Format | Operation |
|--------|----------|--------|-----------|
| 00000 | NOP | — | No operation |
| 00001 | ADD | R | rd = rs1 + rs2 (per lane) |
| 00010 | SUB | R | rd = rs1 - rs2 (per lane) |
| 00011 | MUL | R | rd = rs1 * rs2 (per lane) |
| 00100 | FMA | F | rd = rs1 * rs2 + rs3 (per lane, BF16) |
| 00101 | MAX | R | rd = max(rs1, rs2) (per lane) |
| 01100 | MOV | R | rd = rs1 |
| 01110 | ADDI | I | rd = rs1 + imm19 (broadcast) |
| 10000 | LD | M | rd = DMEM[rs_base + offset12] |
| 10001 | ST | M | DMEM[rs_base + offset12] = rd |
| 10110 | BLT | B | if ($signed(rs1) < $signed(rs2)) PC += offset19 |
| 10111 | BGE | B | if ($signed(rs1) >= $signed(rs2)) PC += offset19 |
| 11000 | RELU | R | rd = max(0, rs1) (per lane) |
| 11010 | BCAST | R | rd = {4{rs1[lane]}}, lane = func[1:0]   (added 2026-04-13) |
| 11011 | MOVI | I | rd = broadcast(imm16) |
| 11111 | HALT | — | Stop execution, set kernel_done=1 |

**Registers:** R0=zero, R1-R12=general, R13=threadID, R14=blockID, R15=blockDim

**Instruction formats:**
```
R-type: [31:27] opcode  [26:23] rd  [22:19] rs1  [18:15] rs2  [14:12] dtype  [11:0] func
I-type: [31:27] opcode  [26:23] rd  [22:19] rs1  [18:0] imm19
M-type: [31:27] opcode  [26:23] rd  [22:19] rbase  [14:12] dtype  [11:0] offset12
F-type: [31:27] opcode  [26:23] rd  [22:19] rs1  [18:15] rs2  [14:12] dtype  [11:8] rs3
B-type: [31:27] opcode  [26:23] rs1  [22:19] rs2  [18:0] offset19
```

**dtype field:** `000`=int16, `100`=BF16

---

## 4. GPU External Interface (gpu_top.v ports)

This is what the integration wrapper connects to.

```
gpu_top
├── clk, rst                        ← System clock (125 MHz) and reset
├── thread_id[31:0]                  ← Hardwired to 32'd0 (single-thread)
├── block_id[31:0]                   ← Hardwired to 32'd0
├── block_dim[31:0]                  ← Hardwired to 32'd1
├── kernel_done                      ← OUTPUT: 1 when HALT reaches WB
│
├── IMEM Port B (external load/readback)
│   ├── ext_imem_addr[9:0]           ← Word address (0-1023)
│   ├── ext_imem_wr_en               ← Write enable
│   ├── ext_imem_wr_data[31:0]       ← 32-bit instruction word
│   └── ext_imem_rd_data[31:0]       ← Read data (1-cycle latency)
│
└── DMEM Port B (external load/readback)
    ├── ext_dmem_addr[9:0]           ← Word address (0-1023)
    ├── ext_dmem_wr_en               ← Write enable
    ├── ext_dmem_wr_data[63:0]       ← 64-bit data word
    └── ext_dmem_rd_data[63:0]       ← Read data (1-cycle latency)
```

**Important constraints (from Batch 3 fix in gpu_nf2_wrapper, not in gpu_top itself):**
- In Lab7 standalone, Port B writes are gated by `gpu_ctrl_reset` (must hold reset to write)
- In Lab8 integration, `lab8_wrapper.v` drives Port B directly — the wrapper must ensure writes only happen while GPU is in reset

---

## 5. Integration with Lab8 (ARM + FIFO + GPU)

### 5.1 System Architecture

```
  Network Packets                                              Network Packets
       │                                                            ▲
       ▼                                                            │
  ┌─────────────────────────────────────────────────────────────────────────┐
  │  lab8_wrapper.v                                                         │
  │                                                                         │
  │  ┌──────────────┐     Port B MUX      ┌──────────┐                     │
  │  │ Convertible  │◄──────────────────► │ ARM CPU  │                     │
  │  │ FIFO         │  (mode=1: CPU)      │ (4-thread│                     │
  │  │              │                      │  ARM v4) │                     │
  │  │ 256×72 BRAM  │◄──── DMA engine ──►│          │                     │
  │  │              │  (mode=2: GPU)       └──────────┘                     │
  │  │ Port A: net  │                                                       │
  │  │ Port B: mux  │◄──── DMA engine ──►┌──────────┐                     │
  │  └──────────────┘                      │ GPU      │                     │
  │                                        │ (6-stage │                     │
  │  PCI Register Ring ◄─────────────────►│  SIMD)   │                     │
  │  (host control)                        └──────────┘                     │
  └─────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Operating Modes (FIFO mode register)

| Mode | Value | Port B driven by | Use case |
|------|-------|-------------------|----------|
| FIFO | 0 | FIFO drain FSM | Normal packet passthrough |
| CPU | 1 | ARM processor ext_mem port | ARM reads/writes packet data |
| GPU | 2 | DMA engine | DMA copies FIFO↔GPU DMEM |

### 5.3 Typical Workflow: GPU Processes Packet Data

```
Step 1: Packet arrives → FIFO buffers it (pkt_ready=1)

Step 2: Host sets mode=2 (GPU mode)

Step 3: Host loads GPU program (while GPU in reset)
   - Write GPU_IMEM_ADDR, GPU_IMEM_WDATA, GPU_IMEM_CMD for each instruction

Step 4: DMA FIFO→GPU (copy input data to GPU DMEM)
   - Write DMA_FIFO_ADDR = 0 (FIFO start)
   - Write DMA_GPU_ADDR = 0 (GPU DMEM start)
   - Write DMA_LENGTH = N (word count)
   - Write DMA_CTRL = 0x01 (start, direction=FIFO→GPU)
   - Poll GPU_STATUS bit[1] until dma_busy=0

Step 5: Run GPU
   - Write GPU_CTRL = 0 (release reset)
   - Poll GPU_STATUS bit[0] until kernel_done=1

Step 6: DMA GPU→FIFO (copy results back)
   - Write DMA_FIFO_ADDR = result_offset
   - Write DMA_GPU_ADDR = result_dmem_addr
   - Write DMA_LENGTH = N
   - Write DMA_CTRL = 0x03 (start, direction=GPU→FIFO)
   - Poll until dma_busy=0

Step 7: Host sets mode=0, drains packet to network
```

### 5.4 GPU DMEM Layout Convention

The GPU program uses LD/ST with base R0 (=0) + offset. The DMEM addresses are fixed by the program:

```
Example: bf16_fma kernel
  DMEM[0] = A operand (4×BF16 packed in 64 bits)
  DMEM[1] = B operand
  DMEM[2] = C operand
  DMEM[3] = result (written by GPU)

Example: vec_add kernel
  DMEM[0] = A operand
  DMEM[1] = B operand
  DMEM[2] = result
```

DMA copies data FROM FIFO BRAM TO these DMEM addresses before GPU runs, and copies results FROM DMEM back TO FIFO BRAM after GPU completes.

### 5.5 Register Map (Lab8 Integration)

| Offset | Register | Type | Key bits |
|--------|----------|------|----------|
| 0x00 | LAB8_CTRL | RW | bit[0]=soft_reset |
| 0x01 | LAB8_STATUS | RO | {pkt_cnt, head, tail, empty, full, pkt_ready} |
| 0x02 | LAB8_FIFO_MODE | RW | mode: 0=FIFO, 1=CPU, 2=GPU |
| 0x03 | LAB8_FIFO_DRAIN | RW | bit[0]=drain_start |
| 0x04-0x0B | BRAM access | RW/RO | Direct FIFO BRAM read/write via PCI |
| 0x0C | CPU_CTRL | RW | bit[0]=start_stop, bit[1]=cpu_reset |
| 0x0D | CPU_STATUS | RO | all_halted, cpsr, thread_id |
| 0x0E-0x11 | CPU_IMEM | RW | IMEM load via PCI |
| 0x12-0x17 | CPU_DMEM | RW | DMEM access via PCI |
| 0x18-0x1A | CPU_LA | RW/RO | Logic analyzer readback |
| 0x20 | GPU_CTRL | RW | bit[0]=gpu_reset (1=hold) |
| 0x21 | GPU_STATUS | RO | bit[0]=kernel_done, bit[1]=dma_busy |
| 0x22-0x25 | GPU_IMEM | RW | IMEM load via PCI |
| 0x26-0x2B | GPU_DMEM | RW | DMEM access via PCI |
| 0x2C | DMA_CTRL | RW | bit[0]=start, bit[1]=dir (0=FIFO→GPU, 1=GPU→FIFO) |
| 0x2D | DMA_FIFO_ADDR | RW | FIFO BRAM start address [7:0] |
| 0x2E | DMA_GPU_ADDR | RW | GPU DMEM start address [9:0] |
| 0x2F | DMA_LENGTH | RW | Word count [7:0] |
| 0x30 | GPU_CYCLE_COUNT | RO | 32-bit free-running counter, runs from `gpu_reset` deassertion until `kernel_done` (added 2026-04-13). Same value the simulator's `cycle_count` would report. |

---

## 6. What Your Teammates Need to Know

**If they work on the ARM side:**
- ARM accesses FIFO BRAM via its external memory port (CPU address 128-255 maps to FIFO BRAM 0-127)
- ARM and GPU never access FIFO BRAM simultaneously — mode register selects who drives Port B
- ARM can also access GPU IMEM/DMEM directly via PCI registers (for loading programs)

**If they work on the FIFO side:**
- FIFO is a 256×72 BRAM (64-bit data + 8-bit control) that buffers one complete network packet
- Port A = network input (always), Port B = multiplexed (FIFO drain / CPU / DMA)
- 1-cycle BRAM read latency requires 2-state prefetch in drain FSM

**If they work on integration/test scripts:**
- The Perl/C test script drives everything through PCI register reads/writes
- GPU program is loaded instruction-by-instruction via GPU_IMEM registers
- GPU data is loaded via DMA (FIFO→GPU) or directly via GPU_DMEM registers
- Workflow: reset GPU → load IMEM → DMA data in → release reset → poll kernel_done → DMA data out
- **GPU cycle count (added 2026-04-13)** is available at register `0x30` (RO). Read once after `kernel_done` to get the cycle count for the most recent kernel run — useful for measuring scalar-vs-BCAST speedup without instrumenting the kernel.

**If they want the ARM CPU to orchestrate the GPU instead of the host (added 2026-05-10):**
- The ARM CPU can drive `GPU_CTRL`, `DMA_*`, `FIFO_DRAIN`, etc. from inside a thread program via the **register-alias window**: a store to DMEM address `0xF0..0xFF` lands in the wrapper's control registers instead of memory.
- This is what powers the Milestone 4 orchestrator: one ARM thread sequences `DMA in → start GPU → poll kernel_done → DMA out → drain` without host involvement.
- The host still loads the program (IMEM/DMEM); the orchestrator handles only the per-packet sequencing.

---

## 7. Updating GPU in Lab8

The Lab8 repo has an older GPU (pre-refinement). To update:

1. Copy all files from `Lab7_synth/src/` to `Lab8_fifo/src/gpu/`
2. The `gpu_top.v` port interface is **unchanged** — same signals, same widths
3. The only difference is `gpu_nf2_wrapper.v` (Lab7-only) vs `lab8_wrapper.v` (Lab8) driving Port B — the `lab8_wrapper` already handles reset-gated writes via its own control logic
4. Re-synthesize and test with `gpureg test_all` equivalent in Lab8
