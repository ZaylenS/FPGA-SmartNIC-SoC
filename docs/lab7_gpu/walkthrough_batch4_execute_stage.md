# Batch 4 — Execute Stage Walkthrough

> **Updated 2026-07-14:** Stale walkthrough content was reconciled with the current RTL implementation by Codex (GPT-5).

> **Update history.**
>
> - **2026-03-19 (Lab 8 refactor).** `bf16_alu.v` had all signed declarations removed for ISE 10.1 compatibility; MUL and ADD exponent arithmetic is purely unsigned. Branch comparison moved to EX1 in `core_top.v` -- `execute_stage.v` itself is unchanged in that regard.
> - **2026-04-13 (BCAST -- commit `e14d012`).** New `ALU_BCAST` op in `int16_alu` and `bf16_alu` -- both treat it as MOV; `simd_alu.v` adds the BCAST cross-lane mux before the per-lane ALUs.
> - **2026-06-25 checkpoint audit.** At that checkpoint `simd_alu.v` still had four INT16 lanes and no input pipeline register, while `execute_stage.v` still had `simd_result_r`.
> - **2026-07-14.** Reconciled with the latest RTL: `simd_alu.v` now registers the BCAST/effective-A path and ALU controls, uses one lane-0 INT16 ALU with replicated output, retains four BF16 lanes, and produces its result directly in EX3. `execute_stage.v` consequently has no `simd_result_r`.

**Files covered:** `int16_alu.v` → `bf16_alu.v` → `simd_alu.v` → `bf16_fma_unit.v` → `execute_stage.v`
The execute stage answers: **"Compute the result."** It takes decoded control signals + register data from ID/EX, routes them to the appropriate compute unit (int16 ALU, BF16 ALU, or BF16 FMA), and drives the data memory interface. Branch resolution is handled in `core_top.v` from the ID/EX branch operands before the EX pipeline advances.

---

## Macro View — The Execute Stage Routing

```
From ID/EX register (Batch 3)
        │
        ├─ alu_op, dtype, use_imm, is_fma
        ├─ rs1_data, rs2_data, rs3_data (64-bit each)
        ├─ imm_ext (64-bit)
        ├─ mem_write
        │
        ▼
┌──────────────────────────────────────────────────────────────┐
│                     execute_stage                            │
│                                                              │
│  ┌─────────┐   op_b = use_imm ? imm_ext : rs2_data          │
│  │ Imm MUX │──────────────────────┐                         │
│  └─────────┘                      │                         │
│                                    ▼                         │
│  ┌─────────────────────────────────────────┐                 │
│  │              simd_alu                    │                 │
│  │  ┌──────────┐  ┌──────────┐             │                 │
│  │  │int16_alu │  │bf16_alu  │             │                 │
│  │  │ lane0 ×1 │  │ ×4 lanes │             │                 │
│  │  └────┬─────┘  └────┬─────┘             │                 │
│  │   lane0 replicate ── dtype MUX ──► simd_result            │
│  └─────────────────────┬───────────────────┘                 │
│                        │                                     │
│  ┌─────────────────────┼───────────────────┐                 │
│  │    bf16_fma_unit    │   ×4 lanes        │                 │
│  │  rs1×rs2+rs3 ───────┼──→ fma_result     │                 │
│  └─────────────────────┼───────────────────┘                 │
│                        │                                     │
│  Result MUX (EX3): is_fma_r2 ? fma_result : simd_result      │
│                                                              │
│  DMEM (EX3): mem_addr_r2 → addr, rs2_data_r2 → wr_data      │
└──────────────────────────────────────────────────────────────┘
        │                                       │
        ▼                                       ▼
   result (64b)                            DMEM Port A
   → EX3/WB reg                           (active in EX3)
```

**Key architectural decisions:**
- **The lane-0 INT16 ALU and four BF16 ALUs run every cycle** — the dtype MUX selects the replicated integer result or packed BF16 result, not their inputs.
- **FMA has its own 4 instances** — separate from the SIMD ALU. The `is_fma_r2` MUX selects in EX3.
- **All compute paths produce results in EX3 (3 EX cycles total):** `simd_alu` first registers BCAST/effective operands and controls, then its BF16 lanes use their internal register while the lane-0 INT16 result is registered for alignment. FMA is 3-cycle pipelined (multiply+align in EX1, shift+add in EX2, LZC+normalize in EX3). DMEM signals are active in EX3.

> **Note:** This file was originally written for the 4-stage pipeline with combinational SIMD ALU and `ex_busy` FMA stalling. It has been updated to reflect the 6-stage pipeline (EX1+EX2+EX3).

---

## 1. int16_alu.v — Single-Lane 16-bit Integer ALU

27 lines. The simplest compute unit. One lane does one 16-bit integer operation.

### 1.1 Port Declaration

```verilog
module int16_alu (
    input  [3:0]          alu_op,
    input  [15:0]         a,
    input  [15:0]         b,
    output reg [15:0]     result
);
```

Ports: `alu_op` selects the operation (ALU_ADD / ALU_SUB / ALU_MUL / ALU_MAX / ALU_MOV / ALU_RELU). `a` and `b` are one 16-bit lane from the 64-bit SIMD operands. `result` is the computed output for this lane.

### 1.2 Multiplier Wire

```verilog
    // 16x16 → 32-bit product; operands ≤18 bits → infers mult18x18
    wire [31:0] product = a * b;
```

**Always computed** regardless of `alu_op`. If the operation isn't MUL, the product wire is unused and XST optimizes it away. The current `simd_alu` instantiates this module once for lane 0, so the multiplier is used when that scalar integer path executes `ALU_MUL`.

**Synthesis inference:** `a * b` with both operands ≤ 18 bits matches XST's multiplier inference pattern exactly. The single current `int16_alu` instance contributes one source-level multiply operator.

### 1.3 Operation Select

```verilog
    always @(*) begin
        case (alu_op)
            `ALU_ADD:  result = a + b;
            `ALU_SUB:  result = a - b;
            `ALU_MUL:  result = product[15:0];
            `ALU_MAX:  result = ($signed(a) > $signed(b)) ? a : b;
            `ALU_MOV:  result = a;
            `ALU_BCAST: result = a;                    // Added 2026-04-13
            `ALU_RELU: result = a[15] ? 16'h0000 : a;
            default:   result = 16'h0000;
        endcase
    end
```

**Line-by-line details:**

- **`product[15:0]`:** Takes only the lower 16 bits. For int16 multiply, this is modular multiplication (result mod 2^16). Overflow is silent — acceptable for SIMD processing where values are typically small (neural net weights/activations).

- **`$signed(a) > $signed(b)`:** Verilog `>` is unsigned by default. `$signed()` casts make the comparison treat bit 15 as the sign bit. Result is still the raw 16-bit value (not sign-extended).

- **`a[15] ? 16'h0000 : a`:** ReLU (Rectified Linear Unit). Checks the sign bit directly — if negative, output zero; if positive/zero, pass through unchanged. This is a single-bit MUX, not a comparator. Very efficient in hardware (1 LUT per bit).

- **`ALU_BCAST` (added 2026-04-13):** Identical handling to `ALU_MOV` — just pass `a` through. The cross-lane mux that makes BCAST useful happens *upstream* of this ALU, in the simd_alu wrapper (see §3). By the time inputs arrive here, `a` already holds the broadcast value, and this ALU just forwards it.

---

## 2. bf16_alu.v — Single-Lane BFloat16 ALU

248 lines. The most complex single module in the design. It implements a truncated, flush-to-zero BF16 subset with explicit zero/inf/NaN handling; it is not a fully IEEE-754-conforming or correctly rounded unit.

### 2.1 Port Declaration (2-cycle pipelined)

```verilog
module bf16_alu (
    input                 clk,
    input                 rst,
    input  [3:0]          alu_op,
    input  [15:0]         a,
    input  [15:0]         b,
    output reg [15:0]     result
);
```

**Now 2-cycle pipelined** (unlike int16_alu which remains combinational). `clk`/`rst` were added for the internal pipeline register that splits the ADD/SUB critical path. EX1 computes through `add_raw`; EX2 does LZC + normalization + output MUX. MUL/MAX/MOV/RELU results are fully computed in EX1 and registered for output in EX2.

### 2.2 Field Extraction + Special Value Detection

```verilog
    wire        a_sign = a[15];
    wire [7:0]  a_exp  = a[14:7];
    wire [6:0]  a_mant = a[6:0];
    wire        b_sign = b[15];
    wire [7:0]  b_exp  = b[14:7];
    wire [6:0]  b_mant = b[6:0];

    // Special value detection
    wire a_is_zero   = (a_exp == 8'd0) && (a_mant == 7'd0);
    wire b_is_zero   = (b_exp == 8'd0) && (b_mant == 7'd0);
    wire a_is_inf    = (a_exp == 8'hFF) && (a_mant == 7'd0);
    wire b_is_inf    = (b_exp == 8'hFF) && (b_mant == 7'd0);
    wire a_is_nan    = (a_exp == 8'hFF) && (a_mant != 7'd0);
    wire b_is_nan    = (b_exp == 8'hFF) && (b_mant != 7'd0);
    wire a_is_denorm = (a_exp == 8'd0) && (a_mant != 7'd0);
    wire b_is_denorm = (b_exp == 8'd0) && (b_mant != 7'd0);
```

BF16 format is `[sign:1][exponent:8][mantissa:7]`, with bias 127 and an implicit leading one for normal values. The detectors recognize zero, infinity, NaN, and denormal encodings.

**Denormal qualification:** BF16 MUL and ADD/SUB, and the separate FMA unit, treat detected denormals as effective zero. MOV and RELU pass/check the raw encoding, and MAX compares it rather than globally flushing every operation. “Flush to zero” therefore describes the arithmetic paths, not a universal input canonicalization stage.

### 2.3 MUL Block — BF16 Multiplication

```verilog
    wire        mul_sign = a_sign ^ b_sign;
```

XOR computes the result sign. Exponent arithmetic is performed with explicit unsigned sums and underflow/overflow flags, avoiding the signed-arithmetic form used in an older revision.

```verilog
    wire [7:0]  a_full = {1'b1, a_mant};
    wire [7:0]  b_full = {1'b1, b_mant};
    wire [15:0] mul_product = a_full * b_full;
```

Prepends the implicit 1 to each 7-bit mantissa, giving 8-bit significands (value in [1.0, 2.0)). The 8x8 = 16-bit product is in [1.0, 4.0): min 1.0 x 1.0 = 1.0 (bit 14 set), max ~2.0 x ~2.0 = ~4.0 (bit 15 set). Since 8 <= 18, XST infers one MULT18x18 block.

```verilog
    wire        mul_norm_shift = mul_product[15];
    wire [6:0]  mul_norm_mant = mul_norm_shift ? mul_product[14:8]
                                               : mul_product[13:7];

    // Unsigned exponent arithmetic (avoids ISE 10.1 signed bug)
    wire [8:0] mul_ab_sum    = {1'b0, a_exp} + {1'b0, b_exp};
    wire [9:0] mul_exp_n0    = {1'b0, mul_ab_sum}     - 10'd127;
    wire [9:0] mul_exp_n1    = {1'b0, mul_ab_sum} + 10'd1 - 10'd127;
    wire [9:0] mul_norm_exp  = mul_norm_shift ? mul_exp_n1 : mul_exp_n0;

    wire mul_exp_under = mul_norm_exp[9] || (mul_norm_exp == 10'd0);
    wire mul_exp_over  = !mul_norm_exp[9] && (mul_norm_exp >= 10'd255);
```

**Why [14:8] vs [13:7]?** The implicit 1 is at different positions:
- If `product[15]=1`: binary is `1x.xxxxxxx_xxxxxxx` → implicit 1 at bit 15, mantissa = bits [14:8]
- If `product[15]=0`: binary is `01.xxxxxxx_xxxxxxx` → implicit 1 at bit 14, mantissa = bits [13:7]

**Truncation (no rounding):** The bits below the mantissa (product[7:0] or [6:0]) are simply discarded. A future improvement could add round-to-nearest-even by inspecting the guard/round/sticky bits.

```verilog
    wire [15:0] mul_result =
        (a_is_nan || b_is_nan)                                      ? `BF16_NAN :
        ((a_is_inf && (b_is_zero || b_is_denorm)) ||
         (b_is_inf && (a_is_zero || a_is_denorm)))                  ? `BF16_NAN :
        (a_is_inf || b_is_inf)                                      ? {mul_sign, 8'hFF, 7'd0} :
        (a_is_zero || b_is_zero || a_is_denorm || b_is_denorm)      ? {mul_sign, 15'd0} :
        mul_exp_under                                                ? {mul_sign, 15'd0} :
        mul_exp_over                                                 ? {mul_sign, 8'hFF, 7'd0} :
        {mul_sign, mul_norm_exp[7:0], mul_norm_mant};
```

**Priority chain:** Specials checked first (NaN > inf > zero > underflow > overflow > normal). This is a cascaded ternary, which synthesizes to a priority MUX chain. NaN always wins.

### 2.4 ADD/SUB Block — BF16 Addition and Subtraction

This is the most complex part of the ALU. BF16 addition requires alignment-shifting the smaller operand's mantissa, performing the addition/subtraction, then normalizing.

```verilog
    wire add_b_sign = (alu_op == `ALU_SUB) ? ~b_sign : b_sign;
```

**SUB reuses the adder.** Instead of a separate subtractor, we negate b's sign and add. `a - b = a + (-b)`. This saves an entire duplicate datapath.

```verilog
    wire a_gt_b_mag = (a_exp > b_exp) ||
                      ((a_exp == b_exp) && (a_mant >= b_mant));

    wire [7:0]  large_exp  = a_gt_b_mag ? a_exp      : b_exp;
    wire [6:0]  large_mant = a_gt_b_mag ? a_mant     : b_mant;
    wire        large_sign = a_gt_b_mag ? a_sign      : add_b_sign;
    wire [7:0]  small_exp  = a_gt_b_mag ? b_exp       : a_exp;
    wire [6:0]  small_mant = a_gt_b_mag ? b_mant      : a_mant;
    wire        small_sign = a_gt_b_mag ? add_b_sign   : a_sign;
```

**Why sort by magnitude?** In floating-point addition, we align the smaller mantissa to the larger exponent. Sorting first simplifies the logic — we always shift the "small" operand right.

**Result sign = sign of the larger magnitude operand** (determined after subtraction).

```verilog
    wire large_is_zero = (large_exp == 8'd0);
    wire small_is_zero = (small_exp == 8'd0);

    wire [8:0] large_full = large_is_zero ? 9'd0 : {1'b1, large_mant, 1'b0};
    wire [8:0] small_full_pre = small_is_zero ? 9'd0 : {1'b1, small_mant, 1'b0};
```

**Guard bit:** One extra bit at the bottom for slightly better precision during alignment. Without it, shifting always loses the LSB. With it, we have one bit of "extra" precision to absorb small alignment shifts.

```verilog
    wire [7:0] exp_diff = large_exp - small_exp;
    wire [3:0] shift_amt = (exp_diff > 8'd9) ? 4'd9 : exp_diff[3:0];
    wire [8:0] small_full = small_full_pre >> shift_amt;
```

**Clamp at 9:** The mantissa is 9 bits wide. Shifting right by more than 9 would produce all zeros anyway, so we clamp to avoid wasting barrel shifter resources.

```verilog
    wire eff_sub = (large_sign != small_sign);

    wire [9:0] add_raw = eff_sub ? ({1'b0, large_full} - {1'b0, small_full})
                                 : ({1'b0, large_full} + {1'b0, small_full});

    wire add_res_sign = large_sign;
```

**10-bit result:** Addition of two 9-bit values can overflow to 10 bits (carry out). `{1'b0, x}` zero-extends to 10 bits to capture the carry.

```verilog
    //------------------------------------------------------------------------
    // Pre-computed ADD/SUB special-case flags (for EX2)
    //------------------------------------------------------------------------
    wire any_nan_add    = a_is_nan || b_is_nan;
    wire inf_sub_inf    = a_is_inf && b_is_inf && (a_sign != add_b_sign);
    wire a_eff_zero     = a_is_zero || a_is_denorm;
    wire add_b_is_zero  = b_is_zero || b_is_denorm;
```

These flags are computed combinationally in EX1 and registered into `s1_` pipeline registers for use in EX2. They drive the `use_special` / `special_result` path, avoiding any dependency on the slow LZC/normalize logic.

**Pipeline Register: EX1 -> EX2.** The `add_raw`, `large_exp`, `eff_sub`, `add_res_sign`, special-case flags, and pre-computed MUL/MAX/MOV/RELU results are all registered with `s1_` prefix. The `s1_alu_op` register carries the operation code for the output MUX in EX2.

```verilog
    // Leading zero count on registered add_raw[8:0]
    reg [3:0] lzc;
    always @(*) begin
        casez (s1_add_raw[8:0])
            9'b1????????: lzc = 4'd0;
            9'b01???????: lzc = 4'd1;
            9'b001??????: lzc = 4'd2;
            9'b0001?????: lzc = 4'd3;
            9'b00001????: lzc = 4'd4;
            9'b000001???: lzc = 4'd5;
            9'b0000001??: lzc = 4'd6;
            9'b00000001?: lzc = 4'd7;
            9'b000000001: lzc = 4'd8;
            default:      lzc = 4'd9;
        endcase
    end
```

**Leading Zero Counter (LZC):** `casez` uses `?` as don't-care bits. The first matching pattern determines the LZC. This synthesizes to a priority encoder — one of the standard building blocks in floating-point hardware.

**Why needed only for subtraction?** When adding same-sign values, the result is always ≥ the larger operand (no cancellation). When subtracting close values (e.g., 1.001 - 1.000 = 0.001), significant bits cancel, leaving leading zeros that must be normalized away.

```verilog
    // Normalization
    wire add_overflow = s1_add_raw[9] && !s1_eff_sub;

    wire [8:0] add_shifted = add_overflow ? s1_add_raw[9:1]
                                          : (s1_add_raw[8:0] << lzc);

    // Unsigned exponent adjustment (avoids ISE 10.1 signed bug)
    wire [9:0] add_exp_adj = add_overflow
        ? ({2'b0, s1_large_exp} + 10'd1)
        : ({2'b0, s1_large_exp} - {6'd0, lzc});
    wire add_exp_underflow = !add_overflow
        && ({6'd0, lzc} > {2'b0, s1_large_exp});

    wire [6:0] add_final_mant = add_shifted[7:1];
    wire [7:0] add_final_exp  = add_exp_adj[7:0];
```

```verilog
    // ADD/SUB: split into special path (fast, registered flags only) and
    // normal path (slow, depends on LZC/normalize).  Parallel computation
    // with 2-way final select replaces the deep 11-entry priority chain.
    wire use_special = s1_any_nan || s1_inf_sub_inf ||
                       s1_a_is_inf || s1_b_is_inf ||
                       (s1_a_eff_zero && s1_add_b_is_zero) ||
                       s1_a_eff_zero || s1_add_b_is_zero ||
                       (s1_add_raw == 10'd0);

    wire [15:0] special_result =
        (s1_any_nan || s1_inf_sub_inf)      ? `BF16_NAN :
        s1_a_is_inf                         ? s1_a :
        s1_b_is_inf                         ? {s1_add_b_sign, s1_b_bits} :
        (s1_a_eff_zero && s1_add_b_is_zero) ? `BF16_ZERO_POS :
        s1_a_eff_zero                       ? {s1_add_b_sign, s1_b_bits} :
        s1_add_b_is_zero                    ? s1_a :
        `BF16_ZERO_POS;  // s1_add_raw == 0 case

    wire [15:0] normal_result =
        (add_exp_underflow || add_exp_adj == 10'd0 || add_exp_adj[9])
                                             ? `BF16_ZERO_POS :
        (!add_exp_adj[9] && add_exp_adj >= 10'd255)
                                             ? {s1_add_res_sign, 8'hFF, 7'd0} :
                                               {s1_add_res_sign, add_final_exp, add_final_mant};

    wire [15:0] add_result = use_special ? special_result : normal_result;
```

**Split path optimization:** Instead of a deep 11-entry priority chain (which creates ~6 cascaded LUTs), the code splits into two parallel paths: `special_result` (uses only registered `s1_` flags, fast) and `normal_result` (depends on LZC/normalize, slower). The `use_special` flag then selects with a single MUX. This reduces the critical path through the output logic.

### 2.5 MAX / MOV / RELU

```verilog
    wire a_gt_b_val =
        (a_is_nan)                      ? 1'b0 :
        (b_is_nan)                      ? 1'b1 :
        (a_sign != b_sign)              ? b_sign :
        (a_sign == 1'b0)                ? a_gt_b_mag :
                                          !a_gt_b_mag;

    wire [15:0] max_result = (a_is_nan || b_is_nan) ? `BF16_NAN :
                             a_gt_b_val ? a : b;

    wire [15:0] mov_result  = a;
    wire [15:0] relu_result = a[15] ? `BF16_ZERO_POS : a;
```

MAX performs signed floating-point comparison: NaN is never greater than anything; different signs means positive wins; same-sign positive uses larger magnitude; same-sign negative uses smaller magnitude (closer to zero). NaN inputs propagate to NaN output. MOV is pass-through. RELU checks the sign bit (a[15]) -- same trick as int16 since BF16 also uses bit 15 as the sign.

**BF16 RELU is identical to int16 RELU** in logic — both check bit [15]. For int16, bit 15 is the two's complement sign. For BF16, bit 15 is the IEEE sign bit. Both: if negative, output zero.

### 2.6 Output MUX

```verilog
    always @(*) begin
        case (s1_alu_op)
            `ALU_ADD:  result = add_result;
            `ALU_SUB:  result = add_result;
            `ALU_MUL:  result = s1_mul_result;
            `ALU_MAX:  result = s1_max_result;
            `ALU_MOV:  result = s1_mov_result;
            `ALU_BCAST: result = s1_mov_result;     // Added 2026-04-13 -- aliases MOV
            `ALU_RELU: result = s1_relu_result;
            default:   result = `BF16_ZERO_POS;
        endcase
    end
```

**All signal names use `s1_` prefix:** The output MUX operates in EX2 on registered values. MUL, MAX, MOV, and RELU results were fully computed in EX1 and simply passed through the pipeline register.

**ADD and SUB both output `add_result`** because the SUB→ADD transformation happened at line 75 (`add_b_sign = ~b_sign`). The add_result already accounts for the sign flip.

**ALU_BCAST aliases ALU_MOV** at this layer — both just output `s1_mov_result`. The lane-shuffle that makes BCAST distinct from MOV happens in simd_alu (§3) *before* operands reach this ALU, so `a` is already the broadcast-selected value by the time we get here. No new MUL/ADD/etc. compute path is needed.

---

## 3. simd_alu.v — Registered BF16/Scalar-INT16 Wrapper

> **Current implementation:** 3-cycle pipelined latency. A combinational BCAST mux feeds an input register for `effective_a`, operand B, `alu_op`, and `dtype`. The registered operands drive one lane-0 `int16_alu` plus four `bf16_alu` instances. A second wrapper register aligns the integer result and dtype with the BF16 results. `execute_stage.v` uses this EX3-aligned result directly.

### 3.1 Ports

```verilog
module simd_alu (
    input                       clk,
    input                       rst,
    input  [3:0]                alu_op,
    input  [2:0]                dtype,
    input  [`DATA_WIDTH-1:0]    operand_a,
    input  [`DATA_WIDTH-1:0]    operand_b,
    output [`DATA_WIDTH-1:0]    result
);
```

`clk`/`rst` drive the wrapper's input/alignment registers and the four BF16 lane pipelines. `dtype_r2 == DTYPE_BF16` selects the packed four-lane BF16 result exactly; every other dtype selects the replicated lane-0 signed-16 result. The output is already aligned with FMA in EX3.

### 3.2 BCAST Cross-Lane Shuffle (Before the Input Register)

```verilog
    // BCAST: select one lane from operand_a and replicate to all 4 positions
    wire [1:0] bcast_lane_sel = operand_b[1:0];
    reg [15:0] bcast_value;
    always @(*) begin
        case (bcast_lane_sel)
            2'd0: bcast_value = operand_a[15:0];
            2'd1: bcast_value = operand_a[31:16];
            2'd2: bcast_value = operand_a[47:32];
            default: bcast_value = operand_a[63:48];
        endcase
    end

    wire [`DATA_WIDTH-1:0] effective_a = (alu_op == `ALU_BCAST)
        ? {bcast_value, bcast_value, bcast_value, bcast_value}
        : operand_a;
```

**This is a 4:1 mux + replication.** Step through it:

1. The decoder packed the lane selector into `imm_ext[1:0]` (see batch3 §1.4 BCAST case). The execute stage's operand_b mux chose `imm_ext` because `use_imm=1`, so `operand_b[1:0]` now carries the lane select.
2. `bcast_value` is a 4:1 mux choosing one of the four 16-bit lanes of `operand_a`.
3. `effective_a` is a 2:1 mux: if the opcode is BCAST, replace the original `operand_a` with `{bcast_value, bcast_value, bcast_value, bcast_value}` (a 64-bit value where all four lanes hold the same 16 bits); otherwise pass `operand_a` through unchanged.

**Why this lives upstream of the ALUs:** The wrapper performs the cross-lane selection once, while the lane-0 integer ALU and each BF16 lane treat `ALU_BCAST` like MOV. The selected `effective_a` is registered before it reaches those ALUs. Structurally this adds a 16-bit-wide 4:1 lane selector and a 64-bit-wide effective-operand mux; an exact LUT cost is not available from source alone.

### 3.3 EX1→EX2 Input Register

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

This timing cut registers the BCAST/effective-A mux output together with operand B and the matching controls. The ALUs therefore see a self-consistent instruction after the first SIMD pipeline edge.

### 3.4 Lane ALU Instantiations

```verilog
    // Scalar INT16 ALU (lane 0 only, replicated to all 4 lanes).
    wire [15:0] int_lane0;
    int16_alu u_alu (
        .alu_op (alu_op_r),
        .a      (effective_a_r[15:0]),
        .b      (operand_b_r[15:0]),
        .result (int_lane0)
    );
```

```verilog
    wire [15:0] bf16_lane_result [0:`SIMD_LANES-1];
    genvar j;
    generate
        for (j = 0; j < `SIMD_LANES; j = j + 1) begin : bf16_lane
            bf16_alu u_bf16 (
                .clk    (clk),
                .rst    (rst),
                .alu_op (alu_op_r),
                .a      (effective_a_r[j*16+15 : j*16]),
                .b      (operand_b_r[j*16+15 : j*16]),
                .result (bf16_lane_result[j])
            );
        end
    endgenerate
```

The integer path consumes only registered lane 0 (`[15:0]`), then later replicates that one 16-bit result into all four output positions. The BF16 path remains true four-lane SIMD and has one `bf16_alu` per lane. BCAST affects `effective_a` before the input register, so both paths receive the selected value through `effective_a_r`.

**BF16 lane slicing: `effective_a_r[j*16+15 : j*16]`:**
```
j=0: bits [15:0]   = lane 0 (LSB)
j=1: bits [31:16]  = lane 1
j=2: bits [47:32]  = lane 2
j=3: bits [63:48]  = lane 3 (MSB)
```

### 3.5 Output Alignment Register + Result MUX

```verilog
    wire [`DATA_WIDTH-1:0] bf16_result = {bf16_lane_result[3], bf16_lane_result[2],
                                           bf16_lane_result[1], bf16_lane_result[0]};

    // EX2 -> EX3 alignment register
    reg [15:0]  int_lane0_r;
    reg [2:0]   dtype_r2;

    always @(posedge clk) begin
        if (rst) begin
            int_lane0_r <= 16'd0;
            dtype_r2    <= 3'd0;
        end else begin
            int_lane0_r <= int_lane0;
            dtype_r2    <= dtype_r1;
        end
    end

    wire [`DATA_WIDTH-1:0] int_result = {4{int_lane0_r}};

    assign result = (dtype_r2 == `DTYPE_BF16) ? bf16_result : int_result;
```

**Latency arithmetic inside `simd_alu`:**

| Path | First edge | Second edge | EX3 output |
|------|------------|-------------|------------|
| BF16 | `effective_a_r`, `operand_b_r`, and `alu_op_r` capture | each lane's `s1_*` state captures | four combinational BF16 lane outputs are packed |
| INT16 | registered lane-0 operands become available | `int_lane0_r` captures the combinational result | that result is replicated four times |
| dtype | `dtype_r1` captures | `dtype_r2` captures | exact-BF16 comparison selects the aligned path |

Both paths are aligned at the current `simd_alu` EX3 output. `execute_stage.v` does not register `simd_result` again; its final mux selects this value directly against the 3-cycle FMA output.

---

## 4. bf16_fma_unit.v — Single-Lane Fused Multiply-Add (3-Stage Pipeline)

306 lines. Computes `result = A × B + C` while retaining a wider product through the addition, followed by one final truncation to BF16. It is split into a 3-stage pipeline; the implementation does not perform IEEE round-to-nearest-even.

### 4.1 Why FMA Matters for Neural Networks

A dot product `sum = a[0]*b[0] + a[1]*b[1] + ... + a[n]*b[n]` is a sequence of FMA operations:
```
acc = 0
acc = a[0]*b[0] + acc    ← FMA
acc = a[1]*b[1] + acc    ← FMA
...
```

Each lane performs an independent multiply-accumulate. Four lanes therefore update four lane-local accumulators in parallel; the FMA unit contains no cross-lane reduction, so producing one scalar dot-product sum requires kernel-level accumulation/reduction across those lane results.

Here “fused” means the 16-bit significand product is kept at wider internal precision before C is added, rather than first truncating the product to BF16. The final pack simply discards low bits; there is no rounding-decision logic, so “one final precision reduction” is more exact than “one rounding.”

### 4.2 Port Declaration

```verilog
module bf16_fma_unit (
    input         clk,
    input         rst,
    input  [15:0] a,
    input  [15:0] b,
    input  [15:0] c,
    output reg [15:0] result
);
```

**Why `clk`/`rst`?** The original purely-combinational FMA had a critical path too long for the VP50's 8ns clock (125 MHz). The multiply, alignment, addition, and normalization together exceeded the timing budget. Splitting into three pipeline stages cuts the critical path to roughly one-third: Stage 1 (EX1) does multiply + pre-computed exponent arithmetic + magnitude sort; Stage 2 (EX2) does barrel shift + 19-bit add/sub; Stage 3 (EX3) does LZC + normalize + special-case MUX.

### 4.3 Field Extraction + Specials

Same pattern as `bf16_alu.v` — extract sign/exp/mant for all three operands, detect zero/inf/NaN/denorm for each. 12 detection wires total.

```verilog
    wire ab_is_zero = a_is_zero || b_is_zero || a_is_denorm || b_is_denorm;
    wire c_eff_zero = c_is_zero || c_is_denorm;
```

`ab_is_zero`: If either multiplicand is zero or denormal, the product is zero. This is a fast-path check. `c_eff_zero`: If the addend is zero or denormal, the FMA degenerates to plain multiply.

### 4.4 Stage 1 (EX1) — Multiply + Pre-Computed Exponent Arithmetic + Magnitude Sort

```verilog
    // Multiply: A x B (infers MULT18X18, ~2.3ns)
    wire        mul_sign = a_sign ^ b_sign;
    wire [7:0]  a_full = {1'b1, a_mant};
    wire [7:0]  b_full = {1'b1, b_mant};
    wire [15:0] product = a_full * b_full;

    // C mantissa widening (no multiply dependency)
    wire [17:0] c_mant_wide = {1'b1, c_mant, 10'b0};
```

The multiply and C widening are independent -- the C path has no data dependency on `product`, enabling parallel computation. The `ab_exp_sum` (defined in the pre-computed alignment section below) feeds both the pre-computed exponent arithmetic and the post-multiply normalization.

After the multiply, product normalization and widening select based on `product[15]`:

```verilog
    wire mul_norm = product[15];

    // Actual exponent values (unsigned, bit[9] = underflow indicator)
    wire [9:0] mul_exp_c0 = {1'b0, ab_sum_c0} - 10'd127;
    wire [9:0] mul_exp_c1 = {1'b0, ab_sum_c1} - 10'd127;
    wire [9:0] mul_exp_norm = mul_norm ? mul_exp_c1 : mul_exp_c0;

    wire [17:0] mul_mant_wide = mul_norm ? {1'b1, product[14:0], 2'b0}
                                         : {1'b1, product[13:0], 3'b0};
```

**Key difference from bf16_alu:** The product is NOT truncated to 7-bit mantissa here. Instead, it's WIDENED to 18 bits (`mul_mant_wide`). The extra bits preserve precision for the subsequent addition with C. This is what makes FMA "fused" — no intermediate rounding.

**18-bit internal precision:** The 16-bit product is widened/aligned into 18 bits before addition. This preserves more information than a BF16 intermediate, but the repository does not establish correctly rounded IEEE BF16 results, and the final pack truncates.

### 4.5 Stage 1 (EX1) — Pre-Computed Alignment

Stage 1 pre-computes exponent arithmetic and magnitude comparison for BOTH possible `product[15]` outcomes (mul_norm=0 and mul_norm=1). This eliminates the barrel shift from Stage 1 — it is deferred to Stage 2 where it operates on registered values.

```verilog
    //--------------------------------------------------------------
    // Pre-compute exponent arithmetic for BOTH mul_norm cases
    // in parallel with MULT18X18 (no product dependency).
    // ALL UNSIGNED: use (a_exp + b_exp) vs (127 + c_exp) comparison
    // to avoid signed subtraction entirely.
    //--------------------------------------------------------------
    wire [8:0] ab_exp_sum = {1'b0, a_exp} + {1'b0, b_exp};  // 0..510
    wire [8:0] ab_sum_c0  = ab_exp_sum;                       // mul_norm = 0
    wire [8:0] ab_sum_c1  = ab_exp_sum + 9'd1;                // mul_norm = 1
    wire [8:0] c_exp_bias = 9'd127 + {1'b0, c_exp};           // 127..382

    // Comparison: mul_exp >= c_exp  ⟺  (a_exp + b_exp + norm) >= (127 + c_exp)
    wire c0_ge = (ab_sum_c0 >= c_exp_bias);
    wire c1_ge = (ab_sum_c1 >= c_exp_bias);

    // Absolute exponent difference (compute both directions, select by comparison)
    wire [8:0] diff_c0_fwd = ab_sum_c0 - c_exp_bias;
    wire [8:0] diff_c0_rev = c_exp_bias - ab_sum_c0;
    wire [8:0] diff_c1_fwd = ab_sum_c1 - c_exp_bias;
    wire [8:0] diff_c1_rev = c_exp_bias - ab_sum_c1;

    wire [8:0] abs_diff_c0 = c0_ge ? diff_c0_fwd : diff_c0_rev;
    wire [8:0] abs_diff_c1 = c1_ge ? diff_c1_fwd : diff_c1_rev;

    wire [4:0] sa_c0 = (abs_diff_c0 > 9'd18) ? 5'd18 : abs_diff_c0[4:0];
    wire [4:0] sa_c1 = (abs_diff_c1 > 9'd18) ? 5'd18 : abs_diff_c1[4:0];

    // Comparison flags for magnitude sort
    wire gt_c0 = c0_ge && (ab_sum_c0 != c_exp_bias);
    wire gt_c1 = c1_ge && (ab_sum_c1 != c_exp_bias);
    wire eq_c0 = (ab_sum_c0 == c_exp_bias);
    wire eq_c1 = (ab_sum_c1 == c_exp_bias);
```

After the multiply completes, `product[15]` selects which set of pre-computed values to use:

```verilog
    // Select pre-computed exponent results
    wire exp_gt      = mul_norm ? gt_c1 : gt_c0;
    wire exp_eq      = mul_norm ? eq_c1 : eq_c0;
    wire exp_ge      = mul_norm ? c1_ge : c0_ge;
    wire [4:0] shift_amt = mul_norm ? sa_c1 : sa_c0;

    // Magnitude comparison (mantissa compare only for equal exponent)
    wire mul_mag_ge = exp_gt || (exp_eq && (mul_mant_wide >= c_mant_wide));

    // Sort by magnitude (barrel shift deferred to Cycle 2)
    wire [17:0] large_mant = mul_mag_ge ? mul_mant_wide : c_mant_wide;
    wire [17:0] small_mant = mul_mag_ge ? c_mant_wide   : mul_mant_wide;
    wire [9:0] aligned_exp = mul_mag_ge ? mul_exp_norm : {2'b0, c_exp};
```

**Key optimization:** By pre-computing exponent arithmetic for both `product[15]` outcomes, the critical path through the MULT18X18 only needs a final MUX-select, not a full exponent subtract + compare chain. The barrel shift is moved to Stage 2 where it operates on registered `small_mant` and `shift_amt` values.

### 4.5a Stage 1 (EX1) — Effective Operation + Result Sign

```verilog
    // Effective operation and result sign
    wire eff_sub  = (mul_sign != c_sign);
    wire res_sign = eff_sub ? (mul_mag_ge ? mul_sign : c_sign) : mul_sign;
```

`eff_sub` determines whether the FMA's addition phase is really a subtraction (when the multiply result and C have opposite signs). `res_sign` picks the sign of the larger-magnitude operand for subtraction, or the common sign for addition.

### 4.5b Stage 1 (EX1) — Standalone Multiply Result (fast path)

```verilog
    // Standalone multiply result (for c_eff_zero fast path)
    // Underflow: mul_exp_norm[9] set or mul_exp_norm == 0
    // Overflow: mul_exp_norm >= 255 and not underflowed
    wire mul_exp_under = mul_exp_norm[9] || (mul_exp_norm == 10'd0);
    wire mul_exp_over  = !mul_exp_norm[9] && (mul_exp_norm >= 10'd255);
    wire [6:0] mul_only_mant = mul_mant_wide[16:10];
    wire [15:0] mul_only_result =
        mul_exp_under ? {mul_sign, 15'd0} :
        mul_exp_over  ? {mul_sign, 8'hFF, 7'd0} :
        {mul_sign, mul_exp_norm[7:0], mul_only_mant};
```

Pre-packs the multiply-only BF16 result in Stage 1 for the `c_eff_zero` fast path. This avoids redundant packing in Stage 2 when C is zero (FMA degenerates to MUL). The underflow/overflow conditions use intermediate wires (`mul_exp_under`, `mul_exp_over`) with unsigned arithmetic -- `mul_exp_norm[9]` acts as the underflow indicator (set when the 10-bit subtraction wraps below zero).

### 4.5c Stage 1 (EX1) — Special Case Flags

```verilog
    // Special case flags
    wire any_nan = a_is_nan || b_is_nan || c_is_nan;
    wire mul_inf = a_is_inf || b_is_inf;
    wire inf_times_zero = (a_is_inf && (b_is_zero || b_is_denorm)) ||
                          (b_is_inf && (a_is_zero || a_is_denorm));
```

These flags drive the Stage 3 special-case priority chain. `inf_times_zero` detects the IEEE-754 invalid operation (∞ × 0), which produces NaN. All three flags are registered through both pipeline boundaries (`s1_` after Stage 1, then `s2_` after Stage 2).

### 4.5d Pipeline Register A: Stage 1 -> Stage 2

All of the Stage 1 results are latched into Pipeline Register A on the clock edge. Note that `small_mant` is registered **unshifted** -- the barrel shift is deferred to Stage 2:

```verilog
    reg [17:0] s1_large_mant;
    reg [17:0] s1_small_mant;
    reg [4:0]  s1_shift_amt;
    reg [9:0]  s1_aligned_exp;
    reg        s1_eff_sub;
    reg        s1_res_sign;
    reg        s1_mul_sign;
    reg        s1_c_sign;
    reg        s1_ab_is_zero;
    reg        s1_c_eff_zero;
    reg        s1_any_nan;
    reg        s1_mul_inf;
    reg        s1_inf_times_zero;
    reg        s1_c_is_inf;
    reg [15:0] s1_c;
    reg [15:0] s1_mul_only_result;

    always @(posedge clk) begin
        if (rst) begin
            s1_large_mant      <= 18'd0;
            s1_small_mant      <= 18'd0;
            s1_shift_amt       <= 5'd0;
            s1_aligned_exp     <= 10'd0;
            s1_eff_sub         <= 1'b0;
            s1_res_sign        <= 1'b0;
            s1_mul_sign        <= 1'b0;
            s1_c_sign          <= 1'b0;
            s1_ab_is_zero      <= 1'b0;
            s1_c_eff_zero      <= 1'b0;
            s1_any_nan         <= 1'b0;
            s1_mul_inf         <= 1'b0;
            s1_inf_times_zero  <= 1'b0;
            s1_c_is_inf        <= 1'b0;
            s1_c               <= 16'd0;
            s1_mul_only_result <= 16'd0;
        end else begin
            s1_large_mant      <= large_mant;
            s1_small_mant      <= small_mant;
            s1_shift_amt       <= shift_amt;
            s1_aligned_exp     <= aligned_exp;
            s1_eff_sub         <= eff_sub;
            s1_res_sign        <= res_sign;
            s1_mul_sign        <= mul_sign;
            s1_c_sign          <= c_sign;
            s1_ab_is_zero      <= ab_is_zero;
            s1_c_eff_zero      <= c_eff_zero;
            s1_any_nan         <= any_nan;
            s1_mul_inf         <= mul_inf;
            s1_inf_times_zero  <= inf_times_zero;
            s1_c_is_inf        <= c_is_inf;
            s1_c               <= c;
            s1_mul_only_result <= mul_only_result;
        end
    end
```

16 pipeline registers total. This is the first timing cut point -- multiply, pre-computed exponent arithmetic, and magnitude sort logic settles in Stage 1, then the registered values feed Stage 2's barrel shift + add logic. The `s1_` prefix identifies signals that have crossed the first pipeline boundary.

The barrel shift (`small_mant >> shift_amt`) has been moved OUT of Stage 1. Instead, `small_mant` and `shift_amt` are registered separately. This shortens Stage 1's critical path, which was previously: MULT18X18 -> normalize -> exponent diff -> magnitude compare -> barrel shift.

### 4.6 Stage 2 (EX2) — Barrel Shift + Addition

Stage 2 operates on registered `s1_` signals from Pipeline Register A. It performs the barrel shift (deferred from Stage 1) and the 19-bit add/sub:

```verilog
    // Barrel shift the smaller mantissa
    wire [17:0] small_shifted = s1_small_mant >> s1_shift_amt;

    // Add / subtract
    wire [18:0] sum = s1_eff_sub ? ({1'b0, s1_large_mant} - {1'b0, small_shifted})
                                 : ({1'b0, s1_large_mant} + {1'b0, small_shifted});
```

**Barrel shift moved here from Stage 1.** In the 2-stage design, the barrel shift was in Stage 1 alongside the multiply and alignment. Moving it to Stage 2 balances the pipeline — Stage 1 (EX1) handles multiply + pre-computation, Stage 2 (EX2) handles shift + add, Stage 3 (EX3) handles LZC + normalize.

### 4.6a Pipeline Register B: Stage 2 -> Stage 3

The sum, aligned exponent, and special-case flags are registered for Stage 3:

```verilog
    reg [18:0] s2_sum;
    reg [9:0]  s2_aligned_exp;
    reg        s2_eff_sub;
    reg        s2_res_sign;
    reg        s2_mul_sign;
    reg        s2_c_sign;
    reg        s2_ab_is_zero;
    reg        s2_c_eff_zero;
    reg        s2_any_nan;
    reg        s2_mul_inf;
    reg        s2_inf_times_zero;
    reg        s2_c_is_inf;
    reg [15:0] s2_c;
    reg [15:0] s2_mul_only_result;

    always @(posedge clk) begin
        if (rst) begin
            s2_sum             <= 19'd0;
            s2_aligned_exp     <= 10'd0;
            s2_eff_sub         <= 1'b0;
            s2_res_sign        <= 1'b0;
            s2_mul_sign        <= 1'b0;
            s2_c_sign          <= 1'b0;
            s2_ab_is_zero      <= 1'b0;
            s2_c_eff_zero      <= 1'b0;
            s2_any_nan         <= 1'b0;
            s2_mul_inf         <= 1'b0;
            s2_inf_times_zero  <= 1'b0;
            s2_c_is_inf        <= 1'b0;
            s2_c               <= 16'd0;
            s2_mul_only_result <= 16'd0;
        end else begin
            s2_sum             <= sum;
            s2_aligned_exp     <= s1_aligned_exp;
            s2_eff_sub         <= s1_eff_sub;
            s2_res_sign        <= s1_res_sign;
            s2_mul_sign        <= s1_mul_sign;
            s2_c_sign          <= s1_c_sign;
            s2_ab_is_zero      <= s1_ab_is_zero;
            s2_c_eff_zero      <= s1_c_eff_zero;
            s2_any_nan         <= s1_any_nan;
            s2_mul_inf         <= s1_mul_inf;
            s2_inf_times_zero  <= s1_inf_times_zero;
            s2_c_is_inf        <= s1_c_is_inf;
            s2_c               <= s1_c;
            s2_mul_only_result <= s1_mul_only_result;
        end
    end
```

The `s2_` prefix identifies signals that have crossed the second pipeline boundary. Special-case flags pass through both registers (Stage 1 -> `s1_` -> Stage 2 -> `s2_`).

### 4.6b Stage 3 (EX3) — LZC + Normalization

Stage 3 operates on registered `s2_` signals from Pipeline Register B:

```verilog
    // Overflow detection
    wire add_overflow = s2_sum[18] && !s2_eff_sub;

    // 18-bit leading zero count
    reg [4:0] lzc;
    always @(*) begin
        casez (s2_sum[17:0])
            18'b1?????????????????: lzc = 5'd0;
            18'b01????????????????: lzc = 5'd1;
            18'b001???????????????: lzc = 5'd2;
            18'b0001??????????????: lzc = 5'd3;
            18'b00001?????????????: lzc = 5'd4;
            18'b000001????????????: lzc = 5'd5;
            18'b0000001???????????: lzc = 5'd6;
            18'b00000001??????????: lzc = 5'd7;
            18'b000000001?????????: lzc = 5'd8;
            18'b0000000001????????: lzc = 5'd9;
            18'b00000000001???????: lzc = 5'd10;
            18'b000000000001??????: lzc = 5'd11;
            18'b0000000000001?????: lzc = 5'd12;
            18'b00000000000001????: lzc = 5'd13;
            18'b000000000000001???: lzc = 5'd14;
            18'b0000000000000001??: lzc = 5'd15;
            18'b00000000000000001?: lzc = 5'd16;
            18'b000000000000000001: lzc = 5'd17;
            default:                lzc = 5'd18;
        endcase
    end
```

**18-bit LZC vs 9-bit in bf16_alu:** FMA operates on wider mantissas, so the LZC must scan more bits. This is a larger priority encoder (18 inputs vs 9), but still O(log n) in hardware depth.

```verilog
    // Normalized mantissa and exponent (unsigned, bit[9] = underflow)
    wire [17:0] norm_mant = add_overflow ? s2_sum[18:1]
                                         : (s2_sum[17:0] << lzc);

    // Exponent adjustment: subtract LZC or add 1 for overflow
    // Use unsigned arithmetic with explicit underflow detection
    wire [9:0] exp_after_lzc = s2_aligned_exp - {5'b0, lzc};
    wire exp_lzc_underflow = ({5'b0, lzc} > s2_aligned_exp);

    wire [9:0] exp_after_ovf = s2_aligned_exp + 10'd1;

    wire [9:0] norm_exp = add_overflow ? exp_after_ovf : exp_after_lzc;
    wire norm_exp_neg = add_overflow ? 1'b0 : exp_lzc_underflow;

    // Pack to BF16: implicit 1 at bit 17, mantissa = bits [16:10]
    wire [6:0] final_mant = norm_mant[16:10];
    wire [7:0] final_exp  = norm_exp[7:0];
```

**Truncation to BF16:** After the wider add, the 18-bit result is reduced to the seven stored mantissa bits (`norm_mant[16:10]`). Low bits are discarded with no guard/round/sticky decision; this is a final truncation, not IEEE rounding.

### 4.7 Stage 3 (EX3) — Fast Paths + Special Cases + Output MUX

The `mul_only_result` is pre-computed in Stage 1 and passed through both pipeline registers as `s2_mul_only_result`. The normal FMA result and special case MUX operate in Stage 3:

```verilog
    // Underflow/overflow checks (unsigned)
    wire norm_under = norm_exp_neg || (norm_exp == 10'd0) || s2_aligned_exp[9];
    wire norm_over  = !norm_exp_neg && !s2_aligned_exp[9] && (norm_exp >= 10'd255);

    // Normal FMA result
    wire [15:0] fma_normal =
        (s2_sum == 19'd0)  ? `BF16_ZERO_POS :
        norm_under          ? `BF16_ZERO_POS :
        norm_over           ? {s2_res_sign, 8'hFF, 7'd0} :
        {s2_res_sign, final_exp, final_mant};

    // Special case priority + output MUX (from registered flags)
    always @(*) begin
        if (s2_any_nan || s2_inf_times_zero)
            result = `BF16_NAN;
        else if (s2_mul_inf && s2_c_is_inf && (s2_mul_sign != s2_c_sign))
            result = `BF16_NAN;          // inf + (-inf)
        else if (s2_mul_inf)
            result = {s2_mul_sign, 8'hFF, 7'd0};
        else if (s2_c_is_inf)
            result = s2_c;
        else if (s2_ab_is_zero && s2_c_eff_zero)
            result = `BF16_ZERO_POS;
        else if (s2_ab_is_zero)
            result = s2_c;              // 0*B + C = C
        else if (s2_c_eff_zero)
            result = s2_mul_only_result; // A*B + 0
        else
            result = fma_normal;
    end
```

**`s2_c_eff_zero` fast path:** When C=0 (first iteration of dot product, or when accumulator hasn't been initialized), the FMA degenerates to plain multiply. The `s2_mul_only_result` (pre-packed in Stage 1, passed through both pipeline registers) skips the entire addition/normalization logic.

**All special-case flags use `s2_` prefixed signals** — they were registered at both the Stage 1→2 and Stage 2→3 boundaries. This ensures the output MUX operates on stable, registered values.

---

## 5. execute_stage.v — The Top-Level Router

111 lines. Routes control and data to the compute units and drives DMEM. In the 6-stage pipeline, this module spans EX1, EX2, and EX3. Branch comparison/target logic is separate in `core_top` EX1, not in decode or `execute_stage`. The old `ex_busy`/`fma_cycle2` mechanism is absent; operations are aligned at EX3.

### 5.1 Port Declaration

```verilog
module execute_stage (
    input                       clk,
    input                       rst,

    // Control signals from ID/EX
    input  [3:0]                alu_op,
    input                       is_fma,
    input                       use_imm,
    input  [2:0]                dtype,
    input                       mem_write,

    // Data from ID/EX
    input  [`DATA_WIDTH-1:0]    rs1_data,
    input  [`DATA_WIDTH-1:0]    rs2_data,
    input  [`DATA_WIDTH-1:0]    rs3_data,
    input  [`DATA_WIDTH-1:0]    imm_ext,

    // ALU result output (valid in EX3)
    output [`DATA_WIDTH-1:0]    result,

    // Data memory interface (active in EX3)
    output [`DMEM_ADDR_W-1:0]   dmem_addr,
    output [`DATA_WIDTH-1:0]    dmem_wr_data,
    output                      dmem_wr_en
);
```

**No more `ex_busy` output.** The 4-stage design needed `ex_busy` around its multi-cycle FMA. In the 6-stage design, FMA spans EX1/EX2/EX3, and the current SIMD wrapper has its own 3-cycle alignment, so no special busy stall is needed.

### 5.2 Internal EX1→EX2→EX3 Registers

The execute stage owns two small internal pipeline registers (EX1→EX2 and EX2→EX3) for the FMA-select and memory side of the datapath. They are separate from the `pipeline_reg_ex` modules in `core_top.v`, which carry downstream control signals such as `reg_write`, `rd`, and `mem_read`. The current `simd_alu` already produces an EX3-aligned result, so neither execute-stage register carries SIMD result data.

```verilog
    //==========================================================================
    // EX1 -> EX2 internal pipeline register (FMA/memory side)
    //==========================================================================
    reg                      is_fma_r;
    reg                      mem_write_r;
    reg [`DATA_WIDTH-1:0]    rs2_data_r;
    reg [`DMEM_ADDR_W-1:0]   mem_addr_r;

    always @(posedge clk) begin
        if (rst) begin
            is_fma_r    <= 1'b0;
            mem_write_r <= 1'b0;
            rs2_data_r  <= {`DATA_WIDTH{1'b0}};
            mem_addr_r  <= {`DMEM_ADDR_W{1'b0}};
        end else begin
            is_fma_r    <= is_fma;
            mem_write_r <= mem_write;
            rs2_data_r  <= rs2_data;
            mem_addr_r  <= rs1_data[`DMEM_ADDR_W-1:0] + imm_ext[`DMEM_ADDR_W-1:0];
        end
    end

    //==========================================================================
    // EX2 -> EX3 internal pipeline register
    //==========================================================================
    reg                      is_fma_r2;
    reg                      mem_write_r2;
    reg [`DATA_WIDTH-1:0]    rs2_data_r2;
    reg [`DMEM_ADDR_W-1:0]   mem_addr_r2;

    always @(posedge clk) begin
        if (rst) begin
            is_fma_r2    <= 1'b0;
            mem_write_r2 <= 1'b0;
            rs2_data_r2  <= {`DATA_WIDTH{1'b0}};
            mem_addr_r2  <= {`DMEM_ADDR_W{1'b0}};
        end else begin
            is_fma_r2    <= is_fma_r;
            mem_write_r2 <= mem_write_r;
            rs2_data_r2  <= rs2_data_r;
            mem_addr_r2  <= mem_addr_r;
        end
    end
```

**What each flop carries:** `is_fma_r/r2` is the EX3 result-mux select; `mem_write_r/r2` is the EX3 DMEM write strobe; `rs2_data_r/r2` is the EX3 store data; and `mem_addr_r/r2` is the EX3 DMEM address (precomputed in EX1 from `rs1_data + imm_ext`). These signals make the full EX1→EX2→EX3 journey while `simd_alu` and the FMA units pipeline their own result data internally.

**No `fma_cycle2`/`ex_busy`:** The 4-stage design needed these to stall the pipeline during FMA's second cycle. In the 6-stage design, the FMA unit's 3-cycle pipeline (Stage 1 = multiply+pre-compute, Stage 2 = shift+add, Stage 3 = LZC+normalize) maps directly to EX1, EX2, and EX3. No special stalling mechanism is needed — all instructions flow through EX1→EX2→EX3 uniformly.

### 5.3 Operand B MUX

```verilog
    wire [`DATA_WIDTH-1:0] op_b = use_imm ? imm_ext : rs2_data;
```

The immediate/control path serves ADDI (`sign_ext(imm19)`), MOVI (`{4{imm16}}`), LD/ST (`sign_ext(offset12)` for the dedicated address adder), and BCAST (lane selector in bits [1:0]). Other register operations use `rs2_data`.

### 5.4 SIMD ALU Instantiation

```verilog
    wire [`DATA_WIDTH-1:0] simd_result;

    simd_alu u_simd_alu (
        .clk       (clk),
        .rst       (rst),
        .alu_op    (alu_op),
        .dtype     (dtype),
        .operand_a (rs1_data),
        .operand_b (op_b),
        .result    (simd_result)
    );
```

**Always runs.** Even for FMA, LD, ST, or branch instructions. The unused result is simply not selected. In the current implementation, `simd_result` is valid in EX3 after `simd_alu`'s registered input and BF16/INT16 alignment stages.

### 5.5 FMA Instantiation (4 Lanes)

```verilog
    wire [15:0] fma_lane_result [0:`SIMD_LANES-1];
    genvar k;
    generate
        for (k = 0; k < `SIMD_LANES; k = k + 1) begin : fma_lane
            bf16_fma_unit u_fma (
                .clk    (clk),
                .rst    (rst),
                .a      (rs1_data[k*16+15 : k*16]),
                .b      (rs2_data[k*16+15 : k*16]),
                .c      (rs3_data[k*16+15 : k*16]),
                .result (fma_lane_result[k])
            );
        end
    endgenerate
    wire [`DATA_WIDTH-1:0] fma_result = {fma_lane_result[3], fma_lane_result[2],
                                          fma_lane_result[1], fma_lane_result[0]};
```

**4 independent FMA lanes.** Each computes `A[k] × B[k] + C[k]`. No cross-lane communication — each lane is a fully independent FMA unit.

**FMA always uses register operands** — never immediates. `rs1_data` and `rs2_data` are used directly (not `op_b`). `rs3_data` is the accumulator from a third register.

### 5.6 Result MUX (EX3)

```verilog
    assign result = is_fma_r2 ? fma_result : simd_result;
```

Uses `is_fma_r2` (double-registered version from section 5.2), not `is_fma`. Both `fma_result` and `simd_result` are valid in EX3, so the mux select must also be from EX3 -- hence the double-registered `is_fma_r2`.

**For LD:** The `result` output for a LD instruction passes through the EX3/WB register, but the writeback MUX selects `mem_data` (DMEM read data) instead. The DMEM address comes from a **separate dedicated adder path** in execute_stage: `rs1_data + imm_ext` (base + offset) is computed in EX1, registered into `mem_addr_r` (EX1->EX2), then `mem_addr_r2` (EX2->EX3), which drives `dmem_addr` in EX3 (see section 5.7). The address presented in EX3 triggers a synchronous BRAM read, delivering data in WB for the writeback MUX.

### 5.7 Data Memory Interface (EX3)

> **Note:** Branch logic is NOT in `execute_stage.v`. Branch resolution is in `core_top.v` using the ID/EX branch operands and metadata; `execute_stage.v` has no branch-related ports or logic.

```verilog
    assign dmem_addr    = mem_addr_r2;
    assign dmem_wr_data = rs2_data_r2;
    assign dmem_wr_en   = mem_write_r2;
```

**All DMEM signals are now in EX3.** In the 4-stage design, these were combinational from EX1. In the 6-stage design:

**`dmem_addr` comes from `mem_addr_r2`** — a dedicated adder in EX1 computes `rs1_data + imm_ext` (base + offset), the result is registered into `mem_addr_r` (EX1→EX2), then `mem_addr_r2` (EX2→EX3). Only the lower 10 bits address the 1024-word DMEM.

**`dmem_wr_data` is `rs2_data_r2`** — the double-registered version of `rs2_data`, passing through both EX1→EX2 and EX2→EX3 registers (see section 5.2). This aligns the store data with the EX3 address.

**`dmem_wr_en` is `mem_write_r2`** — the double-registered version of `mem_write`. HIGH only for ST instructions, delayed by 2 cycles to match the EX3 timing.

**DMEM timing:** Address presented in EX3 → synchronous BRAM read delivers data in WB → writeback MUX selects it.

---

## Resource Summary

The current source supports structural counts, but the available integrated synthesis artifacts predate the latest checked-in `simd_alu.v`/`execute_stage.v`; exact current LUT, flip-flop utilization, and device percentages are therefore not verifiable from this repository.

| Unit | Source-level structure |
|------|------------------------|
| One lane-0 `int16_alu` | One 16×16 multiply operator; combinational result later replicated |
| Four `bf16_alu` lanes | Four 8×8 multiply operators; 126 declared pipeline-state bits per lane (504 total) |
| Four `bf16_fma_unit` lanes | Four 8×8 multiply operators; 164 declared pipeline-state bits per lane (656 total) |
| `simd_alu` wrapper | BCAST/dtype muxing plus 154 declared input/alignment-state bits |
| `execute_stage` | Result/DMEM routing plus 152 declared EX1→EX2→EX3 state bits |
| **Execute hierarchy total** | **9 multiply operators and 1,466 declared pipeline-state bits before synthesis optimization** |

These register/operator counts come directly from declarations and replicated instances. They are not a promise that synthesis maps every operator to a distinct MULT18x18 or retains every state bit.

**Current BCAST/INT16 structure:**
- Added one 4:1 lane-select mux plus one 2:1 `effective_a` mux in `simd_alu.v`.
- `effective_a`, operand B, `alu_op`, and dtype are registered before the ALUs.
- `ALU_BCAST` remains MOV/pass-through inside the one INT16 ALU and four BF16 ALUs.
- The INT16 result is computed from lane 0 and replicated; `execute_stage.v` has no `simd_result_r`.

---

**Next batch:** Writeback + Hazards + Memory — `pipeline_reg_ex.v`, `pipeline_reg_exwb.v`, `writeback_stage.v`, `hazard_unit.v`, `data_memory.v`
