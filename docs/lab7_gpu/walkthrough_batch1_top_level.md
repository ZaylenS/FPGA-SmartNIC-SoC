# Batch 1 — Top-Level Infrastructure Walkthrough

> **Updated 2026-07-14:** Stale walkthrough content was reconciled with the current RTL implementation by Codex (GPT-5).

> **Update history.**
>
> - **2026-03-19 (Lab 8 hardening refinements).** Branch resolution moved Decode→EX1; hazard unit simplified to stall-only; `pipeline_reg_idex` ports adjusted (added `branch_type`, `pc`; removed `rs1_addr`/`rs2_addr`); PC priority changed to `rst > branch > stall > increment`; HALT gating added to core-side `imem_rd_en` and `dmem_wr_en`. Current Port B IMEM/DMEM command writes are not reset-gated, and the current `gpu_top.v` header already describes the 6-stage pipeline.
> - **2026-04-13 (BCAST -- commit `e14d012`).** New opcode `OP_BCAST = 5'b11010` (0x1A) and new internal `ALU_BCAST = 4'd6` (see §1.3, §1.4). The decoder cracks BCAST with `imm_ext = {62'd0, instruction[1:0]}` (lane select in func[1:0]) -- see `batch3 §1.4`. That refinement originally added a BCAST cross-lane mux before four INT16 and four BF16 lane ALUs.
> - **2026-06-25 checkpoint audit.** At that checkpoint the wrapper-level cycle counter was outside the GPU core, and the then-reviewed SIMD source still used four INT16 lanes plus `execute_stage.simd_result_r`.
> - **2026-07-14.** Reconciled the walkthrough with the latest RTL: `simd_alu.v` now registers its BCAST/effective-A inputs, uses one lane-0 INT16 ALU whose result is replicated, retains four BF16 lanes, and directly produces the EX3-aligned SIMD result; `execute_stage.v` no longer has `simd_result_r`. The wrapper now implements the ARM register-alias window as well as the GPU cycle counter.
>
> Sections affected by the 2026-04-13 refinement carry an explicit marker (look for "**Refined 2026-04-13**:" lines below).

**Files covered:** `include/gpu_params.vh` → `src/user_data_path.v` → `src/lab8_wrapper.v` → `src/gpu/gpu_top.v` → `src/gpu/core_top.v`

These files define the "skeleton" of the entire GPU: every constant, the NF2.1 integration layer, the external boundary, and all internal pipeline wiring.

---

## 1. gpu_params.vh — The Single Source of Truth

The active central `define` file included by the GPU modules. Synthesis logs show `include/gpu_params.vh` as the header used by the normal `-I include` build. A stale duplicate at `src/gpu/gpu_params.vh` lacks BCAST definitions; include-path order must not select that copy.

### Include Guard

```verilog
`ifndef GPU_PARAMS_VH
`define GPU_PARAMS_VH
```

Standard include guard -- prevents double-definition errors when multiple modules include this file.

### 1.1 Sizing Constants

```verilog
// Guard DATA_WIDTH — also defined in NF2.1 registers.v (same value: 64)
`ifndef DATA_WIDTH
`define DATA_WIDTH       64          // Register / data-memory word width
`endif
`define INSTR_WIDTH      32          // Instruction width
`define REG_COUNT        16          // Number of registers (4-bit address)
`define REG_ADDR_W       4           // log2(REG_COUNT)
`define IMEM_DEPTH       1024        // Instruction memory depth (words)
`define IMEM_ADDR_W      10          // log2(IMEM_DEPTH)
`define DMEM_DEPTH       1024        // Data memory depth (words)
`define DMEM_ADDR_W      10          // log2(DMEM_DEPTH)
`define PC_WIDTH         10          // Program counter width = IMEM_ADDR_W
`define SIMD_LANES       4           // Number of SIMD lanes (64 / 16)
`define LANE_WIDTH       16          // Per-lane element width (int16 or bf16)
```

**Design rationale — the 64-bit width choice:** One register and one memory word hold 4 × 16-bit elements. BF16 ALU/FMA operations consume all four lanes; the current integer path consumes lane 0 and replicates that result to all four positions. This means:
- Load/Store moves an entire 4-element vector in one cycle
- No partial-word packing/unpacking needed
- Register file, memory, and ALU all agree on 64-bit granularity

**Why 1024-deep memories?** VP50 has 232 Block RAMs (18Kbit each). IMEM 1024×32 ≈ 2 BRAMs. DMEM 1024×64 ≈ 4 BRAMs. Well within budget.

### 1.2 Instruction Field Positions

```verilog
// R-type: [31:27] opcode  [26:23] rd  [22:19] rs1  [18:15] rs2  [14:12] dtype  [11:0] func
`define F_OPCODE_HI      31
`define F_OPCODE_LO      27
`define F_RD_HI          26
`define F_RD_LO          23
`define F_RS1_HI         22
`define F_RS1_LO         19
`define F_RS2_HI         18
`define F_RS2_LO         15
`define F_DTYPE_HI       14
`define F_DTYPE_LO       12
`define F_FUNC_HI        11
`define F_FUNC_LO        0
```

The R-type format packs a 5-bit opcode at the top of the instruction word, followed by three 4-bit register addresses (rd, rs1, rs2), a 3-bit data type selector, and a 12-bit function field. The decoder always extracts those bit positions, but their semantic roles vary by format; in particular, branch operands occupy the fields normally named `rd` and `rs1` by the fixed extractor.

```verilog
// I-type: [31:27] opcode  [26:23] rd  [22:19] rs1  [18:0] imm19
`define F_IMM19_HI       18
`define F_IMM19_LO       0
`define IMM19_WIDTH      19

// M-type: [31:27] opcode  [26:23] rd/rs  [22:19] rbase  [18:15] unused  [14:12] dtype  [11:0] offset12
`define F_OFFSET12_HI    11
`define F_OFFSET12_LO    0
`define OFFSET12_WIDTH   12

// F-type (FMA): [31:27] opcode  [26:23] rd  [22:19] rs1  [18:15] rs2  [14:12] dtype  [11:8] rs3  [7:0] unused
`define F_RS3_HI         11
`define F_RS3_LO         8

// B-type: [31:27] opcode  [26:23] rs1  [22:19] rs2  [18:0] offset19
// (reuses IMM19 field positions for branch offset)
```

The I-type `imm19` is used by ADDI, and the B-type reuses those bits for its signed branch offset. MOVI is different: it replicates `instruction[15:0]` across the four 16-bit lanes. The M-type 12-bit offset is sign-extended for LD/ST's dedicated low-10-bit address adder. The F-type (FMA) packs a 4-bit third source register (rs3) in bits [11:8], overlapping with the function field since FMA does not need it.

**Bit layout across all 5 formats:**
```
Bit:  31..27 | 26..23 | 22..19 | 18..15 | 14..12 | 11..8 | 7..0
      ─────── ──────── ──────── ──────── ──────── ─────── ──────
R:    opcode   rd       rs1      rs2      dtype    func...........
I:    opcode   rd       rs1      ──────── imm19 ─────────────────
M:    opcode   rd       rbase    (unused) dtype    offset12.......
F:    opcode   rd       rs1      rs2      dtype    rs3     (unused)
B:    opcode   rs1      rs2      ──────── offset19 ───────────────
```

**Key insight:** physical extraction positions are fixed, but semantic register roles are format-dependent. For B-type instructions, decoder output `rd` carries branch source 1 and `rs1_addr` carries branch source 2; neither is a destination.

### 1.3 Opcode Encoding

```verilog
`define OP_NOP           5'b00000    // 0x00
`define OP_ADD           5'b00001    // 0x01
`define OP_SUB           5'b00010    // 0x02
`define OP_MUL           5'b00011    // 0x03
`define OP_FMA           5'b00100    // 0x04  — Tensor core op
`define OP_MAX           5'b00101    // 0x05
`define OP_MOV           5'b01100    // 0x0C
`define OP_ADDI          5'b01110    // 0x0E
`define OP_LD            5'b10000    // 0x10
`define OP_ST            5'b10001    // 0x11
`define OP_BLT           5'b10110    // 0x16
`define OP_BGE           5'b10111    // 0x17
`define OP_RELU          5'b11000    // 0x18  — Activation function
`define OP_BCAST         5'b11010    // 0x1A  — Cross-lane broadcast (added 2026-04-13)
`define OP_MOVI          5'b11011    // 0x1B
`define OP_HALT          5'b11111    // 0x1F
```

The opcodes are grouped by category: NOP (0x00) is all-zeros so flushed pipeline registers decode as NOP with no special handling needed. The compute group (0x01-0x05) covers R-type ALU operations including FMA (which is actually F-type: rd = rs1 * rs2 + rs3). MOV (0x0C) and ADDI (0x0E) are register copy and immediate-add. LD/ST (0x10-0x11) are M-type memory operations with base+offset addressing. BLT/BGE (0x16-0x17) are B-type branches that compare rs1 vs rs2. RELU (0x18) is the activation function (max(0, rs1)); it is four-lane on BF16 and lane-0 scalar with replicated output on the current integer path. MOVI (0x1B) broadcasts an immediate across all SIMD lane positions. HALT (0x1F) is all-ones in the opcode field, easy to spot in hex dumps (0xF8000000). The encoding is non-contiguous, with gaps for future expansion.

**Refined 2026-04-13: BCAST (0x1A) added** in opcode-encoding gap between RELU and MOVI. BCAST is a cross-lane mux: `Rd = {Rs1[lane_sel], Rs1[lane_sel], Rs1[lane_sel], Rs1[lane_sel]}` for `lane_sel = instr[1:0]`. Used by the packed IDS kernel to broadcast a layer's neuron output back across all 4 lanes before the next FMA. Without BCAST, multi-layer ANN inference forced one element per kernel run because reductions across lanes weren't possible inside the GPU pipeline. See `batch3 §1.4` for the decode case and `batch4 §3` for the simd_alu BCAST mux.

### 1.4 Data Types, ALU Ops, Branch Types

```verilog
`define DTYPE_S16        3'b000      // Signed 16-bit integer (4-lane SIMD)
`define DTYPE_U16        3'b001      // Unsigned 16-bit integer
`define DTYPE_S32        3'b010      // Signed 32-bit (2-lane or scalar)
`define DTYPE_BF16       3'b100      // BFloat16 (4-lane SIMD)
```

The current SIMD mux selects BF16 only when `dtype == DTYPE_BF16`. Every other encoding selects the signed-16 lane-0 integer result replicated into all four 16-bit output positions. `DTYPE_U16` and `DTYPE_S32` are defined encodings but have no dedicated unsigned-16 or signed-32 implementation in this checkpoint; integer MAX/RELU retain signed-16 behavior.

```verilog
`define ALU_ADD          4'd0
`define ALU_SUB          4'd1
`define ALU_MUL          4'd2
`define ALU_MAX          4'd3
`define ALU_MOV          4'd4
`define ALU_RELU         4'd5
`define ALU_BCAST        4'd6        // Added 2026-04-13

`define BR_NONE          2'b00
`define BR_BLT           2'b01
`define BR_BGE           2'b10
```

These are internal control codes, not ISA-visible. The decoder maps ISA opcodes to ALU operations (e.g., `OP_ADD` becomes `ALU_ADD`). The ALU does not know opcodes — it only knows `ALU_ADD`, `ALU_SUB`, etc. Similarly, branch types decouple branch comparison logic from the opcode encoding.

**Refined 2026-04-13: `ALU_BCAST` added.** Inside the lane-0 `int16_alu` and each `bf16_alu` lane, this op behaves *exactly like* `ALU_MOV` (just pass `a` through). The cross-lane shuffle that makes BCAST useful happens earlier — in the SIMD wrapper, before its input register and lane ALUs see the operands. See `batch4 §3` for the mux and §1.3 / §2.5 for the lane-side handling.

### 1.5 Special Registers

```verilog
`define REG_ZERO         4'd0        // Hardwired zero
`define REG_THREADID     4'd13       // threadIdx.x
`define REG_BLOCKID      4'd14       // blockIdx.x
`define REG_BLOCKDIM     4'd15       // blockDim.x
```

**CUDA mapping:** A kernel uses R13 as its element index, just like `threadIdx.x` in CUDA. With single-thread mode, R13=0; BF16 ALU/FMA operations process four lane elements in parallel, while current integer pointer/counter operations use lane 0 and replicate the result.

### 1.6 BFloat16 Constants

```verilog
`define BF16_WIDTH       16
`define BF16_EXP_W       8
`define BF16_MANT_W      7
`define BF16_BIAS        8'd127
`define BF16_ZERO_POS    16'h0000
`define BF16_ZERO_NEG    16'h8000
`define BF16_INF_POS     16'h7F80
`define BF16_INF_NEG     16'hFF80
`define BF16_NAN         16'h7FC0    // Canonical quiet NaN
`define BF16_ONE         16'h3F80    // 1.0 in BF16
```

**Why BF16 for this GPU?** 16-bit operands fit in a VP50 MULT18x18 primitive, while an FP32 mantissa multiply would not fit in one 18×18 block. The current source structurally contains one lane-0 INT16 multiply operator plus four BF16-ALU and four BF16-FMA multiply operators (9 operators before synthesis sharing/optimization).

---

## 2. user_data_path.v — NF2.1 Data Path Integration

This is the top-level infrastructure module of the NetFPGA user data path. It establishes the packet chain and register ring, placing the current `lab8_wrapper` stage between `output_port_lookup` and `output_queues`.

### 2.1 Module Header and Parameters

```verilog
// user_data_path — NF2.1 data path for Lab8
`timescale 1ns/1ps

module user_data_path
  #(parameter DATA_WIDTH = 64,
    parameter CTRL_WIDTH=DATA_WIDTH/8,
    parameter UDP_REG_SRC_WIDTH = 2,
    parameter NUM_OUTPUT_QUEUES = 8,
    parameter NUM_INPUT_QUEUES = 8,
    parameter SRAM_DATA_WIDTH = DATA_WIDTH+CTRL_WIDTH,
    parameter SRAM_ADDR_WIDTH = 19)
```

The module implements two parallel chains:

1. **Data path chain:** Packets enter from `input_arbiter`, flow through `output_port_lookup`, then through `lab8_wrapper` (convertible FIFO plus ARM/GPU/DMA integration), and finally to `output_queues`.

2. **Register ring:** Host register accesses start at `udp_reg_master`, circulate through input arbiter, output-port lookup, `lab8_wrapper`, and output queues, then return to the master. Each module handles its own block or passes the request along.

The parameters are standard NF2.1 infrastructure: `DATA_WIDTH=64` matches the 64-bit data bus, `CTRL_WIDTH=8` provides per-byte control signals, `NUM_OUTPUT_QUEUES=8` and `NUM_INPUT_QUEUES=8` correspond to the 4 Ethernet MACs x 2 (CPU DMA ports), and `SRAM_ADDR_WIDTH=19` addresses the external ZBT SRAM used by output queues.

### 2.2 Port Declaration

```verilog
   (
    input  [DATA_WIDTH-1:0]            in_data_0,
    input  [CTRL_WIDTH-1:0]            in_ctrl_0,
    input                              in_wr_0,
    output                             in_rdy_0,

    ...

    input  [DATA_WIDTH-1:0]            in_data_7,
    input  [CTRL_WIDTH-1:0]            in_ctrl_7,
    input                              in_wr_7,
    output                             in_rdy_7,

    output  [DATA_WIDTH-1:0]           out_data_0,
    output  [CTRL_WIDTH-1:0]           out_ctrl_0,
    output                             out_wr_0,
    input                              out_rdy_0,

    ...

    output  [DATA_WIDTH-1:0]           out_data_7,
    output  [CTRL_WIDTH-1:0]           out_ctrl_7,
    output                             out_wr_7,
    input                              out_rdy_7,

     // interface to SRAM
     output [SRAM_ADDR_WIDTH-1:0]       wr_0_addr,
     output                             wr_0_req,
     input                              wr_0_ack,
     output [SRAM_DATA_WIDTH-1:0]       wr_0_data,

     input                              rd_0_ack,
     input  [SRAM_DATA_WIDTH-1:0]       rd_0_data,
     input                              rd_0_vld,
     output [SRAM_ADDR_WIDTH-1:0]       rd_0_addr,
     output                             rd_0_req,

     // interface to DRAM
     /* TBD */

     // register interface
     input                              reg_req,
     output                             reg_ack,
     input                              reg_rd_wr_L,
     input [`UDP_REG_ADDR_WIDTH-1:0]    reg_addr,
     output [`CPCI_NF2_DATA_WIDTH-1:0]  reg_rd_data,
     input [`CPCI_NF2_DATA_WIDTH-1:0]   reg_wr_data,

     // misc
     input                              reset,
     input                              clk);
```

There are 8 input port groups (`in_data/ctrl/wr/rdy_0` through `_7`) and 8 output port groups (`out_data/ctrl/wr/rdy_0` through `_7`). Each group uses the NF2.1 handshake: the producer asserts `wr` when data is valid, and the consumer asserts `rdy` when it can accept data. The SRAM interface connects directly to output_queues for packet buffering. The register interface (`reg_req`, `reg_ack`, `reg_rd_wr_L`, `reg_addr`, `reg_rd_data`, `reg_wr_data`) is the host-CPU-facing side that `udp_reg_master` bridges into the internal register ring. The DRAM interface is reserved but unused (`/* TBD */`).

### 2.3 Internal Parameters and log2 Function

```verilog
   function integer log2;
      input integer number;
      begin
         log2=0;
         while(2**log2<number) begin
            log2=log2+1;
         end
      end
   endfunction // log2

   //---------- Internal parameters -----------

   localparam NUM_IQ_BITS = log2(NUM_INPUT_QUEUES);

   localparam IN_ARB_STAGE_NUM = 2;
   localparam OP_LUT_STAGE_NUM = 4;
   localparam OQ_STAGE_NUM     = 6;
```

The `log2` function is a standard NF2.1 utility for computing address widths from depths. The three `STAGE_NUM` localparams identify the standard input-arbiter, output-port-lookup, and output-queue register blocks. The Lab 8 block instead decodes `LAB8_BLOCK_ADDR` from `include/lab8_reg_defines.vh`; there is no current `gpu.xml` or standalone GPU stage number.

### 2.4 Internal Wire Declarations

```verilog
   //-------- Input arbiter wires/regs -------
   wire                             in_arb_in_reg_req;
   wire                             in_arb_in_reg_ack;
   wire                             in_arb_in_reg_rd_wr_L;
   wire [`UDP_REG_ADDR_WIDTH-1:0]   in_arb_in_reg_addr;
   wire [`CPCI_NF2_DATA_WIDTH-1:0]  in_arb_in_reg_data;
   wire [UDP_REG_SRC_WIDTH-1:0]     in_arb_in_reg_src;

   //------- output port lut wires/regs ------
   wire [CTRL_WIDTH-1:0]            op_lut_in_ctrl;
   wire [DATA_WIDTH-1:0]            op_lut_in_data;
   wire                             op_lut_in_wr;
   wire                             op_lut_in_rdy;

   wire                             op_lut_in_reg_req;
   wire                             op_lut_in_reg_ack;
   wire                             op_lut_in_reg_rd_wr_L;
   wire [`UDP_REG_ADDR_WIDTH-1:0]   op_lut_in_reg_addr;
   wire [`CPCI_NF2_DATA_WIDTH-1:0]  op_lut_in_reg_data;
   wire [UDP_REG_SRC_WIDTH-1:0]     op_lut_in_reg_src;

   // --- Lab8 wrapper ---
   wire [CTRL_WIDTH-1:0]            lab8_in_ctrl;
   wire [DATA_WIDTH-1:0]            lab8_in_data;
   wire                             lab8_in_wr;
   wire                             lab8_in_rdy;

   wire                             lab8_in_reg_req;
   wire                             lab8_in_reg_ack;
   wire                             lab8_in_reg_rd_wr_L;
   wire [`UDP_REG_ADDR_WIDTH-1:0]   lab8_in_reg_addr;
   wire [`CPCI_NF2_DATA_WIDTH-1:0]  lab8_in_reg_data;
   wire [UDP_REG_SRC_WIDTH-1:0]     lab8_in_reg_src;

   //------- output queues wires/regs ------
   wire [CTRL_WIDTH-1:0]            oq_in_ctrl;
   wire [DATA_WIDTH-1:0]            oq_in_data;
   wire                             oq_in_wr;
   wire                             oq_in_rdy;

   wire                             oq_in_reg_req;
   wire                             oq_in_reg_ack;
   wire                             oq_in_reg_rd_wr_L;
   wire [`UDP_REG_ADDR_WIDTH-1:0]   oq_in_reg_addr;
   wire [`CPCI_NF2_DATA_WIDTH-1:0]  oq_in_reg_data;
   wire [UDP_REG_SRC_WIDTH-1:0]     oq_in_reg_src;

   //-------- UDP register master wires/regs -------
   wire                             udp_reg_req_in;
   wire                             udp_reg_ack_in;
   wire                             udp_reg_rd_wr_L_in;
   wire [`UDP_REG_ADDR_WIDTH-1:0]   udp_reg_addr_in;
   wire [`CPCI_NF2_DATA_WIDTH-1:0]  udp_reg_data_in;
   wire [UDP_REG_SRC_WIDTH-1:0]     udp_reg_src_in;
```

These wires form the "plumbing" between modules. Each inter-module boundary has two groups:

- **Data path wires** (`*_in_data`, `*_in_ctrl`, `*_in_wr`, `*_in_rdy`): carry packet data between stages. Named by their destination (e.g., `op_lut_in_data` is input to the output_port_lookup module).

- **Register ring wires** (`*_in_reg_req`, `*_in_reg_ack`, `*_in_reg_rd_wr_L`, `*_in_reg_addr`, `*_in_reg_data`, `*_in_reg_src`): carry register access requests around the ring. Each module's `reg_*_out` ports connect to the next module's `reg_*_in` ports.

The naming convention `lab8_in_*` means input to `lab8_wrapper` (output of `output_port_lookup`). Similarly, `oq_in_*` is input to `output_queues` (output of `lab8_wrapper`).

### 2.5 Input Arbiter Instantiation

```verilog
   input_arbiter
     #(.DATA_WIDTH(DATA_WIDTH),
       .CTRL_WIDTH(CTRL_WIDTH),
       .UDP_REG_SRC_WIDTH (UDP_REG_SRC_WIDTH),
       .STAGE_NUMBER(IN_ARB_STAGE_NUM))
   input_arbiter
     (
    .out_data             (op_lut_in_data),
    .out_ctrl             (op_lut_in_ctrl),
    .out_wr               (op_lut_in_wr),
    .out_rdy              (op_lut_in_rdy),

      // --- Interface to the input queues
    .in_data_0            (in_data_0),
    .in_ctrl_0            (in_ctrl_0),
    .in_wr_0              (in_wr_0),
    .in_rdy_0             (in_rdy_0),

      ...

    .in_data_7            (in_data_7),
    .in_ctrl_7            (in_ctrl_7),
    .in_wr_7              (in_wr_7),
    .in_rdy_7             (in_rdy_7),

      // --- Register interface
    .reg_req_in           (in_arb_in_reg_req),
    .reg_ack_in           (in_arb_in_reg_ack),
    .reg_rd_wr_L_in       (in_arb_in_reg_rd_wr_L),
    .reg_addr_in          (in_arb_in_reg_addr),
    .reg_data_in          (in_arb_in_reg_data),
    .reg_src_in           (in_arb_in_reg_src),

    .reg_req_out          (op_lut_in_reg_req),
    .reg_ack_out          (op_lut_in_reg_ack),
    .reg_rd_wr_L_out      (op_lut_in_reg_rd_wr_L),
    .reg_addr_out         (op_lut_in_reg_addr),
    .reg_data_out         (op_lut_in_reg_data),
    .reg_src_out          (op_lut_in_reg_src),

      // --- Misc
    .reset                (reset),
    .clk                  (clk)
    );
```

The input arbiter is a standard NF2.1 module (stage number 2) that round-robins across the 8 input queues, merging them into a single data stream. Its output (`op_lut_in_*`) feeds into output_port_lookup. On the register ring side, it receives from `in_arb_in_reg_*` (coming from udp_reg_master) and passes to `op_lut_in_reg_*` (going to output_port_lookup).

### 2.6 Output Port Lookup Instantiation

```verilog
   output_port_lookup
     #(.DATA_WIDTH(DATA_WIDTH),
       .CTRL_WIDTH(CTRL_WIDTH),
       .UDP_REG_SRC_WIDTH (UDP_REG_SRC_WIDTH),
       .INPUT_ARBITER_STAGE_NUM(IN_ARB_STAGE_NUM),
       .STAGE_NUM(OP_LUT_STAGE_NUM),
       .NUM_OUTPUT_QUEUES(NUM_OUTPUT_QUEUES),
       .NUM_IQ_BITS(NUM_IQ_BITS))
   output_port_lookup
     (.out_data            (lab8_in_data),
     .out_ctrl             (lab8_in_ctrl),
     .out_wr               (lab8_in_wr),
     .out_rdy              (lab8_in_rdy),

      // --- Interface to the rx input queues
     .in_data              (op_lut_in_data),
     .in_ctrl              (op_lut_in_ctrl),
     .in_wr                (op_lut_in_wr),
     .in_rdy               (op_lut_in_rdy),

      // --- Register interface
     .reg_req_in           (op_lut_in_reg_req),
     .reg_ack_in           (op_lut_in_reg_ack),
     .reg_rd_wr_L_in       (op_lut_in_reg_rd_wr_L),
     .reg_addr_in          (op_lut_in_reg_addr),
     .reg_data_in          (op_lut_in_reg_data),
     .reg_src_in           (op_lut_in_reg_src),

     .reg_req_out          (lab8_in_reg_req),
     .reg_ack_out          (lab8_in_reg_ack),
     .reg_rd_wr_L_out      (lab8_in_reg_rd_wr_L),
     .reg_addr_out         (lab8_in_reg_addr),
     .reg_data_out         (lab8_in_reg_data),
     .reg_src_out          (lab8_in_reg_src),

      // --- Misc
     .clk                  (clk),
     .reset                (reset));
```

The output port lookup module (stage number 4) examines each packet's header and stamps it with a destination port bitmap. Its output (`lab8_in_*`) feeds `lab8_wrapper`. The register ring likewise continues from the input arbiter to the Lab 8 block.

### 2.7 Lab 8 Wrapper Instantiation

```verilog
   lab8_wrapper #(
      .DATA_WIDTH(DATA_WIDTH),
      .CTRL_WIDTH(CTRL_WIDTH),
      .UDP_REG_SRC_WIDTH (UDP_REG_SRC_WIDTH)
   ) lab8_wrapper (
      // --- data path interface
      .out_data                          (oq_in_data),
      .out_ctrl                          (oq_in_ctrl),
      .out_wr                            (oq_in_wr),
      .out_rdy                           (oq_in_rdy),

      .in_data                           (lab8_in_data),
      .in_ctrl                           (lab8_in_ctrl),
      .in_wr                             (lab8_in_wr),
      .in_rdy                            (lab8_in_rdy),

      // --- Register interface
      .reg_req_in                        (lab8_in_reg_req),
      .reg_ack_in                        (lab8_in_reg_ack),
      .reg_rd_wr_L_in                    (lab8_in_reg_rd_wr_L),
      .reg_addr_in                       (lab8_in_reg_addr),
      .reg_data_in                       (lab8_in_reg_data),
      .reg_src_in                        (lab8_in_reg_src),

      .reg_req_out                       (oq_in_reg_req),
      .reg_ack_out                       (oq_in_reg_ack),
      .reg_rd_wr_L_out                   (oq_in_reg_rd_wr_L),
      .reg_addr_out                      (oq_in_reg_addr),
      .reg_data_out                      (oq_in_reg_data),
      .reg_src_out                       (oq_in_reg_src),

      // --- Misc
      .clk                               (clk),
      .reset                             (reset)
   );
```

This is the project-specific stage. Packets enter a convertible FIFO rather than a fallthrough passthrough; software can switch FIFO BRAM Port B between drain, ARM, DMA, and host-access roles. The same module implements Lab 8's command registers and instantiates the ARM CPU, GPU, and DMA engine. Its register block is defined by `include/lab8.xml` and `include/lab8_reg_defines.vh`.

### 2.8 Output Queues Instantiation

```verilog
   output_queues
     #(.DATA_WIDTH(DATA_WIDTH),
       .CTRL_WIDTH(CTRL_WIDTH),
       .UDP_REG_SRC_WIDTH (UDP_REG_SRC_WIDTH),
       .OP_LUT_STAGE_NUM(OP_LUT_STAGE_NUM),
       .NUM_OUTPUT_QUEUES(NUM_OUTPUT_QUEUES),
       .STAGE_NUM(OQ_STAGE_NUM),
       .SRAM_ADDR_WIDTH(SRAM_ADDR_WIDTH))
   output_queues
     (// --- data path interface
    .out_data_0       (out_data_0),
    .out_ctrl_0       (out_ctrl_0),
    .out_wr_0         (out_wr_0),
    .out_rdy_0        (out_rdy_0),

      ...

    .out_data_7       (out_data_7),
    .out_ctrl_7       (out_ctrl_7),
    .out_wr_7         (out_wr_7),
    .out_rdy_7        (out_rdy_7),

      // --- Interface to the previous module
    .in_data          (oq_in_data),
    .in_ctrl          (oq_in_ctrl),
    .in_rdy           (oq_in_rdy),
    .in_wr            (oq_in_wr),

      // --- Register interface
    .reg_req_in       (oq_in_reg_req),
    .reg_ack_in       (oq_in_reg_ack),
    .reg_rd_wr_L_in   (oq_in_reg_rd_wr_L),
    .reg_addr_in      (oq_in_reg_addr),
    .reg_data_in      (oq_in_reg_data),
    .reg_src_in       (oq_in_reg_src),

    .reg_req_out      (udp_reg_req_in),
    .reg_ack_out      (udp_reg_ack_in),
    .reg_rd_wr_L_out  (udp_reg_rd_wr_L_in),
    .reg_addr_out     (udp_reg_addr_in),
    .reg_data_out     (udp_reg_data_in),
    .reg_src_out      (udp_reg_src_in),

      // --- SRAM sm interface
    .wr_0_addr        (wr_0_addr),
    .wr_0_req         (wr_0_req),
    .wr_0_ack         (wr_0_ack),
    .wr_0_data        (wr_0_data),
    .rd_0_ack         (rd_0_ack),
    .rd_0_data        (rd_0_data),
    .rd_0_vld         (rd_0_vld),
    .rd_0_addr        (rd_0_addr),
    .rd_0_req         (rd_0_req),

      // --- Misc
    .clk              (clk),
    .reset            (reset));
```

Output queues (stage number 6) is the last module in both chains. It demultiplexes the single merged data stream into 8 output ports based on the destination bitmap stamped by output_port_lookup. It uses external SRAM for packet buffering (connected via `wr_0_*` and `rd_0_*`). On the register ring, its `reg_*_out` ports connect back to `udp_reg_req_in` / `udp_reg_data_in` etc., closing the ring.

### 2.9 UDP Register Master

```verilog
   udp_reg_master #(
      .UDP_REG_SRC_WIDTH (UDP_REG_SRC_WIDTH)
   ) udp_reg_master (
      // Core register interface signals
      .core_reg_req                          (reg_req),
      .core_reg_ack                          (reg_ack),
      .core_reg_rd_wr_L                      (reg_rd_wr_L),

      .core_reg_addr                         (reg_addr),

      .core_reg_rd_data                      (reg_rd_data),
      .core_reg_wr_data                      (reg_wr_data),

      // UDP register interface signals (output)
      .reg_req_out                           (in_arb_in_reg_req),
      .reg_ack_out                           (in_arb_in_reg_ack),
      .reg_rd_wr_L_out                       (in_arb_in_reg_rd_wr_L),

      .reg_addr_out                          (in_arb_in_reg_addr),
      .reg_data_out                          (in_arb_in_reg_data),

      .reg_src_out                           (in_arb_in_reg_src),

      // UDP register interface signals (input)
      .reg_req_in                            (udp_reg_req_in),
      .reg_ack_in                            (udp_reg_ack_in),
      .reg_rd_wr_L_in                        (udp_reg_rd_wr_L_in),

      .reg_addr_in                           (udp_reg_addr_in),
      .reg_data_in                           (udp_reg_data_in),

      .reg_src_in                            (udp_reg_src_in),

      //
      .clk                                   (clk),
      .reset                                 (reset)
   );
```

The UDP register master is the bridge between the host CPU's register interface (`core_reg_*`) and the internal register ring (`reg_*_out` / `reg_*_in`). It converts host read/write requests into ring transactions: it sends a request out through `reg_*_out` (to input_arbiter first), and waits for it to come back through `reg_*_in` (from output_queues last). If a module along the ring claims the address and sets `reg_ack`, the master returns the result to the host. The ring is a complete loop:

```
udp_reg_master → input_arbiter → output_port_lookup → lab8_wrapper → output_queues → udp_reg_master
```

---











## 3. lab8_wrapper.v — Current Integration Bridge

The current repository has no `gpu_nf2_wrapper.v` and no `gpu.xml`. GPU integration is part of `src/lab8_wrapper.v`, whose register definitions come from `include/lab8.xml` and `include/lab8_reg_defines.vh`.

### 3.1 Responsibilities

`lab8_wrapper` combines five functions around the GPU boundary:

1. It inserts the 256×72 convertible FIFO into the packet stream.
2. It instantiates the ARM CPU and maps the CPU external-memory window to FIFO BRAM in CPU mode.
3. It instantiates `gpu_top` and exposes command-register access to GPU IMEM and DMEM.
4. It runs a bidirectional DMA engine between FIFO BRAM's 64-bit data half and GPU DMEM.
5. It implements the Lab 8 register-ring block, the ARM register-alias window, status registers, and GPU cycle counter.

The Lab 8 walkthroughs provide the detailed treatment: Batch 2 covers the wrapper/register ring, Batch 3 covers ARM attachment, and Batch 4 covers GPU/DMA integration.

### 3.2 GPU Boundary

```verilog
gpu_top u_gpu (
    .clk             (clk),
    .rst             (gpu_reset),
    .thread_id       (32'd0),
    .block_id        (32'd0),
    .block_dim       (32'd1),
    .kernel_done     (gpu_kernel_done),
    .ext_imem_addr   (gpu_imem_addr),
    .ext_imem_wr_en  (gpu_imem_wr_en),
    .ext_imem_wr_data(gpu_imem_wr_data),
    .ext_imem_rd_data(gpu_imem_rd_data),
    .ext_dmem_addr   (gpu_dmem_addr),
    .ext_dmem_wr_en  (gpu_dmem_wr_en),
    .ext_dmem_wr_data(gpu_dmem_wr_data),
    .ext_dmem_rd_data(gpu_dmem_rd_data)
);
```

The special-register inputs are hardwired for one invocation. IMEM Port B is host-controlled. DMEM Port B is selected between host command-register access and active DMA.

### 3.3 Command-Register Access

The host does not use the historical standalone wrapper's direct GPU address window. It writes an address register, data register(s), and a command strobe:

- IMEM: `GPU_IMEM_ADDR`, `GPU_IMEM_WDATA`, `GPU_IMEM_CMD`.
- DMEM: `GPU_DMEM_ADDR`, `GPU_DMEM_WDATA_LO/HI`, `GPU_DMEM_CMD`.
- Control/status: `GPU_CTRL` holds reset; `GPU_STATUS` reports completion and DMA activity.
- DMA: direction, FIFO base, GPU base, nonzero 8-bit length, and start strobe.

The external IMEM/DMEM Port B write enables are not gated by `gpu_reset`. Holding reset during loading keeps the core idle but is not required for the host port itself.

### 3.4 Data-Movement Limit

DMA moves 64-bit words. FIFO-to-GPU drops the FIFO control byte; GPU-to-FIFO prepends `8'h00`, so DMA neither preserves nor creates an NF2 module header. The usual flow leaves BRAM[0]'s existing header in place and copies payload words at later addresses.

The nonzero 8-bit length permits 1–255 words. The 10-bit GPU base plus zero-extended offset can select a window anywhere in the 1024-word DMEM; address sums wrap at their native widths.

---

## 4. gpu_top.v — The External Boundary

This is the GPU boundary that `lab8_wrapper` instantiates. It owns the core plus both GPU memories and exposes their Port B interfaces to the integration wrapper.

### 4.1 Module Port Declaration

```verilog
module gpu_top (
    input         clk,
    input         rst,

    // Thread id (directly from host
    input  [31:0] thread_id,
    input  [31:0] block_id,
    input  [31:0] block_dim,


    output        kernel_done,

    // External IMEM interface (Port B
    input  [`IMEM_ADDR_W-1:0]   ext_imem_addr,
    input                        ext_imem_wr_en,
    input  [`INSTR_WIDTH-1:0]   ext_imem_wr_data,
    output [`INSTR_WIDTH-1:0]   ext_imem_rd_data,

    // External DMEM interface (Port B
    input  [`DMEM_ADDR_W-1:0]   ext_dmem_addr,
    input                        ext_dmem_wr_en,
    input  [`DATA_WIDTH-1:0]    ext_dmem_wr_data,
    output [`DATA_WIDTH-1:0]    ext_dmem_rd_data
);
```

The port declaration has `clk` and `rst` (synchronous reset, normally held HIGH during loading to keep the core idle), thread identity inputs (`thread_id` maps to R13, `block_id` to R14, `block_dim` to R15), registered `kernel_done`, and Port B interfaces for IMEM and DMEM. In the integration wrapper the identity values are tied to 0, 0, and 1. Completion asserts after `halted_r` samples a HALT indication from EX3/WB, one clock after that indication first appears.

**Architecture -- why memories are outside the core:**
```
gpu_top
├── core_top              ← Pure logic (pipeline stages + hazard unit)
├── instruction_memory    ← BRAM (infers Block RAM in synthesis)
└── data_memory           ← BRAM (infers Block RAM in synthesis)
```
- **Synthesis:** XST maps top-level memory instances to Block RAM more reliably
- **Dual-port access:** Both memories need Port A (core) and Port B (host). If memories were inside core, you'd route external ports through the core — unnecessary complexity
- **External access:** Host loads programs and data via Port B without touching the pipeline

### 4.2 Internal Wires

```verilog
    wire        core_halted;

    // Core <-> Instruction Memory
    wire [`IMEM_ADDR_W-1:0] imem_addr;
    wire                    imem_rd_en;
    wire [`INSTR_WIDTH-1:0] imem_data;

    // Core <-> Data Memory
    wire [`DMEM_ADDR_W-1:0] dmem_addr;
    wire [`DATA_WIDTH-1:0]  dmem_wr_data;
    wire                    dmem_wr_en;
    wire [`DATA_WIDTH-1:0]  dmem_rd_data;
```

Only eight internal wires connect core and memories. `core_halted` is the registered sticky completion signal. The IMEM wires carry the fetch path: `imem_addr` (PC), `imem_rd_en` (enabled only when not stalled, halted, or redirecting a taken branch), and `imem_data`. The DMEM wires carry the dedicated low-10-bit base+offset address, store data/enable, and synchronous load data. Port A and Port B are independent BRAM ports; same-address cross-port collisions still require avoidance.

### 4.3 Dispatcher Stub

```verilog
    // kernel_done tracks core halt
    assign kernel_done = core_halted;
```

There is no dispatcher FSM in the current path. The wrapper supplies one set of hardwired identity values, and this assignment simply exports the core's sticky completion state.

### 4.4 Core Instantiation

```verilog
    //
    // Processor Core (6-stage: IF -> ID -> EX1 -> EX2 -> EX3 -> WB)

    core_top u_core (
        .clk          (clk),
        .rst          (rst),
        .thread_id    (thread_id),
        .block_id     (block_id),
        .block_dim    (block_dim),
        .halted       (core_halted),
        // IMEM
        .imem_addr    (imem_addr),
        .imem_rd_en   (imem_rd_en),
        .imem_data    (imem_data),
        // DMEM
        .dmem_addr    (dmem_addr),
        .dmem_wr_data (dmem_wr_data),
        .dmem_wr_en   (dmem_wr_en),
        .dmem_rd_data (dmem_rd_data)
    );
```

The core receives `thread_id`, `block_id`, and `block_dim`, which map to R13, R14, and R15. The registered `halted` output becomes sticky after HALT is observed at EX3/WB. IMEM Port A is enabled by `!stall && !halted && !ex1_branch_taken`; DMEM Port A carries the execute-stage load/store path.

### 4.5 Memory Instantiations

```verilog
    //
    // Instruction Memory (1024 x 32-bit BRAM)
    //
    instruction_memory u_imem (
        .clk       (clk),
        .rd_en     (imem_rd_en),
        .addr      (imem_addr),
        .rd_data   (imem_data),
        .addr_b    (ext_imem_addr),
        .wr_en_b   (ext_imem_wr_en),
        .wr_data_b (ext_imem_wr_data),
        .rd_data_b (ext_imem_rd_data)
    );

    //
    // Data Memory (1024 x 64-bit BRAM)
    //
    data_memory u_dmem (
        .clk       (clk),
        .addr      (dmem_addr),
        .wr_en     (dmem_wr_en),
        .wr_data   (dmem_wr_data),
        .rd_data   (dmem_rd_data),
        .addr_b    (ext_dmem_addr),
        .wr_en_b   (ext_dmem_wr_en),
        .wr_data_b (ext_dmem_wr_data),
        .rd_data_b (ext_dmem_rd_data)
    );
```

Both memories are dual-port BRAMs. Port A is core-facing. For IMEM, `rd_en` holds the registered output during a stall, halt, or taken-branch redirect. For DMEM, the dedicated address adder supplies the low 10-bit address, ST supplies write data/enable, and synchronous read data feeds writeback. Port B is driven through `lab8_wrapper` command registers or DMA for program/data loading and result readback.

### 4.6 Operational Flow (Coprocessor Model)

```
Time ──────────────────────────────────────────────────────────►

Phase 1: LOAD              Phase 2: EXECUTE            Phase 3: READ
─────────────────          ──────────────────          ─────────────
rst=1                      rst=0                       kernel_done=1
Host writes IMEM[Port B]   Core fetches IMEM[Port A]   Host reads DMEM[Port B]
Host writes DMEM[Port B]   Core reads/writes DMEM[A]
thread_id=0                PC: 0 → 1 → 2 → ...
                           HALT → kernel_done=1
```

**Critical:** Host MUST hold `rst=1` during Phase 1, or the core fetches garbage from IMEM[0] before the program is loaded.

---

## 5. core_top.v — The Pipeline Orchestrator

All 6 pipeline stages + hazard unit are wired together here. `core_top` also performs the EX1 signed branch comparison/target calculation, HALT latching, and top-level fetch/store gating.

> **Note:** This file was originally written for the 4-stage pipeline (IF/ID/EX/WB). It has been updated to reflect the 6-stage pipeline (IF/ID/EX1/EX2/EX3/WB) implemented as part of the Lab8 timing fix. Key changes: `ex_busy` eliminated, EX split into EX1+EX2+EX3, reusable `pipeline_reg_ex` added, hazard unit checks 4 stages, and branch resolution moved to EX1 in `core_top.v` (2-cycle taken-branch penalty).

### 5.1 Module Ports

```verilog
module core_top (
    input         clk,
    input         rst,

    // Thread identity (from dispatcher)
    input  [31:0] thread_id,
    input  [31:0] block_id,
    input  [31:0] block_dim,

    // Status
    output        halted,

    // Instruction Memory interface
    output [`IMEM_ADDR_W-1:0] imem_addr,
    output                    imem_rd_en,
    input  [`INSTR_WIDTH-1:0] imem_data,

    // Data Memory interface
    output [`DMEM_ADDR_W-1:0] dmem_addr,
    output [`DATA_WIDTH-1:0]  dmem_wr_data,
    output                    dmem_wr_en,
    input  [`DATA_WIDTH-1:0]  dmem_rd_data
);
```

The core receives `thread_id`/`block_id`/`block_dim` from its wrapper inputs (mapped to R13/R14/R15). The registered sticky `halted` output feeds `gpu_top.kernel_done`. The IMEM interface holds its registered output during stalls, after halt, and on taken-branch redirect. The DMEM interface carries the execute stage's dedicated low-10-bit address, ST data/enable, and one-cycle LD data.

### 5.2 Pipeline Control Signals

```verilog
    // Pipeline control signals from hazard unit
    //===========================
    wire stall;
    wire ex1_branch_taken;

    // Hold IMEM output during stall, halt, or branch flush
    //=============================
    assign imem_rd_en = !stall && !halted && !ex1_branch_taken;
```

IMEM uses a synchronous registered output. When `rd_en=0`, it holds the prior instruction. A RAW stall preserves the instruction waiting in decode; halt prevents further fetch progress; and a taken branch prevents the wrong-path address from replacing the held output during redirect.

### 5.3 Inter-Stage Wire Declarations

**Signal naming convention:** `<stage_prefix>_<signal_name>`

```verilog
    // IF/ID pipeline register outputs
    //===========================
    wire [`INSTR_WIDTH-1:0] ifid_instruction;
    wire [`PC_WIDTH-1:0]    ifid_pc;
    wire                    ifid_valid;
```

IF/ID outputs: `ifid_instruction` is the 32-bit instruction from IMEM, `ifid_pc` is the PC that fetched it, and `ifid_valid` indicates whether this is a real instruction (not a bubble after flush/reset).

```verilog
    // Decode stage outputs (into ID/EX pipeline register)
    //================================
    wire [3:0]  dec_alu_op;
    wire        dec_reg_write;
    wire        dec_mem_read;
    wire        dec_mem_write;
    wire        dec_is_fma;
    wire        dec_use_imm;
    wire [2:0]  dec_dtype;
    wire        dec_is_halt;

    wire [`REG_ADDR_W-1:0]  dec_rd;
    wire [`REG_ADDR_W-1:0]  dec_rs1_addr;
    wire [`REG_ADDR_W-1:0]  dec_rs2_addr;
    wire [`REG_ADDR_W-1:0]  dec_rs3_addr;
    wire [`DATA_WIDTH-1:0]  dec_rs1_data;
    wire [`DATA_WIDTH-1:0]  dec_rs2_data;
    wire [`DATA_WIDTH-1:0]  dec_rs3_data;
    wire [`DATA_WIDTH-1:0]  dec_imm_ext;
    wire [`PC_WIDTH-1:0]    dec_pc;
    wire [1:0]              dec_branch_type;
```

Decode outputs: control signals (`dec_alu_op` selects the ALU operation, `dec_reg_write` indicates a register-writing instruction, `dec_mem_read` for LD, `dec_mem_write` for ST, `dec_is_fma` routes to the FMA unit, `dec_use_imm` substitutes immediate for rs2, `dec_dtype` selects int16 vs BF16 path, `dec_is_halt` triggers the sticky halt latch, `dec_branch_type` identifies BLT/BGE). Register addresses feed the hazard unit; register data values feed execute and EX1 branch comparison. `dec_imm_ext` is the sign/zero-extended immediate, and `dec_pc` is forwarded so EX1 can compute a branch target.

```verilog
    // ID/EX pipeline register outputs
    //=====================
    wire [3:0]  idex_alu_op;
    wire        idex_reg_write;
    wire        idex_mem_read;
    wire        idex_mem_write;
    wire        idex_is_fma;
    wire        idex_use_imm;
    wire [2:0]  idex_dtype;
    wire        idex_is_halt;
    wire [1:0]  idex_branch_type;

    wire [`REG_ADDR_W-1:0]  idex_rd;
    wire [`DATA_WIDTH-1:0]  idex_rs1_data;
    wire [`DATA_WIDTH-1:0]  idex_rs2_data;
    wire [`DATA_WIDTH-1:0]  idex_rs3_data;
    wire [`DATA_WIDTH-1:0]  idex_imm_ext;
    wire [`PC_WIDTH-1:0]    idex_pc;
```

ID/EX register outputs: Same execute/branch signals as `dec_*` but registered (1 cycle delayed). Source register address outputs are not carried past decode; the hazard unit checks the muxed `dec_rs*` addresses directly.

```verilog
    // Execute stage outputs
    //==========================
    wire [`DATA_WIDTH-1:0]  ex_result;
    wire                    dmem_wr_en_raw;
```

Execute outputs: the 64-bit ALU/FMA result, valid in EX3, and the raw EX3 store strobe. `core_top` gates the latter with the registered `halted` state before driving DMEM.

```verilog
    // EX1/EX2 pipeline register outputs
    //===========================
    wire        ex1ex2_reg_write;
    wire        ex1ex2_mem_read;
    wire [`REG_ADDR_W-1:0]  ex1ex2_rd;
    wire                    ex1ex2_is_halt;


    // EX2/EX3 pipeline register outputs
    //===========================
    wire        ex2ex3_reg_write;
    wire        ex2ex3_mem_read;
    wire [`REG_ADDR_W-1:0]  ex2ex3_rd;
    wire                    ex2ex3_is_halt;
```

EX1/EX2 and EX2/EX3 register outputs: control signals passing through the execute pipeline stages. These carry `reg_write` (should WB write to register file?), `mem_read` (is this a LD?), `rd` (which register to write), and `is_halt` (HALT instruction). These are also read by the hazard unit for 4-stage dependency checking.

```verilog
    // EX3/WB pipeline register outputs
    //========================
    wire        exwb_reg_write;
    wire        exwb_mem_read;
    wire [`REG_ADDR_W-1:0]  exwb_rd;
    wire [`DATA_WIDTH-1:0]  exwb_alu_result;
    wire                    exwb_is_halt;


    // Writeback stage outputs
    //==========================
    wire                    wb_reg_write;
    wire [`REG_ADDR_W-1:0]  wb_rd;
    wire [`DATA_WIDTH-1:0]  wb_data;
```

EX3/WB register outputs add `exwb_alu_result` (the ALU result from EX3). Writeback outputs (`wb_reg_write`, `wb_rd`, `wb_data`) feed back into the register file write port inside `decode_stage`. `wb_data` is the final data after the writeback MUX (ALU result OR DMEM load data).

**Tracing a signal through the pipeline:** Follow the prefix chain. Example for destination register:
```
ifid_instruction[26:23] → dec_rd → idex_rd → ex1ex2_rd → ex2ex3_rd → exwb_rd → wb_rd
```

### 5.4 Program Counter Instantiation

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
```

**Priority inside PC:** `rst > branch > stall > increment`. On reset, PC=0. On taken branch, PC=target. On stall, PC holds. Otherwise, PC=PC+1.

**Why branch comes from EX1 (2-cycle penalty)?** Decode reads the branch operands and carries them through ID/EX. `core_top.v` compares them in EX1, redirects the PC with `ex1_branch_taken`, and flushes the two younger wrong-path slots.

### 5.5 Fetch Stage

```verilog
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

**Critical design choice:** `ifid_instruction = imem_data` -- the BRAM output register serves double duty as the IF/ID instruction register. `fetch_stage` only tracks metadata (PC + valid bit). This saves 32 flip-flops. `stall` holds PC metadata when stalled, `flush` kills the instruction (branch taken), `pc_in` is the current PC value, `pc_out` is the registered PC for this instruction, and `valid_out` indicates whether this is a real instruction (not a bubble).

**Why `valid_out`?** After reset or flush, the pipeline has bubbles. The valid bit prevents bubbles from writing registers or memory. Without it, a flushed NOP that happens to decode as a real instruction could corrupt state.

### 5.6 Decode Stage

```verilog
    // Decode stage (includes decoder + register file + ID/EX register)
    //================
    decode_stage u_decode (
        .clk             (clk),
        .rst             (rst),
        .stall           (stall),
        .flush           (ex1_branch_taken),
        // From IF/ID
        .instruction     (ifid_instruction),
        .pc_in           (ifid_pc),
        .valid_in        (ifid_valid),
        // Thread identity for special registers
        .thread_id       (thread_id),
        .block_id        (block_id),
        .block_dim       (block_dim),
        // Writeback port (from WB stage)
        .wb_reg_write    (wb_reg_write),
        .wb_rd           (wb_rd),
        .wb_data         (wb_data),
        // Decoded outputs -> ID/EX
        .alu_op_out      (dec_alu_op),
        .reg_write_out   (dec_reg_write),
        .mem_read_out    (dec_mem_read),
        .mem_write_out   (dec_mem_write),
        .is_fma_out      (dec_is_fma),
        .use_imm_out     (dec_use_imm),
        .dtype_out       (dec_dtype),
        .is_halt_out     (dec_is_halt),
        .branch_type_out (dec_branch_type),
        .rd_out          (dec_rd),
        .rs1_addr_out    (dec_rs1_addr),
        .rs2_addr_out    (dec_rs2_addr),
        .rs3_addr_out    (dec_rs3_addr),
        .rs1_data_out    (dec_rs1_data),
        .rs2_data_out    (dec_rs2_data),
        .rs3_data_out    (dec_rs3_data),
        .imm_ext_out     (dec_imm_ext),
        .pc_out          (dec_pc)
    );
```

**The writeback feedback loop:** `wb_reg_write`, `wb_rd`, `wb_data` flow BACKWARD from the writeback stage into decode. This is because the register file lives inside `decode_stage`. When an instruction completes in WB, it writes its result back through these ports. This is a classic pipeline feedback — the end of the pipeline writes to a resource that the beginning reads.

### 5.7 ID/EX Pipeline Register

```verilog
    // ID/EX Pipeline Register
    //=========================
    pipeline_reg_idex u_idex (
        .clk             (clk),
        .rst             (rst),
        .stall           (stall),
        .flush           (stall || ex1_branch_taken),
        // Inputs from decode
        .alu_op_in       (dec_alu_op),
        .reg_write_in    (dec_reg_write),
        .mem_read_in     (dec_mem_read),
        .mem_write_in    (dec_mem_write),
        .is_fma_in       (dec_is_fma),
        .use_imm_in      (dec_use_imm),
        .dtype_in        (dec_dtype),
        .is_halt_in      (dec_is_halt),
        .branch_type_in  (dec_branch_type),
        .rd_in           (dec_rd),
        .rs1_data_in     (dec_rs1_data),
        .rs2_data_in     (dec_rs2_data),
        .rs3_data_in     (dec_rs3_data),
        .imm_ext_in      (dec_imm_ext),
        .pc_in           (dec_pc),
        // Outputs to execute
        .alu_op_out      (idex_alu_op),
        .reg_write_out   (idex_reg_write),
        .mem_read_out    (idex_mem_read),
        .mem_write_out   (idex_mem_write),
        .is_fma_out      (idex_is_fma),
        .use_imm_out     (idex_use_imm),
        .dtype_out       (idex_dtype),
        .is_halt_out     (idex_is_halt),
        .branch_type_out (idex_branch_type),
        .rd_out          (idex_rd),
        .rs1_data_out    (idex_rs1_data),
        .rs2_data_out    (idex_rs2_data),
        .rs3_data_out    (idex_rs3_data),
        .imm_ext_out     (idex_imm_ext),
        .pc_out          (idex_pc)
    );
```

**Why is `flush` wired to `stall || ex1_branch_taken`?** The ID/EX register gets a bubble during RAW stalls and when an EX1 branch is taken:

- **Data hazard stall (`stall=1`):** PC holds, IF/ID holds, and ID/EX must be **flushed to NOP**. Why? The instruction in decode can't advance (it's waiting for a hazard to clear). The instruction currently in ID/EX proceeds normally into EX1→EX2→EX3 via the internal ALU/FMA pipeline and `pipeline_reg_ex` instances.
- **Branch taken (`ex1_branch_taken=1`):** PC redirects and both IF/ID and ID/EX are flushed, killing the two younger wrong-path instructions behind the branch.

```
Data hazard stall:         Branch taken (2-cycle penalty):
  PC:      holds             PC:      → branch target
  IF/ID:   holds             IF/ID:   → bubble (NOP via flush)
  ID/EX:   → bubble (NOP)   ID/EX:   → bubble (NOP via flush)
  EX1/EX2: normal            EX1/EX2: normal
  EX2/EX3: normal            EX2/EX3: normal
  EX3/WB:  normal            EX3/WB:  normal
  WB:      normal            WB:      normal
```

> **History:** The old 4-stage pipeline had `flush | (stall & ~ex_busy)` here, with a special "hold" case for FMA busy stalls. With the 6-stage pipeline, `ex_busy` is eliminated and FMA's 3-cycle pipeline aligns naturally with EX1+EX2+EX3. Current branch resolution is in EX1, so ID/EX flush receives `stall || ex1_branch_taken`.

### 5.8 Execute Stage

```verilog
    //
    // Execute Stage (EX1 inputs from ID/EX, EX3 outputs to EX/WB)
    //========================
    execute_stage u_execute (
        .clk           (clk),
        .rst           (rst),
        .alu_op        (idex_alu_op),
        .is_fma        (idex_is_fma),
        .use_imm       (idex_use_imm),
        .dtype         (idex_dtype),
        .mem_write     (idex_mem_write),
        .rs1_data      (idex_rs1_data),
        .rs2_data      (idex_rs2_data),
        .rs3_data      (idex_rs3_data),
        .imm_ext       (idex_imm_ext),
        // Outputs
        .result        (ex_result),
        // DMEM interface (active in EX3)
        .dmem_addr     (dmem_addr),
        .dmem_wr_data  (dmem_wr_data),
        .dmem_wr_en    (dmem_wr_en_raw)
    );

    // Gate DMEM writes after HALT
    assign dmem_wr_en = dmem_wr_en_raw && !halted;
```

**3-cycle execute alignment.** The FMA unit spans EX1, EX2, and EX3. The current `simd_alu` registers BCAST/effective operands and controls at its input, then aligns its four BF16 lane results with one registered lane-0 INT16 result; it produces `simd_result` directly in EX3, so `execute_stage` has no `simd_result_r`. Branch comparison/target logic lives separately in `core_top` EX1, and there is no `ex_busy` signal.

**DMEM writes happen in EX3.** The execute stage internally registers `mem_write` and `rs2_data` through EX1→EX2 and EX2→EX3 internal registers. In EX3, the DMEM address comes from a doubly-registered pipeline (EX1 compute, EX1→EX2 reg, EX2→EX3 reg), and write data/enable come from the internal registers.

**DMEM reads take one cycle** (synchronous BRAM). The address is driven in EX3, the data arrives at `dmem_rd_data` one cycle later, which aligns with writeback.

### 5.9 EX1/EX2 Pipeline Register

```verilog
    //
    // EX1/EX2 Pipeline Register (control signals only — ALU data pipelined internally)
    //===========================
    pipeline_reg_ex u_ex1ex2 (
        .clk            (clk),
        .rst            (rst),
        .flush          (1'b0),
        // Inputs from ID/EX (latched at end of EX1)
        .reg_write_in   (idex_reg_write),
        .mem_read_in    (idex_mem_read),
        .rd_in          (idex_rd),
        .is_halt_in     (idex_is_halt),
        // Outputs to EX2
        .reg_write_out  (ex1ex2_reg_write),
        .mem_read_out   (ex1ex2_mem_read),
        .rd_out         (ex1ex2_rd),
        .is_halt_out    (ex1ex2_is_halt)
    );
```

**Reusable control-only register.** `pipeline_reg_ex` is a generic control pipeline register instantiated twice -- once for EX1/EX2 and once for EX2/EX3. ALU data is pipelined internally within `execute_stage` (via `simd_alu`/`bf16_alu` and `bf16_fma_unit`). This register carries `reg_write`, `mem_read`, `rd`, and `is_halt`. Its `flush` input is tied to `1'b0`: when a branch resolves in EX1, the branch and all older instructions must complete, while bubbles inserted into ID/EX flow through naturally.

### 5.10 EX2/EX3 Pipeline Register

```verilog
    //
    // EX2/EX3 Pipeline Register (reuses pipeline_reg_ex module)
    //===========================
    pipeline_reg_ex u_ex2ex3 (
        .clk            (clk),
        .rst            (rst),
        .flush          (1'b0),
        // Inputs from EX1/EX2 register
        .reg_write_in   (ex1ex2_reg_write),
        .mem_read_in    (ex1ex2_mem_read),
        .rd_in          (ex1ex2_rd),
        .is_halt_in     (ex1ex2_is_halt),
        // Outputs to EX3
        .reg_write_out  (ex2ex3_reg_write),
        .mem_read_out   (ex2ex3_mem_read),
        .rd_out         (ex2ex3_rd),
        .is_halt_out    (ex2ex3_is_halt)
    );
```

**Same module, second instance.** Identical to the EX1/EX2 register -- `pipeline_reg_ex` is reused. Inputs come from the EX1/EX2 register outputs, and outputs feed the EX3/WB register and hazard unit.

### 5.11 EX3/WB Pipeline Register

```verilog
    //
    // EX3/WB Pipeline Register
    //===========================
    pipeline_reg_exwb u_exwb (
        .clk            (clk),
        .rst            (rst),
        // Inputs from EX3 (control from EX2/EX3 reg, data from execute_stage)
        .reg_write_in   (ex2ex3_reg_write),
        .mem_read_in    (ex2ex3_mem_read),
        .rd_in          (ex2ex3_rd),
        .alu_result_in  (ex_result),
        .is_halt_in     (ex2ex3_is_halt),
        // Outputs to writeback
        .reg_write_out  (exwb_reg_write),
        .mem_read_out   (exwb_mem_read),
        .rd_out         (exwb_rd),
        .alu_result_out (exwb_alu_result),
        .is_halt_out    (exwb_is_halt)
    );
```

**Control from EX2/EX3 register.** Unlike the old 4-stage design where control came directly from ID/EX, control now comes from the EX2/EX3 pipeline register (two cycles delayed from ID/EX). Data (`alu_result`) comes from `execute_stage`'s EX3 output. Both are time-aligned: they represent the same instruction.

**No stall input.** The old `stall` driven by `ex_busy` is eliminated. All operations take exactly 3 EX cycles (EX1+EX2+EX3), so EX3/WB latches unconditionally every cycle.

### 5.12 Writeback Stage

```verilog
    //
    // Writeback Stage
    //=====================
    writeback_stage u_writeback (
        .reg_write_in  (exwb_reg_write),
        .mem_read      (exwb_mem_read),
        .rd_in         (exwb_rd),
        .alu_result    (exwb_alu_result),
        .mem_data      (dmem_rd_data),
        // Outputs
        .reg_write_out (wb_reg_write),
        .rd_out        (wb_rd),
        .data_out      (wb_data)
    );
```

**The entire writeback stage is a 2:1 MUX:** If `mem_read=1` (LD), output DMEM data. Otherwise, output ALU result. Plus pass-through of write enable and destination register.

**`dmem_rd_data` is NOT from the EX3/WB register.** It comes directly from the DMEM output port. The 1-cycle BRAM latency naturally aligns: execute drives the address in EX3 (cycle N), DMEM outputs the data in cycle N+1 (writeback cycle).

### 5.13 Hazard Unit

```verilog
    //
    // Hazard Unit (stall-only, no forwarding)
    //==============================
    hazard_unit u_hazard (
        // Decode-stage source registers
        .de_rs1        (dec_rs1_addr),
        .de_rs2        (dec_rs2_addr),
        .de_rs3        (dec_rs3_addr),
        .de_is_fma     (dec_is_fma),
        // EX1 stage destination (from ID/EX)
        .ex1_rd        (idex_rd),
        .ex1_reg_write (idex_reg_write),
        // EX2 stage destination (from EX1/EX2)
        .ex2_rd        (ex1ex2_rd),
        .ex2_reg_write (ex1ex2_reg_write),
        // EX3 stage destination (from EX2/EX3)
        .ex3_rd        (ex2ex3_rd),
        .ex3_reg_write (ex2ex3_reg_write),
        // WB stage destination (from EX3/WB)
        .wb_rd         (exwb_rd),
        .wb_reg_write  (exwb_reg_write),
        .stall         (stall)
    );
```

**Stall conditions detected (4 stages checked):**
1. **EX1 hazard:** decode reads register X, EX1 is about to write register X → stall
2. **EX2 hazard:** decode reads register X, EX2 is about to write register X → stall
3. **EX3 hazard:** decode reads register X, EX3 is about to write register X → stall
4. **WB hazard:** decode reads register X, WB is about to write register X → stall
5. **R0 exemption:** dependencies on R0 never stall (R0 is hardwired zero)

Worst-case RAW stall: **4 cycles** (back-to-back dependency traverses EX1 → EX2 → EX3 → WB).

**Branch flush is outside the hazard unit.** `core_top.v` derives `ex1_branch_taken` from ID/EX branch metadata, redirects the PC, and flushes IF/ID plus ID/EX. The hazard unit is strictly RAW-stall logic.

### 5.14 Halt Detection

```verilog
    // Halt detection, once HALT reaches WB, stay halted
    //=================================
    reg halted_r;
    always @(posedge clk) begin
        if (rst)
            halted_r <= 1'b0;
        else if (exwb_is_halt)
            halted_r <= 1'b1;
    end
    assign halted = halted_r;
```

**Registered sticky latch:** `halted_r` latches HIGH on the edge where `exwb_is_halt` is sampled and remains HIGH until reset. There is no combinational EX3/WB bypass. Once registered, `halted` holds the PC, disables IMEM reads, and suppresses DMEM writes, but it does not flush/gate `fetch_stage`, ID/EX, or register-file writeback. Thus HALT is completion/status plus limited side-effect gating, not a full pipeline kill: younger work can continue, and the instruction held in the IMEM output can continue entering the ungated downstream pipeline until reset.

---

## Pipeline Timing Diagram

```
Cycle:   0        1        2        3        4        5        6        7
         ──────   ──────   ──────   ──────   ──────   ──────   ──────   ──────
PC:      0        1        2        3        4        5        6        ...
IMEM:    fetch[0] fetch[1] fetch[2] fetch[3] fetch[4] fetch[5] fetch[6]
IF/ID:   ───      instr 0  instr 1  instr 2  instr 3  instr 4  instr 5  instr 6
Decode:  ───      ───      instr 0  instr 1  instr 2  instr 3  instr 4  instr 5
ID/EX:   ───      ───      ───      instr 0  instr 1  instr 2  instr 3  instr 4
EX1:     ───      ───      ───      [ex1  0] [ex1  1] [ex1  2] [ex1  3] [ex1  4]
EX1/EX2: ───      ───      ───      ───      ctrl 0   ctrl 1   ctrl 2   ctrl 3
EX2:     ───      ───      ───      ───      [ex2  0] [ex2  1] [ex2  2] [ex2  3]
EX2/EX3: ───      ───      ───      ───      ───      ctrl 0   ctrl 1   ctrl 2
EX3:     ───      ───      ───      ───      ───      [ex3  0] [ex3  1] [ex3  2]
EX3/WB:  ───      ───      ───      ───      ───      ───      result 0 result 1
WB:      ───      ───      ───      ───      ───      ───      [wb 0]   [wb 1]

Instr 0 latency: fetched at cycle 0, writes back at cycle 6 = 6 cycles
Steady-state throughput: 1 instruction/cycle (IPC = 1, no hazards)
FMA and SIMD paths both align in EX3; SIMD's third stage is now inside `simd_alu` (input register + BF16/INT16 alignment), with no `execute_stage.simd_result_r`
```

---

## Global Control Signal Map

```
 decode source regs ──► hazard_unit ◄── EX1/EX2/EX3/WB destinations
                            │ stall
                            ├──► PC hold + IMEM read disable
                            ├──► IF/ID hold
                            └──► ID/EX flush

 ID/EX branch metadata ──► core_top EX1 compare/target
                                      │ ex1_branch_taken
                                      ├──► PC redirect + IMEM read disable
                                      ├──► IF/ID flush
                                      └──► ID/EX flush

 halted_r ──► PC hold + IMEM read disable + DMEM-write gate
              (does not gate fetch metadata, ID/EX, or register writeback)

              wb_reg_write/wb_rd/wb_data ────────→ register_file (in decode_stage)
              (writeback feedback loop)
```

---

## Summary — What Batch 1 Establishes

1. **include/gpu_params.vh** — the active "contract": every module agrees on widths, opcodes, and field positions; the duplicate under `src/gpu` is stale
2. **user_data_path.v** — the "chassis": NF2.1 data-path and register-ring chain with `lab8_wrapper` between output-port lookup and output queues
3. **lab8_wrapper.v** — the integration bridge: convertible FIFO, ARM, GPU, DMA, command registers, status, and cycle counter; no standalone `gpu_nf2_wrapper.v` exists in this checkpoint
4. **gpu_top.v** — the "boundary": 3 components (core + 2 memories), external host ports
5. **core_top.v** — the "plumbing": 10 sub-modules in a 6-stage pipeline with RAW stall control, EX1 branch redirect/flush, and one feedback loop (writeback to register file). Branches resolve in EX1 with a 2-cycle taken-branch penalty

**Next batch:** Fetch Stage — `program_counter.v`, `instruction_memory.v`, `fetch_stage.v`
