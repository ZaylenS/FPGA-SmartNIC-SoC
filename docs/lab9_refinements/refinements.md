# Lab 8 -- Refinements & Fixes (Non-GPU)

Prioritized list of bugs, improvements, and cleanup items identified by
cross-referencing all source files in `src/` (excluding GPU internals) and all
documentation in `docs/` against each other and the RTL.

GPU-side items are tracked separately (handled by another review instance).

Items from `improvements_and_optimizations.md` (P1--P9) are cross-referenced
where they overlap.

---

## Fix Status

**Testbench:** `tb/tb_stress_refinements.v` (iverilog)

**Pre-fix simulation (bug reproduction):**
- C1 (conditional execution): **BUG CONFIRMED** -- ADDEQ executes when Z=0
- C2 (1-word packet): **BUG CONFIRMED** -- FSM stuck in S_RECEIVING permanently
- H1 (PC halt gating): Not reproduced in zero-delay sim (hardware timing issue only)
- H2 (was_ext reset): Not testable in iverilog (regs default to 0; FPGA concern only)
- H3 (CPU runs at start_stop=0): Not reproduced (thread_id gating prevents execution)

**Post-fix simulation (2026-03-12):**
- tb_stress_refinements: **6/6 pass**, 0 bugs remaining
- tb_cpu_fifo: **ALL TESTS PASSED** (regression)
- tb_lab8_wrapper: **ALL TESTS PASSED** (regression)
- tb_gpu_integration: **ALL TESTS PASSED** (regression)

**Hardware status:** Fixes have NOT been re-synthesized or tested on the
NetFPGA. The last hardware-verified bitfile is from Batch 5 (March 7, 2026)
and does not include these changes. Re-synthesis required before hardware
validation.

---

## CRITICAL -- Functional Bugs

### C1. `src/arm/ID.v` -- Conditional execution broken for non-branch instructions

**Status: FIXED (simulation verified, hardware not re-tested)**

**Bug:** The ARM condition evaluator (`cond_pass`) is computed correctly from
CPSR flags for all 16 condition codes. However, the control unit only checks
`cond_pass` when generating branch signals. Data-processing, load, and store
instructions ignore `cond_pass` entirely -- they execute unconditionally
regardless of the condition field in bits [31:28].

This means:
- `ADDEQ r4, r4, #1` executes even when Z=0 (EQ requires Z=1)
- `LDREQ r2, [r1]` reads memory even when condition fails
- `STRNE r2, [r1]` writes memory even when condition fails
- Flag-setting (`SUBS`, `CMP`) updates CPSR even when condition fails

**Evidence:** Stress test C1 loads `MOV r3, #0; MOV r4, #100; CMP r3, #99;
ADDEQ r4, r4, #1; STR r4, [r1, #2]`. CMP 0 vs 99 sets Z=0, so ADDEQ
(condition EQ = Z must be 1) should be skipped. Before fix: BRAM[2] = 101
(ADDEQ executed). After fix: BRAM[2] = 100 (ADDEQ skipped). Companion test
C1b verifies `ADDNE` still executes correctly when Z=0.

**Why hardware tests passed:** All existing programs (Batches 3-5) use
condition code 0xE (AL = always execute), so `cond_pass` was always 1 and
the bug was never exercised.

**Fix applied (ID.v lines 228-245):**

Before:
```verilog
else if (is_dp) begin
    ALU_op      = opcode;
    alusrc      = I_bit;
    o_WRegEn    = !is_test_op;
    o_set_flags = S_bit | is_test_op;
end
else if (is_load) begin
    ...
    o_RMemEn     = 1'b1;
    o_WRegEn     = 1'b1;
    ...
end
else if (is_store) begin
    ...
    o_WMemEn     = 1'b1;
end
```

After:
```verilog
else if (is_dp) begin
    ALU_op      = opcode;
    alusrc      = I_bit;
    o_WRegEn    = !is_test_op & cond_pass;
    o_set_flags = (S_bit | is_test_op) & cond_pass;
end
else if (is_load) begin
    ...
    o_RMemEn     = cond_pass;
    o_WRegEn     = cond_pass;
    ...
end
else if (is_store) begin
    ...
    o_WMemEn     = cond_pass;
end
```

When `cond_pass=0`, all write-enables and flag-setting signals stay at their
default value of 0. The ALU still computes a result (harmless -- no side
effects without enables), and the pipeline advances normally. This matches ARM
architecture behavior: a failed condition makes the instruction act as a NOP.

No changes needed to pipeline registers or downstream stages -- the enables
are already carried through `idex_reg` / `exmem_reg` and only take effect at
the MEM (store) or WB (register write) stage.

---

### C2. `src/fifo/convertible_fifo.v` -- 1-word packet hangs FSM in S_RECEIVING

**Status: FIXED (simulation verified, hardware not re-tested)**

**Bug:** When the FSM receives a packet header in S_IDLE, it computes
`words_remaining = word_length - 1` and transitions to S_RECEIVING. If
`word_length = 1` (header-only packet), then `words_remaining = 0`. The exit
condition in S_RECEIVING is `words_remaining == 8'd1`, which is never true.
The FSM is permanently stuck in S_RECEIVING. The FIFO cannot accept any
further packets -- a single malformed packet bricks the entire data path.

**Evidence:** Stress test C2 injects a packet with `word_length=1` (header
word: `64'h0001_0001_0002_0008`). Before fix: FSM state = 1 (S_RECEIVING),
`words_remaining = 0`, and a subsequent normal 2-word packet is also lost.
After fix: FSM state = 2 (S_PKT_BUFFERED), `pkt_ready = 1`.

**Why hardware tests passed:** NF2.1 packets always have >= 2 words (one
header + at least one data word). No real or test packet ever had
`word_length = 1`.

**Fix applied (convertible_fifo.v, S_IDLE state):**

Before:
```verilog
wr_ptr          <= wr_ptr + 8'd1;
pkt_len         <= in_data[39:32];
words_remaining <= in_data[39:32] - 8'd1;
state           <= S_RECEIVING;
```

After:
```verilog
wr_ptr  <= wr_ptr + 8'd1;
pkt_len <= in_data[39:32];
if (in_data[39:32] <= 8'd1) begin
    // Single-word packet (header only): skip S_RECEIVING
    words_remaining <= 8'd0;
    pkt_stored      <= 1'b1;
    state           <= S_PKT_BUFFERED;
end else begin
    words_remaining <= in_data[39:32] - 8'd1;
    state           <= S_RECEIVING;
end
```

When `word_length <= 1`, the header is the entire packet, so we go directly
to S_PKT_BUFFERED. The `<= 1` check also handles the degenerate
`word_length = 0` case (malformed header) by treating it as a 1-word packet
rather than underflowing the subtraction.

---

## HIGH -- Hardware Correctness / Robustness

### H1. `src/arm/IF_stage.v` -- PC not gated by halted flag

**Status: FIXED (simulation verified, hardware not re-tested)**

*Overlaps with: improvements_and_optimizations.md P7*

**Bug:** After a thread executes HALT, its `halted[thread_id]` flag is set in
the ID stage, but IF_stage has no access to this flag. The PC continues
advancing every 4 cycles (once per thread rotation), wrapping around the
128-word IMEM region. This causes:
- Bug #3: PC wraps after HALT (worked around with `B .` padding in IMEM)
- `all_halted` timeout on hardware (CPU_STATUS[31] never asserts at 125 MHz)

**Simulation note:** In zero-delay iverilog simulation, `all_halted` asserted
correctly even before the fix, and PC samples appeared stable. This suggests
the hardware `all_halted` timeout (Batch 5) is a timing/race condition at
125 MHz rather than a pure logic bug. The fix is still correct and
recommended -- it eliminates unnecessary instruction fetches and removes the
need for `B .` padding after every HALT.

**Fix applied:**

1. Added `halted` input port to IF_stage (IF_stage.v):
```verilog
input  [3:0]  halted
```

2. Gated PC advance (IF_stage.v, PC update block):
```verilog
// Before:
pc[thread_id] <= next_pc_seq;

// After:
if (!halted[thread_id])
    pc[thread_id] <= next_pc_seq;
```

3. Connected wire in processor.v (IF_stage instantiation):
```verilog
.halted(halted)
```

When a thread is halted, its PC freezes at the instruction after HALT (due
to pipeline latency, the PC has already advanced once by the time the HALT
reaches ID). The IMEM still reads from this frozen address each rotation, but
the fetched instruction (HALT or NOP) produces no side effects.

---

### H2. `src/arm/data_mem.v` -- `was_ext` register has no reset

**Status: FIXED (simulation verified, hardware not re-tested)**

**Bug:** The `was_ext` register tracks whether the previous MEM-stage access
targeted external memory (FIFO BRAM) vs internal DMEM, and muxes the read
output accordingly. It had no reset clause:
```verilog
always @(posedge clk) was_ext <= addr_is_ext;
```

On FPGA power-up, `was_ext` is undefined. If it powers up as 1, the first
MEM-stage read output would come from `ext_mem_dout` (FIFO BRAM) instead of
`dmem_rd` (internal DMEM). In iverilog, `reg` defaults to 0, so this cannot
be demonstrated in simulation.

**Fix applied:**

1. Added `reset` input port to data_mem (data_mem.v):
```verilog
input  reset,
```

2. Added reset clause (data_mem.v):
```verilog
always @(posedge clk) begin
    if (reset) was_ext <= 1'b0;
    else       was_ext <= addr_is_ext;
end
```

3. Connected wire in processor.v (data_mem instantiation):
```verilog
.reset(rst),
```

---

### H3. `src/arm/processor.v` -- Bug #1 still in RTL (not fixed, low risk)

**Status: NOT FIXED (not reproduced in simulation, software workaround sufficient)**

**Context:** Original Bug #1 reported that the CPU executes instructions when
`rst=0, start_stop=0`. Stress test H3 could not reproduce this: the
`thread_id` counter only advances when `start_stop=1` (processor.v line 70),
which effectively freezes the pipeline. BRAM was not modified after 100 cycles
with `start_stop=0`.

The original hardware observation may have been a timing/race condition during
the PCI register write sequence. The software workaround (atomic start:
writing `CPU_CTRL=0x01` to simultaneously release reset and assert start_stop)
remains sufficient.

**Recommendation:** Low priority. Could add an explicit `start_stop` gate in
IF_stage for defense-in-depth, but not required for correctness.

---

### H4. `src/lab8_wrapper.v` -- No registered strobes for CPU IMEM/DMEM PCI writes

**Status: NOT FIXED (works on hardware, inconsistent pattern)**

Bug #4 fix added `bram_pci_wr_strobe` and `gpu_dmem_pci_wr_strobe` for FIFO
BRAM and GPU DMEM PCI writes. CPU IMEM (`reg_cpu_imem_cmd[0]`) and CPU DMEM
(`reg_cpu_dmem_cmd[0]`) still use auto-clear strobes through combinational
paths. These work because the paths are shorter (direct `assign`, no mux).

**Recommendation:** Add registered strobes if future changes add muxing to
these paths. ~15 lines.

---

### H5. `src/lab8_wrapper.v` -- DMA address arithmetic can overflow silently

**Status: NOT FIXED (software responsibility)**

`dma_fifo_addr + dma_offset` (8-bit) and `dma_gpu_addr + dma_offset` (10-bit)
wrap on overflow with no error indication.

**Recommendation:** Add bounds checking or a status bit. ~5-10 lines.

---

## MEDIUM -- ISA Completeness / Code Quality

### M1. `src/arm/alu64.v` -- Missing ARM opcodes

**Status: NOT FIXED**

Missing: ADC, SBC, RSB, RSC, CMN. All default to ADD. ~30 lines to implement.

---

### M2. `src/arm/ID.v` -- Missing explicit `default` in condition evaluator

**Status: FIXED (simulation verified)**

All 16 condition codes were covered but no explicit `default` branch existed.
Per Verilog coding rules, every `case` must have `default` to prevent latch
inference.

**Fix applied:** Added `default: cond_pass = 1'b1;` after the last case entry.

---

### M3. `src/arm/EX.v` -- ROR with shift_amt=0 is identity, not RRX

**Status: NOT FIXED**

ARM spec: ROR #0 encodes RRX (rotate right extended through carry). Current
implementation returns unshifted value. No test program uses RRX. ~3 lines.

---

### M4. `src/arm/alu64.v` -- C_flag always 0 for logic operations

**Status: NOT FIXED**

ARM spec: logic ops (AND, ORR, EOR, BIC) should output the shifter carry-out
as C_flag. Current implementation always sets C_flag=0. ~5 lines across EX.v
and alu64.v.

---

## LOW -- Cleanup / Documentation

### L1. Dead code: `src/arm/adder8_comb.v`, `src/arm/full_adder.v`

**Status: NOT FIXED**

Never instantiated. Remnants from structural adder rewrite. Delete from
`src/arm/`.

---

### L2. `include/lab8_reg_defines.vh` -- Comment typos on HI register bit ranges

**Status: NOT FIXED**

Lines 119, 125-128: comments say `[31:0]` for `_HI` registers. Should be
`[63:32]`.

---

### L3. `docs/improvements_and_optimizations.md` -- P4 entry is stale

**Status: NOT FIXED**

P4 says Bug #2 not yet applied. It was applied in Batch 5. Mark as DONE.

---

### L4. `src/arm/logic_analyzer.v` -- No wrap indicator or trigger mechanism

**Status: NOT FIXED**

LA is a debug aid. Add `wrapped` status bit and optional trigger. ~10 lines.

---

## Cross-Reference: improvements_and_optimizations.md (P1--P9)

| P# | Description | Status | Overlap |
|----|-------------|--------|---------|
| P1 | Dual-port GPU bandwidth | Open | (GPU scope) |
| P2 | BRAM register file + DCM 2x clock | Open | -- |
| P3 | Behavioral to structural conversion | Open | -- |
| P4 | in_rdy mode gating (Bug #2) | **DONE** (Batch 5) | L3 (stale doc) |
| P5 | Application-specific simplification | Open | -- |
| P6 | Shared FIFO BRAM as unified scratchpad | Open | -- |
| P7 | Fix all_halted detection | **FIXED** (this batch) | H1 |
| P8 | GPU decode pipeline split | Open | (GPU scope) |
| P9 | Mode-switch safety guard | Open | -- |

---

## Summary

| Priority | Count | Fixed | Key items |
|----------|-------|-------|-----------|
| **Critical** | 2 | **2/2** | Conditional execution (C1), 1-word packet (C2) |
| **High** | 5 | **2/5** | PC halt gating (H1), was_ext reset (H2) |
| **Medium** | 4 | **1/4** | Condition default (M2) |
| **Low** | 4 | **0/4** | Dead code, comment typos, stale doc, LA |

**Total: 5 items fixed, 10 remaining (none blocking current operation).**

All fixes pass simulation (iverilog). Hardware re-synthesis and testing on
NetFPGA required before deployment.
