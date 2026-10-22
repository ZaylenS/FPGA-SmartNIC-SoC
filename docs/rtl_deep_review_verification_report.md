# RTL Deep Review and Verification Report

Date: 2026-06-25

## Scope

This review covered the current synthesizable RTL in `src/` plus the associated headers in `include/`. I did not modify any file in `src/`. The only code additions made during this review are new simulation testbenches in `tb/`.

Simulation was run with Icarus Verilog using Verilog-2001 mode. Existing testbenches were elaborated with explicit top modules so that unrelated, uninstantiated NetFPGA reference modules would not block tests. A direct all-source elaboration of `src/user_data_path.v` is not possible in this checkpoint without the external NetFPGA reference modules `input_arbiter`, `output_port_lookup`, `output_queues`, and `udp_reg_master`.

## Files Added

- `tb/tb_codex_arm_units.v`
- `tb/tb_codex_fifo_edge_cases.v`
- `tb/tb_codex_gpu_units.v`
- `tb/tb_codex_memory_units.v`
- `tb/tb_codex_user_data_path_smoke.v`
- `docs/rtl_deep_review_verification_report.md`

## Overall Result

Most of the core checked paths still simulate cleanly: the existing FIFO, CPU/FIFO, GPU integration, Lab 8 wrapper, cycle counter, stress refinements, and IDS BCAST benches pass under Icarus. The new GPU unit, memory unit, and `user_data_path` stub smoke benches also pass.

The review found three actionable RTL issues, one coding-rule violation, and several stale or incomplete verification assets:

1. `src/arm/data_mem.v` does not hold several outputs in reset.
2. `src/fifo/convertible_fifo.v` truncates the 16-bit NF2 packet `word_length` field to 8 bits, making a 256-word packet look like length zero.
3. `src/gpu/gpu_params.vh` is stale relative to `include/gpu_params.vh` and breaks builds if the include search path finds the stale header first.
4. `src/arm/processor.v` has a `case` statement without `default`, violating the project coding rule.
5. Several existing testbenches depend on missing `.hex` files or encode expectations that no longer match current RTL.

## Findings

### F1: Stale Duplicate GPU Header

Severity: High for build reliability

Files:

- `include/gpu_params.vh`
- `src/gpu/gpu_params.vh`
- `src/gpu/instruction_decoder.v`
- `src/gpu/simd_alu.v`
- `src/gpu/int16_alu.v`
- `src/gpu/bf16_alu.v`

`include/gpu_params.vh` contains the current BCAST definitions:

- `OP_BCAST`
- `ALU_BCAST`

The duplicate header at `src/gpu/gpu_params.vh` is stale and does not define those macros. Normal repository test commands that pass `-I include` first work, but a build that searches `src/gpu` before `include` fails during preprocessing and parse.

Reproduced failure pattern:

- `OP_BCAST` undefined in `src/gpu/instruction_decoder.v`
- `ALU_BCAST` undefined in `src/gpu/simd_alu.v`
- downstream syntax errors in `src/gpu/int16_alu.v` and `src/gpu/bf16_alu.v`

Recommendation: remove the duplicate header from active include paths, or update it to match `include/gpu_params.vh`. Prefer a single source of truth if possible.

### F2: ARM Data Memory Reset Contract Is Incomplete

Severity: High for reset correctness

File: `src/arm/data_mem.v`

The project rule says every flip-flop needs an explicit reset. `data_mem.v` resets `was_ext`, but several observable outputs are still driven without reset protection:

- `ext_mem_we` is combinationally assigned from `WMemEn & addr_is_ext`; it can assert while reset is active.
- `skip_mem` is assigned inside the clocked block without a reset branch.
- MEM/WB pass-through controls and values are assigned inside the clocked block without reset values.
- Data outputs such as `dmem_rd` and `doutb` are not reset.

New testbench evidence:

- `tb/tb_codex_arm_units.v` result: `17 PASS, 3 FAIL`
- The failing checks are reset-specific:
  - `data_mem ext write is suppressed during reset`
  - `data_mem skip_mem reset value`
  - `data_mem MEM/WB controls reset`

Recommendation: add explicit reset behavior for all registered outputs and gate external write strobes while reset is active.

### F3: FIFO Packet Length Truncates 16-bit NF2 Word Length to 8 Bits

Severity: Medium to high, depending on intended maximum packet size

File: `src/fifo/convertible_fifo.v`

The NF2 header format carries a 16-bit `word_length` field. The FIFO stores only 8 bits:

- `pkt_len` is 8 bits.
- `pkt_word_cnt` is 8 bits.
- Header parsing uses `in_data[39:32]`, which is only the low byte of the 16-bit header length field.

New testbench evidence:

- `tb/tb_codex_fifo_edge_cases.v` result: `5 PASS, 2 FAIL`
- Backpressure and normal drain checks pass.
- A header with `word_length = 16'h0100` completes after the header only and reports length zero.

This means a full-depth 256-word packet is unrepresentable through the current 8-bit length/status path. Any packet with length greater than 255 will also be truncated.

Recommendation: either document and enforce an explicit 1-to-255 word packet limit, or widen the internal packet length/count path and related status interfaces enough to represent 256 words.

### F4: Missing `default` in ARM Processor `case`

Severity: Medium coding-rule violation

File: `src/arm/processor.v`

The CPSR update logic contains a `case (mem_thread_id)` without a `default`. The selector is a 2-bit value and the listed cases are logically exhaustive, but this still violates the project rule that every `case` must have `default`.

Recommendation: add a safe `default` branch that leaves state unchanged or assigns an explicit known value consistent with the intended behavior.

### F5: `user_data_path` Requires External NetFPGA Reference Modules

Severity: Medium verification gap

File: `src/user_data_path.v`

This top-level wrapper instantiates NetFPGA reference modules that are not present in this checkpoint:

- `input_arbiter`
- `output_port_lookup`
- `output_queues`
- `udp_reg_master`

Direct local elaboration fails without the original NetFPGA source tree. I added `tb/tb_codex_user_data_path_smoke.v`, which supplies local behavioral stubs only to verify that the authored wrapper can elaborate, connect the register path, and pass a minimal data-path smoke check.

Result:

- `tb/tb_codex_user_data_path_smoke.v`: `3 PASS, 0 FAIL`

Recommendation: run full `user_data_path` verification in an environment with the original NetFPGA reference modules available. The smoke test is not a replacement for that integration test.

### F6: ARM Register Alias Test Does Not Match Current Wrapper RTL

Severity: Medium, likely stale test or stale documentation

Files:

- `tb/tb_arm_reg_access.v`
- `src/lab8_wrapper.v`
- `docs/arm_orchestrator.md`

The existing `tb_arm_reg_access.v` expects ARM external-memory writes to update wrapper control registers through aliases such as DMA, GPU, FIFO, and CPU control addresses. Current `src/lab8_wrapper.v` updates those software registers through the PCI register request path, while ARM external-memory access is routed to the FIFO BRAM processor port.

Observed result:

- `tb/tb_arm_reg_access.v`: FAIL
- GPU/DMA/FIFO control aliases are not updated as expected.
- DMEM alias readbacks become unknown in the test.

This matches the earlier note in `docs/arm_orchestrator.md` that ARM register writes are blocked because the register write path is gated by the PCI path, even though later historical sections of the same document describe a passing alias-window test.

Recommendation: decide whether the ARM alias register path is intended current behavior. If yes, the RTL needs a new write path. If no, update or remove the stale test expectations and documentation.

### F7: Existing Test Assets Are Missing or Weakly Checked

Severity: Medium verification hygiene

Missing input assets:

- `programs/arm/ids_orchestrator.hex`
- `programs/gpu/bcast_test.hex`
- `programs/gpu/data_bcast_test.hex`
- `programs/gpu/data_ids_11_16_8_2.hex`
- `programs/gpu/expected_ids.hex`

Impacted tests:

- `tb_arm_ids_orchestrator.v` fails because the ARM program hex file is missing.
- `tb_bcast.v` fails because BCAST program/data hex files are missing.
- `tb_ids_inference.v` fails because IDS data hex is missing.
- `tb_ids_generic.v` emits runtime file-open errors but still reports all PASS because the expected memory defaults to zero.
- `tb_ids_bcast_trained.v` is a smoke/print test with no self-checking assertions.

Recommendation: regenerate or restore the missing assets, then tighten the affected benches so file-open failures are fatal and every output test compares against known expected values.

## Existing Testbench Results

| Testbench | Result | Notes |
| --- | --- | --- |
| `tb/tb_convertible_fifo.v` | PASS | Existing FIFO functional test passed. |
| `tb/tb_cpu_fifo.v` | PASS | Existing CPU/FIFO integration test passed. |
| `tb/tb_cycle_counter.v` | PASS | `7 PASS, 0 FAIL`. |
| `tb/tb_gpu_integration.v` | PASS | Existing GPU integration test passed. |
| `tb/tb_ids_bcast.v` | PASS | `26 PASS, 0 FAIL`. |
| `tb/tb_lab8_wrapper.v` | PASS | Existing wrapper test passed. |
| `tb/tb_stress_refinements.v` | PASS/SMOKE | Stress summary reports six tests passed and no reproduced bugs. |
| `tb/tb_ids_bcast_trained.v` | SMOKE | Runs and prints logits, but has no self-checking pass/fail criteria. |
| `tb/tb_arm_ids_orchestrator.v` | FAIL | Missing `programs/arm/ids_orchestrator.hex`; captures zero egress words. |
| `tb/tb_arm_reg_access.v` | FAIL | Test expectation does not match current register write path. |
| `tb/tb_bcast.v` | FAIL | Missing BCAST program/data hex files. |
| `tb/tb_ids_generic.v` | ASSET ERROR | Missing IDS data/expected hex files, but the bench still reports PASS. |
| `tb/tb_ids_inference.v` | FAIL | Missing IDS data hex; output comparisons fail. |

## New Testbench Results

| Testbench | Result | Coverage |
| --- | --- | --- |
| `tb/tb_codex_gpu_units.v` | PASS, `35 PASS, 0 FAIL` | Program counter, fetch, pipeline register, decoder, register file, hazard unit, writeback, SIMD ALU BCAST/BF16, BF16 FMA. |
| `tb/tb_codex_memory_units.v` | PASS, `8 PASS, 0 FAIL` | FIFO BRAM, GPU instruction memory, GPU data memory, ARM instruction memory, logic analyzer. |
| `tb/tb_codex_user_data_path_smoke.v` | PASS, `3 PASS, 0 FAIL` | Stubbed top-level elaboration and minimal register/data-path smoke coverage. |
| `tb/tb_codex_arm_units.v` | FAIL, `17 PASS, 3 FAIL` | ARM ALU/ID/EX pass; `data_mem` reset checks fail. |
| `tb/tb_codex_fifo_edge_cases.v` | FAIL, `5 PASS, 2 FAIL` | Drain backpressure passes; 256-word packet length truncation fails. |

## Subsystem Review Notes

### FIFO

Reviewed:

- `src/fifo/fifo_bram.v`
- `src/fifo/convertible_fifo.v`

Existing FIFO tests pass for normal packet capture and drain behavior. The new edge-case bench adds output backpressure coverage and confirms that drain holds data stable while `out_rdy` is low. The same bench exposes the 8-bit packet length truncation issue.

### Lab 8 Wrapper, DMA, and Register Path

Reviewed:

- `src/lab8_wrapper.v`
- `include/lab8_reg_defines.vh`

Existing wrapper and GPU integration tests pass. The DMA and mode muxing paths are covered by existing benches, but the ARM-to-wrapper register alias expectation in `tb_arm_reg_access.v` does not match the current RTL. DMA length is also effectively 8-bit through `dma_len`, so it should be reviewed together with the FIFO length contract if 256-word transfers are expected.

### ARM CPU

Reviewed:

- `src/arm/addsub64.v`
- `src/arm/alu64.v`
- `src/arm/barrel_shifter.v`
- `src/arm/condition_check.v`
- `src/arm/data_mem.v`
- `src/arm/EX_stage.v`
- `src/arm/ID.v`
- `src/arm/inst_mem.v`
- `src/arm/instruction_follower.v`
- `src/arm/logic_analyzer.v`
- `src/arm/processor.v`
- `src/arm/register_file.v`
- `src/arm/rotator.v`
- `src/arm/sign_extender.v`
- `src/arm/SignExtender.v`

The new ARM unit bench covers representative ALU, decode, execute, and data-memory behavior. Arithmetic and decode checks pass. Reset behavior in `data_mem.v` fails, and `processor.v` contains a project-rule `case` default violation.

### GPU

Reviewed:

- `src/gpu/bf16_alu.v`
- `src/gpu/bf16_fma_unit.v`
- `src/gpu/core_top.v`
- `src/gpu/data_memory.v`
- `src/gpu/decode_stage.v`
- `src/gpu/execute_stage.v`
- `src/gpu/fetch_stage.v`
- `src/gpu/gpu_params.vh`
- `src/gpu/gpu_top.v`
- `src/gpu/hazard_unit.v`
- `src/gpu/instruction_decoder.v`
- `src/gpu/instruction_memory.v`
- `src/gpu/int16_alu.v`
- `src/gpu/pipeline_reg_ex.v`
- `src/gpu/pipeline_reg_exwb.v`
- `src/gpu/pipeline_reg_idex.v`
- `src/gpu/program_counter.v`
- `src/gpu/register_file.v`
- `src/gpu/simd_alu.v`
- `src/gpu/writeback_stage.v`
- `include/gpu_params.vh`

Existing GPU integration and IDS BCAST tests pass. The new unit bench adds direct checks for decode, BCAST ALU behavior, BF16 arithmetic, FMA, hazard behavior, pipeline register flushing, and writeback. The main GPU RTL concern found is not functional behavior under the normal include path, but the stale duplicate `src/gpu/gpu_params.vh`.

### `user_data_path`

Reviewed:

- `src/user_data_path.v`

The wrapper structure and local connection logic were reviewed, and a smoke elaboration bench with stubs was added. Full verification requires the external NetFPGA reference modules.

## Recommended Next Steps

1. Fix or remove the stale `src/gpu/gpu_params.vh` duplicate.
2. Add explicit reset behavior and reset gating in `src/arm/data_mem.v`.
3. Decide whether packets/transfers are intentionally limited to 255 words. If not, widen FIFO and DMA length paths.
4. Add a `default` branch in the CPSR update `case` in `src/arm/processor.v`.
5. Restore or regenerate the missing program/data hex files used by the existing benches.
6. Make file-open failures fatal in IDS/BCAST benches and add assertions to smoke-only tests.
7. Reconcile the ARM register alias documentation/test expectation with the current `lab8_wrapper.v` register write path.
8. Run full `user_data_path` integration in the original NetFPGA source environment or import the needed reference modules into this checkpoint.

## Review Boundary

This review is local simulation and source inspection only. It does not claim ISE 10.1 synthesis closure, Vivado/XSim equivalence, timing closure, or hardware behavior on NetFPGA. No current RTL file in `src/` was changed.
