# GPU Timing Fix — Lab8 Integration Refinement

Post-lab7 refinement to close the timing violation on the core clock domain
before Lab8 (full system integration on NetFPGA).

> **Document refreshed 2026-05-17.** This file is the original 2026-03-05 timing-closure plan for the 4-stage → 6-stage pipeline transition. Two later refinement bundles built on top of it:
>
> - **2026-03-19** moved branch resolution from decode to EX1 → branch penalty grew from 1 to 2 cycles. Several "1-cycle branch penalty" claims in §0/§3 below are stale relative to current RTL; the timing-budget analysis itself is still correct.
> - **2026-04-13** added an input pipeline register *inside* `simd_alu.v` to break a 15.26 ns critical path through the new BCAST mux. The simd_alu internal latency moved from 2 cycles to 3 cycles, but `execute_stage.v` dropped its own `simd_result_r` to keep the external SIMD latency at 3 cycles. The "bf16_alu stays 2-cycle, result delayed 1 cycle in execute_stage" line below is stale; see `walkthrough_batch4_execute_stage.md §3` for the current arrangement.
>
> The rest of this document is preserved as a historical record of how the 6-stage shape was first justified.

---

## 0. Implementation Status

**STATUS: IMPLEMENTED — 6-stage pipeline verified on NetFPGA, all 5 kernels pass.**

Implemented 2026-03-05. The design evolved from the original 5-stage plan to a **6-stage pipeline** (IF → ID → EX1 → EX2 → EX3 → WB) to accommodate the 3-cycle BF16 FMA unit. Key implementation details (as captured 2026-03-05; see refresh note above for what has shifted since):
- `pipeline_reg_idex.v`: No code change needed — the flush port is wired to `stall` in `core_top.v` at the instantiation (so on a stall, the register inserts a NOP bubble).
- `bf16_fma_unit.v`: Upgraded to **3-cycle pipeline** — Cycle1(EX1)=multiply+exp+sort, Cycle2(EX2)=barrel shift+add, Cycle3(EX3)=LZC+normalize+output.
- `bf16_alu.v`: Stays 2-cycle, result delayed 1 cycle in execute_stage so all results arrive in EX3. *(Stale as of 2026-04-13 — bf16_alu still 2-cycle internally, but the alignment register now lives inside `simd_alu.v` next to a new input pipeline register; total simd_alu latency = 3 cycles; `execute_stage.v` no longer has `simd_result_r`.)*
- `pipeline_reg_ex1ex2.v` renamed to `pipeline_reg_ex.v` (module: `pipeline_reg_ex`), reused for both EX1/EX2 and EX2/EX3 boundaries. Flush hardwired to `1'b0`.
- DMEM active in EX3 (doubly-registered address).
- Branch penalty: **1 cycle** — only IF/ID is flushed. Branches resolve in decode; EX stages contain valid prior instructions. *(Stale as of 2026-03-19 — branch resolution moved to EX1, penalty is now 2 cycles, two wrong-path instructions are flushed.)*
- Worst-case RAW stall: **4 cycles** (EX1 + EX2 + EX3 + WB hazard checks), up from 2 in the original 4-stage design.

---

## 1. Problem Statement

### Constraint Violated
```
* TS_core_clk_int = PERIOD "core_clk_int" 8 ns HIGH 50%
  SETUP slack = -13.428 ns   (achievable = 21.428 ns)
  2222 setup violations, Timing Score: 3,816,266
```

The design needs **125 MHz (8 ns)** but achieves only **~46.7 MHz (21.4 ns)**.
The critical path is **2.68x over budget** — 43 levels of logic.

### Exact Critical Path (from XST synthesis estimate)

```
Source:      u_idex/use_imm_out       (FF, core_clk rising)
Destination: u_exwb/alu_result_out_63 (FF, core_clk rising)
Delay:       20.786 ns  (11.1 ns logic, 9.7 ns route)
Levels:      43
```

The path traverses, in order:

1. **ID/EX register** output (`use_imm_out`) — 0.37 ns
2. **Operand B mux** (`op_b = use_imm ? imm_ext : rs2_data`) — 1 LUT
3. **bf16_alu lane 3** — the entire ADD/SUB datapath:
   - `a_gt_b_mag` magnitude comparator (7-stage MUXCY chain) — ~2.1 ns
   - `large_exp` / `small_exp` sorting muxes — 1 LUT
   - `exp_diff` subtractor (3-stage carry chain + XOR) — ~1.4 ns
   - `shift_amt` → alignment barrel shifter (`small_full >> shift_amt`) — 3 LUTs through MUXF5
   - `add_raw` adder/subtractor (4-stage carry chain + XOR) — ~1.4 ns
   - `lzc` + `add_exp_adj` exponent adjustment (3 LUT stages + carry) — ~2.3 ns
   - **Special-case priority mux** (`result = nan ? ... : inf ? ... : zero ? ... : ...`) — 6 cascaded LUTs — ~3.6 ns
4. **dtype mux** in `simd_alu` (BF16 vs int16 select) — 1 LUT
5. **FMA/SIMD result mux** in `execute_stage` — 1 LUT
6. **EX/WB register** setup — 0.2 ns

### Secondary Violated Constraints (minor)
```
* TS_rx_clk  = PERIOD "rx_clock"     8 ns  → slack -1.084 ns (pre-existing, not GPU)
* TS_tx_clk  = PERIOD "tx_clock_gmii" 8 ns → slack -0.594 ns (pre-existing, not GPU)
```
These are in the Ethernet MAC, not caused by the GPU. They exist in the
reference NIC baseline and are typically accepted or addressed separately.

### Resource Headroom (post-PAR)
| Resource     | Used   | Available | Utilization |
|-------------|--------|-----------|-------------|
| Slices      | 15,567 | 23,616    | 65%         |
| RAMB16      | 95     | 232       | 40%         |
| MULT18X18   | 12     | 232       | 5%          |
| BUFGMUX     | 8      | 16        | 50%         |

Plenty of headroom in all categories. We can freely add pipeline registers,
more BRAMs, and use more hardware multipliers.

---

## 2. Root Cause Analysis

The bf16_alu ADD/SUB path is a **single-cycle combinational monster** with
43 logic levels. Breaking it down:

| Sub-operation               | Logic Depth | Approx. Delay |
|-----------------------------|-------------|---------------|
| Operand mux (use_imm)      | 1 LUT       | ~1.0 ns       |
| Magnitude comparator        | 7 MUXCY + 1 LUT | ~2.1 ns  |
| Exp diff + shift amount     | Carry chain + 1 LUT | ~1.4 ns |
| Alignment barrel shift      | 3 LUT levels (MUXF5) | ~1.5 ns |
| 10-bit add/sub (add_raw)   | 4-stage carry + XOR | ~1.4 ns |
| LZC + exp adjustment       | LUT + carry chain | ~2.3 ns |
| Special-case priority mux  | 6 cascaded LUTs | ~3.6 ns |
| dtype + FMA/SIMD result mux| 2 LUTs | ~1.0 ns |
| **Total**                   | **43 levels** | **~20.8 ns** |

The int16_alu is NOT on the critical path — its operations (16-bit add,
16x16 multiply via MULT18X18 hardware) are much faster. The bf16_alu's
deep combinational chain is the sole bottleneck.

The bf16_fma_unit is already 2-cycle pipelined and does NOT appear on the
critical path because its Stage 1→Stage 2 register breaks the timing.

---

## 3. Fix Strategy: Pipeline the BF16 ALU + FMA (4-stage → 6-stage pipeline)

### Approach

Split the execute stage into **EX1**, **EX2**, and **EX3**, distributing the
critical path across three cycles:

```
BEFORE (4-stage):  IF → ID → EX → WB
AFTER  (6-stage):  IF → ID → EX1 → EX2 → EX3 → WB
```

The bf16_alu gets an internal pipeline register (2-cycle), and the
bf16_fma_unit is extended to 3-cycle. All results emerge in EX3:

| Stage | bf16_alu Work | bf16_fma_unit Work | Est. Delay |
|-------|---------------|-------------------|------------|
| **EX1** | Operand mux, field extraction, special-value flags, magnitude compare, exp_diff, alignment shift, raw add/sub (`add_raw`) | Multiply, exponent calculation, operand sorting | ~6.3 ns |
| **EX2** | LZC, normalization shift, exp adjustment, special-case output mux, dtype mux | Barrel shift alignment, addition | ~7 ns |
| **EX3** | (ALU result delayed 1 cycle from EX2, passed through) | LZC, normalization, final output | ~7 ns |

All three stages fit within the 8 ns budget (with routing margin for a Virtex-II Pro -7).

### FMA 3-Cycle Pipeline

The bf16_fma_unit is now 3-cycle, mapping to EX1+EX2+EX3:
- FMA Cycle 1 (EX1): multiply + exponent calculation + operand sorting
- FMA Cycle 2 (EX2): barrel shift alignment + addition
- FMA Cycle 3 (EX3): LZC + normalization + final output

This **eliminates the special `ex_busy` stall mechanism entirely** — all
operations take the same number of pipeline stages (3 EX cycles).

### bf16_alu 2-Cycle + Delay

The bf16_alu stays 2-cycle (EX1+EX2). Its result is delayed by one cycle
inside execute_stage so it arrives in EX3, aligned with FMA output.

### Branch Resolution

Branch comparison (`$signed(rs1) < $signed(rs2)`) is performed in the **decode
stage** (`decode_stage.v`), not in the execute stage. The branch target (`pc + imm`)
is also computed in decode. This is a 64-bit signed comparison — deep as a carry
chain (~2-3 ns) but well within 8 ns.

Branch penalty is **1 cycle** (flush IF/ID only). Branches resolve in decode,
and EX stages contain valid prior instructions that should not be flushed.

### int16_alu

The int16_alu is fast enough for one cycle, but must be registered to match
the 3-cycle EX latency. The int16 result is computed in EX1, registered
through EX2, and delayed again to align with EX3 output.

---

## 4. Detailed File-by-File Change Plan

### 4.1. `bf16_alu.v` — Split into 2-stage pipelined module

Add `clk` and `rst` inputs. Insert a pipeline register after the raw
add/subtract.

**EX1 (combinational + register):**
- Field extraction, special-value detection
- Magnitude compare, operand sorting
- Exponent difference, alignment shift
- Raw 10-bit add/sub → `add_raw`
- Register: `add_raw`, `large_exp`, `eff_sub`, `add_res_sign`, all
  special-case flags, MUL result, MAX result, MOV result, RELU result

**EX2 (combinational from registered values):**
- LZC on `add_raw`
- Normalization shift, exponent adjustment
- Special-case priority mux
- Output mux (ADD/SUB/MUL/MAX/MOV/RELU)

Interface changes:
```verilog
// OLD: module bf16_alu (alu_op, a, b, result);
// NEW:
module bf16_alu (
    input         clk,
    input         rst,
    input  [3:0]  alu_op,       // latched in EX1
    input  [15:0] a,
    input  [15:0] b,
    output [15:0] result        // valid in EX2
);
```

### 4.2. `int16_alu.v` — No changes

Stays purely combinational. Its result will be captured by the new
EX1/EX2 pipeline register (computed in EX1, latched for EX2).

### 4.3. `simd_alu.v` — Add clk/rst, propagate to bf16_alu instances

```verilog
// NEW ports: clk, rst
// bf16_alu instances get clk, rst connected
// int16_alu instances remain combinational
// dtype mux moves to EX2 output (after bf16 registered result is ready)
```

The dtype mux must operate on the **EX2** cycle (when bf16 results are
valid). The int16 results need to be registered in EX1→EX2 so both
paths align. Options:
- Register `int_result` inside simd_alu alongside bf16 pipeline reg.
- Or register it externally in the new EX1/EX2 pipeline register.

**Cleaner: register `int_result` inside simd_alu** so the dtype mux at the
output operates on time-aligned values.

### 4.4. `execute_stage.v` — Split into EX1/EX2

Major restructuring:

**EX1 (combinational, happens in first EX cycle):**
- Operand B mux (`use_imm ? imm_ext : rs2_data`)
- Feed operands to `simd_alu` (which now takes 2 cycles internally)
- DMEM address calculation (for LD/ST, dedicated adder: `rs1_data + imm_ext`)
- DMEM write enable + write data

**EX1→EX2 pipeline register (new `pipeline_reg_ex1ex2.v`):**
- This is largely handled internally by `simd_alu`/`bf16_alu` pipeline regs
- But we also need to latch control signals: `reg_write`, `mem_read`,
  `rd`, `is_halt`, `is_fma`

**EX2 (combinational, happens in second EX cycle):**
- Collect `simd_alu` result (now valid)
- FMA result mux (simd_alu result vs fma_result) — FMA Stage 2 also
  completes in EX2
- Final `result` output to EX/WB register

**Remove `ex_busy` entirely** — all operations now take exactly 2 EX cycles.

### 4.5. `bf16_fma_unit.v` — Extended to 3-cycle pipeline

Split from 2-cycle into 3-cycle:
- **Cycle 1 (EX1):** Multiply, exponent calculation, operand sorting
- **Cycle 2 (EX2):** Barrel shift alignment, addition
- **Cycle 3 (EX3):** LZC, normalization, final output

The `fma_cycle2` tracking in execute_stage is removed since FMA no longer
needs special stall handling — it takes the same 3 EX cycles as everything else.

### 4.6. `pipeline_reg_ex.v` (renamed from `pipeline_reg_ex1ex2.v`)

Module name: `pipeline_reg_ex`. Reused for **both** EX1/EX2 and EX2/EX3 boundaries.
Latches control signals that must survive between EX stages:
```
reg_write, mem_read, rd, is_halt
```
Flush hardwired to `1'b0` — valid instructions in EX stages always complete;
NOP bubbles flow through naturally from flushed ID/EX.

### 4.7. `pipeline_reg_exwb.v` — Minor adjustment

The `ex_busy` stall mechanism was eliminated. The module simply latches
on every cycle — no stall input needed.

### 4.8. `hazard_unit.v` — Add EX2 and EX3 stage hazard checking

Currently checks 2 stages for RAW hazards (EX dest, WB dest).
With the new 6-stage pipeline, check 4 stages:

```
EX1 dest (idex_rd, idex_reg_write)       — stall persists ~3 cycles
EX2 dest (ex1ex2_rd, ex1ex2_reg_write)   — stall persists ~2 cycles
EX3 dest (ex2ex3_rd, ex2ex3_reg_write)   — stall persists ~1 cycle
WB  dest (exwb_rd, exwb_reg_write)       — stall persists ~1 cycle
```

The hazard unit generates a single `stall` signal; the duration depends on how long
the hazard persists as the producing instruction advances through the pipeline.
Worst-case stall penalty is 4 cycles for back-to-back dependent instructions
(up from 2 in the original 4-stage design). Acceptable — the stall-only model
already has significant stalls.

**Future optimization (optional for Lab8):** Add forwarding paths from
EX3→EX1 and WB→EX1 to reduce stall cycles. This is a performance
improvement, not required for timing closure.

### 4.9. `core_top.v` — Wire up new pipeline stages

- Instantiate `pipeline_reg_ex` twice (EX1/EX2 and EX2/EX3 boundaries)
- Route EX1 outputs through EX1/EX2 reg, then through EX2/EX3 reg
- Update flush logic: branch_taken flushes IF/ID only (1-cycle penalty); ID/EX flush wired to `stall`
- Remove `ex_busy` signal and related `flush | (stall & ~ex_busy)` logic
  on ID/EX register
- Wire `ex1ex2_rd`, `ex1ex2_reg_write`, `ex2ex3_rd`, and `ex2ex3_reg_write` to hazard unit

### 4.10. `gpu_params.vh`, `gpu_nf2_wrapper.v`, `gpu_top.v` — No changes expected

The wrapper and memory interfaces are unaffected by internal pipeline changes.

---

## 5. Implementation Order

Recommended bottom-up order to allow incremental testing:

| Step | Files | Description |
|------|-------|-------------|
| 1 | `bf16_alu.v` | Add clk/rst, insert pipeline register after add_raw. Keep same test interface via a wrapper if needed. |
| 2 | `bf16_fma_unit.v` | Extend to 3-cycle pipeline: multiply+exp → shift+add → LZC+normalize. |
| 3 | `simd_alu.v` | Add clk/rst, register int16 results, connect bf16 pipeline. Verify dtype mux timing. |
| 4 | `pipeline_reg_ex.v` | Renamed from pipeline_reg_ex1ex2.v — reusable register stage for both EX1/EX2 and EX2/EX3. |
| 5 | `execute_stage.v` | Restructure: remove ex_busy/fma_cycle2, split into EX1+EX2+EX3. Delay ALU result 1 cycle. DMEM in EX3. |
| 6 | `hazard_unit.v` | Add EX2 and EX3 hazard inputs, update stall logic for 4-stage checking. |
| 7 | `core_top.v` | Wire everything together, instantiate pipeline_reg_ex twice, update flush/stall. |
| 8 | Re-synthesize | Target: minimum period < 8 ns on core_clk. |
| 9 | Re-run all 5 kernel test programs | vec_add, vec_sub, relu, bf16_mul, bf16_fma — verify functional correctness after pipeline change. |

---

## 6. Timing Budget (Post-Fix Estimate)

With the work distributed across three EX stages:

### bf16_alu path (2-cycle, result delayed to EX3)

| Path Segment | EX1 Delay (est.) | EX2 Delay (est.) | EX3 Delay (est.) |
|-------------|-------------------|-------------------|-------------------|
| Operand mux | 1.0 ns | — | — |
| Magnitude compare | 2.1 ns | — | — |
| Exp diff + alignment shift | 2.9 ns | — | — |
| Raw add/sub | 1.4 ns | — | — |
| LZC | — | 1.5 ns | — |
| Normalization + exp adjust | — | 2.3 ns | — |
| Special-case mux | — | 3.0 ns | — |
| dtype + result mux | — | — | passthrough |
| **Pipeline reg overhead** | 0.6 ns | 0.2 ns | 0.2 ns |
| **Total** | **~8.0 ns** | **~7.0 ns** | **< 1 ns** |

### bf16_fma_unit path (3-cycle)

| Path Segment | EX1 Delay (est.) | EX2 Delay (est.) | EX3 Delay (est.) |
|-------------|-------------------|-------------------|-------------------|
| Multiply + exp calc + sort | ~6.3 ns | — | — |
| Barrel shift + addition | — | ~7 ns | — |
| LZC + normalize + output | — | — | ~7 ns |
| **Pipeline reg overhead** | 0.6 ns | 0.2 ns | 0.2 ns |
| **Total** | **~6.9 ns** | **~7.2 ns** | **~7.2 ns** |

The 3-way split distributes the FMA critical path approximately evenly across
~6.3 ns, ~7 ns, and ~7 ns — all well within the 8 ns budget. The bf16_alu
path is comfortable since EX3 is essentially a passthrough for ALU results.

---

## 7. Risk Assessment

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| EX1 still > 8 ns after split | Medium | Move split point earlier (after magnitude compare). Register exp_diff inputs. |
| Functional regression in BF16 ops | Medium | Run all 5 kernel tests. Add targeted BF16 edge-case tests. |
| Increased stall penalty hurts kernel performance | Low | Kernels are small, no tight loops with BF16 data hazards. Add forwarding later if needed. |
| EX2 critical path through special-case mux | Low | Simplify the priority chain — precompute more flags in EX1. |
| DMEM read timing changes (load-use latency) | Low | DMEM active in EX3 with doubly-registered address. Loads now have +2 cycles latency to WB — hazard unit handles this via stall. |

---

## 8. Files Reference

All GPU source files are in `src/`:
```
core_top.v              — Pipeline orchestration (MODIFY)
fetch_stage.v           — IF/ID metadata register (no change)
decode_stage.v          — Decoder + regfile wrapper (no change)
instruction_decoder.v   — Combinational decoder (no change)
register_file.v         — 16x64 FF register file (no change)
pipeline_reg_idex.v     — ID/EX pipeline register (minor: remove ex_busy flush logic)
execute_stage.v         — Execute stage (MAJOR RESTRUCTURE)
bf16_alu.v              — BF16 ALU (MAJOR: add pipeline register)
bf16_fma_unit.v         — BF16 FMA 3-cycle (MAJOR: extended from 2-cycle)
int16_alu.v             — Int16 ALU (no change)
simd_alu.v              — 4-lane SIMD wrapper (MODIFY: add clk/rst, register int16 path)
pipeline_reg_ex.v       — EX1/EX2 and EX2/EX3 pipeline register (renamed from pipeline_reg_ex1ex2.v, reused)
pipeline_reg_exwb.v     — EX3/WB pipeline register (minor: remove ex_busy stall)
writeback_stage.v       — WB mux (no change)
hazard_unit.v           — Hazard detection (MODIFY: add EX2 + EX3 stage checks, 4-stage)
gpu_top.v               — GPU top (no change)
gpu_nf2_wrapper.v       — NF2 wrapper (no change)
user_data_path.v        — NF2 data path (no change)
```

Parameters and register map (`include/gpu_params.vh`, `include/registers.v`)
are unchanged.

**Note:** `bf16_alu.v` still uses `wire signed` for MUL exponent arithmetic
(lines 50, 59). This works correctly because MUL exponent math doesn't mix
signed/unsigned concatenations the way FMA does. The FMA unit was fully
rewritten to unsigned (see `fma_signed_arithmetic_fix.md`), but the simpler
bf16_alu MUL path was left as-is since it produces correct results in ISE 10.1.
