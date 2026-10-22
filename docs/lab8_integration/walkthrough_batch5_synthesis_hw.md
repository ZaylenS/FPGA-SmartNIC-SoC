# Batch 5 -- Synthesis & Hardware Fixes Walkthrough

> **Updated 2026-07-14:** Stale walkthrough content was reconciled with the current RTL implementation by Codex (GPT-5).

**Files covered:** `lab8_wrapper.v` (Bug #4 fix, registered PCI write strobes; Bug #6 fix, readback mux trim) -> `convertible_fifo.v` (Bug #2 RTL fix) -> synthesis results -> hardware test sequence

This batch records Xilinx ISE 10.1 synthesis and NetFPGA V2 (Virtex-II Pro XC2VP50) bring-up fixes. The listed bitfiles passed substantial hardware tests at a requested 125 MHz clock, but static timing was not closed; those tests are empirical coverage, not proof that every path is safe at 125 MHz.

> **Document history.**
> - **2026-03-07** -- original synthesis & bring-up (Bugs #2, #4).
> - **2026-03-20** -- Phase 1 re-synthesis adding GPU branch-to-EX1, HALT gating, BF16 unsigned rewrite (Bug #5 -- §6).
> - **Updated 2026-05-17** with two later synthesis events:
>     - **§7 (new):** 2026-04-13 *Bug #6 -- PCI read returns 0xDEADBEEF*. The readback mux had been folded into a clocked always block; XST trimmed `reg_rd_data` because it judged it conditional. Fix: split the mux into its own combinational always block. See `walkthrough_batch2_wrapper.md §2.8` for the resulting structure.
>     - **§8 (new):** 2026-04-13 *BCAST integration synth*. Adding the cross-lane mux to `simd_alu.v` created a reported 15.26 ns path in later notes.
> - **Reconciled 2026-07-14:** §8 now reflects the current checkpoint RTL. `src/gpu/simd_alu.v` has the BCAST input pipeline register and scalarized lane-0 INT16 refactor, and `execute_stage.v` no longer adds a separate SIMD result register.
>
> Sections §1-§6 preserve the original bring-up chronology, with factual qualifications added where current RTL or checked-in reports cannot prove the original causal explanation.

---

## 1. Bug #4: PCI BRAM Writes Return Zero

### 1.1 Symptom

After synthesis, writing to FIFO BRAM via PCI (`bram_write_full` command) followed by a read returned all zeros. The same logic worked in simulation.

### 1.2 Root Cause

In the pre-fix code, the PCI write path was:

```
reg_bram_cmd[0]  ->  (auto-clear 1 cycle later)
       |
       v
combinational proc port mux  ->  fifo_proc_we  ->  BRAM Port B we_b
```

The contemporaneous diagnosis was that the auto-cleared command bit fed a poorly placed/timed control path into BRAM Port B. The checked-in current source does not preserve the broken implementation or a routed report that isolates this path, so the precise race through the mux cannot be independently re-established here.

What the repository does establish is the observed contrast: the pre-fix logic worked in untimed simulation, hardware writes failed, and request-derived registered strobes were followed by passing hardware readback.

### 1.3 Fix: Registered PCI Write Strobes

The fix adds dedicated registered strobes that bypass the auto-clear timing issue:

```verilog
   wire pci_wr_hit = reg_req_in && !reg_ack_in && block_match && !reg_rd_wr_L_in;

   reg bram_pci_wr_strobe;
   reg gpu_dmem_pci_wr_strobe;

   always @(posedge clk) begin
      if (reset) begin
         bram_pci_wr_strobe     <= 1'b0;
         gpu_dmem_pci_wr_strobe <= 1'b0;
      end else begin
         bram_pci_wr_strobe     <= pci_wr_hit
                                && (local_offset == `LAB8_BRAM_CMD)
                                && reg_data_in[0];
         gpu_dmem_pci_wr_strobe <= pci_wr_hit
                                && (local_offset == `LAB8_GPU_DMEM_CMD)
                                && reg_data_in[0];
      end
   end
```

**How it works:**

`pci_wr_hit` detects the exact cycle when a PCI write request arrives for our block. The registered strobe checks three things simultaneously:
1. `pci_wr_hit` -- this is a write to our register block
2. `local_offset == LAB8_BRAM_CMD` -- specifically to the BRAM command register
3. `reg_data_in[0]` -- the host is writing a 1 to the write-strobe bit

The strobe is registered, so it produces a clean, single-cycle pulse derived directly from the accepted request. It still passes through the wrapper proc mux and the FIFO's mode mux before reaching BRAM; registration does not by itself guarantee timing closure. The hardware result supports that this structural change fixed the observed write failure on the tested build.

### 1.4 Where the Strobe is Used

In the proc port mux, the PCI default path now uses the registered strobe:

```verilog
      end else begin
         // PCI registers drive FIFO BRAM (default)
         fifo_proc_addr = reg_bram_addr[7:0];
         fifo_proc_din  = {reg_bram_wctrl[7:0], reg_bram_wd_hi, reg_bram_wd_lo};
         fifo_proc_we   = bram_pci_wr_strobe;    // registered, not reg_bram_cmd[0]
      end
```

Same pattern for GPU DMEM PCI writes:

```verilog
      end else begin
         gpu_dmem_addr    = reg_gpu_dmem_addr[9:0];
         gpu_dmem_wr_en   = gpu_dmem_pci_wr_strobe;    // registered
         gpu_dmem_wr_data = {reg_gpu_dmem_wd_hi, reg_gpu_dmem_wd_lo};
      end
```

**Why only BRAM and GPU DMEM?** These are the two PCI write paths that go through combinational muxes. The other write paths (CPU IMEM, CPU DMEM, GPU IMEM) are direct `assign` from `reg_*_cmd[0]` without a mux, so the auto-clear timing path is short enough.

---

## 2. Bug #2 RTL Fix (Applied in Batch 5)

Bug #2 was identified in Batch 3 (network packets corrupting BRAM during CPU mode) but was worked around in software. In Batch 5, the RTL fix was applied for synthesis.

### 2.1 The Change

In `convertible_fifo.v`, the `in_rdy` assignment was updated from:

```verilog
// OLD (Batch 1 original):
assign in_rdy = (state == S_IDLE || state == S_RECEIVING) && !pkt_stored;
```

To:

```verilog
// FIXED (Batch 5):
assign in_rdy = (mode == 2'd0)
             && (state == S_IDLE || state == S_RECEIVING)
             && !pkt_stored;
```

The `mode == 2'd0` condition ensures that network input is only accepted when the FIFO is in FIFO mode. In CPU mode (1) or GPU mode (2), `in_rdy` stays LOW, preventing Port A writes from corrupting BRAM while a processor uses Port B.

---

## 3. Synthesis Results

### 3.1 Build Commands

On the Fedora VM with Xilinx ISE 10.1:

```bash
export XIL_TIMING_ALLOW_IMPOSSIBLE=1
cd /root/netfpga/projects/lab8/synth && make
```

`XIL_TIMING_ALLOW_IMPOSSIBLE=1` tells ISE to continue even when timing constraints cannot be met. Without this flag, synthesis would abort due to the GPU's timing violations.

### 3.2 NetFPGA Project Setup

- Base project: `reference_nic`
- `project.xml`: includes the single integrated `lab8` module; no separate current GPU register module is declared
- `lab8.xml`: 49 allocated slots (12 FIFO + 15 CPU + 5 padding + 12 GPU + 4 DMA + 1 cycle counter), of which 44 are implemented registers
- `gpu_nf2_wrapper.v` and `gpu.xml` are absent from this checkpoint; current GPU integration and register decode live in `lab8_wrapper.v`/`lab8.xml`. The repository does not preserve those historical artifacts, so their alleged deletion history cannot be independently verified here.

### 3.3 Timing

- **Core clock: 125 MHz** (8 ns period)
- **March historical capture:** project prose records 4,816 failing paths and a 16.670 ns GPU-decode path. No checked-in raw timing report contains that exact pair, so it should not be read as the current checkpoint result.
- **Checked-in reports vary by build:** archived reports include 7,410 failures/18.377 ns, 4,146/15.150 ns, and 650/12.219 ns. The top-level `synth/nf2_top_par.twr` reports 735 failing endpoints and an 11.909 ns minimum period for its build.
- Those artifacts do not form a clean timing report for the latest checked-in GPU source, so there is no single verified "current RTL" timing number in the repository.

Ordinary setup violations are not made safe by hazard stalls or by a kernel's low average throughput: unless a path is explicitly constrained as multicycle, receiving registers still sample every 8 ns. `XIL_TIMING_ALLOW_IMPOSSIBLE=1` permits implementation to continue; it does not make the bitfile timing-correct. Passing hardware tests on particular routed builds is useful empirical evidence, but it cannot guarantee arbitrary operation at 125 MHz.

---

## 4. Hardware Test Sequence

The project records the following six command-level checks as passing on the tested NetFPGA V2 bitfile. As noted in Test 6 and §5.3, this does not include successful downstream packet egress.

### Test 1: Status Check

```
lab8reg status
```

Reads `LAB8_STATUS` register. Verifies PCI register ring is functional and FIFO reports empty/no packet.

### Test 2: PCI BRAM Write/Read

```
lab8reg bram_write_full <addr> <ctrl_hex> <hi_hex> <lo_hex>
lab8reg fifo_read
```

Writes a known 72-bit BRAM word via PCI, then reads it back. Repeating the command can cover additional locations. This tests the Bug #4 registered-strobe path.

### Test 3: CPU Test

```
lab8reg cpu_test <hex_file>
```

Sequence: reset FIFO -> write test data to BRAM[1] via PCI -> set mode=1 -> load 4-thread program -> start CPU -> poll all_halted -> stop CPU -> read BRAM[1] -> verify BRAM[1] = original + 42.

### Test 4: GPU DMEM Write/Read

```
lab8reg gpu_write_dmem 0 0xDEAD 0xBEEF
lab8reg gpu_read_dmem 0
```

Direct PCI access to GPU DMEM. Tests the `gpu_dmem_pci_wr_strobe` path.

### Test 5: GPU Kernel Execution

```
lab8reg gpu_load_imem <program.hex>
lab8reg gpu_start
lab8reg gpu_status
lab8reg gpu_read_dmem 0
```

Loads a kernel, runs it, reads results. Tests GPU pipeline execution on hardware.

### Test 6: DMA Round-Trip

```
lab8reg gpu_test <hex_file>
```

Integration test: reset -> check packet -> DMA FIFO->GPU -> run kernel -> DMA GPU->FIFO -> verify BRAM by PCI -> trigger drain. It verifies the internal FIFO BRAM/DMA/GPU round trip. The command does not wait for or validate downstream delivery, and §5.3 records that egress stalled.

---

## 5. Real Network Packet Tests (March 7--8 2026)

After basic functional tests, the design was tested with real ARP packets from node0 (nf6.usc.edu) arriving on port0 (10.0.0.3 <-> nf2c0: 10.0.0.2).

### 5.1 Packet Capture

ARP broadcast packets (8 words, 60 bytes) arrive automatically within seconds of FPGA reset. The FIFO captures one packet: BRAM[0] has ctrl=0xFF (NF2 header), BRAM[1..7] have ctrl=0x00 (Ethernet frame).

### 5.2 All 5 GPU Kernels Verified

Each kernel was loaded, DMA'd the packet payload into GPU DMEM, executed, and results verified via PCI DMEM readback:

- **vec_add_i16**: 4-lane SIMD addition (e.g., FFFF+9F0A=9F09)
- **vec_sub_i16**: 4-lane SIMD subtraction (e.g., FFFF-9F0A=60F5)
- **bf16_mul**: BFloat16 multiplication (NaN propagation correct, negative zero)
- **bf16_fma**: BFloat16 fused multiply-add (NaN inputs produce NaN output)
- **relu_i16**: ReLU activation (negative lanes zeroed, positive passed through)

These are preserved as results from the March hardware build. The later current RTL scalarizes INT16 execution to lane 0 and replicates that result, so the historical four-distinct-lane INT16 observations should not be projected onto a new bitfile built from the current source.

### 5.3 Known Issue: Drain Stall

The drain FSM stalls because `out_rdy` from `output_queues` stays LOW. This means drained packets never actually reach the downstream output port. However, this does not block testing -- each test starts with a FIFO reset, and verification is done by PCI readback of BRAM contents, not by inspecting output packets at node0.

---

---

## 6. Phase 1 Re-Synthesis (March 20, 2026)

After the initial Batch 5 hardware verification (March 7), a set of refinements were applied and re-synthesized. See [`docs/lab9_refinements/refinements_plan.md`](../lab9_refinements/refinements_plan.md) for the recorded plan.

### 6.1 Bug #5: GPU HALT Gating Timing Failure

**Symptom:** After re-synthesis with GPU updates (branch-to-EX1, HALT gating, BF16 unsigned rewrite), the GPU kernel's ST instruction did not commit its DMEM write for most kernels (vec_add, vec_sub, bf16_mul, relu). Only bf16_fma passed. ANN inference produced partially wrong results.

**Recorded root-cause diagnosis:** The historical HALT gating was described as using this combinational bypass:
```verilog
// BROKEN at 125 MHz:
assign halted = halted_r || exwb_is_halt;
assign dmem_wr_en = dmem_wr_en_raw && !halted;
```

This structure creates a combinational path from `exwb_is_halt` (EX3/WB register output) through `halted` to `dmem_wr_en` (BRAM Port A write enable). The project record correlates that path with the missing final store and reports that the registered-only change fixed it. The broken source and its routed timing path are not present in this checkpoint, so the more specific claim that `halted` glitched at a particular edge cannot be independently reproduced from the repository.

**Fix:** Remove the combinational bypass, use registered-only `halted`:
```verilog
// FIXED:
assign halted = halted_r;
```

This makes completion registered-only and removes that combinational bypass. Already-issued younger instructions are not flushed: they may continue toward writeback, while fetch and DMEM writes are gated once `halted_r` is high. Correctness therefore depends on post-HALT instruction slots being side-effect-free; it is not enough to assume exactly one harmless NOP in every program.

**Debugging process:** Verified IMEM loads correctly (readback matches hex file). Verified PCI DMEM writes work (readback matches written values). Confirmed the kernel completed (kernel_done=1). The DMEM result address showed stale data unchanged by the kernel. The registered-only fix resolved all failures immediately on re-synthesis.

### 6.2 Phase 1 Hardware Test Results (March 20, 2026)

Test suite recorded with the Python tool now present as `scripts/lab9reg.py` (alongside the legacy Perl `sw/lab8reg`). There is no `lab8reg.py` file in this checkpoint.

| Test | Type | Result |
|------|------|--------|
| cpu_test (all_halted=1) | CPU-FIFO | PASS |
| vec_add_i16 | GPU standalone | PASS |
| vec_sub_i16 | GPU standalone | PASS |
| bf16_mul | GPU standalone | PASS |
| bf16_fma | GPU standalone | PASS |
| relu_i16 | GPU standalone | PASS |
| ANN (hand-crafted weights) | GPU standalone | PASS |
| ANN (trained weights) | GPU standalone | PASS |
| ANN integrated (FIFO->DMA->GPU->DMA->FIFO) | Full data path | PASS |
| ANN trained integrated | Full data path | PASS |
| **Total** | | **9/9 + cpu_test** |

Key improvements over the March 7 bitfile:
- Recorded `all_halted` polling no longer timed out after H1; the bit remains an AND of sticky HALT flags, not proof that IMEM fetch slots are disabled
- GPU HALT gating prevents spurious post-HALT DMEM writes (registered-only fix)
- BF16 unsigned exponent arithmetic avoids ISE 10.1 synthesis bug
- GPU critical path reduced from 16.67ns to ~11ns (branch moved to EX1)

---

## 7. Bug #6: Readback Mux Trimmed by XST (2026-04-13)

**Symptom:** After adding the GPU cycle counter (`LAB8_GPU_CYCLE_COUNT = 0x30`) and re-synthesising, **every** PCI read returned `0xDEADBEEF`. Not just the new register -- everything. `bram_read_full` reported the canary value, status checks looked completely broken, scripts that had worked on the prior bitfile started failing.

**Contemporaneous attribution:** The PCI readback `case` statement (40+ entries) lived inside an `else` branch of the clocked write-path always block:

```verilog
always @(posedge clk) begin
   if (reset) begin
      ...
   end else begin
      ...
      if (reg_req_in && !reg_ack_in && block_match) begin
         if (!reg_rd_wr_L_in) begin
            case (local_offset) /* writes */ endcase
         end else begin
            case (local_offset)
               `LAB8_CTRL: reg_rd_data <= reg_ctrl;
               // ... 40+ register reads ...
               default:    reg_rd_data <= 32'hDEAD_BEEF;
            endcase
         end
      end
   end
end
```

Project notes attributed the all-`0xDEADBEEF` symptom to XST optimizing this deeply conditional readback structure. The included broken-build XST report still identifies a `reg_rd_data` register and mux, so it does not independently prove that the register itself was trimmed or that every read was literally replaced by the default arm. The observed regression and the successful structural refactor are supported; the exact optimizer mechanism remains an attribution.

**Fix:** Split the mux into a dedicated combinational `always @*` block, with a separate clocked flop that latches the muxed value when we own the read request:

```verilog
reg [`CPCI_NF2_DATA_WIDTH-1:0] reg_rd_data_mux;

always @* begin
   case (reg_addr_in[`LAB8_REG_ADDR_WIDTH-1:0])
      `LAB8_CTRL:            reg_rd_data_mux = reg_ctrl;
      // ... all 40+ registers ...
      `LAB8_GPU_CYCLE_COUNT: reg_rd_data_mux = reg_gpu_cycle_count;
      default:               reg_rd_data_mux = 32'hDEAD_BEEF;
   endcase
end

always @(posedge clk) begin
   if (reset) reg_rd_data <= 32'd0;
   else if (reg_req_in && !reg_ack_in && block_match && reg_rd_wr_L_in)
      reg_rd_data <= reg_rd_data_mux;
   else
      reg_rd_data <= reg_data_in;     // pass-through
end
```

Functionally identical. Structurally something XST can't dismiss: the combinational mux drives a wire, and the flop has an unconditional assignment in every branch of its single-level `if/else if/else`. Re-synthesis passed; all PCI reads worked normally.

**Verification:** Hardware-verified on team-6 board 2026-04-13. The 0x30 cycle counter now reads the actual count from the prior kernel run.

---

## 8. BCAST Integration Synthesis Note (current RTL reconciled 2026-07-14)

Adding the cross-lane BCAST mux to `simd_alu.v` (commit `e14d012`) was reported in later notes as introducing this combinational chain:

```
use_imm (EX1) -> op_b mux -> bcast_value mux (4:1) -> effective_a (2:1)
            -> bf16.a_gt_b_mag -> exp_diff -> shift -> add_raw -> FF (EX2)
```

Later notes describe a pre-fix BCAST path of **15.26 ns**, nearly twice the 8 ns budget. The checked-in April 17 TWR is a different post-fix build reporting a 12.219 ns minimum period, so the raw 15.26 ns report is not available here. The note remains useful as recorded timing history, not as a directly verifiable measurement of current source.

**Current checkpoint RTL status:** the checked-in `src/gpu/simd_alu.v` has `OP_BCAST`/`ALU_BCAST`, the 4:1 lane-select mux, and `effective_a`. It then registers `alu_op_r`, `dtype_r1`, `effective_a_r`, and `operand_b_r` before the lane ALUs. The BF16 path uses four `bf16_alu` instances; the INT16 path uses one `int16_alu` on lane 0, captures it in `int_lane0_r`, and replicates that value to all four result positions. `dtype_r2` aligns the final mux. `execute_stage.v` consumes `simd_result` directly in EX3 and has no separate `simd_result_r` register.

The proposed structural refinement is therefore implemented in current source: the BCAST-shuffled operand/control bundle is registered before the ALUs, while removing the later execute-stage register keeps the end-to-end SIMD result aligned with the 3-cycle FMA path. The archived reports do not establish timing closure for this exact source revision, so a fresh routed timing report is still required before claiming the 8 ns constraint is met.

---

## Summary -- What Batch 5 Establishes (current as of 2026-07-14)

1. **Bug #4 fix** (2026-03-07) -- `bram_pci_wr_strobe` and `gpu_dmem_pci_wr_strobe` provide request-derived registered write pulses; the tested build's PCI writes passed, though the pulses still traverse downstream mux logic.
2. **Bug #2 RTL fix** (2026-03-07) -- `in_rdy` now gated by `mode == 0` in `convertible_fifo.v`, preventing network input corruption during CPU/GPU modes.
3. **Bug #5 fix** (2026-03-20) -- GPU `halted` signal changed from combinational (`halted_r || exwb_is_halt`) to registered-only (`halted_r`), fixing DMEM write suppression at 125 MHz.
4. **Bug #6 fix** (2026-04-13) -- readback mux split out of the clocked write block, fixing the "every read returns 0xDEADBEEF" regression; the exact XST trimming mechanism is not proven by the included report.
5. **BCAST timing refinement** (current RTL reconciled 2026-07-14) -- `simd_alu.v` registers the shuffled inputs/controls, uses a scalar lane-0 INT16 ALU with replicated output, and `execute_stage.v` removes its former extra SIMD result register. A current routed report is still needed to quantify timing.
6. **Synthesis** -- all checked-in builds miss the 8 ns constraint, and reports differ by revision. `XIL_TIMING_ALLOW_IMPOSSIBLE` permits bitstream generation but does not establish 125 MHz timing correctness.
7. **Current project structure** -- one integrated `lab8` module; no standalone `gpu_nf2_wrapper.v`/`gpu.xml` artifacts are present.
8. **Recorded hardware coverage** -- 9/9 GPU tests (5 kernels + 2 ANN standalone + 2 ANN integrated) plus `cpu_test` passed on the cited bitfiles.
9. **Live-packet input/internal processing** -- five GPU kernels produced the recorded PCI-readback results from ARP packet data; downstream packet delivery was not verified because drain stalled.
10. **Python test suite** -- the current Python tool is `scripts/lab9reg.py`; legacy Perl remains at `sw/lab8reg`.
