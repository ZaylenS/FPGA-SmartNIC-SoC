# Refinements Plan -- Ordered Execution with Synthesis Checkpoints

Cross-referenced from `refinements.md`, `improvements_and_optimizations.md`, and
`gpu_update_notes.md`. Evaluated 2026-03-19. Updated 2026-03-20.

---

## Phase 1 Status: HARDWARE VERIFIED (2026-03-20)

All Phase 1 items synthesized and tested on NetFPGA (nf5.usc.edu).

| Test | Result |
|------|--------|
| cpu_test (all_halted) | PASS |
| 5 CUDA kernels (PCI-direct) | 5/5 PASS |
| 2 ANN inference (PCI-direct) | 2/2 PASS |
| 2 ANN integrated (FIFO->DMA->GPU->DMA->FIFO) | 2/2 PASS |
| **Total** | **9/9 PASS** |

### Bug found and fixed during HW test

**GPU HALT gating timing failure**: The combinational `assign halted = halted_r || exwb_is_halt`
created a path from `exwb_is_halt` through `halted` to `dmem_wr_en` that failed setup timing
at 125 MHz (4816 existing violations on core_clk_int). The ST instruction's DMEM write was
suppressed for most kernels. Fix: changed to `assign halted = halted_r` (registered only,
1-cycle delay in HALT detection -- harmless, just 1 extra NOP fetched after HALT).

---

## Items Applied and Hardware Verified

| ID | File(s) | What | Status |
|----|---------|------|--------|
| C1 | `ID.v` | Conditional execution gating (`cond_pass`) | FIXED, **HW pass** |
| C2 | `convertible_fifo.v` | 1-word packet FSM hang | FIXED, **HW pass** |
| H1/P7 | `IF_stage.v`, `processor.v` | PC halt gating (freezes halted threads) | FIXED, **HW pass** (all_halted=1 confirmed) |
| H2 | `data_mem.v`, `processor.v` | `was_ext` reset | FIXED, **HW pass** |
| M2 | `ID.v` | `default` in condition case | FIXED, **HW pass** |
| GPU F-02 | `bf16_alu.v` | Unsigned exponent rewrite (ISE synthesis bug) | FIXED, **HW pass** |
| GPU F-03 | `core_top.v` | HALT gating (PC, IMEM, DMEM) -- registered only | FIXED, **HW pass** (after timing fix) |
| GPU F-06/10 | `pipeline_reg_idex.v`, `core_top.v` | Dead wire cleanup | FIXED, **HW pass** |
| GPU branch | `decode_stage.v`, `core_top.v`, `pipeline_reg_idex.v`, `hazard_unit.v`, `program_counter.v` | Branch moved to EX1 (critical path 15.5ns -> 11ns) | FIXED, **HW pass** |
| GPU comments | `pipeline_reg_exwb.v`, `gpu_top.v` | Stale comment fixes | FIXED, **HW pass** |

## Items NOT Yet Applied -- Evaluation

| ID | Source | What | Evaluation |
|----|--------|------|------------|
| **H3** | refinements.md | CPU runs at start_stop=0 | **SKIP** -- Not reproduced. Software workaround (atomic start) is sufficient. Adding an IF_stage gate is harmless but unnecessary churn. |
| **H4** | refinements.md | Registered PCI strobes for CPU IMEM/DMEM | **DEFER** -- Current paths work because they're short (direct assign, no mux). Only needed if you add muxing later. Not worth the risk now. |
| **H5** | refinements.md | DMA address overflow bounds check | **NICE-TO-HAVE** -- Software is responsible for correct addresses. A saturate/error bit is ~5-10 lines but doesn't fix anything that's broken. Low priority. |
| **M1** | refinements.md | Missing ARM opcodes (ADC, SBC, RSB, RSC, CMN) | **SKIP for Lab 8** -- No test program uses these. Adding them risks introducing bugs. Relevant only if Lab 9 needs them. |
| **M3** | refinements.md | ROR #0 should be RRX | **SKIP** -- No program uses RRX. ARM corner case. |
| **M4** | refinements.md | C_flag for logic ops | **SKIP** -- No program depends on carry from AND/ORR/EOR. |
| **L1** | refinements.md | Dead code (`adder8_comb.v`, `full_adder.v`) | **DO** -- Trivial deletion. NF2 auto-includes all .v files, so dead code in src/ could cause naming conflicts or confuse synthesis. |
| **L2** | refinements.md | Comment typos in `lab8_reg_defines.vh` | **DO** -- Trivial, no risk. |
| **L3** | refinements.md | P4 stale in improvements doc | **DO** -- Mark P4 and P7 as DONE. |
| **L4** | refinements.md | Logic analyzer wrap indicator | **SKIP** -- Debug aid, not needed for demo or grading. |
| **P1** | improvements.md | Dual-port GPU bandwidth | **SKIP** -- Major change (FIFO Port A mux, wider DMA, GPU changes). High risk, unlikely needed for Lab 8 grading. Only if Lab 9 demands it. |
| **P2** | improvements.md | BRAM register file + DCM 2x clock | **SKIP** -- Major architectural change. Resource savings not needed (design fits VP50). |
| **P3** | improvements.md | Behavioral -> structural conversion | **SKIP** -- Inference works. Structural instantiation is harder to maintain and debug. Only if timing closure demands it. |
| **P5** | improvements.md | Application-specific simplification | **SKIP** -- Requires knowing the target app. Premature. |
| **P6** | improvements.md | Shared FIFO BRAM as unified scratchpad | **SKIP** -- High complexity, requires GPU RTL changes. |
| **P8** | improvements.md | GPU decode pipeline split | **ADDRESSED** by the branch-to-EX1 move (15.5ns -> 11ns). Still over 8ns budget, but much closer. Full decode split is high risk. |
| **P9** | improvements.md | Mode-switch safety guard | **NICE-TO-HAVE** -- ~5 lines, prevents silent corruption. Low risk. Worth doing if you have time. |

---

## Recommended Execution Order

### Phase 1: Commit & Synthesize Current Changes (CHECKPOINT 1)

Everything already applied in the working tree. This is the biggest value -- bug fixes + GPU timing improvement.

**What's in it:**
- C1: Conditional execution fix (ARM correctness)
- C2: 1-word packet fix (FIFO robustness)
- H1/P7: PC halt gating (all_halted now works, no more B. padding needed)
- H2: was_ext reset (FPGA power-up safety)
- M2: case default (latch prevention)
- GPU: BF16 unsigned rewrite, HALT gating, branch-to-EX1 (critical path 15.5ns -> 11ns)
- GPU: Dead wire cleanup, comment fixes

**Action:** Commit, copy to NetFPGA, synthesize, run all 6 HW tests + real packet tests.

**What to watch for:**
- `all_halted` should now assert (H1 fix) -- `cpu_test` timeout should go away
- GPU timing violations should drop significantly (branch-to-EX1)
- B. padding in IMEM hex files can be removed (but leaving it is harmless)
- BF16 kernel results on hardware must match Lab7 standalone (unsigned rewrite)

---

### Phase 2: Trivial Cleanup (safe, no functional change)

Only after Phase 1 HW passes.

| Item | Change | Risk |
|------|--------|------|
| L1 | Delete `src/arm/adder8_comb.v` and `src/arm/full_adder.v` | None -- never instantiated |
| L2 | Fix `[31:0]` -> `[63:32]` comments in `lab8_reg_defines.vh` | None |
| L3 | Mark P4 and P7 as DONE in `improvements_and_optimizations.md` | None |

No synthesis needed for these alone -- bundle with Phase 3 if you do one.

---

### Phase 3: Low-Risk Hardening (optional, CHECKPOINT 2)

Only if you want extra robustness before Lab 9 or final demo.

| Item | Change | Lines | Risk |
|------|--------|-------|------|
| P9 | Mode-switch safety guard in `lab8_wrapper.v` | ~5 | Low -- prevents silent corruption from software bugs |
| H5 | DMA address bounds check (saturate or status bit) | ~10 | Low -- defensive |

**Action:** If applied, synthesize + run HW tests again.

---

### Phase 4: Skip / Defer

Everything else (H3, H4, M1, M3, M4, L4, P1-P3, P5, P6, P8) -- skip for Lab 8.
These are either:
- Not reproduced / no program exercises them
- Major architectural changes with high risk and no demonstrated need
- Already partially addressed (P8 by branch-to-EX1)

Revisit M1 (missing ARM opcodes) only if Lab 9 programs need ADC/SBC/RSB.

---

**Bottom line:** Phase 1 is the priority -- it's already coded and sim-verified.
One synthesis + HW test confirms everything. Phase 2 is free cleanup. Phase 3 is
optional polish. Everything else is deferred.
