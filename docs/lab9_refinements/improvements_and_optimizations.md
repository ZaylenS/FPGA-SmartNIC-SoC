# Lab 8 — Improvements & Optimizations

Post-synthesis improvements for Lab 8 Network Processor. Items are ordered by
priority (highest first). All changes should be implemented **after** the
current design is synthesized and hardware-tested.

Sources: lab spec (Section 2, bandwidth note), lecture add-ons (handwritten
notes), design analysis.

---

## Priority 1: Dual-Port GPU Bandwidth (Spec Recommendation)

**Source:** Lab spec Figure 2 bandwidth note.

> "If a single Block RAM is configured as a dual-port 256x72-bit memory, it
> can provide up to 128x144 bits per read clock cycle by reading 72 bits from
> one port at address N and 72 bits from the second port at address N+1,
> effectively doubling memory bandwidth."

**Current state:** Port A serves the FIFO pipeline (in/out), Port B serves
the processor (CPU/GPU/DMA). In GPU mode, only Port B feeds data — Port A is
idle.

**Proposed change:** In GPU mode, use **both** ports to feed GPU data:
- Port A reads address N, Port B reads address N+1 simultaneously
- GPU receives 128 bits (2 x 64-bit data) per cycle = 8 SIMD lanes per cycle
- Requires a wider DMA engine or direct GPU fetch path
- FIFO pipeline input must be stalled/disconnected during GPU mode (already
  true via mode register, but `in_rdy` gating should be re-applied)

**Impact:** 2x GPU memory bandwidth. Critical for SIMD tensor operations
where the GPU currently bottlenecks on single-port BRAM reads.

**Complexity:** Medium. Changes to: `convertible_fifo.v` (Port A mux for GPU
mode), `lab8_wrapper.v` (DMA engine or GPU fetch logic), possibly
`gpu_top.v` (wider data input).

---

## Priority 2: BRAM-Based Register File with Double Clock

**Source:** Lecture add-on.

**Concept:** Replace the FF-based register file (currently ~2,200 LUTs for
4 threads x 16 x 64-bit) with a BRAM, using a 2x clock to get enough
read/write ports per CPU cycle.

**How double-clock works:**
- Generate a 2x clock from the main clock using a DCM (Digital Clock Manager)
- The BRAM runs at 2x speed, so each CPU cycle gets 2 BRAM operations per port
- Port A: read Rs1 (first half), write Rd (second half)
- Port B: read Rs2 (first half), idle (second half)
- Both clocks are **synchronous** (derived from the same source via DCM),
  not asynchronous — no clock domain crossing issues

**BRAM addressing:** `{thread_id[1:0], reg_addr[3:0]}` = 6-bit address,
64 entries x 64-bit. Fits in one 18Kb BRAM (configured as 64 x 64).

**Resource savings:** ~2,200 LUTs freed from distributed RAM. VP50 synthesis
report shows 6 of 8 DCMs used — 2 DCMs available for 2x clock generation.

**Applies to:** Both ARM CPU register file and GPU register file.

**Complexity:** Medium. Need DCM instantiation, register file rewrite,
timing constraints for 2x clock domain.

---

## Priority 3: Behavioral to Structural Conversion

**Source:** Lecture add-on.

**Concept:** Convert key modules from behavioral Verilog (inferred
primitives) to structural Verilog (explicit primitive instantiation) for
more predictable synthesis results on ISE 10.1.

**Candidates for conversion:**
1. **FIFO BRAM** — Currently uses `reg [71:0] mem [0:255]` inference pattern.
   Could use explicit `RAMB16_S36_S36` or similar VP50 BRAM primitive for
   guaranteed dual-port behavior and known timing.
2. **Port MUXes** — The 3-way proc port mux (PCI/CPU/DMA) could use
   structural MUX primitives for cleaner routing.
3. **Multipliers** — GPU's `bf16_fma_unit.v` multiplier currently infers
   `mult18x18` blocks. Explicit `MULT18X18` instantiation guarantees
   placement.

**Not recommended for conversion:** Control logic, FSMs, pipeline registers
— behavioral is clearer and ISE handles these well.

**Impact:** More predictable timing closure, easier to meet timing
constraints on critical paths.

**Complexity:** Low-Medium per module. Can be done incrementally (point 6).

---

## Priority 4: Re-apply `in_rdy` Mode Gating (Bug #2 Fix) — DONE

**Status:** Applied in Phase 1 refinements and hardware verified (March 20, 2026).

**Source:** Batch 3 hardware debug.

The fix (`in_rdy` gated by `mode == 0`) prevents network packets from writing
into FIFO BRAM via Port A while the CPU/GPU is using Port B. Applied in
`convertible_fifo.v`. 9/9 HW tests pass.

---

## Priority 5: Application-Specific Simplification

**Source:** Lecture add-on.

**Concept:** Once the target application is chosen (likely image processing
for the final project), simplify the hardware to remove unused features:
- If only int16 image processing: remove BF16 ALU and FMA unit from GPU
  (saves significant slice count and simplifies critical path)
- If GPU not needed for a particular application: remove GPU entirely,
  use CPU-only mode
- Adjust FIFO depth, DMEM size, IMEM size based on actual program/data
  requirements

**Impact:** Potentially large resource savings. The BF16 FMA unit alone
accounts for significant slice usage and contains the critical path.

**Complexity:** Low (mostly deletion). But requires knowing the target
application first.

---

## Priority 6: Shared FIFO BRAM as Unified Scratchpad

**Source:** Lecture add-on (point 12: "scratch memory"), lab spec Figure 2.

**Concept:** Instead of separate CPU DMEM + GPU DMEM + FIFO BRAM, use the
FIFO BRAM as the single shared memory for all three:
- CPU LDR/STR directly accesses FIFO BRAM (already implemented for addr >= 128)
- GPU LD/ST directly accesses FIFO BRAM (replacing separate GPU DMEM)
- Eliminates DMA copy step entirely — GPU operates on data in-place

**Current state:** GPU has separate 1024 x 64-bit DMEM. DMA copies data
between FIFO BRAM and GPU DMEM. This works but wastes BRAMs and adds
latency.

**Trade-offs:**
- Saves 2+ BRAMs (GPU DMEM)
- Eliminates DMA latency
- But: GPU and CPU cannot access BRAM simultaneously (need arbitration)
- GPU address space limited to 256 entries (FIFO BRAM size) instead of 1024
- More complex port arbitration logic

**Complexity:** High. Requires GPU RTL changes (remove DMEM, reroute LD/ST
to external port), new arbitration logic, address mapping changes.

---

## Priority 7: Fix `all_halted` Detection — DONE

**Status:** Applied in Phase 1 refinements (H1) and hardware verified (March 20, 2026).

**Source:** Batch 5 hardware test (March 7, 2026).

PC halt gating applied in `IF_stage.v` — halted threads no longer advance PC.
`all_halted` (CPU_STATUS[31]=1) now asserts reliably. B. padding in IMEM no
longer needed. `cpu_test` passes without timeout.

---

## Priority 8: GPU Decode Stage Pipeline Split (Timing)

**Source:** Batch 5 timing report (`nf2_top_par.twr`).

**Current state:** 4816 setup timing violations on `core_clk_int` (125 MHz).
The worst critical path (16.670ns vs 8ns budget) is in the GPU **DECODE**
stage, not EXECUTE:

```
IMEM BRAM read → instruction decoder → register file read
  → signed branch comparison (64-bit) → PC update
Total: 5.374ns logic + 11.296ns routing (67.8% routing)
```

The EX1/EX2/EX3 pipeline (from Lab 7) already fixed the execute path. Adding
EX4 would NOT help — the bottleneck has moved to DECODE.

**Proposed fix:** Split DECODE into DECODE1 (fetch + decode) and DECODE2
(register read + branch resolve). This adds 1 stage of latency but breaks the
critical path.

**Trade-offs:**
- Fixes the worst timing path
- Increases branch penalty from 1 to 2 cycles
- Requires new hazard detection for the extra pipeline stage
- 67.8% of the delay is routing congestion — reducing design size (P5: remove
  BF16) would help more with less effort

**Complexity:** High. Requires GPU pipeline restructuring, new hazards, updated
stall logic.

---

## Priority 9: Mode-Switch Safety Guard

**Source:** Team design review (March 2026).

**Scenario:** If the host writes a new mode while the CPU or GPU is still
actively accessing FIFO BRAM, the proc port mux switches immediately. The
CPU/GPU continues executing but its memory operations silently miss BRAM.
For example, switching from mode=1 to mode=2 while the CPU is mid-transfer
causes `cpu_drives_proc` to drop (`(mode==1) && cpu_running` becomes false),
and any in-flight STR instructions write to nowhere. The GPU then receives
incomplete data in BRAM with no hardware warning.

**Current mitigation:** Software discipline. The `lab8reg` script enforces
the correct sequence: start -> poll done -> stop -> change mode. No
asynchronous events can change mode unexpectedly (mode is only written by
PCI register access from host software).

**Proposed hardware guard (optional):**
```verilog
// Refuse mode change while CPU or GPU is active
wire mode_locked = cpu_running || gpu_running || dma_active;
always @(posedge clk) begin
    if (reg_fifo_mode_wr && !mode_locked)
        reg_fifo_mode_r <= reg_fifo_mode_next;
end
```

Alternatively, changing mode could auto-assert CPU/GPU reset, or a status
bit could flag "mode changed while processor active."

**Impact:** Prevents silent data corruption from incorrect software
sequencing. Not required for correct operation when using `lab8reg`, but
adds robustness for future software development.

**Complexity:** Low (a few lines of RTL).

---

## General Principles (from lecture)

1. **Incremental approach:** Make things work first, then optimize. Each
   improvement above should be implemented and tested independently.

2. **"Use Network, NO PCI" for data path:** PCI registers are for control
   and configuration only. Packet data must flow through the network path
   (FIFO BRAM), not through PCI register reads/writes. (Already implemented
   in current design — CPU accesses FIFO BRAM via MEM stage mux.)

3. **FIFO as scratch memory for ML:** In ML/neural network applications,
   memory bandwidth is not the bottleneck — computation scalability is.
   FIFOs serve as streaming scratchpads: network -> scratchpad -> compute ->
   scratchpad -> network.
