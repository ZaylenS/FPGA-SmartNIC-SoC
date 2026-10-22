# BF16 FMA Signed Arithmetic Bug — ISE 10.1

> **Document refreshed 2026-05-17.** Historical record of the 2026-03-19 fix. The bf16_fma_unit fix described here is still in the RTL (see `src/gpu/bf16_fma_unit.v`); the same `wire signed` → unsigned-arithmetic transformation was applied at the same time to `src/gpu/bf16_alu.v` (see `gpu_update_notes.md` entry F-02). No further changes since.

## Summary

After the 6-stage pipeline refactor, 4 of 5 kernel tests passed on the NetFPGA
but **bf16_fma failed** on lane 0. Root cause: ISE 10.1 silently miscompiles
`wire signed` arithmetic when mixed with unsigned concatenations. Fix: rewrite
all exponent arithmetic in `bf16_fma_unit.v` using purely unsigned operations.

**Result: 5/5 kernel tests pass on hardware after the fix.**

---

## Symptom

```
=== bf16_fma: R4 = R1*R2 + R3 (BF16) ===
DMEM[0x003](0x2006018)=0x40a040e0_3f0040e0
Expected:              0x40a040e0_3f0040d0
*** FAIL ***
```

Only lane 0 was wrong:

| Lane | A     | B     | C     | Expected | Got    | Status |
|------|-------|-------|-------|----------|--------|--------|
| 0    | 3.0   | 2.0   | 0.5   | 6.5 (0x40D0) | 7.0 (0x40E0) | FAIL |
| 1    | 0.5   | 0.5   | 0.25  | 0.5 (0x3F00) | 0x3F00 | PASS |
| 2    | 2.0   | 3.0   | 1.0   | 7.0 (0x40E0) | 0x40E0 | PASS |
| 3    | 1.0   | 2.0   | 3.0   | 5.0 (0x40A0) | 0x40A0 | PASS |

---

## Root Cause Analysis

### The Error Pattern

Lane 0: `3.0 * 2.0 + 0.5` should be 6.5 but produced 7.0.

- 6.5 = 6.0 + **0.5** (C mantissa shifted right by 3)
- 7.0 = 6.0 + **1.0** (C mantissa shifted right by 2)

The addend C=0.5 was being right-shifted by **2 instead of 3** positions. This
means `shift_amt` was computed as 2 instead of the correct value 3.

### Hand Trace (Correct Result)

For lane 0 (A=3.0, B=2.0, C=0.5):

```
a_exp = 128, b_exp = 128, c_exp = 126
product = {1,1000000} * {1,0000000} = 0x6000, product[15] = 0 → mul_norm = 0
mul_exp = 128 + 128 - 127 = 129
exp_diff = 129 - 126 = 3  →  shift_amt should be 3
```

The hand trace of the Verilog RTL produces the correct answer. The bug is in
how ISE 10.1 **synthesizes** the logic, not in the RTL semantics.

### The ISE 10.1 Signed Synthesis Bug

The original code used `wire signed [9:0]` for exponent arithmetic:

```verilog
// ORIGINAL (BUGGY under ISE 10.1)
wire signed [9:0] mul_exp_raw = {2'b0, a_exp} + {2'b0, b_exp} - 10'sd127;
wire signed [9:0] s_c_exp     = {2'b0, c_exp};
wire signed [9:0] diff_c0     = exp_c0 - s_c_exp;
wire signed [9:0] abs_c0      = diff_c0[9] ? (-diff_c0) : diff_c0;
wire [4:0] sa_c0 = (abs_c0 > 10'sd18) ? 5'd18 : abs_c0[4:0];
```

**Problem:** In Verilog-2001, concatenation (`{2'b0, a_exp}`) always produces
an **unsigned** result. Assigning this to a `wire signed` reinterprets the bits
but relies on the synthesis tool correctly propagating the `signed` attribute
through all downstream operations.

ISE 10.1 (XST from ~2008) does not reliably handle this. The signed/unsigned
type propagation through ternary operators, comparisons, and negation is
inconsistent, leading to incorrect synthesis of the exponent difference chain.

### Why Only Lane 0 Failed

All 4 lanes use identical `bf16_fma_unit` instances with the same RTL. The bug
is data-dependent — it manifests when specific exponent values interact with
the miscompiled signed arithmetic. Lane 0 had `c_exp = 126` (exp_diff = 3),
while lane 2 had `c_exp = 127` (exp_diff = 2) with the same product exponent
and worked correctly.

---

## Fix

Rewrote all exponent arithmetic in `bf16_fma_unit.v` using **purely unsigned**
operations. No `wire signed`, no `reg signed`, no `10'sd` constants.

### Key Technique: Compare Before Subtract

Instead of computing a signed difference and taking the absolute value, compare
the two unsigned values first, then subtract in the correct direction:

```verilog
// FIXED (all unsigned)
wire [8:0] ab_exp_sum = {1'b0, a_exp} + {1'b0, b_exp};   // 0..510
wire [8:0] ab_sum_c0  = ab_exp_sum;                        // mul_norm = 0
wire [8:0] ab_sum_c1  = ab_exp_sum + 9'd1;                 // mul_norm = 1
wire [8:0] c_exp_bias = 9'd127 + {1'b0, c_exp};            // 127..382

// Compare: mul_exp >= c_exp  ⟺  (a+b+norm) >= (127+c)
wire c0_ge = (ab_sum_c0 >= c_exp_bias);
wire c1_ge = (ab_sum_c1 >= c_exp_bias);

// Absolute difference (both directions, select by comparison)
wire [8:0] diff_c0_fwd = ab_sum_c0 - c_exp_bias;  // valid when c0_ge
wire [8:0] diff_c0_rev = c_exp_bias - ab_sum_c0;   // valid when !c0_ge
wire [8:0] abs_diff_c0 = c0_ge ? diff_c0_fwd : diff_c0_rev;

wire [4:0] sa_c0 = (abs_diff_c0 > 9'd18) ? 5'd18 : abs_diff_c0[4:0];
```

The trick: comparing `(a_exp + b_exp + norm)` vs `(127 + c_exp)` is
mathematically equivalent to comparing `mul_exp` vs `c_exp`, but avoids the
intermediate signed subtraction `a_exp + b_exp - 127` entirely. Both sides
of the comparison are small positive unsigned values.

### Exponent Underflow/Overflow Detection

For normalization in Cycle 3, unsigned exponent values use `bit[9]` as an
underflow indicator (values that wrapped around past zero):

```verilog
wire [9:0] exp_after_lzc = s2_aligned_exp - {5'b0, lzc};
wire exp_lzc_underflow   = ({5'b0, lzc} > s2_aligned_exp);

wire norm_under = norm_exp_neg || (norm_exp == 10'd0) || s2_aligned_exp[9];
wire norm_over  = !norm_exp_neg && !s2_aligned_exp[9] && (norm_exp >= 10'd255);
```

---

## Files Changed

| File | Change |
|------|--------|
| `src/bf16_fma_unit.v` | Rewrote all exponent arithmetic as purely unsigned |

No other files were modified. The fix is entirely within the FMA unit's
exponent computation logic.

---

## Verification

Hardware test on NetFPGA (post-synthesis, post-PAR):

```
=== TOTAL: 5/5 passed ===
```

All 5 kernel tests pass: vec_add, vec_sub, relu, bf16_mul, **bf16_fma**.

---

## Lesson Learned

**Never use `wire signed` or `reg signed` in ISE 10.1 designs.** The XST
synthesizer from this era does not reliably propagate signedness through
complex expressions involving concatenation, ternary operators, and negation.
Use purely unsigned arithmetic with explicit comparison-based sign handling.
