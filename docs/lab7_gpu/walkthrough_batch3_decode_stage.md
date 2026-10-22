# Batch 3 — Decode Stage Walkthrough

> **Updated 2026-07-14:** Stale walkthrough content was reconciled with the current RTL implementation by Codex (GPT-5).

> **Update history.**
>
> - **2026-03-19 (Lab 8 branch refactor).** Branch moved from Decode to EX1. `decode_stage.v` no longer has `branch_taken`/`branch_target` outputs or the 64-bit signed comparator; it emits `branch_type_out` and `pc_out`, and the EX1 comparator in `core_top.v` does the branch decision. Branch penalty is 2 cycles. `pipeline_reg_idex` carries `branch_type` and `pc`; it no longer carries source register address outputs.
> - **2026-04-13 (BCAST -- commit `e14d012`).** §1.4 below gained one new opcode case: **BCAST** (`OP_BCAST = 5'b11010`). The decoder picks `instruction[1:0]` as the lane select, zero-extends to 64 bits, and routes it through `imm_ext` so the simd_alu's BCAST mux receives the lane index on `operand_b[1:0]` at EX1. See `## Cross-lane Broadcast` below. The cross-lane shuffle itself is in `batch4 §3` (simd_alu).
> - **2026-06-25.** Refreshed against current RTL. The branch-related walkthrough text below now describes EX1 branch resolution instead of the older decode-resolution design.

**Files covered:** `instruction_decoder.v` → `register_file.v` → `decode_stage.v` → `pipeline_reg_idex.v`

The decode stage answers: **"What does this instruction want to do, and what data does it need?"** It cracks the 32-bit instruction into control signals, reads up to 3 register values, extends the immediate, tags branch instructions with `branch_type`, and packs everything into the ID/EX pipeline register for execute/EX1 branch resolution.

---

## Macro View — How the Four Modules Connect

```
From IF/ID (Batch 2)
        │
        │ instruction (32b) + pc (10b) + valid (1b)
        ▼
┌─────────────────────────────────────────────────────┐
│                  decode_stage (wrapper)              │
│                                                      │
│  ┌────────────────────┐    ┌────────────────────┐    │
│  │ instruction_decoder│    │   register_file    │    │
│  │  (combinational)   │    │ (16×64, FF-based)  │    │
│  │                    │    │                    │    │
│  │ instruction ──────►│    │  3 async read ports│    │
│  │ valid ────────────►│    │  1 sync write port │    │
│  │                    │    │                    │    │
│  │ ──► control (9)    │    │ rd_addr1 ──► data1 │    │
│  │ ──► rd,rs1,rs2,rs3 │───►│ rd_addr2 ──► data2 │    │
│  │ ──► imm_ext        │    │ rd_addr3 ──► data3 │    │
│  └────────────────────┘    │                    │    │
│                            │ ◄── wb_wr (from WB)│    │
│                            └────────────────────┘    │
│                                                      │
│  Output: 9 control + 4 addrs + 3 data + imm + pc    │
│                                                      │
│  Branch metadata:                                    │
│    branch_type + pc + operands forwarded to ID/EX    │
│    core_top resolves BLT/BGE in EX1                  │
└──────────────────────┬──────────────────────────────┘
                       │ registered bundle (to ID/EX)
                       ▼
              ┌──────────────────┐
              │ pipeline_reg_idex│
              │ (registered)     │
              │                  │
              │ rst/flush → NOP  │
              │ standalone stall → hold
              │ core RAW stall → flush/NOP
              │ else → latch     │
              └────────┬─────────┘
                       │ execute controls + operands + branch_type + pc
                       ▼
                 TO EXECUTE STAGE
```

**Key data flow:**
1. Decoder cracks instruction → control signals + register addresses + immediate
2. Register addresses feed into register file → 3 data values read asynchronously
3. Branch-aware register-file muxing makes BLT/BGE read the two comparison operands, but the actual signed comparison happens one stage later in EX1 (`core_top.v`).
4. All execute inputs, including `branch_type` and `pc`, bundle through `decode_stage` wrapper -> `pipeline_reg_idex` -> execute/EX1 branch logic.

---

## 1. instruction_decoder.v — The Instruction Cracker

Pure combinational logic. No clock, no state. Takes a 32-bit instruction + valid bit, outputs 9 control signals + 4 register addresses + 1 immediate value.

### 1.1 Port Declaration

```verilog
module instruction_decoder (
    input  [`INSTR_WIDTH-1:0]   instruction,
    input                       valid,

    // Control signals
    output reg [3:0]            alu_op,
    output reg                  reg_write,
    output reg                  mem_read,
    output reg                  mem_write,
    output reg                  is_fma,
    output reg [1:0]            branch_type,
    output reg                  use_imm,
    output reg [2:0]            dtype,
    output reg                  is_halt,

    // Extracted fields
    output [`REG_ADDR_W-1:0]    rd,
    output [`REG_ADDR_W-1:0]    rs1_addr,
    output [`REG_ADDR_W-1:0]    rs2_addr,
    output [`REG_ADDR_W-1:0]    rs3_addr,
    output reg [`DATA_WIDTH-1:0] imm_ext
);
```

The module takes a 32-bit instruction from IF/ID and a `valid` bit from fetch_stage. When `valid = 0` (bubble), all outputs default to NOP.

**9 control signals** are declared `output reg` because they are assigned inside `always @(*)`. **4 register addresses** are plain `output` (wire) because they use `assign` (continuous assignment). Both are purely combinational -- `reg` here is a Verilog syntax requirement for procedural blocks, not a hardware register.

- `alu_op` [3:0]: which ALU operation (ALU_ADD, ALU_SUB, etc.)
- `reg_write`: will this instruction write to the register file?
- `mem_read`: is this a LD? (WB stage selects DMEM data)
- `mem_write`: is this a ST? (execute drives DMEM write)
- `is_fma`: FMA instruction? (route to FMA unit, read rs3)
- `branch_type` [1:0]: BR_NONE / BR_BLT / BR_BGE
- `use_imm`: replace rs2_data with immediate/control payload? (ADDI/MOVI/LD/ST/BCAST)
- `dtype` [2:0]: data type (S16/U16/BF16) for ALU path select
- `is_halt`: HALT instruction? (triggers sticky latch in core_top)
- `rd` [3:0]: destination register, bits [26:23]
- `rs1_addr` [3:0]: source 1 register, bits [22:19]
- `rs2_addr` [3:0]: source 2 register, bits [18:15]
- `rs3_addr` [3:0]: source 3 register, bits [11:8] (FMA only)
- `imm_ext` [63:0]: sign/zero-extended immediate

### 1.2 Field Extraction (Always Wired)

```verilog
    wire [4:0] opcode = instruction[`F_OPCODE_HI:`F_OPCODE_LO];

    assign rd       = instruction[`F_RD_HI:`F_RD_LO];
    assign rs1_addr = instruction[`F_RS1_HI:`F_RS1_LO];
    assign rs2_addr = instruction[`F_RS2_HI:`F_RS2_LO];
    assign rs3_addr = instruction[`F_RS3_HI:`F_RS3_LO];
```

**All fields extracted unconditionally.** The decoder always pulls rd, rs1, rs2, rs3 from their fixed bit positions regardless of opcode. Only the *interpretation* changes per opcode. This keeps the logic simple and avoids MUXes on field extraction.

The field positions are: `opcode` = bits [31:27], `rd` = bits [26:23], `rs1_addr` = bits [22:19], `rs2_addr` = bits [18:15], `rs3_addr` = bits [11:8].

**For B-type (BLT/BGE):** The authoritative `include/gpu_params.vh` comment documents B-type as `[26:23] rs1  [22:19] rs2  [18:0] offset19`. The fixed extractor still names those first two fields `rd` and `rs1_addr`. Branch-aware register-file muxing reads them as the two comparison operands, and `core_top.v` compares the resulting 64-bit values in EX1.

### 1.3 Immediate Sign-Extension

```verilog
    wire [`DATA_WIDTH-1:0] imm19_sext = {{45{instruction[`F_IMM19_HI]}},
                                          instruction[`F_IMM19_HI:`F_IMM19_LO]};
    wire [`DATA_WIDTH-1:0] imm12_sext = {{52{instruction[`F_OFFSET12_HI]}},
                                          instruction[`F_OFFSET12_HI:`F_OFFSET12_LO]};
```

`imm19_sext`: 19-bit immediate sign-extended to 64 bits. `{45{instruction[18]}}` replicates the MSB (bit 18) 45 times, then concatenates the original 19 bits. Total: 45 + 19 = 64 bits. Used by ADDI, BLT, BGE.

`imm12_sext`: 12-bit offset sign-extended to 64 bits. `{52{instruction[11]}}` replicates the MSB (bit 11) 52 times, then concatenates the original 12 bits. Total: 52 + 12 = 64 bits. Used by LD, ST.

**Sign extension explained:** `{45{instruction[18]}}` takes bit 18 (the MSB of imm19) and replicates it 45 times. If the immediate is positive (bit 18 = 0), the upper 45 bits are all zeros. If negative (bit 18 = 1), the upper 45 bits are all ones. This preserves the two's complement value when widening from 19 bits to 64 bits.

**Both wires are always computed.** The case statement selects which one (if any) feeds into `imm_ext`. Unused computations are optimized away by synthesis.

### 1.4 Control Signal Generation — The Big Case Statement

```verilog
    always @(*) begin
        // Defaults — NOP-safe
        alu_op      = 4'd0;
        reg_write   = 1'b0;
        mem_read    = 1'b0;
        mem_write   = 1'b0;
        is_fma      = 1'b0;
        branch_type = `BR_NONE;
        use_imm     = 1'b0;
        dtype       = instruction[`F_DTYPE_HI:`F_DTYPE_LO];
        is_halt     = 1'b0;
        imm_ext     = 64'd0;
```

**NOP-safe defaults:** Every output starts as "do nothing." If the case statement doesn't override a signal, the instruction behaves like NOP for that signal. This means:
- Unknown opcodes -> NOP (safe)
- Bubbles (`valid=0`) -> NOP (the `if (valid)` guard below)
- Any case arm only sets the signals that DIFFER from NOP

The defaults are: `alu_op = 0` (ALU_ADD, don't-care for NOP), `reg_write/mem_read/mem_write/is_fma/use_imm/is_halt = 0` (no side effects), `branch_type = BR_NONE` (no branch), `imm_ext = 0` (zero immediate). `dtype` defaults to `instruction[14:12]` -- the dtype field position -- so most opcodes automatically get the correct dtype without explicitly setting it. Opcodes that don't use dtype (NOP, HALT, branches) don't care about this value.

```verilog
        if (valid) begin
            case (opcode)
```

**The `valid` guard:** When `valid = 0` (bubble from flush/reset), the entire case statement is skipped. All outputs stay at NOP defaults. This is how bubbles safely pass through decode.

#### R-type Compute (ADD, SUB, MUL, MAX, MOV, RELU)

```verilog
                `OP_ADD: begin
                    alu_op    = `ALU_ADD;
                    reg_write = 1'b1;
                end

                `OP_SUB: begin
                    alu_op    = `ALU_SUB;
                    reg_write = 1'b1;
                end

                `OP_MUL: begin
                    alu_op    = `ALU_MUL;
                    reg_write = 1'b1;
                end

                `OP_MAX: begin
                    alu_op    = `ALU_MAX;
                    reg_write = 1'b1;
                end

                `OP_MOV: begin
                    alu_op    = `ALU_MOV;
                    reg_write = 1'b1;
                end

                `OP_RELU: begin
                    alu_op    = `ALU_RELU;
                    reg_write = 1'b1;
                end
```

**Pattern:** All R-type compute instructions only set `alu_op` + `reg_write`. Everything else stays at defaults (no memory, no branch, no immediate). The actual computation happens in execute; the decoder just says "which operation" and "write the result."

#### FMA (F-type — Tensor Core Operation)

```verilog
                `OP_FMA: begin
                    alu_op    = `ALU_MUL;
                    reg_write = 1'b1;
                    is_fma    = 1'b1;
                end
```

**Why `alu_op = ALU_MUL` for FMA?** The `is_fma` flag is what actually routes the instruction to the FMA unit in execute_stage. The `alu_op` value is irrelevant for FMA — it's only used by simd_alu, which isn't on the FMA path. Setting it to `ALU_MUL` is a convention (FMA includes a multiply), but `ALU_ADD` would work too.

**`is_fma` also tells the hazard unit** that rs3 is a real source register (not just stale bits). Without `is_fma`, the hazard unit would ignore rs3 and miss dependencies.

#### I-type (ADDI, MOVI)

```verilog
                `OP_ADDI: begin
                    alu_op    = `ALU_ADD;
                    reg_write = 1'b1;
                    use_imm   = 1'b1;
                    imm_ext   = imm19_sext;
                end

                `OP_MOVI: begin
                    reg_write = 1'b1;
                    use_imm   = 1'b1;
                    // Broadcast lower 16 bits to all SIMD lanes
                    imm_ext   = {4{instruction[15:0]}};
                end
```

**MOVI broadcast:** The 16-bit immediate is replicated to all four SIMD lanes. MOVI has no dedicated pass-immediate ALU route: it retains the default `ALU_ADD`, so execute computes `rs1_data + broadcast(imm16)`. The normal assembler form encodes rs1 as R0, making the result exactly the immediate. A hand-encoded nonzero rs1 would add that register instead. Because `instruction[15:0]` overlaps the normal dtype/function positions, MOVI is a raw 16-bit lane pattern rather than an independent `imm19` format.

**ADDI vs MOVI immediate handling:** ADDI uses `imm19_sext` (sign-extended 19-bit), MOVI uses `{4{instruction[15:0]}}` (broadcast 16-bit). Different widths, different extension strategies — both produce 64-bit values for the execute stage.

#### Cross-lane Broadcast (BCAST — added 2026-04-13)

```verilog
                `OP_BCAST: begin
                    alu_op    = `ALU_BCAST;
                    reg_write = 1'b1;
                    use_imm   = 1'b1;
                    imm_ext   = {{62{1'b0}}, instruction[1:0]}; // lane select from func[1:0]
                end
```

**What BCAST does at the ISA level:** `Rd = {Rs1[lane], Rs1[lane], Rs1[lane], Rs1[lane]}` where `lane = instruction[1:0]`. Picks one 16-bit lane out of Rs1's four and replicates it to fill Rd's four lanes. This is the cross-lane shuffle that lets a multi-layer ANN reduce the per-neuron FMA accumulator (one scalar per lane) back into the broadcast format the next layer's FMA expects.

**Decode-side mechanics — three signals do all the work:**

1. `alu_op = ALU_BCAST` -- tells the per-lane ALUs to behave like MOV (the actual cross-lane mux is upstream of them, in the simd_alu wrapper).
2. `reg_write = 1` -- writes the muxed result back to Rd. Standard.
3. `use_imm = 1` + `imm_ext = {62'd0, instruction[1:0]}` -- pulls the 2-bit lane selector out of the instruction's *func* field (bits [1:0]) and sleeves it into bits [1:0] of the 64-bit `imm_ext`. The execute stage's operand-B mux then chooses `imm_ext` (because `use_imm=1`), so by EX1 the simd_alu sees `operand_b[1:0] = lane_select`. Bits 63:2 of operand_b are zero — the simd_alu only inspects the bottom 2 bits.

**Why piggyback on `imm_ext` instead of adding a dedicated `lane_sel` port?** It costs zero new pipeline-register width. The ID/EX register already carries a 64-bit `imm_ext` for ADDI/MOVI/LD/ST. BCAST just reuses that slot — the cost is one new opcode entry in the decoder and one new mux in simd_alu. No port plumbing, no new ID/EX bits.

**Field overlap warning.** BCAST's lane selector lives in bits [1:0] of the instruction. Those bits are part of the *func* sub-field for R-type opcodes; for any other opcode they are don't-cares. So programs must not accidentally emit BCAST with garbage in the bottom two bits — the assembler enforces this by default.

#### M-type (LD, ST)

```verilog
                `OP_LD: begin
                    alu_op    = `ALU_ADD;
                    reg_write = 1'b1;
                    mem_read  = 1'b1;
                    use_imm   = 1'b1;
                    imm_ext   = imm12_sext;
                end

                `OP_ST: begin
                    alu_op    = `ALU_ADD;
                    mem_write = 1'b1;
                    use_imm   = 1'b1;
                    imm_ext   = imm12_sext;
                end
```

**LD uses a dedicated address adder.** `execute_stage` computes the 10-bit modular address `rs1_data[9:0] + imm_ext[9:0]`; the 64-bit SIMD ALU result is not the address. `mem_read=1` tells writeback to select the synchronous DMEM output.

**ST address calculation** uses the same dedicated low-10-bit adder. ST does not write a register or select load data; `mem_write=1` is pipelined to the DMEM Port A write enable.

**ST data source:** The store data comes from the register at the `rd` field position [26:23]. This is handled in `decode_stage.v` (not here) — see section 3 below.

#### B-type (BLT, BGE)

```verilog
                `OP_BLT: begin
                    branch_type = `BR_BLT;
                    imm_ext     = imm19_sext;
                end

                `OP_BGE: begin
                    branch_type = `BR_BGE;
                    imm_ext     = imm19_sext;
                end
```

**Branch resolution happens in EX1, not decode.** The decoder outputs `branch_type` so `decode_stage` can identify BLT/BGE, read the correct comparison operands, and pass the branch metadata through ID/EX. `core_top.v` performs one signed 64-bit comparison of the whole packed register values; it is not lane-wise or dtype-sensitive. `reg_write` stays at default 0, and the branch comparator is separate from the SIMD ALU.

**Branch operands -- how the wiring actually works:** `include/gpu_params.vh` documents B-type as `[26:23] rs1  [22:19] rs2  [18:0] offset19`. The decoder nevertheless uses fixed extraction names: bits [26:23] map to `rd`, bits [22:19] to `rs1_addr`, and bits [18:15] to `rs2_addr`. There is no per-format renaming.

In `decode_stage.v`, branch-aware register-file muxing overrides the normal R-type interpretation. Port 1 is wired to `dec_rd` (= instruction[26:23], ISA branch rs1). Port 2 is wired to `dec_rs1_addr` (= instruction[22:19], ISA branch rs2). These become `rs1_data_out` and `rs2_data_out`, pass through `pipeline_reg_idex`, and are compared in EX1.

In other words, the B-type ISA fields labeled "rs1" and "rs2" correspond to decoder outputs `rd` and `rs1_addr` respectively. The `rs2_addr` output (instruction bits [18:15]) overlaps the branch immediate and is not used as a branch register operand.

#### Special (NOP, HALT)

```verilog
                `OP_NOP: begin
                    // All defaults (NOP)
                end

                `OP_HALT: begin
                    is_halt = 1'b1;
                end

                default: begin
                    // Unknown opcode — treat as NOP
                end
            endcase
        end
    end
```

**`default` is mandatory** under the project coding rules. The preceding block-wide default assignments ensure every output has a value, and the `case default` handles unmatched opcodes. Together they keep the decoder purely combinational; a `default` arm alone would not prevent a latch if some outputs were otherwise left unassigned.

---

## 2. register_file.v — 16x64-bit Storage

FF-based (not BRAM), with 3 asynchronous read ports and 1 synchronous write port. Four special registers: R0=zero, R13/R14/R15=thread identity.

### 2.1 Port Declaration

```verilog
module register_file (
    input                       clk,
    input                       rst,

    // Thread identity (externally driven into R13/R14/R15)
    input  [31:0]               thread_id,
    input  [31:0]               block_id,
    input  [31:0]               block_dim,

    // Write port (from writeback stage)
    input                       wr_en,
    input  [`REG_ADDR_W-1:0]    wr_addr,
    input  [`DATA_WIDTH-1:0]    wr_data,

    // Read port 1 (rs1)
    input  [`REG_ADDR_W-1:0]    rd_addr1,
    output [`DATA_WIDTH-1:0]    rd_data1,

    // Read port 2 (rs2)
    input  [`REG_ADDR_W-1:0]    rd_addr2,
    output [`DATA_WIDTH-1:0]    rd_data2,

    // Read port 3 (rs3 — for FMA)
    input  [`REG_ADDR_W-1:0]    rd_addr3,
    output [`DATA_WIDTH-1:0]    rd_data3
);
```

Thread identity inputs (`thread_id`, `block_id`, `block_dim`) are externally driven and map to special register read outputs: when R13 is read it returns `thread_id` (zero-extended to 64b), R14 returns `block_id`, R15 returns `block_dim`. The write port (from writeback stage) provides 1 write per cycle. The three read ports provide 64-bit values asynchronously (combinational, no clock delay).

**Why 3 read ports?** Most instructions need at most 2 operands (rs1, rs2). But FMA needs 3: `rd = rs1 x rs2 + rs3`. A third read port avoids serializing FMA into two cycles.

**Why FF-based (not BRAM)?** Three reasons:
1. BRAM only provides 2 ports. We need 3 reads + 1 write = 4 ports total.
2. 16 registers x 64 bits = 1024 flip-flops. On VP50 (23k slices), this is ~2% of slice FFs — affordable.
3. Async read is required (decode reads in the same cycle as the instruction arrives). BRAM has synchronous read (1-cycle latency), which would add pipeline bubbles.

### 2.2 Storage and Write Logic

```verilog
    reg [`DATA_WIDTH-1:0] regs [0:`REG_COUNT-1];

    integer k;

    always @(posedge clk) begin
        if (rst) begin
            for (k = 0; k < `REG_COUNT; k = k + 1)
                regs[k] <= {`DATA_WIDTH{1'b0}};
        end else if (wr_en && wr_addr != `REG_ZERO
                            && wr_addr != `REG_THREADID
                            && wr_addr != `REG_BLOCKID
                            && wr_addr != `REG_BLOCKDIM) begin
            regs[wr_addr] <= wr_data;
        end
    end
```

`regs` is a 16-entry x 64-bit array = 1024 FFs. `integer k` is the loop variable for reset (synthesis-safe in `for` loops).

**Reset:** The `for` loop inside `always @(posedge clk)` clears all 16 array entries. Synthesis unrolls the constant-bound loop.

**Write guard:** Four conditions must all be true: `wr_en = 1`, and the destination must not be R0 or the externally driven R13–R15 special registers. Writes to those protected addresses are ignored.

**Write:** `regs[wr_addr] <= wr_data` is a nonblocking clocked assignment.

**Write-read timing:** Write happens on posedge (end of WB stage). Async read happens combinationally (during decode stage). If WB writes register X in the same cycle that decode reads register X, the read gets the OLD value (pre-write). This is a data hazard — the hazard unit handles it by stalling.

### 2.3 Async Read with Special Register Overrides

```verilog
    assign rd_data1 = (rd_addr1 == `REG_ZERO)     ? {`DATA_WIDTH{1'b0}} :
                      (rd_addr1 == `REG_THREADID)  ? {{32{1'b0}}, thread_id} :
                      (rd_addr1 == `REG_BLOCKID)   ? {{32{1'b0}}, block_id} :
                      (rd_addr1 == `REG_BLOCKDIM)  ? {{32{1'b0}}, block_dim} :
                      regs[rd_addr1];

    assign rd_data2 = (rd_addr2 == `REG_ZERO)     ? {`DATA_WIDTH{1'b0}} :
                      (rd_addr2 == `REG_THREADID)  ? {{32{1'b0}}, thread_id} :
                      (rd_addr2 == `REG_BLOCKID)   ? {{32{1'b0}}, block_id} :
                      (rd_addr2 == `REG_BLOCKDIM)  ? {{32{1'b0}}, block_dim} :
                      regs[rd_addr2];

    assign rd_data3 = (rd_addr3 == `REG_ZERO)     ? {`DATA_WIDTH{1'b0}} :
                      (rd_addr3 == `REG_THREADID)  ? {{32{1'b0}}, thread_id} :
                      (rd_addr3 == `REG_BLOCKID)   ? {{32{1'b0}}, block_id} :
                      (rd_addr3 == `REG_BLOCKDIM)  ? {{32{1'b0}}, block_dim} :
                      regs[rd_addr3];
```

Each port is a priority-encoded ternary chain: R0 returns all zeros, R13/R14/R15 return the zero-extended 32-bit thread identity values (`{32'b0, thread_id}` etc.), and R1-R12 return the stored value from the `regs` array.

**Why continuous `assign` instead of `always @(*)` with case?**

The current RTL uses continuous assignments for asynchronous reads, producing combinational muxes from the register array plus special-register overrides. An older-tool limitation is sometimes given as the motivation, but that comment and supporting synthesis evidence are not present in the current source or cited baseline, so the exact historical reason is unverifiable here.

**Zero-extension for R13/R14/R15:** `{{32{1'b0}}, thread_id}` pads 32 zeros on top of the 32-bit thread_id input, producing a 64-bit value. The upper 32 bits are always zero because thread counts are small numbers. The register file doesn't sign-extend — these are unsigned counts.

**Three identical assigns:** Yes, the code is duplicated for all 3 ports. This is intentional — each port is an independent 16:1 MUX with 4 special-case overrides. In hardware, these synthesize to 3 separate MUX trees operating in parallel.

**Synthesis cost:** The three asynchronous ports require three independent wide mux trees. An exact LUT count depends on device mapping, special-case sharing, and synthesis optimization; the repository has no current-source report that supports the former fixed 64-LUT-per-port estimate.

---

## 3. decode_stage.v — The Wrapper

Instantiates the decoder + register file, wires them together, and emits branch metadata for EX1. It also handles one important routing detail for ST instructions and one for branch operands.

### 3.1 Port Declaration

```verilog
module decode_stage (
    input                       clk,
    input                       rst,
    input                       stall,
    input                       flush,

    // From IF/ID pipeline register
    input  [`INSTR_WIDTH-1:0]   instruction,
    input  [`PC_WIDTH-1:0]      pc_in,
    input                       valid_in,

    // Thread identity for special registers
    input  [31:0]               thread_id,
    input  [31:0]               block_id,
    input  [31:0]               block_dim,

    // Writeback port (from WB stage → register file)
    input                       wb_reg_write,
    input  [`REG_ADDR_W-1:0]    wb_rd,
    input  [`DATA_WIDTH-1:0]    wb_data,

    // Decoded outputs -> ID/EX pipeline register
    output [3:0]                alu_op_out,
    output                      reg_write_out,
    output                      mem_read_out,
    output                      mem_write_out,
    output                      is_fma_out,
    output                      use_imm_out,
    output [2:0]                dtype_out,
    output                      is_halt_out,
    output [1:0]                branch_type_out,

    output [`REG_ADDR_W-1:0]    rd_out,
    output [`REG_ADDR_W-1:0]    rs1_addr_out,
    output [`REG_ADDR_W-1:0]    rs2_addr_out,
    output [`REG_ADDR_W-1:0]    rs3_addr_out,

    output [`DATA_WIDTH-1:0]    rs1_data_out,
    output [`DATA_WIDTH-1:0]    rs2_data_out,
    output [`DATA_WIDTH-1:0]    rs3_data_out,

    output [`DATA_WIDTH-1:0]    imm_ext_out,
    output [`PC_WIDTH-1:0]      pc_out
);
```

The `stall` and `flush` inputs are present in the module interface but are not used directly inside `decode_stage.v`; `core_top.v` consumes them when controlling `fetch_stage` and `pipeline_reg_idex`.

The outputs split into control signals (`alu_op_out` through `branch_type_out`), register metadata (`rd_out`, source addresses), register data values, `imm_ext_out`, and `pc_out`. The values needed after decode feed the ID/EX pipeline register. `branch_type_out`, `rs1_data_out`, `rs2_data_out`, `imm_ext_out`, and `pc_out` are what let `core_top.v` decide BLT/BGE in EX1.

### 3.2 Internal Wires + Decoder Instantiation

```verilog
    wire [3:0]               dec_alu_op;
    wire                     dec_reg_write;
    wire                     dec_mem_read;
    wire                     dec_mem_write;
    wire                     dec_is_fma;
    wire [1:0]               dec_branch_type;
    wire                     dec_use_imm;
    wire [2:0]               dec_dtype;
    wire                     dec_is_halt;
    wire [`REG_ADDR_W-1:0]   dec_rd;
    wire [`REG_ADDR_W-1:0]   dec_rs1_addr;
    wire [`REG_ADDR_W-1:0]   dec_rs2_addr;
    wire [`REG_ADDR_W-1:0]   dec_rs3_addr;
    wire [`DATA_WIDTH-1:0]   dec_imm_ext;

    instruction_decoder u_decoder (
        .instruction (instruction),
        .valid       (valid_in),
        .alu_op      (dec_alu_op),
        .reg_write   (dec_reg_write),
        .mem_read    (dec_mem_read),
        .mem_write   (dec_mem_write),
        .is_fma      (dec_is_fma),
        .branch_type (dec_branch_type),
        .use_imm     (dec_use_imm),
        .dtype       (dec_dtype),
        .is_halt     (dec_is_halt),
        .rd          (dec_rd),
        .rs1_addr    (dec_rs1_addr),
        .rs2_addr    (dec_rs2_addr),
        .rs3_addr    (dec_rs3_addr),
        .imm_ext     (dec_imm_ext)
    );
```

These are internal wires from the decoder, not exposed directly -- they may be rerouted (e.g., `dec_rd` is used for the ST routing trick). When `valid_in = 0` (bubble), the decoder outputs NOP defaults.

**`dec_branch_type` is forwarded.** It becomes `branch_type_out` and then `idex_branch_type`, so EX1 can decide whether BLT/BGE is taken. Non-branch instructions carry `BR_NONE`.

### 3.3 Register File Instantiation - Branch and ST Routing

```verilog
    // Branch-aware read address muxing
    wire is_branch = (dec_branch_type != `BR_NONE);

    // Port 1: branches read ISA rs1 from rd field
    wire [`REG_ADDR_W-1:0] rf_rd_addr1 = is_branch ? dec_rd : dec_rs1_addr;

    // Port 2: branches read ISA rs2; ST reads store data from rd field
    wire [`REG_ADDR_W-1:0] rf_rd_addr2 = is_branch    ? dec_rs1_addr :
                                          dec_mem_write ? dec_rd :
                                          dec_rs2_addr;

    register_file u_regfile (
        .clk         (clk),
        .rst         (rst),
        .thread_id   (thread_id),
        .block_id    (block_id),
        .block_dim   (block_dim),
        .wr_en       (wb_reg_write),
        .wr_addr     (wb_rd),
        .wr_data     (wb_data),
        .rd_addr1    (rf_rd_addr1),
        .rd_addr2    (rf_rd_addr2),
        .rd_addr3    (dec_rs3_addr),
        .rd_data1    (rs1_data_out),
        .rd_data2    (rs2_data_out),
        .rd_data3    (rs3_data_out)
    );
```

**The read-address muxes are crucial.** The ST instruction format is M-type: `ST rd, rbase, offset`. The register to STORE is encoded in the `rd` field [26:23], but `rd` is normally the destination. For ST, there is no destination -- the data flows from the register to memory.

The register file's port 2 normally reads `dec_rs2_addr` (bits [18:15]). But in M-type, bits [18:15] are unused. The actual source register for store data is at [26:23] (the `rd` position). So the port-2 mux switches:
- For ST (`dec_mem_write=1`): read from `dec_rd` [26:23] -- the register being stored
- For everything else (`dec_mem_write=0`): read from `dec_rs2_addr` [18:15] -- the normal rs2

Branches need a separate override because B-type uses bits [26:23] and [22:19] as rs1/rs2. For BLT/BGE, port 1 reads `dec_rd`, and port 2 reads `dec_rs1_addr`. Port 3 always reads from `dec_rs3_addr` (bits [11:8], FMA only). All three register file data outputs go directly to module outputs -- no intermediate latching. The async reads are combinationally available in the same cycle the instruction arrives from IF/ID.

### 3.4 Output Assignments

```verilog
    assign alu_op_out      = dec_alu_op;
    assign reg_write_out   = dec_reg_write;
    assign mem_read_out    = dec_mem_read;
    assign mem_write_out   = dec_mem_write;
    assign is_fma_out      = dec_is_fma;
    assign use_imm_out     = dec_use_imm;
    assign dtype_out       = dec_dtype;
    assign is_halt_out     = dec_is_halt;
    assign branch_type_out = dec_branch_type;

    assign rd_out          = dec_rd;
    assign rs1_addr_out    = rf_rd_addr1;
    assign rs2_addr_out    = rf_rd_addr2;
    assign rs3_addr_out    = dec_rs3_addr;

    assign imm_ext_out     = dec_imm_ext;
    assign pc_out          = pc_in;
```

Control signals are straight pass-through from the decoder, including `branch_type_out`. Register source addresses use the same muxed addresses as the register file, so the hazard unit sees the actual registers being read. This matters for ST's rd-as-source case and for branch operands. `imm_ext_out` and `pc_out` are straight pass-through.

**Why forward `pc_out`:** EX1 computes the branch target as `idex_pc + idex_imm_ext[PC_WIDTH-1:0]`, so the branch instruction's own PC must travel through ID/EX with the branch metadata.

### 3.5 Branch Metadata - Resolved in EX1

Branches are not resolved inside `decode_stage.v` in the current RTL. Decode identifies branch instructions, reads the two comparison operands through the branch-aware register-file muxes, and forwards `branch_type`, `rs1_data`, `rs2_data`, `imm_ext`, and `pc` through ID/EX.

```verilog
    assign branch_type_out = dec_branch_type;
    assign pc_out          = pc_in;
```

The actual compare and target calculation live in `core_top.v` after ID/EX:

```verilog
    wire signed_lt = ($signed(idex_rs1_data) < $signed(idex_rs2_data));
    assign ex1_branch_taken = (idex_branch_type == `BR_BLT &&  signed_lt) ||
                              (idex_branch_type == `BR_BGE && !signed_lt);
    wire [`PC_WIDTH-1:0] ex1_branch_target =
        idex_pc + idex_imm_ext[`PC_WIDTH-1:0];
```

When `ex1_branch_taken` asserts, `core_top.v` redirects the program counter and flushes both IF/ID and ID/EX. That gives the current design a 2-cycle taken-branch penalty. The hazard unit does not compute a flush signal; it only computes RAW stalls.

---

## 4. pipeline_reg_idex.v — The ID/EX Barrier

Registers the decode outputs that execute/EX1 needs on the clock edge. The module's own priority is reset, then flush-to-NOP, then stall-hold, then latch. In current `core_top`, however, its `flush` input is `stall || ex1_branch_taken`, so a RAW stall takes the flush path and inserts a bubble rather than exercising the standalone hold behavior.

### 4.1 Port Declaration

```verilog
module pipeline_reg_idex (
    input                       clk,
    input                       rst,
    input                       stall,
    input                       flush,

    // Inputs from decode stage
    input  [3:0]                alu_op_in,
    input                       reg_write_in,
    input                       mem_read_in,
    input                       mem_write_in,
    input                       is_fma_in,
    input                       use_imm_in,
    input  [2:0]                dtype_in,
    input                       is_halt_in,
    input  [1:0]                branch_type_in,
    input  [`REG_ADDR_W-1:0]    rd_in,
    input  [`DATA_WIDTH-1:0]    rs1_data_in,
    input  [`DATA_WIDTH-1:0]    rs2_data_in,
    input  [`DATA_WIDTH-1:0]    rs3_data_in,
    input  [`DATA_WIDTH-1:0]    imm_ext_in,
    input  [`PC_WIDTH-1:0]      pc_in,

    // Outputs to execute stage
    output reg [3:0]            alu_op_out,
    output reg                  reg_write_out,
    output reg                  mem_read_out,
    output reg                  mem_write_out,
    output reg                  is_fma_out,
    output reg                  use_imm_out,
    output reg [2:0]            dtype_out,
    output reg                  is_halt_out,
    output reg [1:0]            branch_type_out,
    output reg [`REG_ADDR_W-1:0]  rd_out,
    output reg [`DATA_WIDTH-1:0]  rs1_data_out,
    output reg [`DATA_WIDTH-1:0]  rs2_data_out,
    output reg [`DATA_WIDTH-1:0]  rs3_data_out,
    output reg [`DATA_WIDTH-1:0]  imm_ext_out,
    output reg [`PC_WIDTH-1:0]    pc_out
);
```

At the standalone module interface, `stall` holds all values only when `flush` is low. `flush` has higher priority and inserts a NOP bubble, including `branch_type_out = BR_NONE`, so a flushed slot cannot redirect the PC. Current core wiring makes every RAW stall also assert this flush input.

It is a wide but simple bank of flip-flops with flush/stall control. The current port set carries branch metadata and PC, but not source register addresses.

**Why `branch_type` and `pc` are ports:** branches resolve in EX1. `branch_type_out` tells EX1 whether to test BLT/BGE, and `pc_out` is used with `imm_ext_out` to form the branch target.

**Total flip-flop count:** 4 + 1 + 1 + 1 + 1 + 1 + 3 + 1 + 2 + 4 + 64 + 64 + 64 + 64 + 10 = **285 flip-flops**.

### 4.2 The Register Logic

```verilog
    always @(posedge clk) begin
        if (rst || flush) begin
            // Insert NOP bubble
            alu_op_out      <= 4'd0;
            reg_write_out   <= 1'b0;
            mem_read_out    <= 1'b0;
            mem_write_out   <= 1'b0;
            is_fma_out      <= 1'b0;
            use_imm_out     <= 1'b0;
            dtype_out       <= 3'd0;
            is_halt_out     <= 1'b0;
            branch_type_out <= `BR_NONE;
            rd_out          <= {`REG_ADDR_W{1'b0}};
            rs1_data_out    <= {`DATA_WIDTH{1'b0}};
            rs2_data_out    <= {`DATA_WIDTH{1'b0}};
            rs3_data_out    <= {`DATA_WIDTH{1'b0}};
            imm_ext_out     <= {`DATA_WIDTH{1'b0}};
            pc_out          <= {`PC_WIDTH{1'b0}};
```

**NOP bubble details:** Every output is zeroed. The critical signals for safety are:
- `reg_write_out = 0` → bubble won't corrupt register file
- `mem_write_out = 0` → bubble won't write to DMEM
- `is_halt_out = 0` → bubble won't falsely trigger halt

**`rd_out = R0` on flush:** Even if `reg_write=0` prevents a write, setting `rd=R0` is belt-and-suspenders — R0 writes are also ignored in the register file.

```verilog
        end else if (!stall) begin
            // Latch inputs
            alu_op_out      <= alu_op_in;
            reg_write_out   <= reg_write_in;
            mem_read_out    <= mem_read_in;
            mem_write_out   <= mem_write_in;
            is_fma_out      <= is_fma_in;
            use_imm_out     <= use_imm_in;
            dtype_out       <= dtype_in;
            is_halt_out     <= is_halt_in;
            branch_type_out <= branch_type_in;
            rd_out          <= rd_in;
            rs1_data_out    <= rs1_data_in;
            rs2_data_out    <= rs2_data_in;
            rs3_data_out    <= rs3_data_in;
            imm_ext_out     <= imm_ext_in;
            pc_out          <= pc_in;
        end
        // On stall: hold all current values (implicit)
    end
```

**Recall from Batch 1:** In current `core_top.v`, this module's `flush` input is wired to `stall || ex1_branch_taken`. So:
- **Data-hazard stall:** `stall=1` -> this register gets zeroed (NOP bubble), while fetch/decode hold the stalled instruction. The instruction already in EX1 continues to EX2->EX3 normally via the internal ALU pipeline registers and `pipeline_reg_ex` instances.
- **Taken branch:** `ex1_branch_taken=1` -> this register gets zeroed, killing the younger wrong-path instruction that had just reached decode.

This means the `!stall` branch is only reached when both `flush=0` and `stall=0` -- normal unstalled, unbranched operation. During data-hazard stalls, `flush=1` inserts a NOP bubble into EX1. During a taken branch, `flush=1` prevents the wrong-path decode slot from advancing.

> **Note (6-stage pipeline):** The old 4-stage design had `flush | (stall & ~ex_busy)` here, with a special case to **hold** ID/EX during FMA busy stalls. With the 6-stage pipeline (EX1+EX2+EX3), `ex_busy` is eliminated — FMA's 3-cycle pipeline aligns naturally with EX1+EX2+EX3, so all stalls uniformly flush ID/EX to NOP.

---

## End-to-End Decode Example

Let's trace `ADD R4, R1, R2` (dtype=S16) through the entire decode stage:

```
Instruction bits: 0000_1 0100 0001 0010 000 0000_0000_0000
                  │       │    │    │   │   └── func (unused)
                  │       │    │    │   └── dtype = 3'b000 = S16
                  │       │    │    └── rs2 = 4'd2 (R2)
                  │       │    └── rs1 = 4'd1 (R1)
                  │       └── rd = 4'd4 (R4)
                  └── opcode = 5'b00001 = OP_ADD

instruction_decoder:
  opcode = OP_ADD → alu_op = ALU_ADD, reg_write = 1
  Field extraction: rd=4, rs1_addr=1, rs2_addr=2, rs3_addr=0 (don't care)
  dtype = instruction[14:12] = 3'b000 = S16
  branch_type = BR_NONE
  imm_ext = 64'd0 (not I-type)

register_file:
  Port 1: rd_addr1 = 1 → rd_data1 = regs[1] (whatever R1 contains)
  Port 2: dec_mem_write=0, so rf_rd_addr2 = dec_rs2_addr = 2
          rd_addr2 = 2 → rd_data2 = regs[2] (whatever R2 contains)
  Port 3: rd_addr3 = 0 → rd_data3 = 0 (R0, don't care for ADD)

branch metadata:
  dec_branch_type = BR_NONE -> branch_type_out = BR_NONE
  (no branch -- ADD is not a B-type instruction)

decode_stage outputs:
  alu_op=ALU_ADD, reg_write=1, mem_read=0, mem_write=0
  is_fma=0, use_imm=0, dtype=S16, is_halt=0, branch_type=BR_NONE
  rd=4, rs1_addr=1, rs2_addr=2, rs3_addr=0
  rs1_data=regs[1], rs2_data=regs[2], rs3_data=0
  imm_ext=0, pc=<current PC>

pipeline_reg_idex (next posedge):
  All execute/EX1 values, including branch_type and pc, latch into ID/EX
```

---

## Design Decisions Summary

| Decision | Rationale |
|----------|-----------|
| Combinational decoder (no clock) | Single-cycle decode; control signals available same cycle as instruction |
| NOP-safe defaults with `valid` guard | Bubbles pass through safely; unknown opcodes are harmless |
| FF-based register file (not BRAM) | 3 async read ports required; BRAM only has 2 ports |
| R0/R13/R14/R15 write suppression | Hardware-enforced read-only; software can't corrupt special registers |
| ST read port MUX (`rf_rd_addr2`) | M-type stores data from `rd` position, not `rs2` position |
| `rs2_addr_out` uses MUXed address | Hazard unit sees actual register being read, including ST cases |
| Branch metadata forwarded to EX1 | Current design resolves BLT/BGE in EX1, with a 2-cycle taken-branch penalty |
| `branch_type` and `pc` forwarded past ID/EX | EX1 needs both to decide the branch and compute the target |
| 285 FFs in ID/EX register | Full isolation between decode and execute; stall/flush control at stage boundary |

---

**Next batch:** Execute Stage — `int16_alu.v`, `bf16_alu.v`, `simd_alu.v`, `bf16_fma_unit.v`, `execute_stage.v`
