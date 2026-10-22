# Batch 5 — Writeback, Hazard Unit, and Data Memory Walkthrough

> **Updated 2026-07-14:** Stale walkthrough content was reconciled with the current RTL implementation by Codex (GPT-5).

> **Update history.**
>
> - **2026-03-19 (Lab 8 refactor).** Hazard unit simplified: no `branch_taken` input and no `flush` output. Branch flushing moved to `core_top.v`, driven by `ex1_branch_taken`; `hazard_unit.v` now only produces `stall`. Branch penalty is 2 cycles.
> - **2026-06-25 checkpoint audit.** The writeback, hazard, and DMEM modules matched the stall-only 6-stage design at that checkpoint.
> - **2026-07-14.** Those five covered modules remain unchanged, but the end-to-end example, hierarchy, and resource summary were reconciled with the latest `simd_alu.v`: one lane-0 INT16 ALU now replaces four integer lanes and its result is replicated.

**Files covered:** `src/gpu/pipeline_reg_ex.v` (EX1/EX2 + EX2/EX3) → `src/gpu/pipeline_reg_exwb.v` → `src/gpu/writeback_stage.v` → `src/gpu/hazard_unit.v` → `src/gpu/data_memory.v`
These modules close the pipeline loop: the EX1/EX2 and EX2/EX3 registers (both instances of `pipeline_reg_ex`) carry control signals between execute sub-stages, the EX3/WB register feeds writeback, results commit to the register file, hazards are detected across four downstream stages (EX1, EX2, EX3, WB) to keep the pipeline correct, and the data memory provides LD/ST storage. Together with the previous batches, this completes the entire RTL hierarchy.

---

## Macro View — How Everything Closes the Loop

```
From Execute Stage EX1 (Batch 4)
        │
        ├─ idex_reg_write           ← Should WB write to register file?
        ├─ idex_mem_read            ← Is this a LD?
        ├─ idex_rd (4b)             ← Destination register
        ├─ idex_is_halt             ← HALT instruction?
        │
        ▼
┌────────────────────┐
│ pipeline_reg_ex    │  ← Control signals between EX1 and EX2 (instance u_ex1ex2)
│ (4 control signals)│     flush hardwired to 1'b0
└────────┬───────────┘
         │
         │  ex1ex2_reg_write, ex1ex2_rd, ex1ex2_mem_read, ex1ex2_is_halt
         │
         ▼
┌────────────────────┐
│ pipeline_reg_ex    │  ← Control signals between EX2 and EX3 (instance u_ex2ex3)
│ (4 control signals)│     flush hardwired to 1'b0
└────────┬───────────┘
         │
         │  ex2ex3_reg_write, ex2ex3_rd, ex2ex3_mem_read, ex2ex3_is_halt
         │
         │  From Execute Stage EX3:
         │  ex_result (64b)          ← ALU/FMA computed value (pipelined)
         │
         ▼
┌──────────────────┐
│ pipeline_reg_exwb│  ← Always latches (no stall input) — EX3/WB barrier
│ (5 signals)      │
└────────┬─────────┘
         │
         ├──────────────────────────────────────────┐
         ▼                                          │
┌──────────────────┐          ┌──────────────────┐  │
│ writeback_stage  │          │   data_memory    │  │
│ (combinational)  │◄─────────│  (BRAM Port A)   │  │
│                  │ mem_data  │  rd_data arrives │  │
│ MUX: mem_read ?  │          │  1 cycle after   │  │
│   mem_data :     │          │  addr driven     │  │
│   alu_result     │          └──────────────────┘  │
└────────┬─────────┘                                │
         │                                          │
         │ wb_reg_write + wb_rd + wb_data           │
         │                                          │
         ▼                                          │
┌──────────────────┐                                │
│  register_file   │  (inside decode_stage)         │
│  write port      │                                │
└──────────────────┘                                │
                                                    │
┌──────────────────┐                                │
│   hazard_unit    │◄───────────────────────────────┘
│                  │  exwb_rd, exwb_reg_write (from EX3/WB = WB stage)
│ Compares:        │  ex2ex3_rd, ex2ex3_reg_write (from EX2/EX3 = EX3 stage)
│  decode src regs │  ex1ex2_rd, ex1ex2_reg_write (from EX1/EX2 = EX2 stage)
│  vs 4 downstream │  idex_rd, idex_reg_write (from ID/EX = EX1 stage)
│  stage dests     │  dec_rs1/rs2/rs3 (from decode)
│                  │
│ Output:          │
│  stall → PC,     │
│    IF/ID, ID/EX  │
└──────────────────┘
```

---

## 0. pipeline_reg_ex.v — The EX1/EX2 and EX2/EX3 Barriers

35 lines. Carries control signals between execute sub-stages. This module is instantiated twice in `core_top`: once as `u_ex1ex2` and once as `u_ex2ex3`.

### 0.1 Port Declaration

```verilog
module pipeline_reg_ex (
    input                       clk,
    input                       rst,
    input                       flush,

    // Inputs (control signals from prior stage)
    input                       reg_write_in,
    input                       mem_read_in,
    input  [`REG_ADDR_W-1:0]    rd_in,
    input                       is_halt_in,

    // Outputs (control signals to next stage)
    output reg                  reg_write_out,
    output reg                  mem_read_out,
    output reg [`REG_ADDR_W-1:0]  rd_out,
    output reg                  is_halt_out
);
```

The port comments use generic “prior stage” and “next stage” names because the module is reused. `core_top` hardwires `flush` to `1'b0` in both instances.

**Why a separate module?** The execute_stage has its own internal pipeline registers for data signals (see Batch 4). But the control signals needed by EX3/WB and the hazard unit (`reg_write`, `mem_read`, `rd`, `is_halt`) must be visible at the core_top level. This module makes them available as wires for hazard detection. It is reused for both the EX1/EX2 and EX2/EX3 boundaries — same control signals, different instances.

**Flush hardwired to 1'b0:** Valid instructions in the execute stages always complete — there is no scenario where an EX instruction needs to be killed. NOP bubbles (from upstream flush/stall) flow through naturally with `reg_write=0`.

**Total flip-flop count:** 1 + 1 + 4 + 1 = **7 flip-flops**.

### 0.2 The Register Logic

```verilog
    always @(posedge clk) begin
        if (rst || flush) begin
            reg_write_out <= 1'b0;
            mem_read_out  <= 1'b0;
            rd_out        <= {`REG_ADDR_W{1'b0}};
            is_halt_out   <= 1'b0;
        end else begin
            reg_write_out <= reg_write_in;
            mem_read_out  <= mem_read_in;
            rd_out        <= rd_in;
            is_halt_out   <= is_halt_in;
        end
    end
```

**No stall input.** Unlike ID/EX (which stalls on data hazards), the EX pipeline registers always advance. The pipeline stall mechanism freezes IF, ID, and ID/EX, but instructions already in EX1 continue through EX2 and EX3 on subsequent cycles.

---

## 1. pipeline_reg_exwb.v — The EX3/WB Barrier

38 lines. A simple pipeline register that always latches.

### 1.0 Current Header

The current source accurately identifies the boundary:

```verilog
// pipeline_reg_exwb.v — EX3/WB pipeline register (not stall-gated)
```

### 1.1 Port Declaration

```verilog
module pipeline_reg_exwb (
    input                       clk,
    input                       rst,

    input                       reg_write_in,
    input                       mem_read_in,
    input  [`REG_ADDR_W-1:0]    rd_in,
    input  [`DATA_WIDTH-1:0]    alu_result_in,
    input                       is_halt_in,

    // Outputs to writeback stage
    output reg                  reg_write_out,
    output reg                  mem_read_out,
    output reg [`REG_ADDR_W-1:0]  rd_out,
    output reg [`DATA_WIDTH-1:0]  alu_result_out,
    output reg                  is_halt_out
);
```

The control inputs come from the EX2/EX3 register, while `alu_result_in` comes from `execute_stage`'s EX3 output. `core_top` connects them at the EX3/WB boundary.

**No stall input.** In the 4-stage design, EX/WB had a `stall` input driven by `ex_busy` to hold during FMA's first cycle. In the 6-stage design, `ex_busy` is eliminated — all instructions flow through EX1→EX2→EX3 uniformly, so EX3/WB always latches on every cycle.

**Control signals come from EX2/EX3 register** (not directly from ID/EX). The `reg_write`, `mem_read`, `rd`, and `is_halt` have already been delayed by two cycles through `pipeline_reg_ex` (u_ex1ex2 then u_ex2ex3), so they arrive at EX3/WB aligned with the EX3 data output.

**Only 5 data signals** (vs 15 in ID/EX). What remains for writeback is just: should we write? where? what value? is it a load? is it halt?

**Total flip-flop count:** 1 + 1 + 4 + 64 + 1 = **71 flip-flops** (versus 285 in ID/EX).

### 1.2 The Register Logic

```verilog
    always @(posedge clk) begin
        if (rst) begin
            reg_write_out  <= 1'b0;
            mem_read_out   <= 1'b0;
            rd_out         <= {`REG_ADDR_W{1'b0}};
            alu_result_out <= {`DATA_WIDTH{1'b0}};
            is_halt_out    <= 1'b0;
        end else begin
            reg_write_out  <= reg_write_in;
            mem_read_out   <= mem_read_in;
            rd_out         <= rd_in;
            alu_result_out <= alu_result_in;
            is_halt_out    <= is_halt_in;
        end
    end
```

On reset, all outputs are zeroed — `reg_write=0` prevents spurious writes, `rd` goes to R0 (writes to R0 are ignored anyway), and `alu_result` is zeroed. The `else` branch unconditionally latches all inputs — there is no stall gate. In the 4-stage design, this had `else if (!stall)` to hold during FMA busy. In the 6-stage design, there's no `ex_busy` — all instructions flow through EX1→EX2→EX3→WB uniformly. The register always latches on every cycle.

**What happens when a NOP bubble flows through?** The EX2/EX3 register outputs `reg_write=0` for bubbles. EX3/WB latches this zero. Writeback sees `reg_write=0` and doesn't write the register file. The bubble passes harmlessly.

---

## 2. writeback_stage.v — The Result MUX

21 lines. The simplest stage in the pipeline — purely combinational, just a 2:1 MUX plus pass-through.

### 2.1 Port Declaration

```verilog
module writeback_stage (
    // From EX/WB pipeline register
    input                       reg_write_in,
    input                       mem_read,
    input  [`REG_ADDR_W-1:0]    rd_in,
    input  [`DATA_WIDTH-1:0]    alu_result,

    // From DMEM (synchronous read, BRAM output register = EX/WB for loads)
    input  [`DATA_WIDTH-1:0]    mem_data,

    // To register file write port (in decode stage)
    output                      reg_write_out,
    output [`REG_ADDR_W-1:0]    rd_out,
    output [`DATA_WIDTH-1:0]    data_out
);
```

The `reg_write_in`, `mem_read`, `rd_in`, and `alu_result` come from the EX3/WB pipeline register outputs. The `mem_data` input comes directly from DMEM Port A's `rd_data` — it does NOT pass through the EX3/WB register. The output signals (`reg_write_out`, `rd_out`, `data_out`) connect to the register file write port inside decode_stage.

**`mem_data` comes directly from DMEM**, not from the EX3/WB register. This is because:
- In EX3, the LD instruction drives `dmem_addr` → DMEM Port A
- DMEM has synchronous read (1-cycle latency) — data appears at `rd_data` on the NEXT posedge
- That "next posedge" is the writeback cycle — perfectly aligned

The BRAM's output register effectively IS the EX3/WB latch for load data. No extra register needed.

### 2.2 The Logic — Three Lines

```verilog
    // Pass through control signals
    assign reg_write_out = reg_write_in;
    assign rd_out        = rd_in;

    // MUX: load data or ALU result
    assign data_out = mem_read ? mem_data : alu_result;
```

`reg_write_out` enables the register file write; `rd_out` selects the destination register address. The 64-bit `data_out` MUX selects between DMEM load data (when `mem_read=1`, i.e., a LD instruction) and the ALU/FMA result (for everything else).

**That's the entire writeback stage.** One 64-bit 2:1 MUX and two pass-through wires.

**For different instruction types:**

| Instruction | `reg_write` | `mem_read` | `data_out` | Effect |
|-------------|-------------|------------|------------|--------|
| ADD R3,R1,R2 | 1 | 0 | ALU result (R1+R2) | Write sum to R3 |
| LD R1, 5(R0) | 1 | 1 | DMEM[5] data | Write loaded value to R1 |
| ST R1, 5(R0) | 0 | 0 | (don't care) | No register write |
| NOP | 0 | 0 | (don't care) | No register write |
| HALT | 0 | 0 | (don't care) | No register write |
| BLT rs1,rs2 | 0 | 0 | (don't care) | No register write |

---

## 3. hazard_unit.v — The Pipeline Safety Net

44 lines. Detects data dependencies across four downstream stages (EX1, EX2, EX3, WB) and generates a stall signal. The 6-stage pipeline has no FMA-specific `ex_busy` input.

### 3.1 Why Hazard Detection Is Needed

Without the hazard unit, this sequence would produce wrong results:

```
MOVI R1, 10       ← Cycle 0: Fetch
                   ← Cycle 1: Decode (R1 write not yet happened)
ADD  R2, R1, R0   ← Cycle 1: Fetch
                   ← Cycle 2: Decode reads R1 — but R1 hasn't been written yet!
                              R1 still contains 0 (or stale value)
                              ADD would compute 0 + 0 = 0, not 10 + 0 = 10
```

The hazard unit detects that `ADD` reads R1 while `MOVI` (in execute) is about to write R1. It stalls the pipeline for 1–4 cycles until the write completes and R1 has the correct value.

### 3.2 Port Declaration

```verilog
module hazard_unit (
    // Decode-stage source registers
    input  [`REG_ADDR_W-1:0]    de_rs1,
    input  [`REG_ADDR_W-1:0]    de_rs2,
    input  [`REG_ADDR_W-1:0]    de_rs3,
    input                       de_is_fma,

    // EX1 stage destination (from ID/EX register)
    input  [`REG_ADDR_W-1:0]    ex1_rd,
    input                       ex1_reg_write,

    // EX2 stage destination (from EX1/EX2 register)
    input  [`REG_ADDR_W-1:0]    ex2_rd,
    input                       ex2_reg_write,

    // EX3 stage destination (from EX2/EX3 register)
    input  [`REG_ADDR_W-1:0]    ex3_rd,
    input                       ex3_reg_write,

    // WB stage destination (from EX3/WB register)
    input  [`REG_ADDR_W-1:0]    wb_rd,
    input                       wb_reg_write,

    output                      stall
);
```

The decode-stage source register inputs (`de_rs1`, `de_rs2`, `de_rs3`) come from decode_stage via core_top. `de_is_fma` indicates whether `de_rs3` is active (only FMA instructions use a third source operand). The EX1 destination (`ex1_rd`, `ex1_reg_write`) comes from the ID/EX register (`idex_rd`, `idex_reg_write`). EX2 comes from EX1/EX2 register, EX3 from EX2/EX3 register, and WB from EX3/WB register. The `stall` output drives PC hold, IF/ID hold, and ID/EX bubble insertion through `core_top.v`.

**No more `ex_busy` or `ex_mem_read` inputs.** The 6-stage pipeline eliminates FMA-specific stalling. The `ex_mem_read` was reserved for load-use hazard detection (never used differently from `ex_reg_write`), and is removed for clarity. Now the hazard unit checks four downstream stages: EX1, EX2, EX3, and WB.

### 3.3 Hazard Detection Logic

```verilog
    // Data hazard detection — check all 4 downstream stages
    wire ex1_hazard = ex1_reg_write && (ex1_rd != `REG_ZERO) &&
                      ((ex1_rd == de_rs1) || (ex1_rd == de_rs2) ||
                       (de_is_fma && (ex1_rd == de_rs3)));

    wire ex2_hazard = ex2_reg_write && (ex2_rd != `REG_ZERO) &&
                      ((ex2_rd == de_rs1) || (ex2_rd == de_rs2) ||
                       (de_is_fma && (ex2_rd == de_rs3)));

    wire ex3_hazard = ex3_reg_write && (ex3_rd != `REG_ZERO) &&
                      ((ex3_rd == de_rs1) || (ex3_rd == de_rs2) ||
                       (de_is_fma && (ex3_rd == de_rs3)));

    wire wb_hazard = wb_reg_write && (wb_rd != `REG_ZERO) &&
                     ((wb_rd == de_rs1) || (wb_rd == de_rs2) ||
                      (de_is_fma && (wb_rd == de_rs3)));
```

All four hazard detectors follow the same pattern. Taking `ex1_hazard` as the example:

- **`ex1_reg_write`:** If EX1 isn't writing a register (NOP, ST, branch, HALT), there's no hazard.
- **`ex1_rd != REG_ZERO`:** R0 is hardwired to zero. No dependency possible — even if decode reads R0, the value is always 0 regardless of what EX1 writes.
- **`ex1_rd == de_rs1`:** The classic Read-After-Write (RAW) hazard. Decode wants to read a register that EX1 is about to write. The value won't be ready for 4 more cycles (EX1→EX2→EX3→WB). The same check applies to `de_rs2` and conditionally to `de_rs3` (only for FMA instructions, gated by `de_is_fma`).

**Four-stage checking** (vs two in the 4-stage design). The additional EX2 and EX3 checks are needed because the 6-stage pipeline has more stages between decode and writeback.

**Conservative source checks:** `de_rs1` and `de_rs2` are compared unconditionally; only rs3 is qualified by `de_is_fma`. `decode_stage` supplies its branch/ST-aware read-address muxes, so real branch and store-data dependencies are covered. For instructions whose second extracted field is unused or overlaps an immediate (for example ADDI, MOVI, LD, and BCAST), that field can still match a downstream destination and cause a false-positive stall. This costs performance but does not corrupt results.

**Why check WB too?** The register-file array is written with a nonblocking assignment at the clock edge. Its asynchronous output reflects the new value after that edge, but ID/EX capturing operands on the same edge sees the pre-write value. Keeping the WB hazard for that cycle makes decode wait and capture on a later edge.

**In a forwarding pipeline**, you'd bypass outputs directly to decode, eliminating most stalls. This design chose simplicity (stall-only) over performance (forwarding).

### 3.4 Output Generation

```verilog
    assign stall = (ex1_hazard || ex2_hazard || ex3_hazard || wb_hazard);
```

**Four-way OR:** Any of the four downstream stages having a hazard triggers a stall. Worst case is 4 stall cycles (instruction in EX1 writing a register that decode reads → stall until it reaches WB and completes the write).

**Stall is independent of branch handling.** The stall signal is a pure function of RAW hazards. Branch resolution happens separately in `core_top.v` from the ID/EX branch metadata. If a branch source register is hazardous, the branch instruction stalls in decode until the correct values are available, then advances to EX1 and is resolved there.

**No more `ex_busy`:** The 4-stage design OR'd `ex_busy` here for FMA stalling. The 6-stage pipeline eliminates this entirely — FMA's 3-cycle pipeline naturally maps to EX1+EX2+EX3.

**Simple and clean.** `hazard_unit.v` has no branch ports. When EX1 takes a branch, `core_top.v` redirects the PC and flushes IF/ID and ID/EX with `ex1_branch_taken`, giving a 2-cycle taken-branch penalty.

### 3.5 Stall Timing Diagram

```
Cycle:    1        2        3        4        5        6        7        8
          ──────   ──────   ──────   ──────   ──────   ──────   ──────   ──────
IF/ID:    MOVI R1  ADD R2,  (held)   (held)   (held)   (held)   ADD R2,  ...
                   R1,R0                                         R1,R0
ID/EX:    (bubble) MOVI R1  (bubble) (bubble) (bubble) (bubble) (bubble) ADD R2,R1,R0
EX1/EX2:  ...      (bubble) MOVI R1  (bubble) (bubble) (bubble) ...      ...
EX2/EX3:  ...      ...      (bubble) MOVI R1  (bubble) (bubble) ...      ...
EX3/WB:   ...      ...      ...      (bubble) MOVI R1  (bubble) ...      ...
WB:       ...      ...      ...      ...      (bubble) MOVI R1  ...      ...

Cycle 2: Decode sees ADD reading R1. MOVI R1 is in ID/EX (EX1) with reg_write=1.
         ex1_hazard = 1 → stall = 1
         PC holds, IF/ID holds ADD, ID/EX gets bubble.

Cycle 3: MOVI R1 moves to EX1/EX2 (EX2). ADD still in decode.
         ex1_hazard: ex1_rd = R0 (bubble), no hazard.
         ex2_hazard: ex2_rd = R1 (MOVI), de_rs1 = R1 → ex2_hazard = 1 → stall.
         PC holds, IF/ID holds ADD, ID/EX gets bubble.

Cycle 4: MOVI R1 moves to EX2/EX3 (EX3). ADD still in decode.
         ex1_hazard: no. ex2_hazard: no.
         ex3_hazard: ex3_rd = R1 (MOVI), de_rs1 = R1 → ex3_hazard = 1 → stall.
         PC holds, IF/ID holds ADD, ID/EX gets bubble.

Cycle 5: MOVI R1 moves to EX3/WB (WB). ADD still in decode.
         ex1_hazard: no. ex2_hazard: no. ex3_hazard: no.
         wb_hazard: wb_rd = R1 (MOVI), de_rs1 = R1 → wb_hazard = 1 → stall.
         PC holds, IF/ID holds ADD, ID/EX gets bubble.

Cycle 6: MOVI R1 in WB writes R1. Then moves out.
         No hazard. Stall = 0.

Cycle 7: ADD finally advances into ID/EX. Reads R1 = correct value.
```

**Total penalty: 4 stall cycles** for a back-to-back dependency (vs 2 in the 4-stage design). This is the cost of the extra pipeline stages. With forwarding, this would be 0 or 1 cycle.

### 3.6 All Possible Hazard Scenarios

| Decode reads | EX1 writes | EX2 writes | EX3 writes | WB writes | Result |
|---|---|---|---|---|---|
| R1 | R1 | — | — | — | `ex1_hazard` → stall, then ex2, ex3, wb = 4 cycles |
| R1 | — | R1 | — | — | `ex2_hazard` → stall, then ex3, wb = 3 cycles |
| R1 | — | — | R1 | — | `ex3_hazard` → stall, then wb = 2 cycles |
| R1 | — | — | — | R1 | `wb_hazard` → stall 1 cycle |
| R1 | R2 | — | — | R1 | `wb_hazard` → stall 1 cycle |
| R0 | R0 | — | — | — | No stall (R0 exempt) |
| R1 (FMA rs3) | R1 | — | — | — | `ex1_hazard` (de_is_fma check matches rs3) → stall |
| R1 | — | — | — | — | No stall (no one is writing R1) |
| Branch operands hazard-free | — | — | — | — | No RAW stall; branch resolves in EX1 via `core_top.v` |

---

## 4. data_memory.v — 1024x64-bit True Dual-Port BRAM

37 lines. The data storage for LD/ST operations and external host access.

### 4.1 Port Declaration

```verilog
module data_memory (
    input                            clk,

    // Port A — Core pipeline
    input  [`DMEM_ADDR_W-1:0]       addr,
    input                            wr_en,
    input  [`DATA_WIDTH-1:0]        wr_data,
    output reg [`DATA_WIDTH-1:0]    rd_data,

    // Port B — External host
    input  [`DMEM_ADDR_W-1:0]       addr_b,
    input                            wr_en_b,
    input  [`DATA_WIDTH-1:0]        wr_data_b,
    output reg [`DATA_WIDTH-1:0]    rd_data_b
);
```

A single clock drives both ports. Port A serves the core pipeline: `addr` is a 10-bit address from execute_stage (base + offset), `wr_en` is the ST write enable, `wr_data` is the 64-bit store data from the register file (via execute), and `rd_data` is the 64-bit LD output that feeds the writeback MUX (with 1-cycle synchronous latency). Port B serves the external host: `addr_b`/`wr_en_b`/`wr_data_b` let the host pre-load weights and inputs before execution, and `rd_data_b` lets the host read results after `kernel_done`.

### 4.2 Memory Array

```verilog
    // Memory array — 1024 x 64-bit
    reg [`DATA_WIDTH-1:0] mem [0:`DMEM_DEPTH-1];
```

This declares 1024 entries x 64 bits = 65,536 bits = 64 Kbits. XST infers approximately 4 Block RAMs (each 18 Kbit). Each 64-bit word holds 4 packed SIMD lanes.

**64-bit words:** Each DMEM entry holds a full SIMD vector (4 x 16-bit elements). A single LD instruction fetches all 4 lane values in one memory access. No lane masking or partial reads.

**Synthesis mapping:** 1024 × 64 bits = 64 Kbits. Each VP50 Block RAM is 18 Kbits configurable. XST will likely use 4 Block RAMs in parallel (each configured as 1024 × 16 or 1024 × 18) to build the 64-bit width.

### 4.3 Port A — Core Pipeline Access

```verilog
    // Port A: synchronous write + read (read-first)
    always @(posedge clk) begin
        if (wr_en)
            mem[addr] <= wr_data;
        rd_data <= mem[addr];
    end
```

On ST instructions, `wr_en` is asserted and `wr_data` is written to `mem[addr]`. The `rd_data` output always captures `mem[addr]` on every posedge (1-cycle synchronous latency). This is read-first behavior: if writing and reading the same address simultaneously, the read gets the OLD value (before the write takes effect).

**No read enable** (unlike IMEM Port A which has `rd_en` for stall support). DMEM always reads. This is fine because:
- For LD instructions, the read data is needed (writeback MUX selects it)
- For non-LD instructions, the read data is ignored (writeback MUX selects ALU result)
- The address bus is driven by execute_stage's dedicated address adder (`rs1_data + imm_ext`), doubly-registered through EX1→EX2→EX3. For non-memory instructions, this address is meaningless, and the read data is discarded.

**No DMEM stall support needed:** The DMEM read is consumed by writeback. DMEM's read output is always available the cycle after the address is driven (in EX3), and writeback consumes it normally in WB.

**Memory ordering and read-first behavior:** Port A presents only one address per cycle. On an ST edge, the optional write and the unconditional read use that same address, and `rd_data` receives the pre-write value; the pipeline ignores it because ST has `mem_read=0`. An adjacent LD reaches Port A on a later cycle and observes the ordered result of the earlier store. The hazard unit compares register dependencies only—it has no memory-address comparison and is not what establishes memory ordering. Same-address collisions with independently driven Port B are outside this single-port argument and should be avoided.

### 4.4 Port B — External Host Access

```verilog
    // Port B: synchronous write + read (read-first)
    always @(posedge clk) begin
        if (wr_en_b)
            mem[addr_b] <= wr_data_b;
        rd_data_b <= mem[addr_b];
    end
```

**Identical structure to Port A.** The host uses Port B to:
1. **Phase 1 (LOAD):** Write neural network weights, biases, and input data into DMEM while `rst=1`
2. **Phase 3 (READ):** Read computation results from DMEM after `kernel_done=1`

**Simultaneous access:** Port A and Port B can operate on different addresses simultaneously. During execution the core uses Port A while the host normally idles Port B. The per-port read-first code does not fully specify same-address cross-port read/write or write/write collision results, so software must avoid those collisions.

### 4.5 DMEM vs IMEM Comparison

| Feature | IMEM | DMEM |
|---------|------|------|
| Width | 32 bits (1 instruction) | 64 bits (4 SIMD lanes) |
| Depth | 1024 words | 1024 words |
| Port A | Read-only with `rd_en` | Read + Write |
| Port A read enable | Yes (`!stall && !halted && !ex1_branch_taken`) | No (always reads) |
| Port B | Read + Write (host) | Read + Write (host) |
| Block RAMs | ~2 | ~4 |
| Address source | PC (`program_counter`) | Dedicated low-10-bit base+offset adder (`execute_stage`) |

---

## 5. End-to-End Example — Kernel vec_add Traced Through All Batches

The example follows vec_add end to end, then focuses on the dependency transitions that the RTL can describe unambiguously without inventing a second IF/ID instruction register.

### 5.1 Program and Data

```
IMEM[0] = LD  R1, 0(R0)     — Load A[0..3] from DMEM[0] into R1
IMEM[1] = LD  R2, 1(R0)     — Load B[0..3] from DMEM[1] into R2
IMEM[2] = ADD R3, R1, R2    — S16 path adds lane 0, then replicates that result
IMEM[3] = ST  R3, 2(R0)     — Store R3 to DMEM[2]
IMEM[4] = HALT

DMEM[0] = {0x0001, 0x0002, 0x0003, 0x0004}  = lanes {3,2,1,0} = {1,2,3,4}
DMEM[1] = {0x0005, 0x0006, 0x0007, 0x0008}  = lanes {3,2,1,0} = {5,6,7,8}
```

### 5.2 Dependency-Focused Trace

A literal table with separate “IF/ID instruction” and “Decode instruction” columns would be misleading in this design: `ifid_instruction` is directly assigned from the IMEM registered output and is the instruction consumed by decode. They are not two independently advancing instruction registers. The useful trace is therefore the RAW-dependency sequence:

1. The two LD instructions issue in order and enter the execute pipeline one cycle apart.
2. When ADD reaches decode, the younger producer (LD R2) is in EX1 and the older producer (LD R1) is farther downstream. The hazard unit asserts `stall`.
3. While stalled, PC, IMEM output, and fetch metadata hold the ADD; `core_top` flushes ID/EX to a NOP each cycle. The two loads continue through EX1 → EX2 → EX3 → WB.
4. The youngest producer occupies EX1, EX2, EX3, and WB on four successive hazard cycles. Once its WB hazard clears, ADD captures the now-written R1/R2 values and advances.
5. On the current non-BF16 path, ADD computes lane 0 as `4 + 8 = 12`, registers it, and replicates it into all four R3 positions. ST then encounters the analogous RAW dependency on R3, remains in decode while ADD crosses the four checked stages, and advances only after R3 is safe to capture.
6. In ST's EX3 cycle, the dedicated address path selects DMEM[2] and writes `{12, 12, 12, 12}`. HALT follows through the pipeline and sets the registered completion latch when its EX3/WB indication is sampled.

This excerpt explains both dependency classes without pretending that ST disappears while ADD is stalled. Exact absolute cycle numbers depend on the chosen reset-release edge and how the observer labels synchronous BRAM output cycles; the four-stage hazard progression is fixed by the RTL.

---


## Source-Level Resource Accounting

The available integrated synthesis artifacts predate the latest checked-in SIMD/execute source, so exact current LUT/FF utilization and device percentages cannot be verified. The RTL does support these declaration-level counts:

| State or structure | Source-level amount |
|--------------------|---------------------|
| Program counter + fetch metadata | 10 + 11 bits |
| Register-file array | 1,024 declared bits |
| ID/EX register | 285 bits |
| Execute hierarchy (`bf16_alu`/FMA/SIMD/execute registers) | 1,466 declared bits |
| Two `pipeline_reg_ex` instances + EX3/WB + halt latch | 14 + 71 + 1 bits |
| **Declared core state subtotal** | **2,882 bits before synthesis optimization and BRAM output registers** |
| Multiply operators | 9 source operators (one lane-0 INT16, four BF16-ALU, four BF16-FMA) |
| Logical memories | IMEM 1024×32; DMEM 1024×64 |

Synthesis may optimize constant/special register entries or share/map operators differently, so these are structural facts rather than post-map utilization numbers.

---

## Complete Pipeline Hierarchy (All Batches)

```
gpu_top                                          ← Batch 1: External boundary
├── core_top                                     ← Batch 1: Pipeline orchestrator (6-stage)
│   ├── program_counter                          ← Batch 2: PC generation
│   ├── fetch_stage                              ← Batch 2: IF/ID metadata
│   ├── decode_stage                             ← Batch 3: Instruction cracking
│   │   ├── instruction_decoder                  ← Batch 3: Combinational decode
│   │   └── register_file                        ← Batch 3: 16×64 FF-based, 3R1W
│   ├── pipeline_reg_idex                        ← Batch 3: ID/EX barrier (285 FFs)
│   ├── execute_stage                            ← Batch 4: Compute routing (EX1+EX2+EX3)
│   │   ├── simd_alu                             ← Batch 4: 4-lane BF16 / scalar-INT16 wrapper
│   │   │   ├── int16_alu ×1                     ← Batch 4: Lane-0 integer ALU (result replicated)
│   │   │   └── bf16_alu ×4                      ← Batch 4: BFloat16 ALU per lane (2-cycle)
│   │   └── bf16_fma_unit ×4                     ← Batch 4: FMA per lane (3-cycle)
│   ├── pipeline_reg_ex u_ex1ex2                 ← Batch 5: EX1/EX2 barrier (7 FFs)
│   ├── pipeline_reg_ex u_ex2ex3                 ← Batch 5: EX2/EX3 barrier (7 FFs)
│   ├── pipeline_reg_exwb                        ← Batch 5: EX3/WB barrier (71 FFs)
│   ├── writeback_stage                          ← Batch 5: Result MUX
│   └── hazard_unit                              ← Batch 5: 4-stage stall-only RAW control
├── instruction_memory                           ← Batch 2: 1024×32 BRAM
└── data_memory                                  ← Batch 5: 1024×64 BRAM
```

`src/gpu` contains 19 Verilog module files. The instantiated tree above includes replicated lane instances, so a single “module count” must distinguish unique module definitions from instances. The architecture is a 6-stage pipeline (IF → ID → EX1 → EX2 → EX3 → WB) with 9 source-level multiply operators; current post-map LUT/FF totals remain unverified.

---

**This completes the full RTL walkthrough across all batches.**
