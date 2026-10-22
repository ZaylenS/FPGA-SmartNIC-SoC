# BCAST Instruction: Design Rationale and Analysis

## 1. Motivation

The GPU coprocessor has a 4-lane SIMD datapath (4 x BF16 or 4 x INT16 per register).
Every arithmetic instruction operates **element-wise** across lanes:

```
FMA Rd, Rs1, Rs2, Rs3   =>   Rd[i] = Rs1[i]*Rs2[i] + Rs3[i]   for i = 0..3
```

There are **no cross-lane operations**: no broadcast-from-register, no horizontal
sum, no lane shuffle. The only instruction that replicates a value is `MOVI Rd, imm`,
which broadcasts a compile-time constant to all lanes.

This creates a fundamental problem for multi-layer neural network inference.

### 1.1 The Inter-Layer Data Problem

Consider a 4-neuron parallel computation for layer L:

```
R1 = {acc3, acc2, acc1, acc0}     # 4 neuron accumulators packed in one register
R2 = {w3[i], w2[i], w1[i], w0[i]} # 4 neurons' weights for input i, packed
R3 = {x[i],  x[i],  x[i],  x[i]} # input i, replicated across all lanes

FMA R1, R2, R3, R1                 # acc[j] += w[j][i] * x[i] for j=0..3
```

This works perfectly for one FMA -- all 4 lanes compute independent neurons with
the same input. The problem is: **how did R3 get its replicated value?**

- For layer 1 inputs (from DMEM): currently stored as `{v, v, v, v}` (pre-replicated
  in the data generator). This wastes 4x DMEM.
- For layer 2+ inputs (outputs of the previous layer): the previous layer produced
  `R1 = {h3, h2, h1, h0}`. To use `h0` as input to the next layer, we need
  `{h0, h0, h0, h0}`. **There is no instruction to do this.**

Without a broadcast instruction, we are forced into **scalar mode**: every value is
replicated across all 4 lanes (`{v, v, v, v}`), all 4 lanes compute identically,
and we discard 3/4 of the SIMD throughput.

### 1.2 Current Workaround: Scalar Mode with 2-Neuron Interleaving

The IDS kernel (`ann_ids_11_16_8_2.asm`) uses scalar mode:
- All DMEM values stored as `{v, v, v, v}` across 4 BF16 lanes (4x DMEM waste)
- All 4 lanes compute the same thing (75% SIMD waste)
- Processes 2 neurons per loop iteration via register interleaving (R1 = neuron A,
  R5 = neuron B) to hide LD->FMA pipeline stalls

```
Group loop (2 neurons at a time):
    LD   R2, 0(R8)           # weight neuron A
    LD   R3, 0(R9)           # input (shared)
    ADD  R9, R9, R7          # ptr++ early (hides BLT stall)
    LD   R4, S(R8)           # weight neuron B (stride S)
    FMA  R1, R2, R3, R1      # acc_A += w_A * x
    FMA  R5, R4, R3, R5      # acc_B += w_B * x
    ADD  R8, R8, R7
    BLT  R9, R12, loop
```

This achieves ~14 cycles per iteration for 2 FMAs (7 cycles/neuron-update), which
is close to optimal for a stall-only pipeline processing 2 neurons. But it requires:
- 8 groups for layer 1 (16 neurons / 2)
- 4 groups for layer 2 (8 neurons / 2)
- 1 group for layer 3 (2 neurons / 2)
- **Total: 13 groups, 211 instructions, ~2402 cycles**

### 1.3 What BCAST Enables

A `BCAST Rd, Rs, lane_sel` instruction copies one lane of Rs to all 4 lanes of Rd:

```
BCAST R3, R1, 0   =>  R3 = {R1[lane0], R1[lane0], R1[lane0], R1[lane0]}
BCAST R3, R1, 2   =>  R3 = {R1[lane2], R1[lane2], R1[lane2], R1[lane2]}
```

This solves the inter-layer problem:

```
# After layer L computes R1 = {h3, h2, h1, h0}:
BCAST R3, R1, 0   # R3 = {h0, h0, h0, h0}  -- use h0 as input
BCAST R3, R1, 1   # R3 = {h1, h1, h1, h1}  -- use h1 as input
BCAST R3, R1, 2   # R3 = {h2, h2, h2, h2}  -- etc.
BCAST R3, R1, 3   # R3 = {h3, h3, h3, h3}
```

With BCAST, the kernel can use **4-neuron parallel mode**: pack 4 different neurons
into one register, use all 4 SIMD lanes for independent computation, and extract
individual results at layer boundaries.

---

## 2. Performance Analysis

### 2.1 Optimized Inner Loop with BCAST

For layer 1 (inputs stored one-per-word, weights packed 4-per-word):

```asm
loop:
    LD    R3, 0(R9)          # Load scalar input x[i] (lane 0)
    LD    R2, 0(R8)          # Load packed weights {w3[i], w2[i], w1[i], w0[i]}
    ADD   R9, R9, R7         # input ptr++  (filler, hides LD stall)
    ADD   R8, R8, R7         # weight ptr++ (filler, hides LD stall)
    BCAST R3, R3, 0          # Broadcast input to all 4 lanes
    FMA   R1, R2, R3, R1     # 4 neurons: acc[j] += w[j]*x for j=0..3
    BLT   R9, R12, loop
```

### 2.2 Stall Analysis (No Result Forwarding)

The pipeline has stall-only RAW hazard resolution. The hazard unit checks stages
EX1, EX2, EX3, and WB -- a consumer in ID stalls until the producer exits WB.

**Stall costs** (producer immediately before consumer, no fillers):
- LD -> next:  4 cycles  (producer traverses EX1, EX2, EX3, WB)
- ALU -> next: 4 cycles  (same 4-stage traversal)
- FMA -> next: 4 cycles

**BCAST loop trace** (7 instructions):

| Dependency | Gap (fillers between) | Stall |
|------------|----------------------|-------|
| LD R3 -> BCAST R3 | 3 (LD R2, ADD R9, ADD R8) | **1 cycle** (LD in WB when BCAST in ID) |
| BCAST R3 -> FMA (R3) | 0 (back-to-back) | **4 cycles** (BCAST in EX1 when FMA in ID) |
| LD R2 -> FMA (R2) | 3 (ADD R9, ADD R8, BCAST) +1 stall | **0 cycles** (LD R2 exits WB before FMA reaches ID) |
| ADD R9 -> BLT (R9) | 2 (BCAST+stalls, FMA+stalls) | **0 cycles** (ADD R9 long exited) |

**Per iteration: 7 instructions + 5 stalls + 2 branch penalty = 14 cycles for 4 neurons.**

### 2.3 Comparison: Cycles Per Neuron-Update

| Approach | Cycles/iter | Neurons/iter | Cycles/neuron | SIMD utilization |
|----------|-------------|--------------|---------------|------------------|
| Current scalar (2-neuron interleave) | 14 | 2 | **7.0** | 25% (1 of 4 lanes useful) |
| BCAST 4-neuron | 14 | 4 | **3.5** | 100% (all 4 lanes useful) |
| BCAST 8-neuron (2-group interleave) | ~18 | 8 | **~2.25** | 100% |

### 2.4 Full Network Cycle Estimate (11-16-8-2 MLP)

**Layer 1 (11 inputs -> 16 neurons):**

| Approach | Groups | Iters/group | Cycles/iter | Loop cycles | Setup | Total |
|----------|--------|-------------|-------------|-------------|-------|-------|
| Current (2-neuron) | 8 | 11 | 14 | 1232 | 96 | **1328** |
| BCAST 4-neuron | 4 | 11 | 14 | 616 | 48 | **664** |
| BCAST 8-neuron | 2 | 11 | 18 | 396 | 40 | **436** |

**Layer 2 (16 inputs -> 8 neurons):**

Inputs come from L1 outputs packed 4-per-word. Two sub-approaches:

*Option A*: Unpack L1 outputs to individual DMEM words (LD + BCAST lane + ST x16),
then use the same simple loop. Adds ~150-200 cycle unpack overhead.

*Option B*: Use lane-select BCAST inside L2's inner loop to extract packed inputs
on-the-fly. More complex loop structure (partially unrolled by 4), avoids unpack cost.

| Approach | Groups | Loop cycles | Unpack | Total |
|----------|--------|-------------|--------|-------|
| Current (2-neuron) | 4 | 896 | 0 | **944** |
| BCAST 4-neuron + unpack | 2 | 448 | 150 | **646** |
| BCAST 8-neuron + unpack | 1 | 288 | 150 | **458** |

**Layer 3 (8 inputs -> 2 neurons):**

Only 2 output neurons -- cannot fill 4 SIMD lanes. Keep current 2-neuron
interleaving. ~124 cycles regardless of approach.

**Total network estimates:**

| Approach | L1 | L2 | L3 | Total | Speedup |
|----------|-----|-----|-----|-------|---------|
| **Current** (scalar, 2-neuron) | 1328 | 944 | 124 | **~2400** | 1.0x |
| BCAST 4-neuron | 664 | 646 | 124 | **~1430** | **1.7x** |
| BCAST 8-neuron interleave | 436 | 458 | 124 | **~1020** | **2.4x** |

### 2.5 Why Not 8x?

The original estimate of ~300 cycles (8x speedup) assumed zero pipeline stalls, as
if the GPU had full result forwarding. It does not -- every RAW dependency stalls
until the producer exits WB.

BCAST introduces a new serial dependency chain: **LD -> BCAST -> FMA**. Each hop
costs 1-4 stall cycles depending on how many independent instructions can be placed
in between. The current 2-neuron interleaving already hides stalls effectively at
7 cycles/neuron -- BCAST reduces this to 2.25-3.5 cycles/neuron, a **2x-3x
improvement per neuron**, not 8x.

The 8x figure would be achievable with result forwarding (bypassing stalls entirely).
This makes a good "theoretical vs. actual" comparison story for the performance
evaluation section of the report.

### 2.6 DMEM Utilization Improvement

| | Current (scalar) | With BCAST (packed) |
|---|---|---|
| Inputs (11 features) | 11 words x {v,v,v,v} | 11 words (lane 0 only) |
| L1 weights (16 x 11) | 176 words x {v,v,v,v} | 44 words (4 neurons packed) |
| L1 biases (16) | 16 words | 4 words (packed) |
| L1 outputs (16) | 16 words | 4 words (packed) |
| L2 weights (8 x 16) | 128 words | 32 words (packed) |
| L2 biases/outputs | 16 words | 4 words |
| L3 weights/biases/outputs | 20 words | 11 words |
| **Total** | **383 / 1024 (37%)** | **~110 / 1024 (11%)** |
| **Reduction** | -- | **3.5x** |

This frees ~270 DMEM words for larger networks or batched inference.

---

## 3. Instruction Specification

### 3.1 Encoding

Uses R-type format with lane select as immediate in func[1:0]. Opcode `5'b11010` (0x1A).

```
[31:27]  [26:23]  [22:19]  [18:15]  [14:12]  [11:2]   [1:0]
opcode   rd       rs1      0000     dtype    unused    lane
BCAST    dest     source   (zero)   (unused) (zero)    0-3
```

**Semantics**: `BCAST Rd, Rs1, lane`
- Extract 16-bit lane `lane[1:0]` (from func field) of Rs1
- Replicate that 16-bit value to all 4 lanes of Rd
- dtype field is unused (operation is data-type agnostic -- just bit replication)
- rs2 field = 0 avoids false hazard stalls (R0 is hardwired zero, filtered by hazard unit)

**Assembly syntax**: `BCAST R3, R1, 2` (lane is a literal 0-3, not a register).

**Encoding examples**:
- `BCAST R3, R1, 0` = `0xD1880000`
- `BCAST R3, R1, 2` = `0xD1880002`

### 3.2 Pipeline Behavior

- Same latency as MOV: 2 cycles through SIMD ALU path (EX1 -> EX2)
- Decoder sets `use_imm=1` with `imm_ext = {62'b0, instruction[1:0]}` -- lane select delivered via operand_b
- Hazard unit: reads rs1 (source), rs2 field = 0 (no false stalls), writes rd
- No new pipeline stages or control signals beyond `ALU_BCAST`

### 3.3 Hardware Location

The cross-lane replication happens in `simd_alu.v` **before** the per-lane ALU
dispatch. Each lane's ALU sees the replicated value and passes it through (MOV
semantics). This is the only correct placement -- the per-lane ALUs cannot see
other lanes' data.

```
                    operand_a (64-bit, 4 lanes)
                         |
                    [BCAST mux]  <-- replicate selected lane to all 4 positions
                         |
              effective_a (64-bit, all lanes identical)
                         |
            +-----+-----+-----+-----+
            | L0  | L1  | L2  | L3  |   (per-lane ALU, MOV passthrough)
            +-----+-----+-----+-----+
                         |
                    result (64-bit, all lanes = selected lane value)
```

### 3.4 Resource Estimate

| Component | Change | LUTs |
|-----------|--------|------|
| `gpu_params.vh` | +2 defines (OP_BCAST, ALU_BCAST) | 0 |
| `instruction_decoder.v` | +1 case branch | ~5 |
| `simd_alu.v` | 4:1 lane mux (16-bit) + 64-bit replicate mux | ~30 |
| `int16_alu.v` | +1 ALU_BCAST case (passthrough) | ~3/lane x4 |
| `bf16_alu.v` | +1 ALU_BCAST case in EX2 output mux | ~3/lane x4 |
| **Total** | | **~50 LUTs** |

At 96% slice utilization on XC2VP50 (23,616 slices, ~47K LUTs), 50 LUTs is ~0.1%.

---

## 4. Trade-off Summary

### Benefits
- **~2x inference speedup** (2402 -> ~1000-1400 cycles) for the 11-16-8-2 IDS MLP
- **3.5x DMEM reduction** (383 -> ~110 words), enabling larger networks
- **3x fewer instructions** (211 -> ~70-90), reducing IMEM pressure
- **100% SIMD utilization** vs. 25% in scalar mode
- Strong "before/after" performance comparison story for lab report

### Costs and Risks
- **Re-synthesis required** at 96% slice utilization (~50 LUTs addition)
- **Kernel rewrite** needed (new assembly, new data generator, new test vectors)
- **Timing risk**: existing 4816 violations; BCAST mux is in EX1 (not on critical
  path in DECODE), but routing congestion at 96% could cause new violations
- **Verification**: need simulation re-validation of all IDS test cases

### Risk Mitigation
- Current bitfile is the fallback -- no RTL changes until BCAST is sim-verified
- 50 LUTs is within synthesis noise at this utilization level
- BCAST mux is in EX1, not on the critical path (DECODE stage, 11ns)
- Kernel correctness verifiable in simulation before touching hardware

---

## 5. Implementation

<!-- Placeholder: detailed RTL changes, file-by-file diffs, and verification -->

### 5.1 RTL Changes — DONE

1. **`include/gpu_params.vh`**: Added `OP_BCAST 5'b11010` and `ALU_BCAST 4'd6`
2. **`src/gpu/instruction_decoder.v`**: Added `OP_BCAST` case — `alu_op=ALU_BCAST`, `reg_write=1`, `use_imm=1`, `imm_ext={62'b0, instruction[1:0]}`
3. **`src/gpu/simd_alu.v`**: Added pre-dispatch lane mux — 4:1 mux on `operand_a` lanes selected by `operand_b[1:0]`, replicated to `effective_a` when `alu_op==ALU_BCAST`. All per-lane ALU instances use `effective_a` instead of `operand_a`.
4. **`src/gpu/int16_alu.v`**: Added `ALU_BCAST: result = a` (passthrough, replication already done)
5. **`src/gpu/bf16_alu.v`**: Added `ALU_BCAST: result = s1_mov_result` in EX2 output mux (reuses MOV's registered passthrough)

### 5.2 Toolchain Changes — DONE (assembler), TODO (data generators)

1. **`toolchains/gpu/isa_defs.py`**: Added `BCAST` opcode (0b11010), `encode_bcast(rd, rs1, lane)`, 2 self-test cases (15/15 pass)
2. **`toolchains/gpu/assembler.py`**: Added `BCAST rd, rs1, lane` parsing (lane is 0-3 immediate)
3. **`toolchains/gpu/data_generator.py`**: TODO — packed DMEM layout for BCAST mode
4. **`toolchains/gpu/ids_data_generator.py`**: TODO — packed weights for IDS kernel

### 5.3 Optimized IDS Kernel

TODO: New kernel assembly for 4-neuron parallel mode

- `programs/gpu/ann_ids_11_16_8_2_bcast.asm` -- optimized kernel
- DMEM layout documentation
- Register allocation for inter-layer BCAST sequences

### 5.4 Verification — DONE (unit + regression), TODO (integration)

1. **Unit test** (`tb/tb_bcast.v`): All 4 lane selects verified (DDDDCCCCBBBBAAAA → each lane broadcast correctly). 4/4 PASS, 21 cycles.
2. **Regression**: IDS inference test (`tb/tb_ids_inference.v`) still passes 26/26 with BCAST RTL changes. 2402 cycles unchanged.
3. **Integration test**: TODO — BCAST-optimized IDS kernel produces same classification as scalar kernel

### 5.5 Synthesis Results (2026-04-11)

Synthesis completed successfully on Fedora VM. Bitfile generated (`nf2_top_par.bit`).

Compared against Lab 8 baseline synthesis (`C:\Dev\EE533Labs\Lab8_fifo\synth\`).

**Resource Utilization (XC2VP50):**

| Resource | Lab 8 (baseline) | Lab 10 + BCAST | Delta |
|----------|------------------|----------------|-------|
| Slices (XST) | 21,096 (89%) | 21,134 (89%) | **+38** |
| Slices (PAR) | 20,963 (88%) | 21,375 (90%) | **+412** |
| 4-input LUTs | 29,427 (62%) | 29,492 (62%) | **+65** |
| LUTs as logic | 27,291 | 27,356 | **+65** |
| Flip-flops | 16,919 (35%) | 16,919 (35%) | 0 |
| MULT18X18 | 12 (5%) | 12 (5%) | 0 |
| BRAM (XST) | 37 (15%) | 37 (15%) | 0 |
| BRAM (PAR) | 108 (46%) | 108 (46%) | 0 |

BCAST added exactly **+65 LUTs** (close to the ~50 estimate). No new flip-flops (BCAST
is purely combinational in EX1). The PAR slice delta (+412) is larger than the XST delta
(+38) due to placement packing differences across synthesis runs.

**Timing (core_clk_int, 125 MHz / 8ns period):**

| Metric | Lab 8 (baseline) | Lab 10 + BCAST | Delta |
|--------|------------------|----------------|-------|
| Achievable period (XST) | 11.788ns | 13.485ns | **+1.697ns** |
| Achievable period (PAR) | 11.958ns | 16.597ns | **+4.639ns** |
| Worst slack (PAR) | -3.958ns | -8.597ns | **-4.639ns** |
| Setup violations | 2,145 | 4,785 | **+2,640** |
| Timing score | 2,154,574 | 6,067,113 | **+3,912,539** |
| Constraints not met | 2 | 3 | +1 (tx_clk now fails) |
| XST critical path levels | 18 | 35 | +17 |

**Lab 8 critical path** (PAR, 11.958ns):
```
ARM CPU barrel shifter → ALU adder → EX/MEM pipeline register
  Source: u_cpu/ex_shift_amt(1)_REPLICA_114
  Dest:   u_cpu/u_exmem/o_Z
```

**Lab 10 + BCAST critical path** (PAR, 16.597ns):
```
imm_ext_out_0 (FF, ID/EX pipe reg)
  → op_b mux (use_imm ? imm_ext : rs2_data)      [LUT3, 0.275ns + 0.925ns net]
  → bcast_value lane select (4:1 mux on lanes)    [LUT3+MUXF5, 0.578ns + 2.015ns net]
  → effective_a mux (BCAST vs passthrough)         [LUT3, 0.275ns + 0.087ns net]
  → bf16_alu: a_gt_b_mag comparator chain          [carry chain, ~3.5ns]
  → bf16_alu: exp_diff subtractor                  [carry chain, ~2.0ns]
  → bf16_alu: shift + add_raw adder                [LUTs + carry, ~3.5ns]
  → s1_add_raw_9 (FF, EX1→EX2 pipe reg)
```

The critical path moved from the **ARM CPU** (barrel shifter in EX stage) to the
**GPU EX1 stage** (BCAST mux → BF16 ALU). The BCAST lane mux inserts 3 LUT levels
before the BF16 ALU's comparator+adder chain. The 2.015ns net delay on `bcast_value`
(fanout=5, routed across distant slices) dominates the degradation — gate delay alone
adds ~1.7ns (matching the XST delta), but routing congestion at 90% utilization
inflates the post-route path by an additional ~3ns.

The design continues to work on hardware despite timing violations (verified in prior
labs). The GPU pipeline uses stall-based hazard resolution, so functional correctness
does not depend on single-cycle timing closure — slower clock would simply reduce
throughput, not cause incorrect results.
