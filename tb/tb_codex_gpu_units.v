`timescale 1ns / 1ps
`include "gpu_params.vh"

module tb_codex_gpu_units;
    reg clk;
    integer pass_count;
    integer fail_count;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task check;
        input cond;
        input [1023:0] label;
        begin
            if (cond) begin
                pass_count = pass_count + 1;
                $display("PASS: %0s", label);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: %0s", label);
            end
        end
    endtask

    task check32;
        input [31:0] actual;
        input [31:0] expected;
        input [1023:0] label;
        begin
            if (actual === expected) begin
                pass_count = pass_count + 1;
                $display("PASS: %0s = 0x%08h", label, actual);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: %0s got 0x%08h expected 0x%08h", label, actual, expected);
            end
        end
    endtask

    task check64;
        input [63:0] actual;
        input [63:0] expected;
        input [1023:0] label;
        begin
            if (actual === expected) begin
                pass_count = pass_count + 1;
                $display("PASS: %0s = 0x%016h", label, actual);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: %0s got 0x%016h expected 0x%016h", label, actual, expected);
            end
        end
    endtask

    // Program counter
    reg pc_rst;
    reg pc_stall;
    reg pc_branch_en;
    reg [`PC_WIDTH-1:0] pc_branch_target;
    wire [`PC_WIDTH-1:0] pc_out;

    program_counter u_pc (
        .clk(clk),
        .rst(pc_rst),
        .stall(pc_stall),
        .branch_en(pc_branch_en),
        .branch_target(pc_branch_target),
        .pc_out(pc_out)
    );

    // Fetch stage
    reg fetch_rst;
    reg fetch_stall;
    reg fetch_flush;
    reg [`PC_WIDTH-1:0] fetch_pc_in;
    wire [`PC_WIDTH-1:0] fetch_pc_out;
    wire fetch_valid_out;

    fetch_stage u_fetch (
        .clk(clk),
        .rst(fetch_rst),
        .stall(fetch_stall),
        .flush(fetch_flush),
        .pc_in(fetch_pc_in),
        .pc_out(fetch_pc_out),
        .valid_out(fetch_valid_out)
    );

    // ID/EX pipeline register
    reg pipe_rst;
    reg pipe_stall;
    reg pipe_flush;
    reg [3:0] pipe_alu_in;
    reg pipe_reg_write_in;
    reg pipe_mem_read_in;
    reg pipe_mem_write_in;
    reg pipe_is_fma_in;
    reg pipe_use_imm_in;
    reg [2:0] pipe_dtype_in;
    reg pipe_is_halt_in;
    reg [1:0] pipe_branch_type_in;
    reg [`REG_ADDR_W-1:0] pipe_rd_in;
    reg [`DATA_WIDTH-1:0] pipe_rs1_in;
    reg [`DATA_WIDTH-1:0] pipe_rs2_in;
    reg [`DATA_WIDTH-1:0] pipe_rs3_in;
    reg [`DATA_WIDTH-1:0] pipe_imm_in;
    reg [`PC_WIDTH-1:0] pipe_pc_in;
    wire [3:0] pipe_alu_out;
    wire pipe_reg_write_out;
    wire pipe_mem_read_out;
    wire pipe_mem_write_out;
    wire pipe_is_fma_out;
    wire pipe_use_imm_out;
    wire [2:0] pipe_dtype_out;
    wire pipe_is_halt_out;
    wire [1:0] pipe_branch_type_out;
    wire [`REG_ADDR_W-1:0] pipe_rd_out;
    wire [`DATA_WIDTH-1:0] pipe_rs1_out;
    wire [`DATA_WIDTH-1:0] pipe_rs2_out;
    wire [`DATA_WIDTH-1:0] pipe_rs3_out;
    wire [`DATA_WIDTH-1:0] pipe_imm_out;
    wire [`PC_WIDTH-1:0] pipe_pc_out;

    pipeline_reg_idex u_idex (
        .clk(clk),
        .rst(pipe_rst),
        .stall(pipe_stall),
        .flush(pipe_flush),
        .alu_op_in(pipe_alu_in),
        .reg_write_in(pipe_reg_write_in),
        .mem_read_in(pipe_mem_read_in),
        .mem_write_in(pipe_mem_write_in),
        .is_fma_in(pipe_is_fma_in),
        .use_imm_in(pipe_use_imm_in),
        .dtype_in(pipe_dtype_in),
        .is_halt_in(pipe_is_halt_in),
        .branch_type_in(pipe_branch_type_in),
        .rd_in(pipe_rd_in),
        .rs1_data_in(pipe_rs1_in),
        .rs2_data_in(pipe_rs2_in),
        .rs3_data_in(pipe_rs3_in),
        .imm_ext_in(pipe_imm_in),
        .pc_in(pipe_pc_in),
        .alu_op_out(pipe_alu_out),
        .reg_write_out(pipe_reg_write_out),
        .mem_read_out(pipe_mem_read_out),
        .mem_write_out(pipe_mem_write_out),
        .is_fma_out(pipe_is_fma_out),
        .use_imm_out(pipe_use_imm_out),
        .dtype_out(pipe_dtype_out),
        .is_halt_out(pipe_is_halt_out),
        .branch_type_out(pipe_branch_type_out),
        .rd_out(pipe_rd_out),
        .rs1_data_out(pipe_rs1_out),
        .rs2_data_out(pipe_rs2_out),
        .rs3_data_out(pipe_rs3_out),
        .imm_ext_out(pipe_imm_out),
        .pc_out(pipe_pc_out)
    );

    // Decoder
    reg [`INSTR_WIDTH-1:0] dec_instruction;
    reg dec_valid;
    wire [3:0] dec_alu_op;
    wire dec_reg_write;
    wire dec_mem_read;
    wire dec_mem_write;
    wire dec_is_fma;
    wire [1:0] dec_branch_type;
    wire dec_use_imm;
    wire [2:0] dec_dtype;
    wire dec_is_halt;
    wire [`REG_ADDR_W-1:0] dec_rd;
    wire [`REG_ADDR_W-1:0] dec_rs1;
    wire [`REG_ADDR_W-1:0] dec_rs2;
    wire [`REG_ADDR_W-1:0] dec_rs3;
    wire [`DATA_WIDTH-1:0] dec_imm_ext;

    instruction_decoder u_decoder (
        .instruction(dec_instruction),
        .valid(dec_valid),
        .alu_op(dec_alu_op),
        .reg_write(dec_reg_write),
        .mem_read(dec_mem_read),
        .mem_write(dec_mem_write),
        .is_fma(dec_is_fma),
        .branch_type(dec_branch_type),
        .use_imm(dec_use_imm),
        .dtype(dec_dtype),
        .is_halt(dec_is_halt),
        .rd(dec_rd),
        .rs1_addr(dec_rs1),
        .rs2_addr(dec_rs2),
        .rs3_addr(dec_rs3),
        .imm_ext(dec_imm_ext)
    );

    // Register file
    reg rf_rst;
    reg rf_wr_en;
    reg [`REG_ADDR_W-1:0] rf_wr_addr;
    reg [`DATA_WIDTH-1:0] rf_wr_data;
    reg [`REG_ADDR_W-1:0] rf_rd_addr1;
    reg [`REG_ADDR_W-1:0] rf_rd_addr2;
    reg [`REG_ADDR_W-1:0] rf_rd_addr3;
    wire [`DATA_WIDTH-1:0] rf_rd_data1;
    wire [`DATA_WIDTH-1:0] rf_rd_data2;
    wire [`DATA_WIDTH-1:0] rf_rd_data3;

    register_file u_rf (
        .clk(clk),
        .rst(rf_rst),
        .thread_id(32'h0000002a),
        .block_id(32'h00000007),
        .block_dim(32'h00000004),
        .wr_en(rf_wr_en),
        .wr_addr(rf_wr_addr),
        .wr_data(rf_wr_data),
        .rd_addr1(rf_rd_addr1),
        .rd_data1(rf_rd_data1),
        .rd_addr2(rf_rd_addr2),
        .rd_data2(rf_rd_data2),
        .rd_addr3(rf_rd_addr3),
        .rd_data3(rf_rd_data3)
    );

    // Hazard unit
    reg [`REG_ADDR_W-1:0] hz_rs1;
    reg [`REG_ADDR_W-1:0] hz_rs2;
    reg [`REG_ADDR_W-1:0] hz_rs3;
    reg hz_is_fma;
    reg [`REG_ADDR_W-1:0] hz_ex1_rd;
    reg hz_ex1_wr;
    reg [`REG_ADDR_W-1:0] hz_ex2_rd;
    reg hz_ex2_wr;
    reg [`REG_ADDR_W-1:0] hz_ex3_rd;
    reg hz_ex3_wr;
    reg [`REG_ADDR_W-1:0] hz_wb_rd;
    reg hz_wb_wr;
    wire hz_stall;

    hazard_unit u_hazard (
        .de_rs1(hz_rs1),
        .de_rs2(hz_rs2),
        .de_rs3(hz_rs3),
        .de_is_fma(hz_is_fma),
        .ex1_rd(hz_ex1_rd),
        .ex1_reg_write(hz_ex1_wr),
        .ex2_rd(hz_ex2_rd),
        .ex2_reg_write(hz_ex2_wr),
        .ex3_rd(hz_ex3_rd),
        .ex3_reg_write(hz_ex3_wr),
        .wb_rd(hz_wb_rd),
        .wb_reg_write(hz_wb_wr),
        .stall(hz_stall)
    );

    // Writeback stage
    reg wb_reg_write_in;
    reg wb_mem_read;
    reg [`REG_ADDR_W-1:0] wb_rd_in;
    reg [`DATA_WIDTH-1:0] wb_alu_result;
    reg [`DATA_WIDTH-1:0] wb_mem_data;
    wire wb_reg_write_out;
    wire [`REG_ADDR_W-1:0] wb_rd_out;
    wire [`DATA_WIDTH-1:0] wb_data_out;

    writeback_stage u_wb (
        .reg_write_in(wb_reg_write_in),
        .mem_read(wb_mem_read),
        .rd_in(wb_rd_in),
        .alu_result(wb_alu_result),
        .mem_data(wb_mem_data),
        .reg_write_out(wb_reg_write_out),
        .rd_out(wb_rd_out),
        .data_out(wb_data_out)
    );

    // SIMD and BF16 arithmetic
    reg simd_rst;
    reg [3:0] simd_alu_op;
    reg [2:0] simd_dtype;
    reg [`DATA_WIDTH-1:0] simd_a;
    reg [`DATA_WIDTH-1:0] simd_b;
    wire [`DATA_WIDTH-1:0] simd_result;

    simd_alu u_simd (
        .clk(clk),
        .rst(simd_rst),
        .alu_op(simd_alu_op),
        .dtype(simd_dtype),
        .operand_a(simd_a),
        .operand_b(simd_b),
        .result(simd_result)
    );

    reg fma_rst;
    reg [15:0] fma_a;
    reg [15:0] fma_b;
    reg [15:0] fma_c;
    wire [15:0] fma_result;

    bf16_fma_unit u_fma (
        .clk(clk),
        .rst(fma_rst),
        .a(fma_a),
        .b(fma_b),
        .c(fma_c),
        .result(fma_result)
    );

    initial begin
        pass_count = 0;
        fail_count = 0;

        pc_rst = 1'b1;
        pc_stall = 1'b0;
        pc_branch_en = 1'b0;
        pc_branch_target = 10'd0;

        fetch_rst = 1'b1;
        fetch_stall = 1'b0;
        fetch_flush = 1'b0;
        fetch_pc_in = 10'd0;

        pipe_rst = 1'b1;
        pipe_stall = 1'b0;
        pipe_flush = 1'b0;
        pipe_alu_in = `ALU_ADD;
        pipe_reg_write_in = 1'b0;
        pipe_mem_read_in = 1'b0;
        pipe_mem_write_in = 1'b0;
        pipe_is_fma_in = 1'b0;
        pipe_use_imm_in = 1'b0;
        pipe_dtype_in = `DTYPE_S16;
        pipe_is_halt_in = 1'b0;
        pipe_branch_type_in = `BR_NONE;
        pipe_rd_in = 4'd0;
        pipe_rs1_in = 64'd0;
        pipe_rs2_in = 64'd0;
        pipe_rs3_in = 64'd0;
        pipe_imm_in = 64'd0;
        pipe_pc_in = 10'd0;

        dec_instruction = 32'd0;
        dec_valid = 1'b0;

        rf_rst = 1'b1;
        rf_wr_en = 1'b0;
        rf_wr_addr = 4'd0;
        rf_wr_data = 64'd0;
        rf_rd_addr1 = 4'd0;
        rf_rd_addr2 = 4'd0;
        rf_rd_addr3 = 4'd0;

        hz_rs1 = 4'd1;
        hz_rs2 = 4'd2;
        hz_rs3 = 4'd3;
        hz_is_fma = 1'b0;
        hz_ex1_rd = 4'd0;
        hz_ex1_wr = 1'b0;
        hz_ex2_rd = 4'd0;
        hz_ex2_wr = 1'b0;
        hz_ex3_rd = 4'd0;
        hz_ex3_wr = 1'b0;
        hz_wb_rd = 4'd0;
        hz_wb_wr = 1'b0;

        wb_reg_write_in = 1'b0;
        wb_mem_read = 1'b0;
        wb_rd_in = 4'd0;
        wb_alu_result = 64'd0;
        wb_mem_data = 64'd0;

        simd_rst = 1'b1;
        simd_alu_op = `ALU_ADD;
        simd_dtype = `DTYPE_S16;
        simd_a = 64'd0;
        simd_b = 64'd0;

        fma_rst = 1'b1;
        fma_a = 16'h0000;
        fma_b = 16'h0000;
        fma_c = 16'h0000;

        repeat (2) @(posedge clk);
        #1;
        check(pc_out === 10'd0, "program_counter reset clears PC");
        check(fetch_valid_out === 1'b0, "fetch reset clears valid");
        check(pipe_reg_write_out === 1'b0 && pipe_mem_write_out === 1'b0,
              "ID/EX reset clears write controls");

        pc_rst = 1'b0;
        @(posedge clk); #1;
        check(pc_out === 10'd1, "program_counter increments");
        pc_stall = 1'b1;
        @(posedge clk); #1;
        check(pc_out === 10'd1, "program_counter holds during stall");
        pc_branch_en = 1'b1;
        pc_branch_target = 10'd42;
        @(posedge clk); #1;
        check(pc_out === 10'd42, "program_counter branch overrides stall");
        pc_stall = 1'b0;
        pc_branch_en = 1'b0;

        fetch_rst = 1'b0;
        fetch_pc_in = 10'd12;
        @(posedge clk); #1;
        check(fetch_valid_out === 1'b1 && fetch_pc_out === 10'd12,
              "fetch captures PC and valid");
        fetch_stall = 1'b1;
        fetch_pc_in = 10'd13;
        @(posedge clk); #1;
        check(fetch_pc_out === 10'd12, "fetch holds PC during stall");
        fetch_stall = 1'b0;
        fetch_flush = 1'b1;
        @(posedge clk); #1;
        check(fetch_valid_out === 1'b0 && fetch_pc_out === 10'd0,
              "fetch flush clears metadata");
        fetch_flush = 1'b0;

        pipe_rst = 1'b0;
        pipe_alu_in = `ALU_BCAST;
        pipe_reg_write_in = 1'b1;
        pipe_mem_read_in = 1'b1;
        pipe_mem_write_in = 1'b1;
        pipe_is_fma_in = 1'b1;
        pipe_use_imm_in = 1'b1;
        pipe_dtype_in = `DTYPE_BF16;
        pipe_is_halt_in = 1'b1;
        pipe_branch_type_in = `BR_BGE;
        pipe_rd_in = 4'd9;
        pipe_rs1_in = 64'h1111222233334444;
        pipe_rs2_in = 64'h5555666677778888;
        pipe_rs3_in = 64'h9999aaaabbbbcccc;
        pipe_imm_in = 64'hffff000000000123;
        pipe_pc_in = 10'd77;
        @(posedge clk); #1;
        check(pipe_alu_out === `ALU_BCAST && pipe_rd_out === 4'd9 &&
              pipe_pc_out === 10'd77 && pipe_is_halt_out === 1'b1,
              "ID/EX captures payload");
        pipe_stall = 1'b1;
        pipe_rd_in = 4'd4;
        @(posedge clk); #1;
        check(pipe_rd_out === 4'd9, "ID/EX holds during stall");
        pipe_stall = 1'b0;
        pipe_flush = 1'b1;
        @(posedge clk); #1;
        check(pipe_reg_write_out === 1'b0 && pipe_rd_out === 4'd0 &&
              pipe_branch_type_out === `BR_NONE, "ID/EX flush clears controls");
        pipe_flush = 1'b0;

        dec_valid = 1'b0;
        dec_instruction = {`OP_ADD, 27'd0};
        #1;
        check(dec_reg_write === 1'b0 && dec_alu_op === 4'd0,
              "decoder valid=0 suppresses controls");

        dec_valid = 1'b1;
        dec_instruction = {`OP_ADDI, 4'd3, 4'd2, 19'h7ffff};
        #1;
        check(dec_reg_write && dec_use_imm && dec_rd === 4'd3 && dec_rs1 === 4'd2,
              "decoder ADDI control fields");
        check64(dec_imm_ext, 64'hffffffffffffffff, "decoder ADDI sign extension");

        dec_instruction = {`OP_LD, 4'd4, 4'd5, 4'd0, `DTYPE_BF16, 12'hfff};
        #1;
        check(dec_mem_read && dec_reg_write && dec_use_imm && dec_dtype === `DTYPE_BF16,
              "decoder LD controls");
        check64(dec_imm_ext, 64'hffffffffffffffff, "decoder LD offset sign extension");

        dec_instruction = {`OP_ST, 4'd6, 4'd7, 4'd0, `DTYPE_S16, 12'h001};
        #1;
        check(dec_mem_write && !dec_reg_write && dec_use_imm,
              "decoder ST controls");

        dec_instruction = {`OP_BCAST, 4'd8, 4'd9, 4'd0, `DTYPE_S16, 12'h002};
        #1;
        check(dec_reg_write && dec_use_imm && dec_alu_op === `ALU_BCAST,
              "decoder BCAST controls");
        check64(dec_imm_ext, 64'd2, "decoder BCAST lane immediate");

        dec_instruction = {`OP_MOVI, 4'd10, 4'd0, 19'h01234};
        #1;
        check(dec_reg_write && dec_use_imm, "decoder MOVI controls");
        check64(dec_imm_ext, 64'h1234123412341234, "decoder MOVI lane broadcast");

        rf_rst = 1'b1;
        @(posedge clk); #1;
        rf_rst = 1'b0;
        rf_rd_addr1 = 4'd0;
        rf_rd_addr2 = `REG_THREADID;
        rf_rd_addr3 = `REG_BLOCKDIM;
        #1;
        check64(rf_rd_data1, 64'd0, "register_file R0 hardwired zero");
        check64(rf_rd_data2, 64'h000000000000002a, "register_file THREADID special");
        check64(rf_rd_data3, 64'h0000000000000004, "register_file BLOCKDIM special");
        rf_wr_en = 1'b1;
        rf_wr_addr = 4'd1;
        rf_wr_data = 64'h0123456789abcdef;
        @(posedge clk); #1;
        rf_wr_en = 1'b0;
        rf_rd_addr1 = 4'd1;
        #1;
        check64(rf_rd_data1, 64'h0123456789abcdef, "register_file normal write/read");
        rf_wr_en = 1'b1;
        rf_wr_addr = `REG_THREADID;
        rf_wr_data = 64'hffffffffffffffff;
        @(posedge clk); #1;
        rf_wr_en = 1'b0;
        rf_rd_addr1 = `REG_THREADID;
        #1;
        check64(rf_rd_data1, 64'h000000000000002a, "register_file ignores special writes");

        hz_rs1 = 4'd1;
        hz_rs2 = 4'd2;
        hz_rs3 = 4'd3;
        hz_is_fma = 1'b0;
        hz_ex1_rd = 4'd1;
        hz_ex1_wr = 1'b1;
        #1;
        check(hz_stall === 1'b1, "hazard detects rs1 RAW");
        hz_ex1_rd = `REG_ZERO;
        hz_is_fma = 1'b1;
        hz_ex2_rd = 4'd3;
        hz_ex2_wr = 1'b1;
        #1;
        check(hz_stall === 1'b1, "hazard detects FMA rs3 RAW");
        hz_ex2_wr = 1'b0;
        #1;
        check(hz_stall === 1'b0, "hazard ignores zero/no-write cases");

        wb_reg_write_in = 1'b1;
        wb_rd_in = 4'd5;
        wb_alu_result = 64'h1111111122222222;
        wb_mem_data = 64'h3333333344444444;
        wb_mem_read = 1'b0;
        #1;
        check64(wb_data_out, 64'h1111111122222222, "writeback selects ALU result");
        wb_mem_read = 1'b1;
        #1;
        check64(wb_data_out, 64'h3333333344444444, "writeback selects memory data");

        simd_rst = 1'b1;
        @(posedge clk); #1;
        simd_rst = 1'b0;
        simd_alu_op = `ALU_BCAST;
        simd_dtype = `DTYPE_S16;
        simd_a = 64'hddddccccbbbbaaaa;
        simd_b = 64'd2;
        @(posedge clk); #1;
        check64(simd_result, 64'hcccccccccccccccc, "SIMD BCAST lane 2");

        simd_alu_op = `ALU_ADD;
        simd_dtype = `DTYPE_BF16;
        simd_a = 64'h3f803f803f803f80;
        simd_b = 64'h3f803f803f803f80;
        @(posedge clk); #1;
        check64(simd_result, 64'h4000400040004000, "SIMD BF16 add 1.0 + 1.0");

        fma_rst = 1'b1;
        @(posedge clk); #1;
        fma_rst = 1'b0;
        fma_a = 16'h3f80; // 1.0
        fma_b = 16'h4000; // 2.0
        fma_c = 16'h4040; // 3.0
        repeat (2) @(posedge clk);
        #1;
        check(fma_result === 16'h40a0, "BF16 FMA computes 1.0*2.0+3.0=5.0");

        $display("Results: %0d PASS, %0d FAIL", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end
endmodule
