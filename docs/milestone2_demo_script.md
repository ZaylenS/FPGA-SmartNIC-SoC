# Project Milestone 2 Demo Video Script

**Extends: [Milestone 1 Demo Script](milestone1_demo_script.md)**

**Duration: ~5-6 minutes. Audio recorded separately with OBS. Live-typed notes in a side document complement the narration.**

---

## Pre-Recording Setup

1. FPGA programmed on nf6 with the new bitfile: `nf_download nf2_top_par.bit`
2. Files deployed to nf6 (`~/zil_testing_folder/`):
   - `lab10reg.py` (with fixed `ids_load` CLI + `ids_compare_perf` command)
   - `lab9reg.py` (with `gpu_read_cycle_count` + `GPU_CYCLE_COUNT_REG`)
   - `ann_ids_11_16_8_2.hex`, `data_ids_11_16_8_2.hex`
   - `ann_ids_11_16_8_2_bcast.hex`, `data_ids_11_16_8_2_bcast.hex`
   - `nf2_top_par.bit`
3. **Keep the earlier DEADBEEF terminal tab open and scrolled to the failed `ids_compare_perf` output** -- this is the "before" shot
4. Two windows: left = nf6 (live demo), right = dev machine (RTL + synth inspection)
5. GPU in reset (`GPU_CTRL = 0x1`) at recording start -- a fresh `nf_download` gets you there

---

## Video Actions

### Part 1: BCAST RTL -- Decoder and Lane Mux (~50 sec)

On dev machine, show the opcode and ALU op defines:
```powershell
Select-String -Path include/gpu_params.vh -Pattern "OP_BCAST|ALU_BCAST" -Context 0,0
```
Point at `gpu_params.vh:72` (`OP_BCAST 5'b11010`) and line 93 (`ALU_BCAST 4'd6`).

Show the decoder entry:
```powershell
Get-Content src/gpu/instruction_decoder.v | Select-Object -Index (125..131)
```
(`instruction_decoder.v:126-131` -- lane select plucked from `instruction[1:0]` into `imm_ext`.)

Then the actual cross-lane replication -- the heart of BCAST:
```powershell
Get-Content src/gpu/simd_alu.v | Select-Object -Index (20..35)
```
(`simd_alu.v:21-35` -- 4:1 lane mux on `operand_a`, then `effective_a = {bcast_value, bcast_value, bcast_value, bcast_value}` when `alu_op == ALU_BCAST`.)

### Part 2: Hardware Cycle Counter (~20 sec)

On dev machine, show the counter register and always block:
```powershell
Get-Content src/lab8_wrapper.v | Select-Object -Index (396..411)
```
(`lab8_wrapper.v:397-411` -- 32-bit counter, armed on reset, freezes on `gpu_kernel_done`.)

Show the PCI register define:
```powershell
Select-String -Path include/lab8_reg_defines.vh -Pattern "LAB8_GPU_CYCLE_COUNT"
```

### Part 3: The DEADBEEF Episode (~30 sec)

On nf6, **scroll up in the preserved terminal tab** to show the earlier `ids_compare_perf` output with `GPU cycles : 3735928559`. Highlight that number.

On dev machine:
```powershell
python -c "print(hex(3735928559))"
```
Output: `0xdeadbeef` -- the sentinel from the readback mux default.

### Part 4: Root Cause and Fix (~50 sec)

On dev machine, the refactored readback mux lives in two dedicated always blocks. Show the combinational half:
```powershell
Get-Content src/lab8_wrapper.v | Select-Object -Index (423..478)
```
(`lab8_wrapper.v:424` declares `reg_rd_data_mux`, lines 431-478 are the new `always @*` case.)

Show the sequential half:
```powershell
Get-Content src/lab8_wrapper.v | Select-Object -Index (480..493)
```
(`lab8_wrapper.v:484-494` -- clean `always @(posedge clk)` that picks between `reg_rd_data_mux` and `reg_data_in`. No more nested-inside-a-bigger-block.)

### Part 5: Re-Synth Delta (~20 sec)

On dev machine:
```powershell
Select-String -Path synth/nf2_top.srp -Pattern "Number of Slices|4 input LUTs|inferred .* Multiplexer" | Select-Object -Last 6
```
Slices 21438 → 21068 (-370), LUTs 29527 → 29421, muxes in `lab8_wrapper` 96 → 64. Timing endpoints 7553 → ~4400.

### Part 6: Readback Sanity Check (~15 sec)

On nf6:
```bash
python -c "from lab9reg import *; print('CTRL=', hex(regread(GPU_CTRL_REG)), 'STATUS=', hex(regread(GPU_STATUS_REG)), 'DMA_CTRL=', hex(regread(DMA_CTRL_REG)), 'CYCLE=', hex(regread(GPU_CYCLE_COUNT_REG)))"
```
Expected: `CTRL= 0x1 STATUS= 0x0 DMA_CTRL= 0x0 CYCLE= 0x0` -- no more `0xdeadbeef`.

### Part 7: Performance Comparison (~50 sec)

On nf6:
```bash
python lab10reg.py ids_compare_perf
```
Point at: Scalar 1254 cycles, BCAST 732 cycles, 1.71x hardware speedup.

### Part 8: BCAST 5x Run -- Timing Non-Determinism (~60 sec)

On nf6:
```bash
for i in 1 2 3 4 5; do
  echo "=== Run $i ==="
  python lab9reg.py reset > /dev/null
  python lab10reg.py ids_load ann_ids_11_16_8_2_bcast.hex data_ids_11_16_8_2_bcast.hex > /dev/null
  python lab9reg.py gpu_start > /dev/null
  python -c "from lab9reg import *; print('cycles=', gpu_read_cycle_count())"
  python lab9reg.py gpu_read_dmem 126 1
done
```

Expected: a mix of correct runs (`cycles= 732`, `DMEM[126]: 0x41b041b0_41b041b0`) and glitched runs (cycles 14/28/42 short, output 1.0/2.0/3.0 BF16 low -- e.g. `704 / 0x41a0` = 20.0, `690 / 0x4198` = 19.0). The correlation is diagnostic: every dropped loop iteration costs exactly 14 cycles and 1.0 in the final BF16 output. The correct runs prove the kernel works; the glitched runs show we are at the timing edge on the branch-evaluation path.

### Part 9: Decode the Output (~15 sec)

On nf6:
```bash
python -c "
import struct
bf16 = 0x41b0
raw = struct.pack('>I', bf16 << 16)
print('BF16 0x%04x = %.4f' % (bf16, struct.unpack('>f', raw)[0]))
"
```
Output: `BF16 0x41b0 = 22.0000`.

---

## Audio Transcript

This is milestone 2. We took the milestone 1 IDS inference pipeline and added a hardware-level performance optimization, plus the instrumentation to measure it. Along the way we encoutered a synthesis bug and had to fix it.

The optimization is a new SIMD instruction called BCAST. Our GPU is 4-lane BFloat16 but the ISA has no cross-lane operations, so inter-layer data flow in a neural network forces us into scalar mode with all four lanes replicated -- cause only 25 percent utilization. BCAST replicates one selected lane of a source register to all four lanes of the destination, which lets us run four neurons in parallel with packed weights. The actual work is a 4-to-1 lane mux in the SIMD ALU stage, about 30 LUTs, combinational in EX1, using the existing stall-based hazard logic.

To measure speedup from the host, I added a 32-bit cycle counter in `lab8_wrapper.v` that counts core clock cycles from GPU reset release until `kernel_done`, and exposed it as a new PCI register at offset 0x30. Simulation passed all checks -- 732 cycles for BCAST, 2402 for scalar. I re-synthesized and deployed to the FPGA.

Here's what the first hardware run looked like. GPU cycles: three billion seven hundred thirty five million, five hundred fifty nine. That's 0xDEADBEEF in hex -- the default from the readback mux. Not just the counter: every LAB8 register read returned 0xDEADBEEF. The entire readback path was broken. After grepping the RTL and the timing report, the root cause was that `reg_rd_data` -- the register holding the readback value -- had been completely dead-code-eliminated by the synthesis tool. Adding one case entry for the cycle counter pushed the nested case statement past an XST heuristic and the whole readback mux got trimmed.

The fix was structural. I pulled the readback out of the big clocked always block and into two dedicated blocks: a combinational `always @*` that drives `reg_rd_data_mux` from the case, and a separate sequential flop that picks between that mux and the ring pass-through. The re-synth confirmed the fix: slices went *down* by 370, mux count in the wrapper dropped from 96 to 64, and timing violations dropped from 7553 to about 4400.

Now the live hardware test. Sanity check reads return real values, not DEADBEEF. The performance comparison: scalar 1254 cycles, BCAST 732 cycles. One caveat -- the scalar hardware number disagrees with sim's 2402. The scalar kernel's tight 2-neuron interleaved FMA loop is hitting BF16 ALU timing violations that BCAST happens to dodge. So the honest claim is: **BCAST is hardware-verified at 732 cycles matching sim, scalar is sim-authoritative at 2402 cycles, and the real speedup is 3.28x**.

To close, here is a five-run loop of the BCAST kernel. The correct runs show 732 cycles and DMEM[126] reads `0x41b041b0`, which decodes to BFloat16 22.0 on all four lanes -- that is the analytic output for our test data, 8 times 0.25 times 11. But not every run is correct. Some runs drop by exactly 14 cycles and exactly 1.0 in the output per dropped loop iteration. The BCAST inner loop is 14 cycles, so what you are watching is one iteration being terminated a cycle early by a timing-violated branch signal. The correct runs prove the kernel computes the right answer; the glitched runs prove we are at the edge of timing closure on this bitfile. It is the same class of issue that hits the scalar kernel on every run -- BCAST mostly dodges it, scalar never does. A clean fix would require another synthesis pass to close timing on the branch-evaluation path, which is future work.

Milestone 2 deliverables: one new ISA instruction designed, implemented, and correct under sim and the majority of hardware runs; a 3x DMEM reduction via packed layout; a hardware cycle counter exposed over PCI; a major readback regression found and fixed through RTL restructuring; a 3.28x sim-authoritative speedup on the IDS inference kernel, with hardware showing the same 732-cycle BCAST number whenever the branch path meets timing. Plus one good DEADBEEF story and a very clean diagnostic on the remaining timing issue.
