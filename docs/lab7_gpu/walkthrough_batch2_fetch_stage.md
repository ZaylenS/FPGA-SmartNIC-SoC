# Batch 2 — Fetch Stage Walkthrough

Reviewed and updated where necessary on 2026-07-11 by GPT-5.6 Sol Ultra.

> **Update history.**
>
> - **2026-03-19 (Lab 8 refactor).** Branch moved from Decode to EX1; `program_counter.v` `branch_en` is driven by `ex1_branch_taken`; PC priority chain is `rst > branch > stall > increment`; branch penalty is 2 cycles; HALT gating was added to `imem_rd_en` and the PC `stall` input; `fetch_stage` flush is driven by `ex1_branch_taken`.
> - **2026-06-25.** Refreshed against current RTL. No further changes to the fetch-stage files since 2026-03-19; the body below now matches the EX1 branch wiring in `src/gpu/core_top.v`.

**Files covered:** `src/gpu/program_counter.v` → `src/gpu/instruction_memory.v` → `src/gpu/fetch_stage.v`

The fetch stage answers one question every cycle: **"What instruction should the pipeline decode next?"** It does this with three cooperating modules: a PC that generates addresses, a BRAM that holds the program, and a metadata register that tracks validity.

---

## Macro View — How the Three Modules Connect

```
                    stall ──────────────┐
                    branch_en ────────┐ │
                    branch_target ──┐ │ │
                                    │ │ │
                                    ▼ ▼ ▼
                               ┌──────────┐
                     rst ────► │ program_  │
                               │ counter   │
                               └────┬──────┘
                                    │ pc_out (10 bits)
                          ┌─────────┼──────────────┐
                          │         │              │
                          ▼         ▼              ▼
                   ┌────────────┐         ┌────────────┐
                   │ instruction│         │ fetch_     │
 !stall&&!halted&&!branch ──►│ _memory    │         │ stage      │
                   │ (BRAM)     │         │ (metadata) │
                   └─────┬──────┘         └──┬────┬────┘
                         │ rd_data (32b)     │    │
                         │                   │    │
                         ▼                   ▼    ▼
                   ifid_instruction      ifid_pc  ifid_valid
                   (= imem_data)         (10b)    (1b)
                         │                   │    │
                         └───────────────────┼────┘
                                             ▼
                                      TO DECODE STAGE
```

**Key insight:** The BRAM output register (`rd_data`) itself acts as the IF/ID instruction register. `fetch_stage` only holds the PC and valid bit as sideband metadata. This saves 32 flip-flops and leverages the BRAM's built-in output register.

---

## 1. program_counter.v — Address Generator

27 lines total. The simplest module in the design, but the most safety-critical — a wrong PC value means wrong instructions enter the pipeline.

### 1.1 Port Declaration

```verilog
module program_counter (
    input                    clk,
    input                    rst,
    input                    stall,
    input                    branch_en,
    input  [`PC_WIDTH-1:0]   branch_target,
    output reg [`PC_WIDTH-1:0] pc_out
);
```

- **`rst`** — Synchronous reset, drives PC to 0.
- **`stall`** — From hazard_unit: freezes the PC at its current value.
- **`branch_en`** — From `core_top` EX1 branch resolution (`ex1_branch_taken`): redirects the PC to `branch_target`.
- **`branch_target`** — From `core_top` EX1 branch target calculation (`idex_pc + idex_imm_ext`).
- **`pc_out`** — Declared as `output reg` (registered output, updated on clock edge). This is the standard pattern for pipeline registers in Verilog-2001. Drives both the IMEM address input and `fetch_stage`'s `pc_in`.

`PC_WIDTH = 10` → addresses 0 to 1023, matching IMEM depth.

### 1.2 The Priority Chain

```verilog
    // Priority: rst > branch > stall > increment
    always @(posedge clk) begin
        if (rst) begin
            pc_out <= {`PC_WIDTH{1'b0}};
        end else if (branch_en) begin
            pc_out <= branch_target;    // Branch
        end else if (stall) begin
            pc_out <= pc_out;           // Hold
        end else begin
            pc_out <= pc_out + 1'b1;    // PC + 1
        end
    end
```

**Line-by-line:**

- **`pc_out <= {`PC_WIDTH{1'b0}}`:** Reset drives PC to zero. The replication operator creates a 10-bit zero — equivalent to `10'd0` but parameterized so it adjusts automatically if `PC_WIDTH` ever changes.

- **`pc_out <= branch_target` (Branch):** Loads the branch target computed in `core_top` from the branch instruction's ID/EX PC plus its sign-extended immediate. This takes effect on the next posedge, so the instruction at `branch_target` appears at IMEM output one cycle later.

- **`pc_out <= pc_out` (Hold):** Explicitly holds value. Could be omitted (registers hold by default when not assigned), but making it explicit documents the intent and matches the `if-else` structure.

- **`pc_out <= pc_out + 1'b1` (PC + 1):** Word-addressed memory, so +1 means "next instruction." No byte addressing.

**Priority analysis - why branch > stall?**

`stall` comes from RAW hazards and `halted`; `branch_en` comes from EX1 after the branch instruction has already advanced into ID/EX. If a branch is taken, the PC must redirect immediately and the wrong-path IF/ID and ID/EX slots are flushed. Giving branch priority prevents a simultaneous stall from holding the PC on the wrong path. Reset still wins over both.

**Wrapping behavior:** When PC reaches 1023 and increments, it wraps to 0 (10-bit unsigned overflow). This is fine — programs always end with HALT before reaching address 1023.

---

## 2. instruction_memory.v — True Dual-Port BRAM

35 lines. The program storage. This module must infer as Block RAM (not distributed RAM or flip-flops) for efficient synthesis on VP50.

### 2.1 Port Declaration

```verilog
module instruction_memory (
    input                            clk,

    // Port A — Core pipeline (read-only with enable)
    input                            rd_en,     // read enable (hold output when low)
    input  [`IMEM_ADDR_W-1:0]       addr,
    output reg [`INSTR_WIDTH-1:0]   rd_data,

    // Port B — External host (read + write)
    input  [`IMEM_ADDR_W-1:0]       addr_b,
    input                            wr_en_b,
    input  [`INSTR_WIDTH-1:0]       wr_data_b,
    output reg [`INSTR_WIDTH-1:0]   rd_data_b
);
```

- **`clk`** — Single clock for both ports.
- **`rd_en`** — Read enable: when low, the output register holds its value. `core_top` drives it low during a RAW stall, after registered halt, and on a taken-branch redirect.
- **`addr`** — 10-bit address from `program_counter`.
- **`rd_data`** — 32-bit instruction to the pipeline. Declared `output reg` (registered output, the standard BRAM inference pattern).
- **`addr_b` / `wr_en_b` / `wr_data_b`** — Host-side port for program loading.
- **`rd_data_b`** — Read-back output for host verification.

**Port asymmetry:** Port A is read-only (the core never writes instructions). Port B is read+write (the host loads the program). This is legal for true dual-port BRAM — each port can have independent capabilities.

### 2.2 Memory Array Declaration

```verilog
    // Memory array
    reg [`INSTR_WIDTH-1:0] mem [0:`IMEM_DEPTH-1];
```

This declares 1024 entries of 32 bits = 32,768 bits = 32 Kbits, which infers approximately 2 Block RAMs (18 Kbit each) on the VP50.

**Synthesis inference:** XST recognizes this pattern — a `reg` array accessed with synchronous read/write inside `always @(posedge clk)` — and maps it to Block RAM. The `[0:IMEM_DEPTH-1]` indexing is standard ascending range. If the array were too small (< ~256 entries), XST might use distributed RAM (LUTs) instead.

**No `initial $readmemh` in synthesizable RTL.** Programs are loaded via Port B at runtime by the host, not hard-coded at synthesis time.

### 2.3 Port A — Synchronous Read with Enable

```verilog
    // Port A: synchronous read with enable
    // When rd_en=0 (pipeline stall), output register holds its value
    always @(posedge clk) begin
        if (rd_en)
            rd_data <= mem[addr];
    end
```

`rd_en` is driven by `!stall && !halted && !ex1_branch_taken` in `core_top`. When any gate is active, `rd_data` retains its previous value because the clocked block does not assign it on that edge.

**This is the crucial stall mechanism.** During a RAW stall:
- `rd_data` holds the previous instruction (the output register is not updated)
- The PC also holds (stalled separately)
- Result: the same instruction stays at the decode stage input for as many cycles as the stall lasts

**Why not `else rd_data <= rd_data;`?** In Verilog, a `reg` that is not assigned in a clock edge retains its value automatically. The `if` without `else` is the standard BRAM-with-enable pattern that XST recognizes. Adding an explicit `else` would still work but is unnecessary.

**Synthesis mapping:** XST maps this to the Block RAM's built-in output register with clock enable. The VP50's Block RAM primitives (`RAMB16_S36_S36`) have optional output register enables — this Verilog maps directly to that hardware feature.

### 2.4 Port B — Synchronous Write + Read (Read-First)

```verilog
    // Port B: synchronous write + read (read-first)
    always @(posedge clk) begin
        if (wr_en_b)
            mem[addr_b] <= wr_data_b;
        rd_data_b <= mem[addr_b];
    end
```

**Line-by-line:**

- **`mem[addr_b] <= wr_data_b`:** Non-blocking assignment writes to the memory array. Guarded by `wr_en_b`. The host uses this to load the program one instruction at a time while the core is held in reset.

- **`rd_data_b <= mem[addr_b]`:** Always reads, regardless of `wr_en_b` — there is no read enable gate on Port B. This is the "read-first" pattern: if writing and reading that Port B address on the same edge, the read gets the old value.

**Read-first vs write-first:** In read-first mode, a simultaneous write+read to the same address returns the pre-write data. In write-first (also called "write-through"), it returns the newly-written data. Read-first is the default and most portable across FPGA families.

**No read enable on Port B:** The host always gets a read. This means `rd_data_b` updates every cycle even if the host isn't looking. That's fine — unused read data is simply ignored. Adding a read enable would complicate synthesis inference for negligible benefit.

### 2.5 True Dual-Port Summary

```
Port A (Core):            Port B (Host):
├── Read-only             ├── Read + Write
├── Has rd_en (stall)     ├── No read enable (always reads)
├── 10-bit addr           ├── 10-bit addr_b
├── 32-bit rd_data out    ├── 32-bit rd_data_b out
└── No write              └── 32-bit wr_data_b in + wr_en_b
```

Both ports share the same clock and support independent different-address operations. The code establishes read-first behavior for a same-port Port B write/read. It does not define all same-address cross-port read/write or write/write collision cases; host software avoids modifying an address the core is concurrently fetching.

---

## 3. fetch_stage.v — IF/ID Metadata Register

27 lines. The thinnest pipeline register in the design — it tracks 11 bits of metadata (10-bit PC + 1-bit valid) because the instruction itself is held by the BRAM output register.

### 3.1 Port Declaration

```verilog
module fetch_stage (
    input                        clk,
    input                        rst,
    input                        stall,
    input                        flush,

    // From PC
    input  [`PC_WIDTH-1:0]       pc_in,

    // To decode stage
    output reg [`PC_WIDTH-1:0]    pc_out,
    output reg                    valid_out
);
```

- **`stall`** — From hazard_unit: holds the metadata registers at their current values.
- **`flush`** — From EX1 branch resolution (`ex1_branch_taken`): kills the in-flight wrong-path instruction by inserting a bubble (`valid_out = 0`).
- **`pc_in`** — Current PC value from `program_counter`; `core_top` wires it through `imem_addr`.
- **`pc_out`** — Registered PC forwarded to the decode stage. Tells decode "this instruction was fetched from address X."
- **`valid_out`** — Is this a real instruction? When 0 (bubble after reset/flush), decode ignores the slot.

**Why track PC here?** The decode stage needs the PC for two reasons:
1. **Branch target calculation:** `target = PC + offset` — the PC of the branch instruction, not the current PC
2. **Debugging/tracing:** Which instruction is currently in each stage

**Why track `valid_out`?** After reset or flush, the pipeline contains "bubbles" — invalid instruction slots. Without the valid bit, a bubble that happens to contain old data could be decoded as a real instruction and corrupt register/memory state. The valid bit tells decode: "ignore this slot."

### 3.2 The Priority Chain

```verilog
    // Priority: (rst | flush) > stall > latch
    always @(posedge clk) begin
        if (rst || flush) begin
            pc_out    <= {`PC_WIDTH{1'b0}};
            valid_out <= 1'b0;
        end else if (!stall) begin
            pc_out    <= pc_in;
            valid_out <= 1'b1;
        end
        // If stall: clocked registers hold their current values
    end
```

**Line-by-line:**

- **`if (rst || flush)`:** Both reset and flush insert a bubble. On reset, the pipeline is empty. On flush, the instruction being fetched is on the wrong path and must be killed.

- **`pc_out <= {`PC_WIDTH{1'b0}}`:** Sets PC to 0 during a bubble. The value does not matter because `valid_out = 0` makes decode ignore the slot.

- **`valid_out <= 1'b0`:** When decode sees `valid_out = 0`, it generates NOP controls. The bubble passes harmlessly through the pipeline.

- **`else if (!stall)`:** Only latch new values when not stalled.

- **`pc_out <= pc_in`:** `pc_in` is connected to `program_counter.pc_out` through `imem_addr`. It captures the PC metadata aligned with the BRAM output.

- **`valid_out <= 1'b1`:** Normal fetch — mark the slot valid.

- **Implicit clock-enable behavior:** When stalled (`stall=1` and no flush/reset), nothing is assigned in this edge-triggered block, so the flip-flops hold their values. No level-sensitive latch is inferred.

**Stall vs flush timing coordination with IMEM:**

| Signal State | PC | IMEM `rd_data` | fetch_stage `pc_out` | fetch_stage `valid_out` |
|---|---|---|---|---|
| Normal | increments | updates to new instruction | latches current PC | 1 |
| Stall | holds | holds (rd_en=0) | holds | holds (stays 1) |
| Flush | redirects to branch target | holds (`rd_en=0`) | zeroed | 0 |
| Reset | → 0 | may sample the pre-edge PC if `rd_en` was high | zeroed | 0 |

**The stall contract:** When stalled, ALL three modules freeze in unison:
- PC holds → same address at IMEM input
- IMEM holds → same instruction at output (`rd_en=0`)
- fetch_stage holds → same PC + valid at output

This is critical — if any one of the three advanced while the others held, the pipeline would see mismatched instruction/PC pairs.

---

## 4. core_top.v Wiring — How the Fetch Modules Connect

In `core_top.v`, the three fetch-path modules are wired together as follows:

```verilog
    // Program counter
    //======================
    program_counter u_pc (
        .clk           (clk),
        .rst           (rst),
        .stall         (stall || halted),
        .branch_en     (ex1_branch_taken),
        .branch_target (ex1_branch_target),
        .pc_out        (imem_addr)
    );


    // Fetch stage — IMEM synchronous output as IF/ID instruction register
    //=====================================
    assign ifid_instruction = imem_data;

    fetch_stage u_fetch (
        .clk       (clk),
        .rst       (rst),
        .stall     (stall),
        .flush     (ex1_branch_taken),
        .pc_in     (imem_addr),
        .pc_out    (ifid_pc),
        .valid_out (ifid_valid)
    );
```

Key wiring details:

- **`imem_addr`** is the shared wire between `program_counter.pc_out` and both `instruction_memory.addr` (via the module port `imem_addr`) and `fetch_stage.pc_in`. This is why the walkthrough refers to `pc_out` feeding both IMEM and fetch_stage — in `core_top`, that signal is named `imem_addr`.
- **`imem_rd_en`** is driven by `assign imem_rd_en = !stall && !halted && !ex1_branch_taken`. The IMEM itself is instantiated outside `core_top` (in `gpu_top.v`), but the read-enable logic lives here.
- **`ifid_instruction`** is simply assigned from `imem_data` (the BRAM's registered output). There is no separate flip-flop — the BRAM output register IS the IF/ID instruction register.
- **`branch_en`** is wired to `ex1_branch_taken`, and **`branch_target`** is wired to `ex1_branch_target`. Both are computed in `core_top` from the ID/EX branch metadata and register values.
- **`flush`** is wired directly to `ex1_branch_taken`, killing the wrong-path instruction held by the fetch metadata stage.

---

## Timing Deep-Dive — IMEM Latency

The IMEM uses synchronous read (output registered), which introduces 1-cycle latency:

```
Cycle 0 (posedge):  PC outputs addr=0
                     IMEM sees addr=0, starts reading mem[0]
                     IMEM rd_data still holds PREVIOUS value (or X after reset)

Cycle 1 (posedge):  IMEM rd_data updates to mem[0] ← instruction at addr 0
                     PC has already advanced to addr=1
                     fetch_stage latches pc=0, valid=1
                     Decode sees: instruction=mem[0], pc=0, valid=1  ✓

Cycle 2 (posedge):  IMEM rd_data updates to mem[1]
                     fetch_stage latches pc=1, valid=1
                     Decode sees: instruction=mem[1], pc=1, valid=1  ✓
```

**The 1-cycle BRAM latency is absorbed naturally.** The BRAM output register and `fetch_stage` update on the same clock edge. By the time decode samples them, both are consistent. There's no "extra" cycle of latency from the pipeline's perspective — it's baked into the 6-stage design (IF/ID/EX1/EX2/EX3/WB — Fetch IS the cycle where BRAM reads).

---

## Design Decisions Summary

| Decision | Rationale |
|----------|-----------|
| BRAM output = IF/ID instruction register | Saves 32 flip-flops; leverages hardware output register |
| `rd_en` for stall (not address gating) | Clean synthesis pattern; XST maps to Block RAM clock enable |
| Read-first mode on Port B | Most portable; write-first adds complexity for no benefit here |
| No `$readmemh` in synthesis RTL | Programs loaded at runtime via Port B by the host |
| 1024-deep IMEM | ~2 Block RAMs; accommodates current kernels ranging into a few hundred instructions |
| Word-addressed (not byte) | Simplifies PC logic; every instruction is exactly 1 word |

---

**Next batch:** Decode Stage — `instruction_decoder.v`, `register_file.v`, `decode_stage.v`, `pipeline_reg_idex.v`
