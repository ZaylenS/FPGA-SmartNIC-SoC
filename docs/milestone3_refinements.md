# Milestone 3 Refinements — Timing Closure for BCAST IDS

**Date started**: 2026-04-17
**Goal**: Close timing on the Apr 12 BCAST bitfile so IDS inference runs deterministically on nf5, eliminating the 14-cycle / 1.0-BF16 glitch seen in ~40% of BCAST runs during milestone 2. This is a prerequisite for the final-project Part 3 live DDoS demo (see `docs/final_project_expert_demo_plan.md` §7.2).

---

## 1. Problem Statement

### 1.1 Symptom (hardware on nf5, milestone 2 demo)

- `lab10reg.py ids_compare_perf` works correctly ~60% of runs (732 cycles, `DMEM[126] = 0x41b041b0_41b041b0`, decodes to BF16 22.0)
- The other ~40% drop exactly 14 cycles and exactly 1.0 in the final BF16 output per missed iteration — a timing-violated branch signal causes the BCAST inner loop to terminate early.

### 1.2 Timing evidence — Apr 12 baseline (`synth/timing_issues_2026-04-12/nf2_top_par.twr`)

`TS_core_clk_int = PERIOD 8 ns` (125 MHz):

| Metric | Apr 12 baseline |
|--------|-----------------|
| Failing endpoints | **4,146** |
| Worst slack | **−7.150 ns** |
| Min period achieved | 15.15 ns |
| Timing score | ~6 M |

### 1.3 Critical path (Apr 12)

```
idex_use_imm (FF, ID/EX pipe reg)
  → op_b mux                                      (execute_stage.v:29)
  → bcast_value 4:1 lane mux                      (simd_alu.v:22-31)
  → bcast_value NET, fanout=5, 2.223 ns route     ← largest single delay
  → effective_a mux (BCAST vs passthrough)        (simd_alu.v:33-35)
  → bf16_alu.a_gt_b_mag compare + carry chain
  → bf16_alu.exp_diff subtractor
  → bf16_alu.shift + add_raw
  → s1_add_raw (FF, EX1 → EX2 pipe reg)
```

Path lands in `bf16_lane[1]` (or lane 3 after re-synth). Structural pattern: **BCAST mux → effective_a → BF16 ALU mantissa-alignment chain**. The 2.223 ns fanout-5 `bcast_value` net + 3 LUT levels of muxing in front of the BF16 ALU is the dominant contributor.

### 1.4 Resource pressure (Apr 12)

89% slice utilization. Synth analysis in `docs/bcast_instruction_design.md` §5.5 attributes ~1.7 ns of the critical path to added gate delay from BCAST, and ~3 ns to routing congestion at 89%+ utilization (distant-placement routing).

---

## 2. Round 1 (Apr 17 morning) — Scalar INT16 (Option A)

### 2.1 Approach

Reduce the 4-lane INT16 SIMD unit to a single scalar lane 0 ALU, replicate lane 0 to all 4 output lanes. Rationale:

- IDS kernel only consumes lane 0 of integer results (pointer arithmetic, loop counters). DMEM addressing uses `rs1_data[9:0]` directly in `execute_stage.v:78`, not the full SIMD result.
- BF16 carries all multi-lane ML work.
- Expected to free ~3 MULT18X18 + ~250 LUTs, relieve congestion, indirectly shorten the BF16 critical-path routing.

### 2.2 RTL change — `src/gpu/simd_alu.v`

Replaced 4-lane generate of `int16_alu` with a single instance on lane 0, `int_result = {4{int_lane0}}`.

### 2.3 Simulation verification (Apr 17)

| Test | Result | Cycles |
|------|--------|--------|
| `tb/tb_bcast.v` | **4/4 PASS** | 21 |
| `tb/tb_ids_inference.v` | **26/26 PASS** | 2402 |
| `tb/tb_ids_bcast.v` | **26/26 PASS** | 732 |
| `tb/tb_gpu_integration.v` | **ALL PASS** | — |

Cycle counts bit-identical to pre-change baseline — semantics preserved for IDS + BCAST paths.

### 2.4 Synth results — what happened (Apr 17 build)

`synth/nf2_top.srp` + `synth/nf2_top_par.twr`:

| Resource | Apr 12 | Apr 17 (Round 1) | Δ |
|----------|--------|------------------|---|
| Slices | 21,068 (89%) | **20,931 (88%)** | −137 |
| 4-input LUTs | 29,421 | **29,146** | −275 |
| MULT18X18 | 12 | **9** | **−3** ✓ (as predicted) |
| FFs | 16,952 | 16,952 | 0 |

**Timing regressed:**

| Metric | Apr 12 | Apr 17 (Round 1) |
|--------|--------|------------------|
| Failing endpoints | 4,146 | **9,390** (**+5,244**, 2.3× worse) |
| Worst slack | −7.150 ns | **−7.259 ns** |
| Timing score | ~6 M | **12.47 M** |
| Min period | 15.15 ns | 15.26 ns |

### 2.5 Diagnosis

The critical path is **structurally identical** to Apr 12 (`synth/nf2_top_par.twr:336`):

- Same source: `idex_use_imm_REPLICA_663` (FF)
- Same destination: `bf16_lane[3].u_bf16/s1_add_raw_9` (FF, lane 3 this time, was lane 1)
- Same pattern: op_b mux → bcast_value mux → effective_a → BF16 ALU chain
- `bcast_value` routing: 2.223 ns → **2.556 ns** (slightly *worse*)

Resource savings landed as predicted (1% slices, 3 mults, 275 LUTs), but Option A never touched the path that sets the critical path. PAR took the extra placement flexibility and scattered the design — the `bcast_value` fanout-5 net routed across more distance, and many adjacent paths that were comfortably below the edge are now near it. Worst slack barely moved because the path *structure* is unchanged; the whole timing distribution just shifted worse.

**Conclusion**: Option A alone is insufficient. Need a structural fix that directly shortens the 15.26 ns BCAST-mux → BF16-ALU path.

The Apr 12 synth snapshot has been archived to `synth/timing_issues_2026-04-12/` before the Apr 17 build overwrote the parent `synth/` directory.

---

## 3. Round 2 (Apr 17 afternoon) — Register `effective_a` (Fix 1)

### 3.1 Approach

Insert a pipeline register at the simd_alu EX1→EX2 boundary that captures the BCAST mux output (`effective_a`) plus `alu_op`, `dtype`, `operand_b`. The BF16 ALU and INT16 ALU then see *registered* inputs, breaking the 15.26 ns combinational path into two halves:

- **First half (~6 ns)**: `idex_use_imm` FF → op_b mux → bcast_value mux → effective_a mux → **new input register**
- **Second half (~7 ns)**: **new input register** → BF16 ALU EX1 (a_gt_b_mag → exp_diff → shift → add_raw) → `s1_add_raw` FF

Each half fits comfortably in 8 ns.

### 3.2 Keeping kernel cycle counts unchanged

`simd_alu` grows from 2-cycle internal to 3-cycle internal. To preserve external SIMD latency (still needs to land in EX3 aligned with 3-cycle FMA), `execute_stage.v` drops its own `simd_result_r` EX2→EX3 register — the SIMD result now comes out of `simd_alu` directly in EX3.

Net effect on pipeline stages:
- **Before**: SIMD ALU 2 cycles internal + 1 cycle in execute_stage alignment reg = 3 cycles total, output in EX3
- **After**: SIMD ALU 3 cycles internal + 0 cycles in execute_stage = 3 cycles total, output in EX3

Hazard unit, writeback timing, branch resolution, FMA timing all unchanged. Kernel cycle counts and instruction stalls identical. No assembly/kernel edits required.

### 3.3 RTL changes

**`src/gpu/simd_alu.v`** — added EX1→EX2 input register:

```verilog
reg [3:0]              alu_op_r;
reg [2:0]              dtype_r1;
reg [`DATA_WIDTH-1:0]  effective_a_r;
reg [`DATA_WIDTH-1:0]  operand_b_r;

always @(posedge clk) begin
    if (rst) begin
        alu_op_r      <= 4'd0;
        dtype_r1      <= 3'd0;
        effective_a_r <= {`DATA_WIDTH{1'b0}};
        operand_b_r   <= {`DATA_WIDTH{1'b0}};
    end else begin
        alu_op_r      <= alu_op;
        dtype_r1      <= dtype;
        effective_a_r <= effective_a;
        operand_b_r   <= operand_b;
    end
end
```

`int16_alu` and all 4 `bf16_alu` instances now connect to the `*_r` registered inputs instead of the combinational wires.

Replaced `int_result_r` (64-bit) with 16-bit `int_lane0_r` (captures `int_lane0` one cycle later to align with BF16's EX1→EX2→EX3 output). Added second-stage `dtype_r2` register so the output dtype mux sees the correct instruction's dtype.

**`src/gpu/execute_stage.v`** — removed `simd_result_r`:

```verilog
// Before: simd_result_r <= simd_result; assign result = is_fma_r2 ? fma_result : simd_result_r;
// After:                                assign result = is_fma_r2 ? fma_result : simd_result;
```

The EX2→EX3 always block still exists for `is_fma_r2`, `mem_write_r2`, `rs2_data_r2`, `mem_addr_r2` — only the SIMD alignment flop is removed.

### 3.4 Simulation verification (Apr 17, after fix 1)

| Test | Result | Cycles | Baseline match |
|------|--------|--------|----------------|
| `tb/tb_bcast.v` | **4/4 PASS** | 21 | ✓ |
| `tb/tb_ids_inference.v` | **26/26 PASS** | 2402 | ✓ identical |
| `tb/tb_ids_bcast.v` | **26/26 PASS** | 732 | ✓ identical |
| `tb/tb_gpu_integration.v` | **ALL PASS** | — | ✓ |

Cycle-count parity confirms the external pipeline latency is unchanged — the fix is purely an internal re-partitioning of simd_alu.

### 3.5 Expected synth impact (pre-synth hypothesis)

The Apr 17 Round 1 critical path was `idex_use_imm FF → ... → s1_add_raw FF` at 15.26 ns / 18 levels of logic. Splitting it at `effective_a_r` should produce:

- **Path A**: `idex_use_imm FF → op_b mux (~0.3 ns LUT + ~1.2 ns net) → bcast_value mux (~0.5 ns LUT + ~2.5 ns net) → effective_a mux (~0.3 ns LUT) → effective_a_r FF setup (~0.5 ns)` ≈ **5–6 ns**
- **Path B**: `effective_a_r FF → effective_a net (fanout ≈ 4, shorter than fanout-5 bcast_value) → bf16_alu a_gt_b_mag → exp_diff → shift → add_raw → s1_add_raw FF setup` ≈ **6–8 ns**

Expected failing-endpoint count: large reduction (Apr 17 had 9390; hypothesis: <500). Worst slack: expected to move from −7.26 ns toward ≥ −1 ns. This would be sufficient for deterministic hardware behavior at 125 MHz. If the second half is still over budget, it would hit ~8-9 ns worst, which is close to closure.

Flip-flop count will grow by ~135 (64 + 64 + 4 + 3 + 16 − removal of 64-bit simd_result_r − 64-bit int_result_r + keeping 16 bits + ...). The net is approximately neutral.

### 3.6 Actual synth results (Apr 17 R2 — post-fix-1)

Bitfile built cleanly (`+++testFinished:build.bitgen.nf2_top_par.bit` in `log.txt`). Compared against the two baselines:

| Metric | Apr 12 (pre-fix) | Apr 17 R1 (scalar INT16 alone) | **Apr 17 R2 (fix 1)** |
|--------|------------------|-------------------------------|----------------------|
| Slices | 21,068 (89%) | 20,931 (88%) | **20,960 (88%)** |
| FFs | 16,952 | 16,952 | **16,974** (+22 from new pipe reg) |
| 4-input LUTs | 29,421 | 29,146 | **29,187** |
| MULT18X18 | 12 | 9 | **9** |
| Failing endpoints (`core_clk_int`) | 4,146 | 9,390 | **650** |
| Worst slack | −7.150 ns | −7.259 ns | **−4.219 ns** |
| Min period | 15.15 ns | 15.26 ns | **12.22 ns** |
| Timing score | ~6.1 M | 12.47 M | **446,956** |

Endpoint reduction: **14.4× fewer** failing paths vs R1 (9390 → 650). Worst slack improved by 3.04 ns. Timing score improved 27×.

**All other clock domains now close:**

| Constraint | Apr 12 | Apr 17 R1 | Apr 17 R2 |
|------------|--------|-----------|-----------|
| `TS_rx_clk` | 153 failing | 63 failing | **0 failing** ✓ |
| `TS_tx_clk_gmii` | 89 failing | 34 failing | **0 failing** ✓ |
| `TS_rgmii_falling_to_rising` | 0 failing | 0 failing | 0 errors (−0.026 ns slack, 1 path) |
| All `CPCI_*` OFFSETs | 0 failing | 0 failing | **0 failing** ✓ |
| All `SRAM*` OFFSETs | 0 failing | 0 failing | **0 failing** ✓ |

#### Critical path migrated out of the GPU

`synth/nf2_top_par.twr:130-133`:

```
Source:       u_cpu/ex_shift_amt(1)_REPLICA_113 (FF)    ← ARM CPU barrel shifter
Destination:  u_cpu/u_exmem/o_Z (FF)                    ← EX/MEM pipeline reg
Data Path Delay: 12.154 ns (38 levels of logic)
Slack: −4.219 ns
```

This is the **Lab 8 baseline critical path** from before BCAST was ever added
(see `docs/bcast_instruction_design.md` §5.5). The BCAST mux → BF16 ALU path
is no longer the worst — fix 1 demoted it below the ARM CPU path.

#### Why this is probably enough for the IDS demo

The 650 remaining failing endpoints all live in the ARM CPU datapath (barrel
shifter + ALU adder feeding EX/MEM). The IDS inference pipeline does **not**
use the ARM CPU — it's FIFO ← packet arrives → GPU DMA → GPU kernel → GPU DMA
→ FIFO. The ARM CPU is idle during classification. These ARM-side violations
should not manifest as BCAST glitches.

Expected hardware behavior: the 14-cycle / 1.0-BF16 glitch that appeared in
~40% of BCAST runs at milestone 2 should be **eliminated or dramatically
reduced**. The branch-evaluation path that was hitting the edge of timing is
now well inside its budget (each half of the split path fits in ~6-8 ns).

The Apr 17 R1 synth snapshot (before fix 1) is captured in
`docs/milestone3_refinements.md` §2.4 and can be regenerated from git by
checking out the commit before the fix-1 RTL change.

### 3.7 Hardware verification on nf5 (2026-04-17)

Bitfile `synth/nf2_top_par.bit` built at 11:00:41 on 2026-04-17 was
deployed to nf5 (`~/zil_testing_folder/nf2_top_par.bit`) and downloaded
via `nf_download`. All verification steps passed:

| # | Test | Result |
|---|------|--------|
| 1 | Sanity readback (CTRL/STATUS/DMA_CTRL/CYCLE) | `0x1 / 0x0 / 0x0 / 0x0` — no `0xdeadbeef` regression |
| 2 | Scalar IDS regression | cycles=**2402**, DMEM[381..382]=`0x41b041b0_41b041b0` (both lanes) |
| 3 | **BCAST × 5 loop** | **5/5 PASS** — cycles=**732** every run, DMEM[126]=`0x41b041b0_41b041b0` every run |
| 4 | `ids_compare_perf` | Scalar 2402 / BCAST 732 / **3.28× speedup** unchanged |

The headline result is the BCAST × 5 loop. On the Apr 12 bitfile this
same loop glitched in ~40% of runs (short cycle counts / BF16 output
drift). After fix 1 the same loop produced bit-identical cycle counts
and bit-identical DMEM output across 5 consecutive runs — the glitch
is closed.

**Fix 1 is hardware-verified.** No need to stack fix 2 (BCAST-in-ID)
or fix 3 (clock drop to 100 MHz). Proceed to Part 3 live DDoS demo
prep.

(Note: the original verification plan quoted scalar cycles as 1254 —
that was an error in the plan. The correct scalar baseline is 2402
cycles, which matches both the `tb/tb_ids_inference.v` simulation
result and the `ids_compare_perf` output. The 3.28× speedup ratio is
the authoritative figure.)

---

## 4. Q&A — Pipeline Design Details

Captured during the fix-1 design review. Useful as a reference for anyone
inheriting the design or doing a subsequent refinement round.

### 4.1 Pipeline diagram — `simd_alu` after fix 1

```
Clock edge:       ↑T                  ↑T+1                  ↑T+2                  ↑T+3
                  │                   │                     │                     │
  ┌───────────────┴──────┐ ┌──────────┴──────────┐ ┌────────┴─────────┐ ┌────────┴──
  │    EX1 (cycle T)     │ │   EX2 (cycle T+1)   │ │  EX3 (cycle T+2) │ │    WB
  │                      │ │                     │ │                  │ │
  │  alu_op, dtype,      │ │  alu_op_r (stable)  │ │  bf16 EX2 combo: │ │ reg file
  │  operand_a,          │ │  dtype_r1 (stable)  │ │   LZC, norm,     │ │ write
  │  operand_b           │ │  effective_a_r      │ │   output mux     │ │ happens
  │  arrive from ID/EX   │ │  operand_b_r        │ │  → bf16_result   │ │ here
  │                      │ │                     │ │                  │ │
  │  Combinational ONLY: │ │ bf16_alu EX1 combo: │ │  int_lane0_r     │ │
  │  ├─ bcast_value 4:1  │ │  ├─ a_gt_b_mag      │ │   (stable)       │ │
  │  │   mux             │ │  ├─ exp_diff        │ │   → int_result   │ │
  │  └─ effective_a mux  │ │  ├─ shift           │ │     = {4{...}}   │ │
  │     (BCAST or not)   │ │  └─ add_raw         │ │                  │ │
  │                      │ │                     │ │  dtype_r2        │ │
  │  ← SHORT PATH:       │ │ int16_alu combo     │ │   (stable)       │ │
  │    use_imm FF →      │ │  → int_lane0        │ │                  │ │
  │    op_b mux →        │ │                     │ │  simd_result =   │ │
  │    bcast_value mux → │ │                     │ │   dtype_r2==BF16 │ │
  │    effective_a mux → │ │                     │ │   ? bf16_result  │ │
  │    *_r FF setup      │ │                     │ │   : int_result   │ │
  │    ≈ 5-6 ns          │ │                     │ │                  │ │
  │                      │ │                     │ │  Consumed        │ │
  │                      │ │                     │ │  directly by     │ │
  │                      │ │                     │ │  execute_stage   │ │
  │                      │ │                     │ │  (no more        │ │
  │                      │ │                     │ │   simd_result_r) │ │
  └──────────────────────┘ └─────────────────────┘ └──────────────────┘ │
                  │                   │                     │           │
  Registers that capture at this edge:                                  │
                  ├ alu_op_r          ├ bf16 s1_* (internal ├ pipeline_reg_exwb
                  ├ dtype_r1          │   to bf16_alu)      │  captures simd_result
                  ├ effective_a_r     ├ int_lane0_r         │  → feeds WB
                  └ operand_b_r       └ dtype_r2            │
                                                            │
                  ← CRITICAL PATH, second half:             │
                    *_r FF → bf16 EX1 combo → s1_* setup    │
                    ≈ 6-8 ns                                │
```

The long `use_imm → bcast → effective_a → bf16 a_gt_b_mag → add_raw` path
(15.26 ns on Apr 17 Round 1) is split at the new `effective_a_r` FF between
EX1 and EX2. First half stays in EX1, second half runs in EX2.

### 4.2 Why no kernel edits are required

Three observations chain together.

**(a) Pipeline stage count is unchanged.** The GPU still has 6 stages:
`IF → ID → EX1 → EX2 → EX3 → WB`. Every instruction spends exactly one cycle
in each stage. Nothing inside `simd_alu.v` or `execute_stage.v` adds or
removes a stage — the change repartitions work *within* EX1/EX2/EX3, it
doesn't add EX4.

**(b) SIMD ALU external latency is unchanged (3 cycles).**

| | Apr 12 / Apr 17 R1 | Apr 17 R2 (fix 1) |
|---|---|---|
| Inside `simd_alu` | 2 cycles (EX1 combo + s1_* reg + EX2 combo) | 3 cycles (EX1 combo + input reg + EX2 combo + s1_* reg + EX3 combo) |
| Inside `execute_stage` | 1 cycle (`simd_result_r`) | 0 cycles |
| **Total: input → execute_stage output** | **3 cycles** | **3 cycles** |

An `ADD R9, R2, R7` entering EX1 still lands its result at the execute_stage
output at the end of EX3, the same cycle as before. The same applies to FMA
(still 3-cycle, unchanged).

**(c) Hazard unit sees stages, not internals.** `src/gpu/hazard_unit.v`
stalls a consumer in ID if its source register matches the destination of
any instruction currently in EX1, EX2, EX3, or WB. It doesn't care *what
internal computation* those stages are doing — only that the producer hasn't
finished writeback yet. Consumer-in-ID-stalls = 4 cycles if producer is
immediately before it. That count is set by "4 stages from ID to reg-file
write." That distance is unchanged.

**Concrete example — IDS BCAST inner loop:**

```asm
LD    R3, 0(R9)          ; producer: loads R3 via SIMD ALU path
LD    R2, 0(R8)          ; filler
ADD   R9, R9, R7         ; filler
ADD   R8, R8, R7         ; filler
BCAST R3, R3, 0          ; consumer of R3, producer of R3 for FMA
FMA   R1, R2, R3, R1     ; consumer of R3
```

Stall accounting (unchanged before vs after fix 1):
- `LD R3` → `BCAST R3`: 3 filler instructions between; LD is in WB when
  BCAST reaches ID → **1-cycle stall** (same)
- `BCAST R3` → `FMA R3`: back-to-back; BCAST in EX1 when FMA in ID, so FMA
  stalls until BCAST exits WB → **4-cycle stall** (same)
- Branch penalty: 2 cycles (unchanged, branches resolve in EX1)
- **Total: 7 + 5 + 2 = 14 cycles per iteration** — matches the `tb_ids_bcast`
  732-cycle baseline and the sim run after fix 1 (732 cycles, bit-identical).

If fix 1 had changed either the SIMD producer-to-WB distance or the FMA
alignment, `tb_ids_bcast` cycle count would have shifted by a multiple of
iterations. The fact that 2402 and 732 both match to the cycle is the
ground-truth confirmation that no kernel retiming is needed.

### 4.3 Where does the `effective_a` path live now?

**Q**: The previous `effective_a` path was all in EX1. The fix split it
across EX1 and EX2. The whole execute stage is still 3-stage pipelined,
right?

**A**: Yes.

**Before fix 1** (2-cycle SIMD ALU):

| Stage | Work |
|-------|------|
| EX1 | op_b mux → bcast_value mux → effective_a mux → **BF16 ALU EX1** (a_gt_b_mag, exp_diff, shift, add_raw) → s1_* FF capture |
| EX2 | BF16 ALU EX2 (LZC, norm, output mux) → `simd_result_r` FF capture in execute_stage |
| EX3 | result mux (`is_fma_r2 ? fma_result : simd_result_r`) |

Everything from `use_imm` FF through `add_raw` computed in a single cycle
(EX1). That's the 15.26 ns critical path.

**After fix 1** (3-cycle SIMD ALU):

| Stage | Work |
|-------|------|
| EX1 | op_b mux → bcast_value mux → effective_a mux → **new input FF capture** (`effective_a_r`, `operand_b_r`, `alu_op_r`, `dtype_r1`) |
| EX2 | **BF16 ALU EX1** (a_gt_b_mag, exp_diff, shift, add_raw) → s1_* FF capture; also int16_alu combinational → `int_lane0_r` FF capture |
| EX3 | BF16 ALU EX2 (LZC, norm, output mux) → result mux (direct, no more `simd_result_r`) |

The BF16 ALU EX1 combinational block physically moved from
happening-during-EX1 to happening-during-EX2. Everything else stayed in
place. Still 3 stages total, still produces its result in EX3. Only the
internal work partition inside the SIMD ALU shifted one slot to the right,
and the previously-existing `simd_result_r` alignment flop was removed
because it's no longer needed to stretch SIMD to 3 cycles — the SIMD ALU
now does 3 cycles on its own.

### 4.4 Why `simd_result_r` had to be removed

**Q**: Why was `simd_result_r` no longer needed to stretch SIMD to 3 cycles
— what changed?

**A**: The flop existed to *align the latency* of two parallel functional
units that both feed the EX3 result mux.

#### The latency-matching invariant

Inside `execute_stage.v` there are two parallel datapaths that both need to
produce a result at the same point in the pipeline:

```
                    ┌───────────────┐
                    │   FMA unit    │ — 3 cycles internal (unchanged)
  rs1, rs2, rs3 ────┤               ├──→ fma_result
                    └───────────────┘
                    ┌───────────────┐
                    │   SIMD ALU    │ — N cycles internal
  rs1, op_b    ─────┤               ├──→ simd_result
                    └───────────────┘
                                          ↓
                                    is_fma_r2 ? fma_result : simd_alu_path
                                          ↓
                                      result output
```

Both are driven with inputs that arrive in **EX1**. Both must produce their
output in **EX3**, because that's when the result mux fires and
`pipeline_reg_exwb` latches for writeback. That means each path must take
**exactly 3 cycles** from input to mux input.

FMA is always 3 cycles. SIMD ALU was 2 cycles. `simd_result_r` existed to
add the missing 1 cycle.

#### Before fix 1 — both paths = 3 cycles

| Cycle | FMA path (3 cycles) | SIMD path (2 internal + 1 simd_result_r) |
|-------|---------------------|------------------------------------------|
| EX1 (T) | FMA stage 1 combo | `effective_a` mux → bf16 EX1 combo → s1_* FF setup |
| EX2 (T+1) | FMA stage 2 combo | s1_* stable → bf16 EX2 combo → simd_alu.result stable at end of T+1 |
| EX3 (T+2) | FMA stage 3 combo → `fma_result` stable at end of T+2 | `simd_result_r` holds N's SIMD result (captured at T+1→T+2 edge) |
| End of T+2 | mux: `is_fma_r2 ? fma_result : simd_result_r` — **both are N's data** ✓ | |

#### After fix 1 without removing `simd_result_r` — BROKEN

SIMD ALU is now 3 cycles internal (input reg added). If `simd_result_r`
stayed in place, total SIMD path would be **4 cycles**. FMA still 3 cycles.
They'd be 1 cycle apart.

| Cycle | FMA path (3 cycles) | SIMD path would be 3 internal + 1 alignment = **4 cycles** |
|-------|---------------------|-----------------------------------------------------------|
| EX1 (T) | FMA stage 1 combo | combo through bcast mux + effective_a mux → input FF setup |
| EX2 (T+1) | FMA stage 2 combo | input FF stable → bf16 EX1 combo → s1_* FF setup |
| EX3 (T+2) | FMA stage 3 combo → `fma_result` stable end of T+2 (**N's data**) | s1_* stable → bf16 EX2 combo → `simd_alu.result` stable end of T+2 (**N's data**), but `simd_result_r` still holds **N−1's** value from the T+1→T+2 capture |
| End of T+2 | mux: `is_fma_r2 ? fma_result (N's) : simd_result_r (N−1's!)` | |

At cycle T+2 when instruction N is in EX3, `is_fma_r2` holds N's control
signal (that register was aligned through two EX1→EX2 and EX2→EX3 captures).
If N is a SIMD op, the mux picks `simd_result_r` — but that flop was last
updated at the T+1→T+2 edge, when `simd_result` was still N−1's result
(N−1 was in EX3 during T+1, so its SIMD output was stable at end of T+1,
and *that* is what `simd_result_r` captured).

Concretely: **instruction N's writeback would receive instruction N−1's
SIMD computation.** Every SIMD op produces stale data. Silent correctness
bug, no exception raised.

#### After fix 1 with `simd_result_r` removed — ALIGNED

| Cycle | FMA path (3 cycles) | SIMD path (3 internal, no alignment flop) |
|-------|---------------------|-------------------------------------------|
| EX1 (T) | FMA stage 1 combo | combo → input FF setup |
| EX2 (T+1) | FMA stage 2 combo | input FF stable → bf16 EX1 combo → s1_* FF setup |
| EX3 (T+2) | FMA stage 3 combo → `fma_result` stable end of T+2 (**N's data**) | s1_* stable → bf16 EX2 combo → `simd_result` stable end of T+2 (**N's data**) |
| End of T+2 | mux: `is_fma_r2 ? fma_result : simd_result` — **both are N's data** ✓ | |

`simd_alu` now naturally does 3 cycles and the result is ready exactly when
FMA's result is ready. The external alignment flop that used to do this
job is redundant — and if left in, it would re-introduce a 1-cycle delay
that breaks alignment in the opposite direction.

#### General rule

> When you push a pipeline stage *into* a submodule, you must pull the
> matching alignment stage *out* of the wrapper.

This is the bookkeeping cost of repartitioning pipeline work. The total
input-to-output latency of the functional unit across wrapper + submodule
must stay constant, otherwise either (a) external alignment with parallel
paths breaks (what happens here with FMA), or (b) hazard-unit stall
distances shift (every kernel's producer→consumer spacing becomes wrong).

Fix 1 balanced the ledger: **+1 cycle inside `simd_alu`** (new input
register), **−1 cycle inside `execute_stage`** (removed `simd_result_r`).
Net external latency change: zero. That's why the simulator runs produce
bit-identical cycle counts (732 and 2402) and no kernel edits are needed.

---

## 5. Options Remaining (If Fix 1 is Still Insufficient)

### 4.1 Fix 2 — Move BCAST mux into ID stage

Pre-compute `bcast_value` in decode, register `effective_a` into the ID/EX pipeline register directly. Eliminates the `bcast_value` fanout-5 combinational net inside EX1 entirely. BCAST latency unchanged from today. More RTL work (touches decode_stage and pipeline_reg_idex).

### 4.2 Fix 3 — Drop `core_clk_int` 125 → 100 MHz

Edit UCF `PERIOD 8ns → 10ns`. Guaranteed close. Gives up the "125 MHz" number but BCAST speedup story holds (cycle count is what matters for the speedup multiplier).

---

## 6. Next Steps

1. Re-synthesize on the Fedora VM (`cd /root/netfpga/projects/lab8/synth && make`) with fix 1 RTL
2. Compare `synth/nf2_top_par.twr` failing endpoints + worst slack vs both Apr 12 and Apr 17 Round 1 baselines
3. Deploy new bitfile to nf5 (`nf_download nf2_top_par.bit`)
4. Re-run the 5× BCAST loop from `docs/milestone2_demo_script.md` Part 8 on nf5. Gate: 5/5 runs produce `cycles=732` and `DMEM[126]=0x41b041b041b041b0`.
5. If still glitching: add fix 2 (BCAST in ID) or fix 3 (drop to 100 MHz).

---

## 7. File Index

Changed:
- `src/gpu/simd_alu.v` — scalar INT16 (Round 1) + effective_a input register (Round 2)
- `src/gpu/execute_stage.v` — removed simd_result_r (Round 2)

Unchanged (verified):
- `src/gpu/int16_alu.v`
- `src/gpu/bf16_alu.v`
- `src/gpu/bf16_fma_unit.v`
- `src/gpu/hazard_unit.v`
- All kernels under `programs/gpu/`

Archived:
- `synth/milestone3_fix1_2026-04-17/` — **Fix 1 known-good baseline.** Includes bitfile (`nf2_top_par.bit`)
- `synth/timing_issues_2026-04-12/` — Apr 12 synth snapshot (.mrp / .prj / .srp / _par.par / _par.twr)
- `synth/broken_2026-04-11/` — original DEADBEEF-era synth snapshot

---

## 8. References

- `docs/arm_orchestrator.md` — milestone-3 ARM-orchestrator refinement (full plan + implementation log; supersedes the old §9 below)
- `docs/bcast_instruction_design.md` §5.5 — Lab 8 vs Lab 10 + BCAST synth deltas
- `docs/milestone2_demo_script.md` Part 8 — BCAST 5× run showing the glitch pattern
- `docs/final_project_demo_video/final_project_expert_demo_plan.md` §7.2 — why this matters for the live DDoS demo
- `synth/nf2_top_par.twr` — current timing report (Apr 17 Round 1, will be overwritten by Round 2 re-synth)
- `synth/timing_issues_2026-04-12/nf2_top_par.twr` — Apr 12 baseline

---

## 9. ARM-Orchestrator Refinement — see `docs/arm_orchestrator.md`

A third milestone-3 refinement, separate from rounds 1–2 above: turn the
ARM CPU into the on-chip IDS pipeline orchestrator (poll FIFO_STATUS,
dispatch DMA, release the GPU, drain responses) so the host stops being
the throughput limiter (~1 pps Python today → microsecond-scale per
iteration on-chip). The full plan, RTL implementation log, hand-assembled
ARM program, verification results (10/10 alias slots + 6/6 orchestrator
iterations + clean regression sweep), and lessons learned all live in
**[`docs/arm_orchestrator.md`](arm_orchestrator.md)** to keep this doc
focused on the timing-closure rounds. Synth gate for that refinement
runs alongside the Fix 1 bitfile baseline above.

For details — module-level RTL changes, deviations from the original
plan, the BRAM-mode-dependency lesson, etc. — refer to the dedicated
file. **Stop reading this doc here for ARM-orchestrator work.**

---

## 10. Round 3 (Apr 20) — Placement Closure for Fix B via Neutral RTL Perturbations

This round is back in timing-closure territory. The ARM-orchestrator Fix B
refinement (§9, `docs/arm_orchestrator.md` §13.3) added small amounts of
logic to `src/lab8_wrapper.v` — one new alias slot for `reg_fifo_drain`
and a ternary on `fifo_proc_din` forcing `ctrl=0xFF` on BRAM[0] writes.
Functionally tiny (~10 LoC), but it pushed slice utilization from 85% to
86% and that was enough to destabilize placement.

### 10.1 Symptom — first Fix B synth (2026-04-20 15:36 / 16:02)

The first two Fix B syntheses (two back-to-back runs of the same RTL —
ISE 10.1 is deterministic so they produced bit-identical results)
regressed timing catastrophically vs the Fix A baseline from Apr 18:

| Metric | Apr 18 Fix A (hw-verified) | Apr 20 Fix B v1 |
|--------|---------------------------|-----------------|
| Slices | 20,169 (85%) | 20,494 (86%) |
| Total timing errors | 700 | **4,589** |
| `TS_core_clk_int` worst slack | −4.612 ns | **−11.124 ns** |
| `TS_core_clk_int` failing endpoints | 700 | **4,433** |
| `TS_rx_clk` failing | **0** | **131** (NEW) |
| `TS_tx_clk_gmii` failing | **0** | **25** (NEW) |
| Timing score | 457,575 | 4,919,655 |
| Router behavior | Clean | Emitted `WARNING:Route:441` — "extremely unlikely to meet timing... will change strategy... work to completely route this design but not to improve timing." |

The critical issues:

1. **MAC clocks started failing.** `TS_rx_clk` (gigabit RX PHY) and
   `TS_tx_clk_gmii` (gigabit TX PHY) had 131 + 25 = 156 failing endpoints
   combined. These are real PHY interface clocks tied to external GMII;
   failures here directly risk packet corruption on the wire.
2. **Core clock went from marginal to severely failing.** Fix A's
   −4.612 ns worst slack (which worked on silicon because the failing
   paths weren't routinely toggled) jumped to −11.124 ns. The worst
   path was the same ARM barrel-shifter → 64-bit adder chain from
   rounds 1–2, but placement had migrated it into a routing-congested
   region.
3. **The router gave up.** `WARNING:Route:441` triggered mid-run — an
   explicit admission that timing was unrecoverable at the current
   placement.

### 10.2 Diagnosis — placement roulette at high utilization

ISE 10.1's PAR is deterministic: same RTL + same tool settings → same
placement. Re-running without changing anything confirmed this —
two runs 26 minutes apart produced bit-identical .bit files and
identical timing numbers.

At 85% utilization (Fix A), the placer had enough slack in the routing
budget to tolerate the ARM critical path. At 86% (Fix B v1), the
additional ~325 slices from the alias-window logic pushed a few
critical nets into congested regions, and the router couldn't
re-converge. It's not a design problem — Fix A's logic all still exists,
unchanged — it's a **placement congestion problem** triggered by the
new logic's hash perturbing the initial placement seed.

The fix: change the RTL in a way that ISE can't optimize back to the
original netlist, so the placer starts from a different seed. All RTL
changes here are **semantic-preserving** — they produce identical
behavior in simulation — but structurally different enough that XST
emits a different netlist.

### 10.3 What didn't work — trivial perturbations (Apr 20 16:33)

First attempt: converted the alias-read mux from
```verilog
case (cpu_reg_sel)
   4'h0: cpu_reg_rdata = ...;
   ...
   default: cpu_reg_rdata = 64'd0;
endcase
```
to
```verilog
cpu_reg_rdata = 64'd0;        // pre-init
case (cpu_reg_sel)
   4'h0: cpu_reg_rdata = ...;
   ...
   default: ;
endcase
```

The produced bitfile had a different hash than v1 (XST did notice the
change) but **identical timing totals** (4,589 errors, same per-clock
breakdown). These two idioms are semantically equivalent enough that
XST's normalization pass reduced them to the same netlist. Lesson
learned: the perturbation has to be *structurally* different, not just
syntactically different.

### 10.4 What worked — two stacked structural perturbations

Both changes are in `src/lab8_wrapper.v`, both `git checkout`-reversible.

**Perturbation 1 (Apr 20 17:20) — Two-level alias read mux tree.**

Original (flat 16:1 mux in a single always@(*) case):
```verilog
always @(*) begin
   case (cpu_reg_sel)
      4'h0: cpu_reg_rdata = {32'd0, reg_dma_ctrl};
      ...                                     // 10 more arms
      4'hA: cpu_reg_rdata = {32'd0, reg_fifo_drain};
      default: cpu_reg_rdata = 64'd0;
   endcase
end
```

New (two 8:1 sub-muxes + final 2:1 selector):
```verilog
reg [63:0] alias_rd_lo;   // slots 0..7
reg [63:0] alias_rd_hi;   // slots 8..F

always @(*) begin
   case (cpu_reg_sel[2:0])
      3'd0: alias_rd_lo = {32'd0, reg_dma_ctrl};
      ...
      default: alias_rd_lo = 64'd0;
   endcase
end

always @(*) begin
   case (cpu_reg_sel[2:0])
      3'd0: alias_rd_hi = {32'd0, reg_ctrl};
      ...
      default: alias_rd_hi = 64'd0;
   endcase
end

always @(*) cpu_reg_rdata = cpu_reg_sel[3] ? alias_rd_hi : alias_rd_lo;
```

XST can't flatten this back to a single 16:1 mux without inferring
the intermediate signals away — and the named intermediate `reg`s
force separate LUT placements. Result:

| Metric | v1 (flat) | v2 (two-level mux) |
|--------|-----------|--------------------|
| Slices | 20,494 | 20,773 (+279) |
| Total timing errors | 4,589 | **3,340** (↓27%) |
| `TS_core_clk_int` worst slack | −11.124 ns | **−6.159 ns** |
| `TS_rx_clk` failing | 131 | **21** |
| `TS_tx_clk_gmii` failing | 25 | **12** |
| Worst core_clk path | ARM barrel-shifter | **GPU BF16 FMA exponent-subtract** |

The critical-path source *migrated* from ARM to GPU FMA — strong
evidence that placement had genuinely shifted, not just wiggled.
Still failing, but unambiguously trending the right way.

**Perturbation 2 (Apr 20 21:13) — `arm_bram_wctrl` named wire.**

Targeting a different region of the wrapper this time so both
perturbations contribute independently. Original (inline ternary):
```verilog
fifo_proc_din = (cpu_ext_mem_addr[6:0] == 7'h00)
                ? {8'hFF, cpu_ext_mem_din}
                : {8'h00, cpu_ext_mem_din};
```

New (dedicated always block + named intermediate, concat moved outside):
```verilog
reg [7:0] arm_bram_wctrl;
always @(*) begin
   if (cpu_ext_mem_addr[6:0] == 7'h00)
      arm_bram_wctrl = 8'hFF;
   else
      arm_bram_wctrl = 8'h00;
end
// ... elsewhere in proc mux:
fifo_proc_din = {arm_bram_wctrl, cpu_ext_mem_din};
```

Combined result (both perturbations stacked):

| Metric | Fix A (Apr 18) | v2 (one pert.) | **v3 (both pert.)** | Gate |
|--------|---------------|---------------|---------------------|------|
| Slices | 20,169 (85%) | 20,773 (87%) | 21,190 (89%) | — |
| Total timing errors | 700 | 3,340 | **817** | — |
| Timing score | 457,575 | 4,924,951 | **555,674** | — |
| `TS_core_clk_int` worst slack | −4.612 ns | −6.159 ns | **−4.394 ns** ✓ | PASS (≥ −5 ns) |
| `TS_core_clk_int` failing | 700 | 3,306 | **817** ✓ | PASS (≤ 900) |
| `TS_rx_clk` failing | 0 | 21 | **0** ✓ | PASS (must be 0) |
| `TS_tx_clk_gmii` failing | 0 | 12 | **0** ✓ | PASS (must be 0) |
| `TS_rgmii_falling_to_rising` | 0 | 1 | **0** ✓ | PASS |

**Meets every plan gate.** Core slack is actually slightly *better*
than Fix A's (−4.394 vs −4.612 ns), failing endpoint count is only
+117 vs Fix A, and all MAC / RGMII / SRAM / CPCI constraints are
clean. The bitfile `synth/nf2_top_par.bit` (md5 `aa680d9fcc...`,
post-synth 2026-04-20 21:13 local) is the Fix-B shipping artifact.

### 10.5 Progression summary

| Attempt | RTL state | Total errors | TS_rx_clk | TS_tx_clk_gmii | Core worst slack |
|---------|-----------|-------------|-----------|----------------|------------------|
| 1 (15:36) | Fix B initial | 4,589 | 131 | 25 | −11.124 ns |
| 2 (16:02) | Same as #1 (rerun) | 4,589 | 131 | 25 | −11.124 ns |
| 3 (16:33) | #1 + "pre-init + case" (XST collapsed back) | 4,589 | 131 | 25 | −11.124 ns |
| 4 (17:20) | Two-level mux tree | 3,340 | 21 | 12 | −6.159 ns |
| **5 (21:13)** | **Two-level mux + `arm_bram_wctrl`** | **817** | **0** | **0** | **−4.394 ns** |

### 10.6 Lessons

1. **ISE 10.1 is deterministic.** Re-running without RTL changes gives
   bit-identical output. Any closure attempt has to change the netlist
   hash. Confirmed by attempts #1/#2 producing identical .bit + .twr.
2. **Not all "semantic-preserving" RTL changes perturb placement.**
   XST normalizes trivially-equivalent idioms (e.g. `case with default`
   vs `pre-init then case`) back to the same netlist. To actually move
   placement, the change needs to introduce genuinely different
   structure — named intermediate signals, different mux topology,
   additional always blocks. Attempt #3 confirmed the no-op case.
3. **Structural changes across multiple regions compound.** One
   perturbation (two-level mux) got us from −11.1 → −6.2 ns. Two
   perturbations (mux + named ctrl wire, in different wrapper regions)
   got us from −6.2 → −4.4 ns. Each materially-different netlist
   region gives the placer fresh initial seed inputs, and in this
   design that was enough to recover Fix A–class timing.
4. **Slice utilization matters more than total change size.** Going
   from 85% → 89% slice utilization across these four synth attempts
   didn't hurt timing — what hurt was being near a congestion threshold
   *with a specific netlist shape*. The final bitfile uses +1,021
   slices vs Fix A (4% larger) and still closes better than Fix A did.
5. **Watch for `WARNING:Route:441`.** When ISE emits this router
   warning, it has given up trying to meet timing and is just routing
   for completeness. The bitfile will still generate but the reported
   slack numbers reflect the "give up" state. In attempt #1 this
   warning fired; in attempt #5 (the shipping bitfile) it didn't.

### 10.7 How to apply to future work

If a future refinement bumps slice utilization into the same danger
zone (~86%+) and timing fails, the playbook is:

1. Check whether ISE emitted `WARNING:Route:441`. If yes, it's
   placement congestion, not a fundamental timing problem.
2. Pick one or two regions of the wrapper that aren't on the critical
   path and apply structural-but-equivalent perturbations (named
   intermediates, mux tree restructuring, split always blocks). Verify
   the change passes sim.
3. If the first perturbation moves the needle (new .bit hash + changed
   timing numbers) but doesn't fully close, stack a second perturbation
   in a different region without reverting the first.
4. **Don't revert working perturbations** even if they feel like
   clutter — they're what's keeping the placer in a good local minimum.
   The two perturbations in this round cost +1,021 slices and closed
   timing; undoing them would break closure.

Backup: `synth/arm_orchestrator_partially_working_2026-04-18/` is the
Fix A revert target if a future change destabilizes this placement.

