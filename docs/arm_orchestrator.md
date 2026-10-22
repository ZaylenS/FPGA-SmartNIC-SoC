# ARM-Orchestrated IDS Pipeline Refinement

**Plan written**: 2026-04-17 (originally §9 of `milestone3_refinements.md`)
**RTL + sim landed**: 2026-04-18
**Synth gate**: handled separately on the Fedora VM. The previously deployed `synth/nf2_top_par.bit` (post-synth 2026-04-18 01:41 local time) includes the Fix A alias-window RTL but not Fix B (§13.3). `synth/milestone3_fix1_2026-04-17/` is the pre-orchestrator Fix 1 backup — timing-closed GPU inference pipeline only, no alias window — kept as a revert target. Fix B re-synth pending.
**Hardware bring-up**: Fix A hardware-verified 2026-04-18 (two iterations: hex/DMA-length change in §13.2, plus host-side 8-byte trailer-word workaround in §13.2.1 for the classifier/FSM `word_length` semantic mismatch). End-to-end silicon result with `send_ids.py --replicated 1.0 × 11`: `DMEM[126..127] = 0x41B0_41B0_41B0_41B0` (BF16 22.0) — bit-identical to `tb_ids_bcast` sim reference. ARM-side orchestration of the GPU inference pipeline is numerically correct on silicon.
**Fix B sim landed**: 2026-04-20 (RTL + hex + TB) — §13.3 plan implemented and verified in iverilog. `tb_arm_ids_orchestrator.v` now captures the NF2 egress stream and asserts the rewritten headers + logit payload word-by-word (18/18 words match on Test 1; 3/3 iterations match on Test 2). All regression TBs still pass. See §13.3 "As-built (2026-04-20)" below. Silicon verification pending the next re-synth.

This refinement still belongs to milestone 3 — it lives in its own
file rather than in `milestone3_refinements.md` only because of length.
Rounds 1–2 in that doc closed the GPU's BCAST timing path; this round
turns the ARM CPU into the on-chip orchestrator that drives the IDS
classification pipeline end-to-end so the host stops being the
throughput limiter.

`milestone3_refinements.md` keeps a pointer in §9 and treats this doc
as the canonical source for everything below.

---

## 1. Motivation

Rounds 1–2 of milestone 3 (Fix 1) focused on GPU timing. This round
moves in a different direction: **put the ARM CPU into the IDS hot path
as the on-chip pipeline orchestrator**. Two reasons:

1. **Architectural completeness.** Today the ARM is idle during IDS
   inference. The convertible-FIFO + ARM + GPU + DMA layout is the
   archetype of a SmartNIC / small DPU: a CPU dispatches work, an
   accelerator computes, a DMA engine bridges. We have the pieces but
   aren't using the CPU for the piece that is its job.
2. **Throughput.** Measured 2026-04-17 on nf5: `cmd_ids_batch_packets`
   at `--delay 0.5` captures 8/20, `--delay 2.5` captures 20/20. Real
   end-to-end ceiling is ~1 pps, limited by Python-over-PCI orchestration
   (11× DMEM writes + GPU release + poll + response-packet + fifo_reset
   ≈ 500 ms per packet). ARM doing the same work at 125 MHz would complete
   each iteration in **microseconds**, so the ceiling jumps from ~1 pps to
   thousands of pps. The rate limiter stops being the orchestrator.

This also removes the need for the `--delay 2.5s` workaround in the
live-DDoS demo (see
`docs/final_project_demo_video/final_project_expert_demo_plan.md` §2.3).

## 2. Architectural blocker (pre-refinement snapshot)

From `src/arm/data_mem.v` and `src/lab8_wrapper.v` as of milestone 3
rounds 1–2:

| ARM action | Pre-refinement status | Reason |
|------------|-----------------------|--------|
| Read/write FIFO BRAM | ✅ Works | `addr[7]=1` routes to `cpu_ext_mem_*`, muxed into FIFO BRAM Port B |
| Poll GPU_STATUS (kernel_done, dma_busy) | ❌ Blocked | `reg_gpu_status` is a PCI-read-only wire, not in ARM's address space |
| Write DMA_CTRL to trigger DMA | ❌ Blocked | `reg_dma_ctrl` is gated on `reg_req && !reg_wr_rd_L` (PCI path only) |
| Write GPU_CTRL to release GPU | ❌ Blocked | Same as DMA_CTRL |
| Write GPU IMEM/DMEM | ❌ Blocked | Reachable only via PCI register-based BRAM-access protocol or DMA |

The fix is small: give ARM a memory-mapped window onto the control
registers it needs. Nothing about the register flops themselves
changes — we just add a second write/read path alongside the existing
PCI one.

## 3. RTL plan — register-alias window

### 3.1 ARM DMEM address map

| ARM DMEM address | Maps to | Notes |
|------------------|---------|-------|
| `0x00 – 0x7F` | Internal DMEM (128 × 64-bit) | unchanged |
| `0x80 – 0xEF` | FIFO BRAM window (112 × 64-bit view into FIFO[0x00..0x6F]) | was `0x80 – 0xFF`; we give up the top 16 slots. FIFO BRAM 0x70–0x7F lose ARM access but stay PCI-visible. |
| `0xF0 – 0xFF` | Control-register aliases (new) | 16 × 64-bit (10 used, 6 reserved) |

### 3.2 Register-alias slot assignment

| ARM alias | Wrapper register | R/W from ARM | Semantics |
|-----------|------------------|--------------|-----------|
| `0xF0` | `reg_dma_ctrl` | RW | bit[0]=start (auto-clear), bit[1]=dir (0=FIFO→GPU, 1=GPU→FIFO) |
| `0xF1` | `reg_dma_fifo_addr` | RW | [7:0] FIFO BRAM start |
| `0xF2` | `reg_dma_gpu_addr` | RW | [9:0] GPU DMEM start |
| `0xF3` | `reg_dma_length` | RW | [7:0] word count |
| `0xF4` | `reg_gpu_ctrl` | RW | bit[0]=1 holds GPU in reset, 0 releases |
| `0xF5` | `reg_gpu_status` | RO | bit[0]=kernel_done, bit[1]=dma_busy |
| `0xF6` | FIFO status word (`reg_status`) | RO | bit[0]=pkt_ready, other status bits as today |
| `0xF7` | `reg_fifo_mode_r` | RW | [1:0] 0=passthrough, 1=CPU, 2=DMA/GPU |
| `0xF8` | `reg_ctrl` | RW | bit[0]=soft_reset (auto-clear, see §8.3) |
| `0xF9` | `reg_gpu_cycle_count` | RO | [31:0] cycles from gpu_reset deassert to kernel_done |
| `0xFA – 0xFF` | reserved | — | readback returns 0; writes silently dropped |

### 3.3 File-by-file plan

**`src/arm/data_mem.v`** (~20 LoC added):

- Decode `addr_is_reg = (addra[7:4] == 4'hF)`.
- Redefine `addr_is_ext = addra[7] & ~addr_is_reg` so FIFO-window writes don't clash.
- New module I/O: `reg_alias_sel` (4b out), `reg_alias_wdata` (64b out), `reg_alias_we` (1b out), `reg_alias_rdata` (64b in).
- Track `was_reg` with a flop mirroring `was_ext`, extend `douta` mux to 3 ways.

**`src/arm/processor.v`** (~10 LoC added):

- Plumb the four alias ports through as top-level ports on the `processor` module.

**`src/lab8_wrapper.v`** (~40 LoC added):

- New wires `cpu_reg_sel/wdata/we/rdata`.
- Wire to `u_cpu`.
- Write path: `else if (cpu_reg_we)` branch added to the existing register-write `always @(posedge clk)` block. PCI takes priority via outer `else if` ordering. Read-only and reserved slots silently drop ARM writes via `default: ;`.
- Read path: combinational `always @(*)` mux on `cpu_reg_sel`.

GPU, FIFO BRAM, DMA engine, and register-generator infrastructure are untouched.

## 4. ARM orchestrator program

### 4.1 Single-thread first

T0 runs the orchestrator; T1–T3 sit at HALT. 4-thread FGMT stays
available but isn't needed — T0 at 31.25 MHz effective is already
~100× faster than the ~6 ms BCAST kernel it's waiting on.

### 4.2 Control flow

```text
; r0 = 0xF0 (alias-window base pointer)
main:
    MOV     r0, #0xF0

wait_pkt:
    LDR     r1, [r0, #0x06]                 ; FIFO_STATUS
    TST     r1, #1                          ; bit[0] = pkt_ready
    BEQ     wait_pkt

    MOV     r1, #2
    STR     r1, [r0, #0x07]                 ; FIFO_MODE = 2

    ; DMA in: FIFO[7..17] (11 words, replicated BF16 features) -> GPU DMEM[0..10]
    ; (The `#11` here was originally `#3` -- the 2026-04-18 hardware bring-up
    ;  revealed a packet-layout mismatch; see section 13 for the rationale.)
    MOV     r1, #7
    STR     r1, [r0, #0x01]                 ; DMA_FIFO_ADDR
    MOV     r1, #0
    STR     r1, [r0, #0x02]                 ; DMA_GPU_ADDR
    MOV     r1, #11
    STR     r1, [r0, #0x03]                 ; DMA_LENGTH
    MOV     r1, #1                          ; start=1, dir=0
    STR     r1, [r0, #0x00]                 ; DMA_CTRL

wait_dma_in:
    LDR     r1, [r0, #0x05]                 ; GPU_STATUS
    TST     r1, #2                          ; bit[1] = dma_busy
    BNE     wait_dma_in

    MOV     r1, #0
    STR     r1, [r0, #0x04]                 ; GPU_CTRL = 0 (release)

wait_kernel:
    LDR     r1, [r0, #0x05]
    TST     r1, #1                          ; bit[0] = kernel_done
    BEQ     wait_kernel

    MOV     r1, #1
    STR     r1, [r0, #0x04]                 ; GPU_CTRL = 1 (hold)

    ; DMA out: GPU DMEM[126..127] (2 words) -> FIFO[10..11]
    MOV     r1, #10
    STR     r1, [r0, #0x01]
    MOV     r1, #126
    STR     r1, [r0, #0x02]
    MOV     r1, #2
    STR     r1, [r0, #0x03]
    MOV     r1, #3                          ; start=1, dir=1
    STR     r1, [r0, #0x00]

wait_dma_out:
    LDR     r1, [r0, #0x05]
    TST     r1, #2
    BNE     wait_dma_out

    MOV     r1, #0
    STR     r1, [r0, #0x07]                 ; FIFO_MODE = 0
    MOV     r1, #1
    STR     r1, [r0, #0x08]                 ; FIFO_CTRL = 1 (auto-clear)

    B       wait_pkt
```

40 instructions assembled — well under the 128-word-per-thread budget.

The ARM toolchain in `toolchains/arm/` does not yet emit this program;
for now the testbench in `tb/tb_arm_ids_orchestrator.v` hand-assembles
it inline (full hex listing in §8.2).

### 4.3 Host-side setup (unchanged from today)

1. Load BCAST kernel into GPU IMEM via PCI.
2. Load weights/biases into GPU DMEM[3..127] via PCI (DMEM[0..2] gets overwritten by DMA per packet).
3. Load `ids_orchestrator.hex` into ARM IMEM T0 region via PCI.
4. Release ARM reset.
5. Host can now sit back — ARM handles everything packet-by-packet.

Python's role shrinks to "load + go." The `ids_live_loop.py` from the
expert demo plan reduces to a monitor that reads FIFO output packets
and feeds the visualizer.

## 5. Verification plan

### 5.1 `tb/tb_arm_reg_access.v` — unit test for the alias window

Tiny ARM program: write a unique pattern to each RW alias, read back via
PCI, assert match. Covers DMA_CTRL / FIFO_ADDR / GPU_ADDR / LENGTH /
GPU_CTRL / FIFO_MODE / FIFO_CTRL. For RO aliases (GPU_STATUS,
FIFO_STATUS, CYCLE_COUNT), drive synthetic values at the wrapper side
and read via ARM into DMEM, then PCI-read DMEM and assert match.

**Gate**: all 7 RW aliases coherent; all 3 RO aliases readable.

### 5.2 `tb/tb_arm_ids_orchestrator.v` — full-stack integration

- Load BCAST kernel + IDS test data + orchestrator program via PCI.
- Release ARM reset.
- Inject a pre-crafted IDS feature packet (18 NF2 words: 1 header + 6 padding
  + 11 replicated feature words at FIFO[7..17]). The 2026-04-18 fix in §13
  bumped this from 10 words / 3 packed features — the BCAST kernel expects
  one feature per DMEM word, replicated across all 4 SIMD lanes.
- Wait a fixed cycle budget (avoids polling races — see §10).
- Read FIFO BRAM[10..11] via PCI and assert match against the BCAST
  reference output (22.0 BF16 = `0x41B0` packed across 4 lanes).

**Gate**: orchestrator completes one loop iteration; response matches
reference bit-for-bit. Then extend to a 5-packet sequence to stress
the FIFO_MODE flips and the FIFO_CTRL auto-clear.

### 5.3 Regression — `tb/tb_gpu_integration.v`, `tb/tb_cpu_fifo.v`, `tb/tb_ids_inference.v`, `tb/tb_ids_bcast.v`

Existing tests must still pass with PCI-orchestrated flow (ARM held in
reset). Proves we haven't broken Fix 1 bitfile behavior or the
underlying GPU kernels.

## 6. Synthesis and timing gate

(Run by user on the Fedora VM; not driven from this doc.)

### 6.1 Expected deltas vs Fix 1 baseline

| Metric | Fix 1 (Apr 17 R2) | Estimated impact |
|--------|-------------------|------------------|
| Slice FFs | 16,974 | +64 (alias rdata pipeline reg added in §8.3) |
| 4-input LUTs | 29,187 | +20 to +40 (3-way mux + 16-way decoder) |
| Slices | 20,960 (88%) | +0 to +30 |
| MULT18X18 | 9 | unchanged |
| Failing endpoints (core_clk_int) | 650 | ±200 expected |
| Worst slack | −4.219 ns | ±1 ns expected |

The new critical-path candidate is the `cpu_reg_wdata → case-decoder →
reg_dma_ctrl FF` chain. If that hits ≤ 5 ns (one LUT level of decode
plus one net), we're well inside budget. The 3-way `douta` mux replaces
a 2-way mux in the MEM-stage critical path of the ARM CPU; that path
currently has ~3 ns of slack, so adding one LUT level should stay
inside budget.

### 6.2 Gate criteria (same shape as Fix 1 gate)

| Metric | Pass | Marginal | Fail |
|--------|------|----------|------|
| `core_clk_int` worst slack | ≥ −5 ns | −5 to −7 ns | < −7 ns |
| Failing endpoints | ≤ 900 | 900–1500 | > 1500 |
| `TS_rx_clk`, `TS_tx_clk_gmii` | 0 failing | — | > 0 |
| `CPCI_*`, `SRAM*` | 0 failing | — | > 0 |

**Early abort**: if after 4 hours of PAR the worst slack is still below
−10 ns with no clear placement fix, revert to the Fix 1 bitfile and
narrate the demo with Python orchestration (Option C in the expert demo
plan).

## 7. Risks, what-this-unlocks, non-goals

### 7.1 Risks

1. **Timing regression.** Fix 1 closed with −4.22 ns worst slack; margin
   is thin. New LUT levels in the register-alias path could push over
   budget. The `reg_alias_rdata_r` flop added in §8.3 helps by breaking
   the alias readback into a registered path instead of a long combo.
   Mitigation: gate criteria above; revert-ready RTL.
2. **Write contention.** PCI and ARM both write the same register flops.
   Mitigation: PCI-priority `else if` ordering in the wrapper write
   block; host-side discipline that ARM runs only after PCI setup
   completes; `CPU_CTRL` start/stop already gates this.
3. **Auto-clear semantics on ARM writes.** DMA_CTRL[0] auto-clears, so
   ARM writes a 1-cycle strobe; the DMA FSM samples on a single edge.
   FIFO_CTRL[0] auto-clear was *added* in §8.3 — see deviation note.
4. **ARM debugging is harder than Python.** Mitigation: single-thread
   first; the alias-window unit test in §5.1 builds confidence before
   the full orchestrator.
5. **GPU_STATUS read latency.** `reg_gpu_status = {30'd0, dma_active,
   gpu_kernel_done}` is purely combinational from same-clock-domain
   wires. ARM polling loop behaves identically to PCI polling loop.

### 7.2 What this unlocks for the May 13 demo

With this refinement landed in a bitfile, the expert-demo narrative
upgrades from:

> "Python on the host orchestrates the pipeline over PCI. The FPGA runs
> the ML kernel."

to:

> "The SoC orchestrates its own pipeline end-to-end. The ARM CPU polls
> the FIFO, dispatches DMA, releases the GPU, and drains responses —
> all on-chip. The host just loads the program and gets out of the way."

That is the correct story for a SmartNIC / DPU archetype and what Prof
Cho hinted at during the 2026-03-26 meeting (SoC advantage, IoT edge
framing). The ~1000× throughput jump is a bonus — the narrative win is
the main prize.

If the synth gate fails, Fix 1 still stands as the last good bitfile.
Demo proceeds with Python orchestration at ~1 pps, narrated honestly
(Option C in the expert demo plan).

### 7.3 Non-goals

- **In-FPGA packet filter action.** Even with ARM orchestration, we
  still only *detect*; we don't drop. Adding a drop path requires NF2
  data-path changes, not a control-plane refactor.
- **ARM feature extraction.** Flow tables and sliding windows stay in
  Python on nf7. ARM only orchestrates the classification pipeline.
  ARM ISA in this design has no MUL/DIV and tight DMEM, which makes
  per-flow stats the wrong fit.
- **Multi-thread ARM.** Single-thread (T0) is enough. FGMT upgrade is
  available later if we need higher throughput or want to demo the
  4-thread capability.

---

## 8. Implementation log (2026-04-18)

### 8.1 Files actually changed

| File | Status | What changed |
|------|--------|--------------|
| `src/arm/data_mem.v` | modified | Alias-window decode + 4 new ports + `was_reg` flop + `reg_alias_rdata_r` pipeline reg |
| `src/arm/processor.v` | modified | Pass-through ports for the alias bus |
| `src/lab8_wrapper.v` | modified | `cpu_reg_*` wires, `u_cpu` port mapping, combinational read mux, `else if (cpu_reg_we)` write branch, **`reg_ctrl[0]` auto-clear added** |
| `tb/tb_arm_reg_access.v` | new | §5.1 unit test |
| `tb/tb_arm_ids_orchestrator.v` | new | §5.2 full-stack integration |
| `programs/arm/ids_orchestrator.asm` | not yet written | Toolchain emit pending; testbench hand-assembles inline |
| `programs/arm/ids_orchestrator.hex` | materialized 2026-04-18 | 385-line hex (40 orch instr + HALT padding through T3 entry); see §13 for the DMA-length fix applied at the same time |

### 8.2 Code-level summary

**`src/arm/data_mem.v`** — address decode now three-way:

```verilog
wire addr_is_reg = (addra[7:4] == 4'hF);
wire addr_is_ext = addra[7] & ~addr_is_reg;
```

Internal-DMEM writes are gated by both negations
(`!addr_is_ext && !addr_is_reg`) so the alias window can't accidentally
land in `mem[]`. Two captured-cycle flops (`was_ext`, `was_reg`) drive
a 3-way `douta` mux, and a new `reg_alias_rdata_r` flop captures the
wrapper's combinational mux on the same edge that latches `was_reg`
(see §8.3 deviation #1 for why the flop is needed).

**`src/arm/processor.v`** — pure pass-through. Four new top-level ports,
forwarded straight to `u_mem`.

**`src/lab8_wrapper.v`** — three blocks added:

- Wires + `u_cpu` port mapping (10 LoC).
- Combinational read mux on `cpu_reg_sel`, returning each register
  zero-extended to 64 bits (~30 LoC). Slot `4'h6` returns the existing
  `reg_status` wire; slot `4'h8` returns the existing `reg_ctrl`.
- Write path: `else if (cpu_reg_we)` branch in the existing register
  `always @(posedge clk)` block, after the PCI write case. RO slots and
  reserved slots `default: ;` silently drop writes.
- One auto-clear strobe added: `if (reg_ctrl[0]) reg_ctrl[0] <= 1'b0;`
  (§8.3 deviation #2).

**`tb/tb_arm_reg_access.v`** — 23-instruction ARM program: T0 writes a
unique pattern to each RW alias, then reads each RO alias into
DMEM[0..2]. PCI verifies all 10 slots after halt. T1–T3 also run the
same program (FGMT writes converge because all threads write the same
patterns; reads are deterministic because GPU is held in reset
throughout).

Hand-assembled instruction stream (the test embeds these as 32-bit
hex constants):

```text
idx  hex          mnemonic                          notes
 0   E3A000F0     MOV r0, #0xF0                     alias base
 1   E3A03000     MOV r3, #0x00                     DMEM base
 2   E3A01002     MOV r1, #0x02
 3   E5801000     STR r1, [r0, #0x00]               DMA_CTRL = 0x02
 4   E3A01042     MOV r1, #0x42
 5   E5801001     STR r1, [r0, #0x01]               DMA_FIFO_ADDR = 0x42
 6   E3A01053     MOV r1, #0x53
 7   E5801002     STR r1, [r0, #0x02]               DMA_GPU_ADDR = 0x53
 8   E3A01064     MOV r1, #0x64
 9   E5801003     STR r1, [r0, #0x03]               DMA_LENGTH = 0x64
10   E3A01081     MOV r1, #0x81
11   E5801004     STR r1, [r0, #0x04]               GPU_CTRL = 0x81 (bit[0]=1 holds GPU)
12   E3A01002     MOV r1, #0x02
13   E5801007     STR r1, [r0, #0x07]               FIFO_MODE = 0x02
14   E3A01080     MOV r1, #0x80
15   E5801008     STR r1, [r0, #0x08]               CTRL = 0x80 (bit[0]=0 keeps soft-reset deasserted)
16   E5902005     LDR r2, [r0, #0x05]               GPU_STATUS
17   E5832000     STR r2, [r3, #0x00]               -> DMEM[0]
18   E5902006     LDR r2, [r0, #0x06]               FIFO_STATUS
19   E5832001     STR r2, [r3, #0x01]               -> DMEM[1]
20   E5902009     LDR r2, [r0, #0x09]               CYCLE_COUNT
21   E5832002     STR r2, [r3, #0x02]               -> DMEM[2]
22   FFFFFFFF     HALT
```

**`tb/tb_arm_ids_orchestrator.v`** — full-stack integration. Loads:
- `programs/gpu/ann_ids_11_16_8_2_bcast.hex` (108 GPU instructions) via PCI.
- `programs/gpu/data_ids_11_16_8_2_bcast.hex` (128 GPU DMEM words) via PCI.
- 40-instruction orchestrator into ARM T0 IMEM[0..39], with `HALT`
  trip wires at IMEM[40, 128, 256, 384] for T0 overshoot and T1–T3
  start positions.

Hand-assembled orchestrator instruction stream (loaded into T0 IMEM[0..39]):

```text
idx  hex          mnemonic                                  label / purpose
 0   E3A000F0     MOV r0, #0xF0                             alias base
 1   E5901006     LDR r1, [r0, #0x06]                       wait_pkt:  read FIFO_STATUS
 2   E3110001     TST r1, #1                                check pkt_ready
 3   0AFFFFFC     BEQ wait_pkt                              loop while bit clear
 4   E3A01002     MOV r1, #2
 5   E5801007     STR r1, [r0, #0x07]                       FIFO_MODE = 2
 6   E3A01007     MOV r1, #7
 7   E5801001     STR r1, [r0, #0x01]                       DMA_FIFO_ADDR = 7
 8   E3A01000     MOV r1, #0
 9   E5801002     STR r1, [r0, #0x02]                       DMA_GPU_ADDR = 0
10   E3A0100B     MOV r1, #11                               (was #3; see §13)
11   E5801003     STR r1, [r0, #0x03]                       DMA_LENGTH = 11
12   E3A01001     MOV r1, #1
13   E5801000     STR r1, [r0, #0x00]                       DMA_CTRL start, dir=0
14   E5901005     LDR r1, [r0, #0x05]                       wait_dma_in: read GPU_STATUS
15   E3110002     TST r1, #2
16   1AFFFFFC     BNE wait_dma_in                           loop while dma_busy
17   E3A01000     MOV r1, #0
18   E5801004     STR r1, [r0, #0x04]                       GPU_CTRL = 0 (release)
19   E5901005     LDR r1, [r0, #0x05]                       wait_kernel:
20   E3110001     TST r1, #1
21   0AFFFFFC     BEQ wait_kernel                           loop while !kernel_done
22   E3A01001     MOV r1, #1
23   E5801004     STR r1, [r0, #0x04]                       GPU_CTRL = 1 (hold)
24   E3A0100A     MOV r1, #10
25   E5801001     STR r1, [r0, #0x01]                       DMA_FIFO_ADDR = 10
26   E3A0107E     MOV r1, #126
27   E5801002     STR r1, [r0, #0x02]                       DMA_GPU_ADDR = 126
28   E3A01002     MOV r1, #2
29   E5801003     STR r1, [r0, #0x03]                       DMA_LENGTH = 2
30   E3A01003     MOV r1, #3                                start=1, dir=1
31   E5801000     STR r1, [r0, #0x00]                       DMA_CTRL
32   E5901005     LDR r1, [r0, #0x05]                       wait_dma_out:
33   E3110002     TST r1, #2
34   1AFFFFFC     BNE wait_dma_out
35   E3A01000     MOV r1, #0
36   E5801007     STR r1, [r0, #0x07]                       FIFO_MODE = 0
37   E3A01001     MOV r1, #1
38   E5801008     STR r1, [r0, #0x08]                       FIFO_CTRL = 1 (auto-clear)
39   EAFFFFD8     B wait_pkt                                offset = -40 words
```

ARMv4 branch encoding cross-check: target = `(inst_addr + 8) +
sign_extend(offset24) << 2`. For B at idx 39 (byte 156) targeting
wait_pkt at idx 1 (byte 4): `4 = 156 + 8 + offset*4 → offset = -40 =
0xFFFFD8`, encoding `EAFFFFD8`. ID stage uses `ifid_pc + 4 +
branch_offset` (`src/arm/ID.v:130`), which is the same equation.

### 8.3 Deviations from the §3.3 plan

The plan as written was correct in shape but had three small mismatches
with the existing codebase that surfaced once the RTL went into
simulation. All resolved without redesign.

1. **`reg_alias_rdata_r` pipeline flop in `data_mem.v`.** The plan's
   pseudo-code showed `douta = was_reg ? reg_alias_rdata : ...` with
   `reg_alias_rdata` taken straight from the wrapper's combinational
   mux. That works for a single-issue CPU but breaks under FGMT: at
   cycle T+1 the consumer in WB needs T0's data, but `reg_alias_rdata`
   is now driven by T+1's `cpu_reg_sel` (a different thread). Captured
   the wrapper's mux output on the same edge that latches `was_reg`,
   matching the existing `dmem_rd <= mem[addra]` and BRAM-Port-B
   timing. Costs one 64-bit flop; eliminates a thread-crosstalk bug.
2. **`reg_ctrl[0]` auto-clear added to the wrapper.** Plan §3.3 said
   "Auto-clear bits (DMA_CTRL[0], FIFO_CTRL[0]) already auto-clear via
   existing logic — no change needed." False for `reg_ctrl[0]`: the
   existing wrapper had no auto-clear strobe for it, and the
   orchestrator's instr 38 issues a single `FIFO_CTRL=1` write
   expecting a one-cycle pulse. Added one line in the auto-clear block:
   ```verilog
   if (reg_ctrl[0]) reg_ctrl[0] <= 1'b0;
   ```
   PCI behavior change: a write of `1` to LAB8_CTRL now produces a
   one-cycle soft-reset pulse instead of a sticky reset. Existing
   scripts that wrote `1` then `0` are unaffected (the `0` write is now
   a no-op). One synchronous clock cycle of reset is enough for the
   `convertible_fifo` state machine.
3. **Slot `4'h7` (FIFO_MODE) writes use [31:0], not [1:0].** The plan
   showed `reg_fifo_mode_r <= cpu_reg_wdata[1:0]` for that one slot.
   Likely a typo, since every other slot uses `[31:0]` and PCI writes
   the full 32-bit word too. Used `[31:0]` for consistency; only bits
   `[1:0]` are interpreted by the FIFO mux anyway, so behavior is
   identical.
4. **Slot `4'h8` aliases the existing `reg_ctrl`**, not a new
   `reg_fifo_ctrl` register. The plan named it `reg_fifo_ctrl` but
   `reg_ctrl` is what controls the FIFO soft-reset already. Reused
   the existing flop instead of adding a new one.

## 9. Verification results (iverilog, 2026-04-18)

All sims run with the project-default `iverilog -g2001` invocation
documented in `CLAUDE.md`. Class deliverables will be re-run on Xilinx
ISE 10.1 sim before submission per project policy.

### 9.1 `tb_arm_reg_access.v`

```
=== Step 1: hold CPU in reset, load IMEM for all 4 threads ===
PASS: IMEM[0] readback = 0xe3a000f0

=== Step 2: release CPU, wait for all_halted ===
CPU halted after 93 cycles

=== Step 3: PCI verifies the 7 RW alias writes ===
PASS: DMA_CTRL = 0x00000002
PASS: DMA_FIFO_ADDR = 0x00000042
PASS: DMA_GPU_ADDR = 0x00000053
PASS: DMA_LENGTH = 0x00000064
PASS: GPU_CTRL = 0x00000081
PASS: FIFO_MODE = 0x00000002
PASS: CTRL = 0x00000080

=== Step 4: PCI verifies the 3 RO alias reads via DMEM ===
PASS: DMEM[0] (GPU_STATUS) = 0x00000000
PASS: DMEM[1] (FIFO_STATUS) = 0x00000004
PASS: DMEM[2] (CYCLE_COUNT) = 0x00000000

ALL TESTS PASSED  (10/10 alias slots coherent)
```

The 93-cycle halt time matches a hand-trace: 23 instructions × 4
cycles/instruction (FGMT) + ~1 cycle per thread for halt detection
to propagate to `all_halted`.

### 9.2 `tb_arm_ids_orchestrator.v`

```
# Test 1: single-packet end-to-end orchestration
  PASS: FIFO[10] = 0x41b041b041b041b0
  PASS: FIFO[11] = 0x41b041b041b041b0

# Test 2: 5-packet stress (auto-clear, mode flip)
  --- iteration 0 ---  PASS  (0x41b041b041b041b0, 0x41b041b041b041b0)
  --- iteration 1 ---  PASS  (0x41b041b041b041b0, 0x41b041b041b041b0)
  --- iteration 2 ---  PASS  (0x41b041b041b041b0, 0x41b041b041b041b0)
  --- iteration 3 ---  PASS  (0x41b041b041b041b0, 0x41b041b041b041b0)
  --- iteration 4 ---  PASS  (0x41b041b041b041b0, 0x41b041b041b041b0)

ALL TESTS PASSED
```

`0x41B0` is BF16 22.0; the BCAST kernel replicates each output across
all 4 lanes, hence the 4×0x41B0 packing. Reference output verified
independently by `tb_ids_bcast.v`. Total sim wall time 340 µs
(`$finish` at 340 225 000 ps).

Each iteration self-poisons its FIFO[10..11] with `0xDEADBEEFCAFEF00D`
before injecting the next packet, so a stale match from the previous
iteration cannot pass spuriously.

### 9.3 Regression sweep

| Testbench | Result | Notes |
|-----------|--------|-------|
| `tb_arm_reg_access` | 10/10 PASS | new in §5.1 |
| `tb_arm_ids_orchestrator` | 6/6 PASS | new in §5.2 (1 single + 5 stress) |
| `tb_cpu_fifo` | ALL PASS | 21-cycle halt unchanged |
| `tb_gpu_integration` | ALL PASS | 5-cycle GPU + DMA round-trip unchanged |
| `tb_ids_inference` | 26/26 PASS | scalar baseline unchanged |
| `tb_ids_bcast` | 26/26 PASS | BCAST 732-cycle baseline unchanged |

## 10. Lessons learned during implementation

These didn't appear in the §3 plan — they only surface when you
actually wire the design up.

1. **`convertible_fifo` Port-B mode dependency.** When the FIFO is in
   mode 0 (passthrough), Port B's address is hard-wired to the FIFO's
   internal `rd_ptr`, *not* the wrapper's `proc_addr`
   (`src/fifo/convertible_fifo.v:115-128`). PCI BRAM reads in mode 0
   therefore return whatever the FIFO read pointer happens to point at
   (typically `BRAM[0]` = packet header), not the address in
   `LAB8_BRAM_ADDR`. The orchestrator testbench's `fifo_bram_read`
   wraps each access in a brief mode-2 window so PCI's `proc_addr`
   actually reaches the BRAM. This is a sim-side helper only; the
   orchestrator itself never reads BRAM via PCI, so production code is
   unaffected.
2. **Polling races the orchestrator.** First version of
   `tb_arm_ids_orchestrator.v` polled `FIFO[10]` every 200 cycles
   while waiting for the response. Each poll flipped `FIFO_MODE` (per
   lesson #1) — and the orchestrator's own `FIFO_MODE` writes raced
   that, intermittently leaving the mode at the wrong value when DMA
   was supposed to start. Result: pseudo-random pass/fail (iterations
   1 and 3 passed, 0/2/4 failed). Switched to a flat 5000-cycle wait
   per iteration; 5/5 PASS. Real hardware won't have this problem
   because the host won't be reading BRAM mid-iteration in the
   production flow.
3. **`MOV r1, #imm` in this ARM core does zero-extend the imm to 64
   bits**, so `STR r1, [r0, #X]` writes the full 64-bit word to the
   alias bus. The wrapper takes `cpu_reg_wdata[31:0]`, so the upper
   half is harmlessly discarded. Verified by `tb_arm_reg_access` —
   patterns like `0x42`, `0x53`, etc. round-trip cleanly.
4. **Branch encoding.** The ARM ID stage uses `branch_target = ifid_pc
   + 4 + sign_extend(offset24) << 2` (`src/arm/ID.v:130`). `ifid_pc`
   is `pc_plus4_out` (= current_inst_addr + 4), so the equation
   simplifies to standard ARMv4 `target = current_addr + 8 + offset*4`.
   All four loops (`wait_pkt`, `wait_dma_in`, `wait_kernel`,
   `wait_dma_out`) and the final `B wait_pkt` use this convention.
5. **FGMT halt behavior.** When T1–T3 hit HALT at their first
   instruction, `IF_stage.v:51` stops advancing `pc[tid]` for halted
   threads, so they re-fetch the same HALT every cycle indefinitely.
   No side effects (the HALT instruction has `WMemEn=0`, etc.). T0
   then runs at one instruction every 4 cycles — fast enough that the
   GPU kernel (~750 cycles per inference) is still the throughput
   bottleneck.

---

## 11. File index

Modified:
- `src/arm/data_mem.v` — register-alias decode, 4 new ports, `was_reg` flop, `reg_alias_rdata_r` pipeline reg
- `src/arm/processor.v` — pass-through ports for the alias bus
- `src/lab8_wrapper.v` — `cpu_reg_*` wires + `u_cpu` ports + read mux + write else-if + `reg_ctrl[0]` auto-clear

New:
- `tb/tb_arm_reg_access.v` — alias-window unit test (§5.1)
- `tb/tb_arm_ids_orchestrator.v` — full-stack integration (§5.2)
- `programs/arm/ids_orchestrator.hex` — 385-line hex (40 orch instr at T0 + HALT padding through T3 entry at idx 384). Materialized 2026-04-18. See §13 for the DMA-length fix (idx 10) applied after first silicon bring-up.
- `scripts/send_ids.py` — added `--replicated` flag (2026-04-18, §13.2): emits 11 one-feature-per-word packets at BRAM[7..17] (88-byte payload) to match the BCAST kernel's DMEM[0..10] layout convention. Default behavior (3 packed words at BRAM[7..9]) is unchanged and still drives `lab10reg.py ids_batch_packets`.

Pending (blocking hardware bring-up completion — see §13.3):
- `programs/arm/ids_orchestrator.asm` — source for the ARM toolchain (not yet written; hex is hand-assembled)
- Response-packet egress path on-chip (drain trigger + header fixup). Planned as the §13.3 follow-up refinement. The hex above gets results into GPU DMEM[126..127] + FIFO[10..11] correctly; what's missing is transmitting them back out the NF2 output queue to the sender.

Unchanged:
- GPU (all of `src/gpu/`)
- FIFO BRAM, convertible FIFO
- DMA engine inside `lab8_wrapper.v`
- All GPU kernels under `programs/gpu/`
- All other testbenches

## 12. References

- `docs/milestone3_refinements.md` — milestone 3 (Fix 1) baseline; §9 used to live there and now redirects here.
- `docs/bcast_instruction_design.md` — BCAST instruction added in milestone 2; the orchestrator drives the BCAST IDS kernel.
- `docs/final_project_demo_video/final_project_expert_demo_plan.md` §2.3, §5 Track A, §7.2 — why ARM orchestration matters for the live DDoS demo and the throughput story.
- `src/fifo/convertible_fifo.v:115-128` — Port-B mode dependency that lesson §10.1 documents.
- `src/arm/ID.v:130` — branch-target equation referenced in §8.2.
- `src/arm/IF_stage.v:51` — halt-stops-PC behavior referenced in §10.5.

---

## 13. Hardware Bring-Up Findings and Fixes (2026-04-18)

Sim (§9.2) passed 6/6 before the bitfile was built. First silicon bring-up on team-6's NetFPGA exposed two gaps that the simulation path never exercised: a packet-layout contract between the sender and the BCAST kernel, and the absence of a response-packet egress path on-chip. This section captures what happened and how it was (partially) closed.

### 13.1 Bring-up sequence and the first broken flow

The hex listing from §8.2 was materialized as `programs/arm/ids_orchestrator.hex` (385 lines: 40 orchestrator instructions at idx 0–39 + HALT padding through idx 384 so T1/T2/T3 halt at their start slots). The current bitfile `synth/nf2_top_par.bit` (timing-closed Fix 1 + alias-window RTL; post-synth 2026-04-18 01:41 local) was deployed to team-6's NetFPGA and the flow from §4.3 attempted:

```
python lab10reg.py ids_load ann_ids_11_16_8_2_bcast.hex data_ids_11_16_8_2_bcast.hex
python lab9reg.py cpu_load_imem ids_orchestrator.hex
python lab9reg.py cpu_start
# node1: python send_ids.py --csv test_features.csv --delay 0.01
```

Observations:
1. `cpu_start` sets `FIFO_MODE=1` as a side-effect (it's shared with the old Lab 8 "CPU mode" path where ARM drives Port B directly). Mode 1 disconnects Port-B from the NF2 ingress pipeline, so no packets reached the FIFO. Fixable from the host side with `python lab9reg.py mode 0` + `python lab9reg.py reset` after `cpu_start`, but it's a foot-gun worth remembering. A future `cmd_cpu_start_orchestrator` wrapper could hide this.
2. Once capture was re-enabled, `status` polls consistently read `pkt_ready=0`. Initially read as "ARM blocking capture." It was actually the ARM processing and soft-resetting each packet in ~10 µs, far shorter than the ~1 ms Python poll interval, so the host never saw the transient `pkt_ready=1` window.
3. No response packet ever came back to node1. That's the §13.3 egress gap.

### 13.2 Fix A (applied 2026-04-18) — packet-layout mismatch

**Symptom.** After running the full orchestrator path on hardware and halting the ARM, `GPU DMEM[126..127]` showed `0x4181_4181_4181_4181` in both words (BF16 ≈ 16.125). The data file's pre-loaded value at those addresses is zero, so the BCAST kernel **did** run and write results. But:

- For an all-1.0 input the tb_ids_bcast reference is `0x41B0` (22.0).
- For the attack sample that node1 actually sent, the PCI-flow reference gives distinct per-class logits.

Getting the same value for both output logits, close to but not matching the all-1.0 reference, is the signature of a kernel running on partially-garbage inputs.

**Root cause.** Two input-layout conventions for the BCAST kernel coexisted, and the orchestrator was written to one while the kernel was built for the other:

| Path | Layout at GPU DMEM[0..10] |
|------|---------------------------|
| Kernel's baked-in default (`data_ids_11_16_8_2_bcast.hex` lines 1–11) | 11 words; each word = `0x3F80_3F80_3F80_3F80` — one BF16 1.0 replicated across all 4 SIMD lanes. |
| PCI flow (`lab10reg.py ids_load_inputs`, lines 206–223) | 11 writes; each DMEM[i] = the i-th feature replicated 4× across lanes. Matches the baked-in convention. |
| Network packet (`send_ids.py`) | Historically 3 packed words at BRAM[7..9], 4 distinct BF16 values per word. The PCI flow then **unpacks** these (`lab10reg.py:530-534`) back into the replicated DMEM convention before running the kernel. |
| ARM orchestrator DMA (as originally designed in §4.2 / §8.2) | 3 words DMA'd straight from BRAM[7..9] → DMEM[0..2], no unpack. DMEM[3..10] untouched, retaining pre-loaded `0x3F80...` from `data_ids_11_16_8_2_bcast.hex`. |

The kernel reads DMEM[0..10] one at a time and BCASTs lane-0 of each — so the orchestrator's direct DMA fed it 3 wrong values (lane-0 of the packed words) plus 8 stale `1.0`s. Close to but not the all-ones reference → `0x4181` ≠ `0x41B0`.

**Why sim didn't catch it.** `tb_arm_ids_orchestrator.v` injected a crafted packet whose three feature words were `64'h3F80_3F80_3F80_3F80` — identical across all 4 lanes. That degenerate choice satisfies **both** layout conventions (lane-0 BCAST = any-lane BCAST when all lanes are equal), so sim passed while the layouts were silently inconsistent. The sim also read `FIFO[10..11]` via PCI to verify output, not over the network, so the §13.3 egress gap was invisible too.

**Fix.** Adopt the replicated layout across the ARM orchestrator path. Specifically:

1. **`programs/arm/ids_orchestrator.hex` idx 10**: `e3a01003` → `e3a0100b` (`MOV r1, #3` → `MOV r1, #11`). DMA length becomes 11 words instead of 3. Every other instruction is unchanged — `DMA_FIFO_ADDR=7` and `DMA_GPU_ADDR=0` already point at the right spots.
2. **`tb/tb_arm_ids_orchestrator.v`**: match the hex (`orch[10]`), grow `PKT_HEADER` word_length from `0x000A` → `0x0012` (10 → 18), extend `inject_packet_1p0` from 3 to 11 `FEAT_1P0` writes. Sim crafted packet remains degenerate (all lanes = 1.0), so the PASS criterion `FIFO[10..11] = 0x41B0...` stands.
3. **`scripts/send_ids.py` `--replicated` flag**: new `pack_features_replicated()` emits 11 eight-byte words, each being one BF16 feature repeated 4× across the 64-bit lane packing. Default behavior (3 packed words at BRAM[7..9], PCI-flow compatible) is unchanged so the existing `lab10reg.py ids_batch_packets` regression path keeps working. The flag is documented in §4.3 below.
4. **`docs/arm_orchestrator.md` §4.2 / §5.2 / §8.2 / §11**: updated inline to show DMA_LENGTH=11, 18-NF2-word packet, 11 replicated features at BRAM[7..17].

**No RTL change, no re-synthesis.** The currently-deployed `synth/nf2_top_par.bit` (which already includes the alias-window RTL) still covers this fix — Fix A is purely a `.hex` + host-side Python change. The `synth/milestone3_fix1_2026-04-17/` backup predates the alias window and would *not* support the orchestrator at all; it is retained only as a revert target for the Fix 1 GPU timing work.

### 13.2.1 Fix A residual — FIFO FSM silently drops the last data word

First Fix A verification on silicon did *not* produce the expected `0x41B0` for all-1.0 input — instead it produced `0x41A0` (= 20.0), off by exactly 2.0 from the reference 22.0. Per the BCAST kernel's uniform-0.25-weight compute, each input x_i contributes exactly 2.0 to the output, so this pattern meant *exactly one* of DMEM[0..10] was reading as 0 instead of 1.0.

**Diagnostic.** A PCI-driven DMA (identical config to the orchestrator: `DMA_FIFO_ADDR=7`, `DMA_GPU_ADDR=0`, `DMA_LENGTH=11`) with all-1.0 packet in place showed:

```
GPU DMEM[0..9]  = 0x3f803f80_3f803f80  (correct — packet 1.0 replicated)
GPU DMEM[10]    = 0x00000000_00000000  (zero, pre-loaded 1.0 was clobbered)
```

`GPU DMEM[10]` pre-DMA was `0x3F80...` (from `cmd_ids_load`). Post-DMA it is zero — meaning the DMA *did* fire a write to DMEM[10], it just wrote zero instead of the `0x3F80...` sitting at BRAM[17]. So the DMA engine isn't off-by-one; it's copying BRAM[17] faithfully and BRAM[17] happens to be zero.

**Root cause.** The NF2 `status` register reported `tail=17, pkt_word_cnt=17` for this packet. `tail=17` means `wr_ptr` inside the convertible_fifo stopped at 17, i.e. only **16 data words** ever committed (1 header at BRAM[0] + 16 data writes take `wr_ptr` from 0 to 17). BRAM[17] was never written. The 17th data word of the Ethernet frame — which carries the 11th feature — was dropped on the floor.

The mismatch lives at `src/fifo/convertible_fifo.v:164`:

```verilog
words_remaining <= in_data[39:32] - 8'd1;   // pkt_len - 1 after header
```

The FSM treats the NF2 header's `word_length` field as **"total NF2 words including header"** (subtracts 1 to count the remaining *data* words). The real NF2 classifier on silicon instead writes `word_length = data-word count`. For a 136-byte frame / 17 data words the classifier stores 17, the FSM computes `words_remaining = 16`, and exits S_RECEIVING one word too early. BRAM[17] is stuck at its uninitialized/stale value (zero after a fresh fifo_reset).

**Why the packed PCI path never exposed this.** 80-byte packed packet → 10 data words → classifier reports 10 → FSM captures 9 → BRAM[1..9] written. Features live at BRAM[7..9] — all three land inside the captured range. The dropped 10th word was pure trailing padding; no observable effect.

**Why sim missed it.** `tb_arm_ids_orchestrator.v` injects the packet by calling `fifo_write` directly on the convertible_fifo's Port-A interface, which **bypasses the NF2 classifier entirely**. The TB writes its `PKT_HEADER` with `word_length = total-including-header` (18 for the Fix-A packet, per line 306), which is the same convention the FSM uses. So the TB and FSM agree internally, and the sim never sees the classifier's different convention. The mismatch is a silicon-exposed wiring issue between two components that are both individually correct-looking.

**Fix.** Append 8 zero bytes (one extra 8-byte NF2 word) to the UDP payload in `pack_features_replicated()`. Frame grows 136 → 144 bytes = 18 data NF2 words. Classifier reports 18. FSM computes `words_remaining = 17` and captures 17 data writes — BRAM[1..17], which covers the 11 features at BRAM[7..17]. The 18th data word (the zero trailer) lands at BRAM[18] and is the newly-sacrificial word, but we don't read it. No RTL change; pure host-side Python.

**This is not a permanent solution.** The real fix is to reconcile the classifier/FSM convention — either change the classifier to emit "total-including-header" or change the FSM line 164 to use `pkt_len` directly without the `-1`. Both are one-line RTL edits and would require re-synthesis. They'd also need audit of every other packet path in the design (the PCI flow's packed-packet handling, the drain FSM for response packets) to make sure nothing relies on the current behavior. Deferring this along with Fix B (§13.3) since the host-side workaround unblocks Fix A verification without touching silicon.

**Expected verification after Fix A (post-13.2.1)** (hardware, with Option-2 §13.3 still outstanding):
- `python lab9reg.py cpu_load_imem ids_orchestrator.hex` (new version)
- `python lab9reg.py cpu_start` + `mode 0` + `reset`
- `python send_ids.py --replicated` from node1
- `python lab9reg.py cpu_stop` on FPGA, `python lab9reg.py gpu_read_dmem 126 2`
- Expect BF16 logits at DMEM[126..127] that match what the PCI flow produces for the same input on the same BCAST weights. Still no network response (that's §13.3).

### 13.3 Fix B (planned — full on-chip round-trip)

**Gap.** Even with Fix A making inference correct, the orchestrator has no way to transmit a response packet back to the sender. Two distinct problems:

1. **Soft-reset ≠ drain.** Instruction 38 writes `FIFO_CTRL=1`, which strobes `reg_ctrl[0]` → the convertible_fifo's `.reset()` pin (`src/lab8_wrapper.v:304`). That wipes the FIFO state (pointers, `pkt_ready`) without transmitting. The actual egress trigger is `reg_fifo_drain[0]` → `.drain_start` (`src/lab8_wrapper.v:332`, `src/fifo/convertible_fifo.v:185`), which is **not currently mapped into the register-alias window**. The ARM has no way to drain.
2. **No header fixup.** Even if a drain happened, the NF2.1 header in BRAM[0] still says `dst_port=0x0002` (CPU0 — the FPGA's host interface) from the inbound packet. The response would route to the host, not back to node1. The PCI flow does this fixup in `lab10reg.py:_form_and_drain_response` (lines 846–930): MAC swap (BRAM[1..2]), IP swap (BRAM[4..5]), UDP port swap (BRAM[5]), UDP checksum zero (BRAM[6]), result write (BRAM[bram_start]), NF2.1 header `dst_port=0x0001, src_port=0x0002` (BRAM[0]). ~50 lines of byte-level munging in Python.

**Why sim missed it.** `tb_arm_ids_orchestrator.v §5.2` verifies by PCI BRAM read of FIFO[10..11] after a fixed cycle budget. It never tries to send the packet out. Network egress is silicon-only functionality from the sim's perspective.

**Planned RTL change (minimal).** Add `reg_fifo_drain` to the alias window as a new RW slot. Options:

| Alias slot | Wrapper register | RW | Purpose |
|------------|------------------|----|---------|
| `0xFA` | `reg_fifo_drain` | RW | New: bit[0]=drain trigger (auto-clear, same pattern as DMA_CTRL / CTRL) |

Slot `0xFA` is currently reserved (see §3.2), so this doesn't re-use a load-bearing slot and keeps PCI access unchanged. Add one `case` arm in the combinational read mux and one arm in the write-path `else if (cpu_reg_we)` block of `src/lab8_wrapper.v`. `reg_fifo_drain` already has an auto-clear strobe at line 634. Estimated 10 LoC total.

**Planned ARM program extension (~50 instr).** Extend the orchestrator at instructions 35–38 (before the soft-reset/loop) to:

1. Read BRAM[0], swap NF2.1 `dst_port` / `src_port` fields (2 LDR + ~6 bit-shift + STR).
2. Read BRAM[1..2], swap 6-byte MAC addresses (this is the gnarly one — needs byte-level masking since the ARM ISA has no `REV` or byte-permute; do it with shifts + ORs, ~15 instr).
3. Read BRAM[4..5], swap IP and UDP-port fields (similar shape, ~10 instr).
4. Zero BRAM[6]'s UDP checksum (STR 0; ~3 instr).
5. Write the two-word result (logits + prediction) into BRAM[bram_start..+3], zero the trailer slots (~8 instr).
6. Write `FIFO_MODE=0`, write `FIFO_DRAIN=1` to the new alias slot 0xFA. Wait for pkt_ready to clear (readback poll on FIFO_STATUS). **Then** do soft-reset.

All of this still fits in the 128-instruction-per-thread budget (T0 would land at ~90 instructions). Hand-assembly is realistic but is the point where it's probably worth investing in an assembler pass so it's maintainable.

**Re-synth required.** Adding an alias slot touches `src/lab8_wrapper.v` which is in the synthesis netlist. Timing impact is minimal — the combinational read mux grows by one arm (LUT level unchanged at 4 inputs), and the write-path case statement grows by one arm (also unchanged). Expected timing delta: ±50 endpoints vs. Fix 1 baseline.

**Ordering.** Do Fix A verification first (confirms the GPU inference result ends up correct in DMEM[126..127] on silicon). Then do Fix B in one batch: RTL change + new hand-assembled orchestrator + new testbench that actually asserts on network egress. The user has indicated this work is queued for a later session.

### 13.3.1 As-built (2026-04-20) — Fix B implementation log

RTL, hex, and TB all landed in one session. Sim (iverilog) passes end-to-end; silicon verification queued for the next Fedora-VM re-synth.

**Files actually changed:**

| File | Status | What changed |
|------|--------|--------------|
| `src/lab8_wrapper.v` | modified | (a) Added alias slot `0xA` (read mux + write case) for `reg_fifo_drain` — enables ARM drain trigger. (b) `fifo_proc_din` ternary forces `ctrl=0xFF` when `cpu_drives_proc` writes to BRAM[0] (`cpu_ext_mem_addr[6:0] == 7'h00`), so ARM-side NF2 header rewrites keep the header marker. |
| `programs/arm/ids_orchestrator.hex` | rewritten | 40 → 117 T0 instructions. Adds mask setup at idx 0..10 (six 64-bit byte-pair masks in `r9..r14`), MAC swap at idx 47..65, IP+UDP port swap at idx 66..93, UDP-cksum zero at idx 94..95, NF2 header fixup at idx 96..108, drain at idx 109..116. Padding through idx 384 unchanged. Same hand-assembled style; no assembler yet. |
| `tb/tb_arm_ids_orchestrator.v` | rewritten | (a) Loads full 385-line orch hex via `$readmemh` instead of inline array. (b) Crafts a packet with realistic Eth/IP/UDP headers at BRAM[1..6] (DstMAC=broadcast, SrcMAC=AA:BB:CC:DD:EE:FF, SrcIP=10.0.4.2, DstIP=10.0.7.255, UDP ports 0x1111/0x270F). (c) Passive `always @(posedge clk)` capture of the `out_data/out_ctrl/out_wr` stream into a 32-deep buffer. (d) Replaced PCI BRAM read verification with word-by-word egress asserts (`check_word` task). |

No toolchain or other source files touched; GPU, DMA engine, FIFO, reg-ring infrastructure unchanged.

**Alias slot 0xA assignment** — extends §3.2 table:

| ARM alias | Wrapper register | R/W from ARM | Semantics |
|-----------|------------------|--------------|-----------|
| `0xFA` | `reg_fifo_drain` | RW | bit[0]=drain trigger (auto-clear; strobes `convertible_fifo.drain_start`) |

Slot `0xFA` was marked reserved in §3.2 table (2026-04-18 plan), so the addition is purely additive — PCI `LAB8_FIFO_DRAIN` access unchanged, existing scripts unaffected.

**ARM register allocation** (single thread, T0 only):

```text
r0  = 0xF0                         alias-window base pointer
r1  = scratch (poll value, imm)
r3  = 0x80                         FIFO BRAM window base pointer
r4, r5  = loaded BRAM words (b1/b2, b4/b5, or header)
r6, r7, r8  = intermediate shifted/masked values
r9  = m_h32 = 0xFFFF_FFFF_0000_0000    (upper 32 bits)
r10 = m_b01 = 0xFFFF_0000_0000_0000    (bytes 0..1)
r11 = m_b23 = 0x0000_FFFF_0000_0000    (bytes 2..3)
r12 = m_b45 = 0x0000_0000_FFFF_0000    (bytes 4..5)
r13 = m_b67 = 0x0000_0000_0000_FFFF    (bytes 6..7)
r14 = m_mid = 0x0000_FFFF_FFFF_0000    (bytes 2..5; used by MAC swap)
```

Six 64-bit byte-pair masks are built at startup (idx 0..10, 11 instructions) by chaining `MVN` + `LSR`/`LSL #16`s. Required because ARM v4 immediate shifts are capped at 5 bits (0..31 bit range), so any mask wider than 16 bits or positioned above bit 31 has to be constructed via sequential shifts rather than in a single rotated immediate.

**Swap math** (each new word is a 4-way OR of byte-aligned pieces, each masked to its target byte range so the other bytes stay zero before OR-ing):

```text
MAC swap (BRAM[1..2]):
  new_b1 = (b1 << 48)               & m_b01   // Src0..1 from b1[15:0]
         | ((b2 >> 16) & m_mid)               // Src2..5 from b2[63:32] repositioned
         | ((b1 >> 48))                        // Dst0..1 from b1[63:48]
  new_b2 = ((b1 << 16) & m_h32)              // Dst2..5 from b1[47:16]
         | (b2 & ~m_h32)                       // EtherType+IPverIHL+TOS unchanged

IP+UDP port swap (BRAM[4..5]):
  new_b4 = (b4 & m_b01)                       // IPcksum unchanged
         | ((b4 << 32) & m_b23)               // DstIP[0..1] from b4[15:0]
         | ((b5 >> 32) & m_b45)               // DstIP[2..3] from b5[63:48]
         | ((b4 >> 32) & m_b67)               // SrcIP[0..1] from b4[47:32]
  new_b5 = ((b4 << 32) & m_b01)               // SrcIP[2..3] from b4[31:16]
         | ((b5 << 16) & m_b23)               // UDPdst from b5[31:16]
         | ((b5 >> 16) & m_b45)               // UDPsrc from b5[47:32]
         | (b5 & m_b67)                       // UDPlen unchanged
```

Each 48-bit shift in the code is chained LSL/LSR #16 × 3 (since `shift_amt` is only 5 bits). IP checksum is intentionally preserved — swapping IP src/dst doesn't change the 16-bit one's-complement sum, so no recompute needed.

**NF2 header fixup** (idx 96..108, 13 instructions): read old header, mask out word_length and byte_length (preserved), build new dst_port=0x0001 and src_port=0x0002 at their byte positions via `MOV #1` / `MOV #2` + three LSL #16s, OR everything together, store to BRAM[0]. The wrapper change forces ctrl=0xFF on this write so the drained frame starts with a valid NF2 header marker.

**Drain sequence** (idx 109..116): FIFO_MODE=0 via alias 7, FIFO_DRAIN=1 via alias 0xA (new slot), poll FIFO_STATUS until pkt_ready clears, `B wait_pkt` (offset −107 words; encoded `EAFFFF95`). Total loop length = 106 instructions, fits the 128-word-per-thread budget with 11 slots spare.

### 13.3.2 Sim results (2026-04-20)

```
# Test 1: single-packet end-to-end egress
  Captured 18 egress words (expect 18)
  PASS: word[ 0] (NF2 header)            ctrl=0xff data=0x0001_0012_0002_0090
  PASS: word[ 1] (Eth1 MAC swap)          ctrl=0x00 data=0xAABB_CCDD_EEFF_FFFF
  PASS: word[ 2] (Eth2 MAC swap)          ctrl=0x00 data=0xFFFF_FFFF_0800_4500
  PASS: word[ 3] (IP hdr1 unchanged)      ctrl=0x00 data=0x0082_ABCD_0000_4011
  PASS: word[ 4] (IP hdr2 + IP swap)      ctrl=0x00 data=0x1234_0A00_07FF_0A00
  PASS: word[ 5] (UDP hdr + port swap)    ctrl=0x00 data=0x0402_270F_1111_006E
  PASS: word[ 6] (UDP cksum + pad zero)   ctrl=0x00 data=0x0000_0000_0000_0000
  PASS: word[ 7] (logit0 replicated)      ctrl=0x00 data=0x41B0_41B0_41B0_41B0
  PASS: word[ 8] (logit1 replicated)      ctrl=0x00 data=0x41B0_41B0_41B0_41B0
  PASS: word[ 9] (residual feature)       ctrl=0x00 data=0x3F80_3F80_3F80_3F80
  PASS: word[17] (residual feature)       ctrl=0x00 data=0x3F80_3F80_3F80_3F80

# Test 2: 3-packet stress (auto-clear, mode flips, back-to-back)
  iter 0: PASS (header/MAC/logits)
  iter 1: PASS (header/MAC/logits)
  iter 2: PASS (header/MAC/logits)

ALL TESTS PASSED
```

Regression sweep (all previously-passing TBs, verified 2026-04-20):

| Testbench | Result | Notes |
|-----------|--------|-------|
| `tb_arm_reg_access` | 10/10 PASS | Fix B RTL doesn't change existing alias slots |
| `tb_arm_ids_orchestrator` | Test 1 + Test 2 PASS | Fix B egress verified |
| `tb_cpu_fifo` | ALL PASS | ARM-writes-BRAM[0] ctrl=0xFF force doesn't affect CPU-FIFO mode 1 test (which doesn't write BRAM[0]) |
| `tb_gpu_integration` | ALL PASS | DMA-only path unaffected |
| `tb_ids_inference` | 26/26 PASS | Scalar kernel unchanged |
| `tb_ids_bcast` | 26/26 PASS | BCAST kernel unchanged |

**Residual feature tail (words 9..17):** The original ingress feature words at BRAM[9..17] are left untouched by the orchestrator. They drain as part of the 18-word response frame (pkt_len is fixed at ingest, §10.2). Receivers only care about words 7..8 (the logits) and the Eth/IP/UDP headers at words 1..6, so this is acceptable. An alternative would be to also zero BRAM[9..17] in the orchestrator at ~18 instructions of cost; skipped for now since the 11-instruction savings matter more than a zero-padded response tail.

### 13.3.3 Deviations from the §13.3 plan

1. **Extra RTL change for BRAM[0] ctrl byte.** The §13.3 plan listed "one alias slot + ~10 LoC wrapper changes". In sim the orchestrator immediately hit the ctrl-byte issue: when ARM in mode 1 writes to BRAM[0], `fifo_proc_din = {8'h00, ...}` hard-coded the ctrl nibble to zero, so the drained first word came out with `out_ctrl=0x00` instead of `0xFF` and the downstream NF2 output queue would not recognize it as a header. Added a one-line ternary in `fifo_proc_din` (line 339) that forces ctrl=0xFF when `cpu_ext_mem_addr[6:0] == 7'h00`. Non-invasive to all other code paths (PCI BRAM writes, DMA writes, ARM non-BRAM[0] writes). Could have been avoided with a different response-packet layout that never touches BRAM[0], but at the cost of missing the on-chip `dst_port=MAC0` fixup that makes the demo narrative land.

2. **Response payload at BRAM[7..8] not BRAM[7] (compared to PCI's `_form_and_drain_response`).** Python packs `{logit0, logit1, pred, 0}` into a single 8-byte word at BRAM[7]. The ARM orchestrator instead emits the two raw BCAST kernel outputs (4× replicated BF16 values each) at BRAM[7..8] via a straight DMA — no per-logit extraction, no argmax. Saves ~11 instructions (no shift/OR for the logit-pair construct) and no ARM-side BF16 compare. Node1's receiver picks up lane 0 of each word (`out[7][63:48]=logit0`, `out[8][63:48]=logit1`), computes argmax in Python. Documented in the hex header comment.

3. **Residual feature tail.** §13.3 plan §5 item said "Write the two-word result (logits + prediction) into BRAM[bram_start..+3], zero the trailer slots (~8 instr)." We ended up with `~2 instr` for that (just the UDP cksum zero at BRAM[6]) — BRAM[9..17] tail not zeroed. See the note above.

4. **Instruction count is 117, not ~90.** The mask-based byte-swap idiom came in at the predicted cost (MAC 19, IP/UDP 28, header 13) but setup (11 instr) was underestimated. Still comfortably under the 128-word budget.

### 13.3.4 Hardware verification (2026-04-21) — orchestrator works; response delivery blocked

After the Apr 20 21:13 timing-closed Fix B bitfile (md5 `aa680d9f...`) was deployed on team-6 FPGA, two findings from bring-up:

**Finding 1 — Fix B orchestrator BRAM rewrite is silicon-verified correct.**

Via `lab10reg.py ids_arm_debug_once 116` (patches `B wait_pkt` at IMEM[116] with HALT → ARM halts after processing exactly one packet; then dumps FIFO/CPU/GPU/DMA status, LA, and BRAM[0..17]):

```
BRAM[ 0]: ctrl=0xff data=0x00010012_00020090   <- dst=MAC0, word_len=0x12, src=CPU0, byte_len=0x90
BRAM[ 1]: ctrl=0x00 data=0xa0369f0a_0eb3ffff   <- DstMAC=a0:36:9f:0a:0e:b3 (was SrcMAC), +SrcMAC[0..1]=ff:ff
BRAM[ 2]: ctrl=0x00 data=0xffffffff_08004500   <- SrcMAC[2..5]=ff:ff:ff:ff + EtherType+IPverIHL+TOS
BRAM[ 3]: ctrl=0x00 data=0x00820000_40004011   <- IP length/ID/flags/TTL/proto (unchanged)
BRAM[ 4]: ctrl=0x00 data=0x1a6a0a00_07ff0a00   <- IPcksum + DstIP=10.0.7.255 (was SrcIP) + SrcIP[0..1]=10.0
BRAM[ 5]: ctrl=0x00 data=0x0403270f_9f5f006e   <- SrcIP[2..3]=04:03 + UDPdst=0x270f + UDPsrc=0x9f5f + UDPlen
BRAM[ 6]: ctrl=0x00 data=0x00000000_00000000   <- UDP cksum zeroed + payload bytes 0..5 zeroed
BRAM[ 7]: ctrl=0x00 data=0x3fa83fa8_3fa83fa8   <- BF16 logit0 replicated 4x (DMA out from GPU DMEM[126])
BRAM[ 8]: ctrl=0x00 data=0x3fa83fa8_3fa83fa8   <- BF16 logit1 replicated 4x (DMA out from GPU DMEM[127])
BRAM[ 9..17]                                    <- residual ingress feature payload (not zeroed)
```

`FIFO_STATUS` post-halt: `pkt_ready=0, empty=1, full=0` — drain completed; all 18 NF2 words were emitted into the downstream NF2.1 output stream.

Every rewrite matches the Fix B §13.3 plan exactly. The on-chip round-trip architecture works.

**Finding 2 — Response packets don't reach node1 in EITHER PCI or ARM mode.**

Setup: `lab10reg.py ids_pci_throughput 3` on nf6, `send_ids.py --csv test_features.csv --count 3 --delay 2.0 --replicated --listen` on node1. nf6 reports `Serviced: 3 of 3 packets`; node1 reports `Received: 0 responses`. Same in ARM mode (`ids_arm_start` + `send_ids.py --listen`).

This is **not** a Fix B–specific bug. It affects both PCI's `_form_and_drain_response` (lab10reg.py) and the Fix B ARM orchestrator, because both paths produce the same egress header after swap:

- `SrcMAC = ff:ff:ff:ff:ff:ff` ← was ingress DstMAC (node1 sent to broadcast `10.0.7.255`, which resolves to broadcast MAC)
- `SrcIP = 10.0.7.255` ← was ingress DstIP (same broadcast)

Both are invalid for a unicast response. Linux RPF (`net.ipv4.conf.all.rp_filter=1` default) silently drops unicast frames with broadcast SrcIP. Some stacks also flag broadcast SrcMAC as "martian" and drop.

Milestone 1 (2026-04-06) never caught this because its 75%-accuracy evaluation used `cmd_ids_batch_packets` on nf6 with `send_response=True` — "20/20" counted packets *processed on nf6*, not responses *received on node1*. Processed ≠ delivered.

**Next steps (for a future session):**

1. **Wire-level verification:** `tcpdump -i <iface> -nne udp port 9998` on node1 while running either PCI or ARM test.
   - If tcpdump sees frames → kernel filter drops (RPF/martian). Either `sudo sysctl -w net.ipv4.conf.all.rp_filter=0` on node1 (quick hack), or implement a header fix (next step).
   - If tcpdump sees nothing → MAC0 TX not reaching node1 (cabling, MAC TX silicon issue, or `output_queues` dst_port routing off). Separate investigation.

2. **Permanent fix** (if RPF is the culprit): replace the swap in both paths with a header rewrite that uses valid source addresses:
   - `SrcMAC` ← hardcoded FPGA MAC (read from bitfile's nominal MAC0 register, or use a locally-administered value like `02:00:00:00:00:01`)
   - `SrcIP` ← hardcoded FPGA IP (a real IP in node1's subnet, e.g., `10.0.7.2`)
   - `DstMAC` / `DstIP` ← ingress SrcMAC / SrcIP (unchanged from current swap)
   - IP checksum → set to 0 (most stacks accept) or recompute (add ~15 ARM instructions)

   Effort: ~10 LoC in `_form_and_drain_response` (lab10reg.py ~line 884); ~20 ARM instructions inserted into `ids_orchestrator.hex` between the existing swap and drain.

3. **Once delivery works:** re-run `ids_pci_throughput 50` vs `ids_arm_start` + `send_ids.py --count 50 --delay 0 --listen`. Expected demo slide numbers: PCI ≈ 0.65 pps, ARM ≈ hundreds to thousands of pps.

### 13.4 Doc hygiene

- §4.2, §5.2, §8.1, §8.2, §11 were updated inline to reflect the current orchestrator layout (DMA_LENGTH=11, 18-word packet, 11-feature replicated layout, `ids_orchestrator.hex` as materialized).
- §13 is the narrative-of-record for *why* those numbers changed. Keep §4.2/§8.2 correct going forward; document further changes here when they happen.
- §13.3.1/§13.3.2/§13.3.3 log Fix B as built (2026-04-20). §4.2 and §8.2 still show the 40-instruction Fix A orchestrator; the §13.3 subsections are the current source of truth for the 117-instruction Fix B orchestrator that now lives in `programs/arm/ids_orchestrator.hex`.
- `docs/milestone3_refinements.md` remains the home for non-orchestrator milestone 3 refinements (timing closure, Fix 1, etc.). Pointer in that doc's §9 references this document as the canonical source.
