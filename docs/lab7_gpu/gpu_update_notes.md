# GPU Core Update Log

Refinements to `src/gpu/` since the original Lab 7 standalone GPU was integrated. Each section is dated and lists which RTL files were touched. This file is the canonical short-form changelog for the GPU; for the walkthrough-level descriptions of what each change does, see the per-batch walkthroughs (and `timing_fix_refine_lab8.md` for synthesis details).

---

## 2026-03-19 — Lab 8 integration refinements

GPU source files in `src/gpu/` updated from `Lab7_synth` with the following refinements.

1. **BF16 ALU unsigned rewrite (F-02)**: All `wire signed` removed from `bf16_alu.v`. MUL/ADD exponent arithmetic rewritten as purely unsigned to avoid ISE 10.1 synthesis bug.
2. **HALT gating (F-03)**: PC, IMEM read enable, and DMEM write enable gated by `halted` signal in `core_top.v`. Prevents post-HALT instruction execution and spurious DMEM writes.
3. **Port B write protection (F-04)**: In Lab7's `gpu_nf2_wrapper.v` only (not used in Lab8). Lab8's `lab8_wrapper.v` handles Port B access via its own mux logic.
4. **Branch moved to EX1**: 64-bit signed branch comparison moved from decode stage to EX1 in `core_top.v`. Branch penalty increased from 1 to 2 cycles. `decode_stage.v` now outputs `branch_type` instead of `branch_taken`/`branch_target`. `pipeline_reg_idex.v` gained `branch_type` and `pc` passthrough ports, lost `rs1_addr`/`rs2_addr` ports. `hazard_unit.v` no longer has `branch_taken`/`flush` ports. `program_counter.v` priority changed: branch overrides stall. Critical path reduced from 15.5 ns to 11 ns.
5. **Dead wire cleanup (F-06/F-10)**: Unused `rs1_addr`/`rs2_addr` removed from `pipeline_reg_idex.v` and `core_top.v`.
6. **Stale comments fixed (F-18/F-19)**: `pipeline_reg_exwb.v` header corrected to "EX3/WB". `gpu_top.v` comment corrected to "6-stage pipeline".

### Lab 8 integration interface
**Unchanged** — all `gpu_top.v` ports remain valid for `lab8_wrapper.v`:
- `clk`, `rst`, `thread_id`, `block_id`, `block_dim`, `kernel_done`
- IMEM Port B: `ext_imem_addr[9:0]`, `ext_imem_wr_en`, `ext_imem_wr_data[31:0]`, `ext_imem_rd_data[31:0]`
- DMEM Port B: `ext_dmem_addr[9:0]`, `ext_dmem_wr_en`, `ext_dmem_wr_data[63:0]`, `ext_dmem_rd_data[63:0]`

### Verification
All 5 kernel tests + 2 ANN inference tests passed on NetFPGA hardware (nf5.usc.edu, 2026-03-19) using the Lab7 standalone configuration. Lab 8 integration re-synthesis and hardware test followed.

---

## 2026-04-13 — BCAST cross-lane instruction + simd_alu pipeline restructure

Commit `e14d012` — added a cross-lane shuffle instruction to enable multi-layer ANN inference inside a single GPU kernel, and restructured the SIMD ALU pipeline for timing closure on the larger IDS kernel.

**Files touched:**
- `include/gpu_params.vh` — added `OP_BCAST = 5'b11010` (0x1A) and `ALU_BCAST = 4'd6`.
- `src/gpu/instruction_decoder.v` — new BCAST case (`alu_op=ALU_BCAST`, `reg_write=1`, `use_imm=1`, `imm_ext = {62'd0, instruction[1:0]}` — lane selector pulled from func field).
- `src/gpu/int16_alu.v` — added `ALU_BCAST: result = a;` (aliases MOV).
- `src/gpu/bf16_alu.v` — added `ALU_BCAST: result = s1_mov_result;` (aliases MOV at the output mux).
- `src/gpu/simd_alu.v` — **major rewrite** (see below).
- `src/gpu/execute_stage.v` — dropped the `simd_result_r` flop (no longer needed because simd_alu now lands its result in EX3 directly).

**Why BCAST.** Before BCAST, multi-layer ANN inference forced a kernel-per-element loop because there was no way to reduce a per-lane FMA accumulator into a single scalar that the next layer could broadcast back across all 4 lanes. With BCAST, a layer can do its FMA in vector form, write the scalar accumulator to a register, then `BCAST Rd, Rs1, #lane` to replicate one element of Rs1 across all 4 of Rd's lanes — ready for the next layer's FMA.

**simd_alu rewrite — what changed.** The original simd_alu was 2-cycle internal latency: 4 combinational int16_alu instances + 4 bf16_alu (2-cycle) instances + one alignment register for the int16 path. The rewrite:

1. **Added a BCAST cross-lane mux** (combinational, before any per-lane logic). 4:1 mux selects one lane of `operand_a` by `operand_b[1:0]`, replicated to fill `effective_a` if `alu_op == ALU_BCAST`; otherwise `effective_a = operand_a`.
2. **Added an input pipeline register** (`alu_op_r`, `dtype_r1`, `effective_a_r`, `operand_b_r`) between the BCAST mux and the per-lane ALUs. This was the timing fix — see below.
3. **Reduced int16_alu from 4 lanes to 1.** Lane 0's result is replicated to all 4 output positions (`int_result = {4{int_lane0_r}}`). Saves 3 MULT18X18 + ~250 LUTs. Safe because IDS/ANN kernels only ever consume lane 0 of an INT16 result.
4. **Added a second alignment register** (`int_lane0_r`, `dtype_r2`) so the int16 path's 1-cycle combinational output matches bf16's 2-cycle internal output at the EX3 result mux.

Net internal latency: 2 → 3 cycles. But `execute_stage.v`'s external `simd_result_r` register was dropped at the same time, so the **end-to-end SIMD latency from EX1 inputs to EX3 result mux is unchanged at 3 cycles**.

**Timing motivation.** On the 2026-04-17 timing report (after the IDS kernel work integrated), the worst-case path was:
```
use_imm mux (EX1) -> op_b mux -> bcast_value mux -> effective_a ->
bf16.a_gt_b_mag -> exp_diff -> shift -> add_raw -> FF (EX2)
```
= 15.26 ns vs the 8 ns budget. Putting a register between the BCAST mux output and the bf16 chain splits it into ~6 ns (input → input reg) + ~7 ns (input reg → bf16 s1_* FF), both within budget.

**Verification.** Updated testbenches (`tb_ids_inference`, `tb_ids_bcast`) cover both scalar and packed kernels. Hardware-verified on team-6 NetFPGA bitfile 2026-04-18: 5/5 BCAST runs at 732 cycles (3.28× speedup vs 2402-cycle scalar), 75% accuracy on 20-sample batch matches simulation.

---

## 2026-04-13 — GPU cycle counter PCI register (wrapper-side)

Commit `b4648bd`. Outside `src/gpu/` proper (lives in `src/lab8_wrapper.v`), but listed here for completeness.

- New PCI register `LAB8_GPU_CYCLE_COUNT = 6'h30` exposes a 32-bit counter that counts `core_clk` cycles from `gpu_reset` deassertion until `gpu_kernel_done` first asserts.
- Matches the cycle count reported by `tb_ids_inference`/`tb_ids_bcast`, so scalar-vs-BCAST speedup can be read directly from the host via PCI without instrumenting the kernel.
- Same commit also refactored the wrapper's readback mux into a dedicated `always @*` block. The mux had been getting XST-trimmed when it lived inside the clocked write-path always block; the symptom was every PCI read returning `0xDEADBEEF`. See `docs/lab8_integration/walkthrough_batch2_wrapper.md` and `docs/lab8_integration/walkthrough_batch5_synthesis_hw.md`.

---

## 2026-05-10 — ARM register-alias window (no GPU-core changes)

Commit `942decf`. No files inside `src/gpu/` changed. For completeness:

- `src/arm/processor.v` and `src/arm/data_mem.v` gained a `reg_alias_*` port that lets the ARM CPU read/write the wrapper's control registers from inside a thread program (DMEM addresses `0xF0..0xFF`).
- `src/lab8_wrapper.v` exposes that bus via a 16-slot mux (slot map in `docs/lab8_integration/walkthrough_batch2_wrapper.md`).
- Enables the Milestone 4 ARM orchestrator: one ARM thread sequences GPU+DMA without host involvement.

This is purely an integration-side change. GPU IMEM/DMEM, kernel programs, and the FMA/SIMD pipeline are all unaffected.

---

## Document refresh log

- 2026-03-19 — file created, captured Lab 7 → Lab 8 refinements.
- 2026-05-17 — extended to cover the 2026-04-13 BCAST + cycle-counter refactor and the 2026-05-10 ARM orchestrator.
