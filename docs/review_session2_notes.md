# Review Session 2 — Design Q&A Notes

Exam-ready answers to four design questions about the Lab 10 IDS-on-NetFPGA
project. Each answer is anchored in actual code (file:line references) so the
real implementation can be re-read under pressure.

---

## Q1. What is the DMA doing, and how is it implemented?

**One-line answer**: a 3-state FSM that moves one 64-bit BRAM word per cycle
between the FIFO BRAM and GPU DMEM, in either direction, with no ARM
involvement.

**Where it lives**: `src/lab8_wrapper.v:195-253` (not its own module — inlined
in the wrapper next to the register file).

**States**:

- **`DMA_IDLE`** — waits for `dma_start`, which is
  `reg_dma_ctrl[0] && (fifo_mode == 2) && (length != 0)` (line 323). The
  `mode == 2` guard is a safety interlock so DMA can't stomp on the FIFO
  while ARM is using it in mode 1.
- **`DMA_READ`** — a one-cycle pipeline prime. It issues the very first read
  address and sets `dma_rd_ptr <= 1` (since address 0 was already issued this
  cycle).
- **`DMA_COPY`** — the steady state. Every cycle: increment both
  `dma_rd_ptr` and `dma_wr_ptr`. The data read N cycles ago lands on
  `fifo_proc_dout` / `gpu_dmem_rd_data` this cycle and is written to the
  destination now. Exits when `dma_wr_ptr + 1 == dma_len`.

**Registers latched at start (lines 231-236)**:

- `dma_dir` ← `reg_dma_ctrl[1]`: 0 = FIFO→GPU, 1 = GPU→FIFO
- `dma_fifo_base` (8 bits, 256-deep BRAM), `dma_gpu_base` (10 bits,
  1024-deep DMEM), `dma_len` (8 bits, max 256 words)

**Address generation (lines 356-389)** — two `always @(*)` blocks, one per
BRAM port:

- **FIFO→GPU**: `fifo_proc_addr = fifo_base + rd_ptr` (read side),
  `gpu_dmem_addr = gpu_base + wr_ptr` (write side).
  `gpu_dmem_wr_data = fifo_proc_dout[63:0]` — drops the 8-bit ctrl byte,
  keeps the 64-bit payload. `gpu_dmem_wr_en = (dma_state == DMA_COPY)`.
- **GPU→FIFO**: mirror. `fifo_proc_din = {8'h00, gpu_dmem_rd_data}` — stamps
  ctrl=0x00 as a data word (BRAM[0] keeps ctrl=0xFF because of the
  `arm_bram_wctrl` logic at line 340, but that only matters for ARM writes,
  not DMA).

**Why the 1-cycle prime (READ state)**: both BRAMs are synchronous-read —
when you drive an address, the data isn't valid until the next clock edge.
In READ, we issue the addr for word 0 and do nothing else. In the first COPY
cycle, word 0's data arrives; we write it to the destination while
simultaneously issuing the addr for word 1. After that, every cycle both
reads and writes. Total cost: **N + 1 cycles for N words**.

**Gotcha for TA follow-up**: the DMA is memory-mapped via
`reg_dma_ctrl / fifo_addr / gpu_addr / length` (register offsets 0x2C-0x2F).
Software triggers it with a single write to DMA_CTRL bit 0 — that's why the
BCAST demo path uses `ids_load` to pre-stage weights once and then only DMA
the input per packet.

---

## Q2. How does the inference actually work — IMEM and DMEM walk-through

Use the **scalar kernel** (`programs/gpu/ann_ids_11_16_8_2.asm`) as the
mental model — it's cleaner. BCAST is an optimization on top (Q3).

**The network** (11 → 16 → 8 → 2, all BF16):

- L1: `h1[n] = ReLU(Σ w1[n][i]·x[i] + b1[n])` for n=0..15, i=0..10
- L2: `h2[n] = ReLU(Σ w2[n][i]·h1[i] + b2[n])` for n=0..7,  i=0..15
- L3: `out[n] = Σ w3[n][i]·h2[i] + b3[n]`      for n=0..1,  i=0..7
  (no activation — raw logits for softmax)

**IMEM is the program; DMEM is everything else.** IMEM holds the ~130
instructions that make up the kernel. DMEM holds inputs, weights, biases,
layer outputs, and the final output — all in the same 1024-word space.

**DMEM layout, scalar mode (383 words total)** — from the asm header
comment at line 26:

```
[0..10]     x[0..10]           input features
[11..186]   w1[n][i]           L1 weights, row-major (176 = 16×11)
[187..202]  b1[0..15]          L1 biases
[203..218]  h1[0..15]          L1 output (written by kernel)
[219..346]  w2[n][i]           L2 weights (128 = 8×16)
[347..354]  b2[0..7]           L2 biases
[355..362]  h2[0..7]           L2 output
[363..378]  w3[n][i]           L3 weights (16 = 2×8)
[379..380]  b3[0..1]           L3 biases
[381..382]  out[0..1]          final logits
```

Each DMEM word is 64 bits = 4 BF16 lanes. In scalar mode, **every word holds
the same BF16 value in all 4 lanes: `{v,v,v,v}`**. That turns the 4-lane
SIMD hardware into a scalar ISA — every FMA computes `v·v+v` four times and
we use one result.

**One neuron = one inner-loop iteration.** L1 group 0 computes neurons 0
and 1 in parallel (lines 49-65):

```asm
LD   R1, 187(R0)       # acc_A = b1[0]             ← start with bias
LD   R5, 188(R0)       # acc_B = b1[1]
MOVI R8, 11            # weight pointer → &w1[0][0]
MOVI R9, 0             # input pointer → &x[0]
l1g0:
    LD   R2, 0(R8)         # load w1[n][i]
    LD   R3, 0(R9)         # load x[i]
    ADD  R9, R9, R7        # input_ptr++     (R7={1,1,1,1}, lane-uniform)
    LD   R4, 11(R8)        # load w1[n+1][i] — stride=11 away
    FMA  R1, R2, R3, R1    # acc_A += w1[n]·x[i]
    FMA  R5, R4, R3, R5    # acc_B += w1[n+1]·x[i]  ← second neuron
    ADD  R8, R8, R7        # weight_ptr++
    BLT  R9, R12, l1g0     # loop i<11
RELU R1, R1, BF16
RELU R5, R5, BF16
ST   R1, 203(R0)       # h1[0]
ST   R5, 204(R0)       # h1[1]
```

The **2-neuron interleave** hides the 3-cycle FMA latency — by the time
control wraps back to the first FMA, the previous result is ready. That
matters because the BF16 FMA unit in `src/gpu/execute_stage.v:44-60` is a
3-stage pipeline (EX1 → EX2 → EX3).

L1 repeats this 8 times (groups 0-7) for neuron pairs (0,1), (2,3), …,
(14,15). L2 does it 4 times with stride=16 reading from `h1[0..15]`. L3
does it once with stride=8, no ReLU, and stores to `out[0..1]` before HALT.

**End-to-end data flow**:

1. Host DMAs input packet → BRAM → `x[0..10]` in DMEM (11 words).
2. Weights/biases were pre-loaded once via `ids_load`.
3. Host writes GPU_CTRL to release reset → IMEM runs → HALT asserted.
4. Host reads DMEM[381..382] via PCI → `{out[0], out[1]}` → argmax =
   predicted class (normal vs attack).

**Cycle count**: ~2402 cycles for the scalar kernel
(memory: `project_lab10_ids_kernel.md`).

---

## Q3. Scalar vs BCAST — why the speedup

This is the punchline of the whole BCAST design.

**The core insight**: scalar mode wastes **75% of every SIMD ALU**. Every
DMEM word is `{v,v,v,v}`, every FMA does `v·v+v` four times, and three of
the four lane results are thrown away. We *had* to do this because without
a cross-lane op, layer N+1 couldn't consume a packed output from layer N —
if L1 produced `{n3,n2,n1,n0}` in a single word, L2 has no way to pull
lane 0 out and feed it as a scalar `{n0,n0,n0,n0}` to the next FMA. So all
inter-layer data had to be scalar-replicated, forcing all FMAs to be
scalar.

**BCAST is the cross-lane permute that breaks that constraint.** From
`src/gpu/simd_alu.v:19-32`:

```verilog
wire [1:0] bcast_lane_sel = operand_b[1:0];
case (bcast_lane_sel)
    2'd0: bcast_value = operand_a[15:0];      // lane 0
    2'd1: bcast_value = operand_a[31:16];     // lane 1
    2'd2: bcast_value = operand_a[47:32];     // lane 2
    default: bcast_value = operand_a[63:48];  // lane 3
endcase
effective_a = {bcast_value, bcast_value, bcast_value, bcast_value};
```

`BCAST Rd, Rs, k` picks lane k of `Rs` and replicates it to all four lanes
of `Rd`. Now `{n3,n2,n1,n0}` can be unpacked into four scalar words
`{n0,n0,n0,n0}`, `{n1,n1,n1,n1}`, …

**BCAST-packed kernel** (`programs/gpu/ann_ids_11_16_8_2_bcast.asm:63-68`):

```asm
LD   R2, 0(R8)         # R2 = {w[3][i], w[2][i], w[1][i], w[0][i]}  ← packed
LD   R3, 0(R9)         # R3 = {x[i],    x[i],    x[i],    x[i]}      ← scalar
LD   R4, 11(R8)        # R4 = next 4 neurons' weights (super-group interleave)
FMA  R1, R2, R3, R1    # R1[j] += w[j][i]·x[i] for j=0..3 — 4 neurons, 1 FMA
FMA  R5, R4, R3, R5    # 4 more neurons, 1 FMA
```

One FMA updates four independent neuron accumulators. Combined with the
2-super-group interleave (R1 and R5), the inner loop produces **8
neuron-updates per iteration**, vs. 2 in the scalar kernel — **4× the work
per FMA**.

**Hardware utilization**:

| Mode           | Lane 0    | Lane 1    | Lane 2    | Lane 3    | Util                     |
| -------------- | --------- | --------- | --------- | --------- | ------------------------ |
| Scalar FMA     | `v·v+v`   | `v·v+v`   | `v·v+v`   | `v·v+v`   | **25%** (1 useful of 4)  |
| BCAST-packed   | `w0·x+a0` | `w1·x+a1` | `w2·x+a2` | `w3·x+a3` | **100%** (4 distinct)    |

**Measured result**: 2402 cycles → **732 cycles = 3.28× speedup**
(hardware-verified 2026-04-11 per `project_bcast_implementation.md`,
re-verified post-Fix 1 on 2026-04-17).

**Why not 4×?** Three sources of tax:

1. **Unpack overhead** — after each layer, the packed accumulator must be
   split into 4 scalar stores with `BCAST R?, R1, k` + `ST`. That's 4 BCAST
   + 4 ST per 4-neuron group (lines 74-90 of the bcast asm), which the
   scalar kernel doesn't pay.
2. **L3 is only 2-wide** — the output layer has only 2 neurons, so packed
   weights are `{0, 0, w3[1][i], w3[0][i]}` (DMEM layout lines 28-31 of
   the bcast asm). Lanes 2 and 3 multiply by zero. 50% lane util on L3.
3. **Loop overhead** (LD ptr, ADD ptr, BLT) is fixed per iteration, not
   parallelized.

**Bonus point**: BCAST also shrinks **DMEM from 383 words → 128 words
(3× smaller)**. Faster weight upload over PCI, smaller DMA, and the whole
packed payload fits in a single network packet's worth of BRAM.

---

## Q4. How do you write the CUDA kernels based on the neural net and our hardware

Two distinct flows in this project — worth being explicit about which
applies.

### Flow A: primitive ops (CUDA → PTX → our ISA, automated)

The 5 baseline kernels (`vec_add_i16`, `vec_sub_i16`, `bf16_mul`,
`bf16_fma`, `relu_i16`) really are written as CUDA and auto-translated.
Pipeline:

```
kernel.cu     (hand-written CUDA C++,  programs/gpu/kernels/kernel.cu)
    ↓ nvcc -ptx
kernel.ptx    (NVIDIA intermediate — 4 scalar ops per CUDA thread)
    ↓ toolchains/gpu/ptx_translator.py
*.asm         (our custom ISA — 1 SIMD instruction per 4-element group)
    ↓ toolchains/gpu/assembler.py
*.hex         (binary, loaded into IMEM via PCI)
```

The **key idiom in kernel.cu**: every thread does exactly 4 elements:

```cpp
int tid  = (int)threadIdx.x;
int base = tid * 4;                          // kernel.cu:31-32
if (base + 3 >= n_elements) return;
out[base + 0] = a[base + 0] + b[base + 0];
out[base + 1] = a[base + 1] + b[base + 1];
out[base + 2] = a[base + 2] + b[base + 2];
out[base + 3] = a[base + 3] + b[base + 3];
```

That 4-element unroll exists specifically so nvcc emits 4 scalar PTX adds,
which `ptx_translator.py` pattern-matches and collapses into **one** SIMD
`ADD` on our hardware (from its docstring: *"Our GPU has 4-lane SIMD — one
instruction processes all 4 elements. So the translator must … Collapse 4
scalar iterations into 1 SIMD instruction"*). The translator recognizes
exactly 4 PTX ops: `add.s16`, `sub.s16`, `max.s16`, `fma.rn.bf16` — plus
the `fma with c=-0.0` idiom that nvcc emits for `__hmul`.

### Flow B: whole ANN kernels (hand-written assembly)

The IDS kernel (`ann_ids_11_16_8_2*.asm`) is **not CUDA-translated** —
it's hand-written. Three reasons:

1. The translator is per-primitive (one add/relu/fma at a time). A full
   MLP needs nested loops, layer-to-layer data flow, ReLU in the inner
   loop — well outside the pattern language.
2. Scalar-uniformity discipline across lanes is a hand-crafted invariant
   (per the `feedback_gpu_simd_gotchas` memory: `ADDI` breaks lane
   uniformity, so we only use `ADD Rd, Rs, R7` with `R7={1,1,1,1}`). nvcc
   has no reason to preserve that.
3. **BCAST is unique to our ISA.** There's no CUDA intrinsic for
   `shfl`-style lane-broadcast that maps cleanly to ours, so the compiler
   can't produce the packed kernel. The 3.28× speedup is from hand
   writing.

**What is auto-generated for the ANN flow is the DMEM payload, not the
kernel.** `toolchains/gpu/ids_data_generator_bcast.py`:

1. Reads trained weights from JSON (`data_ids_trained_bcast_weights.json`).
2. Quantizes to BF16.
3. **Packs** them 4-per-word (or 2-per-word for L3) in the exact DMEM
   layout the hand-written kernel expects.
4. Emits the hex file that `ids_load` pushes over PCI.

### The practical recipe — "how do I write a kernel for network X on our hardware?"

1. **Pick a template**. Scalar (simple, 25% lane util) or BCAST-packed
   (complex, ~100% util, 3.28× speedup).
2. **Size-check DMEM**. Scalar layout is `in + fan_in·neurons + neurons`
   per layer; BCAST is ≈¼ that plus unpack scratch. Must fit in 1024 DMEM
   words and ideally in a BRAM-sized packet payload.
3. **Lay out DMEM** (inputs → layer 1 weights → layer 1 biases → layer 1
   output → … → final output). Commit the addresses; the kernel
   hard-codes them.
4. **Write the kernel body per layer**: bias-load into accumulator →
   inner FMA loop with stride=fan_in → ReLU (or skip for output layer)
   → store. Pair neurons in twos (or fours, with BCAST) to hide FMA
   latency.
5. **Stay lane-uniform**: only `R1-R12` as writable regs (R13-R15 are
   read-only THREADID / BLOCKID / BLOCKDIM per
   `feedback_gpu_readonly_regs`), pointer updates via `ADD Rd, Rs, R7`
   never `ADDI`.
6. **Write the companion data-generator** in Python to quantize + pack
   weights into the layout the kernel expects.
7. Run the iverilog integration TB first (`tb_gpu_integration`) to
   validate bit-exactly, then load on NetFPGA.

---

## Key file map (for quick re-reference under pressure)

| Topic                    | File                                         |
| ------------------------ | -------------------------------------------- |
| DMA FSM                  | `src/lab8_wrapper.v:195-253, 356-389`        |
| BCAST hardware           | `src/gpu/simd_alu.v:19-32`                   |
| FMA pipeline (3-stage)   | `src/gpu/execute_stage.v:44-60`              |
| Scalar IDS kernel        | `programs/gpu/ann_ids_11_16_8_2.asm`         |
| BCAST-packed IDS kernel  | `programs/gpu/ann_ids_11_16_8_2_bcast.asm`   |
| CUDA baseline kernels    | `programs/gpu/kernels/kernel.cu`             |
| PTX → our ISA translator | `toolchains/gpu/ptx_translator.py`           |
| DMEM packer (BCAST)      | `toolchains/gpu/ids_data_generator_bcast.py` |
| Register map             | `include/lab8_reg_defines.vh`                |
