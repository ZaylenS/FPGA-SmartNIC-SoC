`timescale 1ns / 1ps
`include "lab8_reg_defines.vh"

module input_arbiter
  #(parameter DATA_WIDTH = 64,
    parameter CTRL_WIDTH = DATA_WIDTH/8,
    parameter UDP_REG_SRC_WIDTH = 2,
    parameter STAGE_NUMBER = 0)
   (
    output [DATA_WIDTH-1:0] out_data,
    output [CTRL_WIDTH-1:0] out_ctrl,
    output out_wr,
    input out_rdy,
    input [DATA_WIDTH-1:0] in_data_0,
    input [CTRL_WIDTH-1:0] in_ctrl_0,
    input in_wr_0,
    output in_rdy_0,
    input [DATA_WIDTH-1:0] in_data_1,
    input [CTRL_WIDTH-1:0] in_ctrl_1,
    input in_wr_1,
    output in_rdy_1,
    input [DATA_WIDTH-1:0] in_data_2,
    input [CTRL_WIDTH-1:0] in_ctrl_2,
    input in_wr_2,
    output in_rdy_2,
    input [DATA_WIDTH-1:0] in_data_3,
    input [CTRL_WIDTH-1:0] in_ctrl_3,
    input in_wr_3,
    output in_rdy_3,
    input [DATA_WIDTH-1:0] in_data_4,
    input [CTRL_WIDTH-1:0] in_ctrl_4,
    input in_wr_4,
    output in_rdy_4,
    input [DATA_WIDTH-1:0] in_data_5,
    input [CTRL_WIDTH-1:0] in_ctrl_5,
    input in_wr_5,
    output in_rdy_5,
    input [DATA_WIDTH-1:0] in_data_6,
    input [CTRL_WIDTH-1:0] in_ctrl_6,
    input in_wr_6,
    output in_rdy_6,
    input [DATA_WIDTH-1:0] in_data_7,
    input [CTRL_WIDTH-1:0] in_ctrl_7,
    input in_wr_7,
    output in_rdy_7,
    input reg_req_in,
    input reg_ack_in,
    input reg_rd_wr_L_in,
    input [`UDP_REG_ADDR_WIDTH-1:0] reg_addr_in,
    input [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_in,
    input [UDP_REG_SRC_WIDTH-1:0] reg_src_in,
    output reg_req_out,
    output reg_ack_out,
    output reg_rd_wr_L_out,
    output [`UDP_REG_ADDR_WIDTH-1:0] reg_addr_out,
    output [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_out,
    output [UDP_REG_SRC_WIDTH-1:0] reg_src_out,
    input reset,
    input clk
    );

    assign out_data = in_data_0;
    assign out_ctrl = in_ctrl_0;
    assign out_wr = in_wr_0;
    assign in_rdy_0 = out_rdy;
    assign in_rdy_1 = 1'b0;
    assign in_rdy_2 = 1'b0;
    assign in_rdy_3 = 1'b0;
    assign in_rdy_4 = 1'b0;
    assign in_rdy_5 = 1'b0;
    assign in_rdy_6 = 1'b0;
    assign in_rdy_7 = 1'b0;

    assign reg_req_out = reg_req_in;
    assign reg_ack_out = reg_ack_in;
    assign reg_rd_wr_L_out = reg_rd_wr_L_in;
    assign reg_addr_out = reg_addr_in;
    assign reg_data_out = reg_data_in;
    assign reg_src_out = reg_src_in;
endmodule

module output_port_lookup
  #(parameter DATA_WIDTH = 64,
    parameter CTRL_WIDTH = DATA_WIDTH/8,
    parameter UDP_REG_SRC_WIDTH = 2,
    parameter INPUT_ARBITER_STAGE_NUM = 0,
    parameter STAGE_NUM = 0,
    parameter NUM_OUTPUT_QUEUES = 8,
    parameter NUM_IQ_BITS = 3)
   (
    output [DATA_WIDTH-1:0] out_data,
    output [CTRL_WIDTH-1:0] out_ctrl,
    output out_wr,
    input out_rdy,
    input [DATA_WIDTH-1:0] in_data,
    input [CTRL_WIDTH-1:0] in_ctrl,
    input in_wr,
    output in_rdy,
    input reg_req_in,
    input reg_ack_in,
    input reg_rd_wr_L_in,
    input [`UDP_REG_ADDR_WIDTH-1:0] reg_addr_in,
    input [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_in,
    input [UDP_REG_SRC_WIDTH-1:0] reg_src_in,
    output reg_req_out,
    output reg_ack_out,
    output reg_rd_wr_L_out,
    output [`UDP_REG_ADDR_WIDTH-1:0] reg_addr_out,
    output [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_out,
    output [UDP_REG_SRC_WIDTH-1:0] reg_src_out,
    input clk,
    input reset
    );

    assign out_data = in_data;
    assign out_ctrl = in_ctrl;
    assign out_wr = in_wr;
    assign in_rdy = out_rdy;
    assign reg_req_out = reg_req_in;
    assign reg_ack_out = reg_ack_in;
    assign reg_rd_wr_L_out = reg_rd_wr_L_in;
    assign reg_addr_out = reg_addr_in;
    assign reg_data_out = reg_data_in;
    assign reg_src_out = reg_src_in;
endmodule

module output_queues
  #(parameter DATA_WIDTH = 64,
    parameter CTRL_WIDTH = DATA_WIDTH/8,
    parameter UDP_REG_SRC_WIDTH = 2,
    parameter OP_LUT_STAGE_NUM = 0,
    parameter NUM_OUTPUT_QUEUES = 8,
    parameter STAGE_NUM = 0,
    parameter SRAM_ADDR_WIDTH = 19)
   (
    output [DATA_WIDTH-1:0] out_data_0,
    output [CTRL_WIDTH-1:0] out_ctrl_0,
    output out_wr_0,
    input out_rdy_0,
    output [DATA_WIDTH-1:0] out_data_1,
    output [CTRL_WIDTH-1:0] out_ctrl_1,
    output out_wr_1,
    input out_rdy_1,
    output [DATA_WIDTH-1:0] out_data_2,
    output [CTRL_WIDTH-1:0] out_ctrl_2,
    output out_wr_2,
    input out_rdy_2,
    output [DATA_WIDTH-1:0] out_data_3,
    output [CTRL_WIDTH-1:0] out_ctrl_3,
    output out_wr_3,
    input out_rdy_3,
    output [DATA_WIDTH-1:0] out_data_4,
    output [CTRL_WIDTH-1:0] out_ctrl_4,
    output out_wr_4,
    input out_rdy_4,
    output [DATA_WIDTH-1:0] out_data_5,
    output [CTRL_WIDTH-1:0] out_ctrl_5,
    output out_wr_5,
    input out_rdy_5,
    output [DATA_WIDTH-1:0] out_data_6,
    output [CTRL_WIDTH-1:0] out_ctrl_6,
    output out_wr_6,
    input out_rdy_6,
    output [DATA_WIDTH-1:0] out_data_7,
    output [CTRL_WIDTH-1:0] out_ctrl_7,
    output out_wr_7,
    input out_rdy_7,
    input [DATA_WIDTH-1:0] in_data,
    input [CTRL_WIDTH-1:0] in_ctrl,
    output in_rdy,
    input in_wr,
    input reg_req_in,
    input reg_ack_in,
    input reg_rd_wr_L_in,
    input [`UDP_REG_ADDR_WIDTH-1:0] reg_addr_in,
    input [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_in,
    input [UDP_REG_SRC_WIDTH-1:0] reg_src_in,
    output reg_req_out,
    output reg_ack_out,
    output reg_rd_wr_L_out,
    output [`UDP_REG_ADDR_WIDTH-1:0] reg_addr_out,
    output [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_out,
    output [UDP_REG_SRC_WIDTH-1:0] reg_src_out,
    output [SRAM_ADDR_WIDTH-1:0] wr_0_addr,
    output wr_0_req,
    input wr_0_ack,
    output [DATA_WIDTH+CTRL_WIDTH-1:0] wr_0_data,
    input rd_0_ack,
    input [DATA_WIDTH+CTRL_WIDTH-1:0] rd_0_data,
    input rd_0_vld,
    output [SRAM_ADDR_WIDTH-1:0] rd_0_addr,
    output rd_0_req,
    input clk,
    input reset
    );

    assign out_data_0 = in_data;
    assign out_ctrl_0 = in_ctrl;
    assign out_wr_0 = in_wr;
    assign out_data_1 = {DATA_WIDTH{1'b0}};
    assign out_ctrl_1 = {CTRL_WIDTH{1'b0}};
    assign out_wr_1 = 1'b0;
    assign out_data_2 = {DATA_WIDTH{1'b0}};
    assign out_ctrl_2 = {CTRL_WIDTH{1'b0}};
    assign out_wr_2 = 1'b0;
    assign out_data_3 = {DATA_WIDTH{1'b0}};
    assign out_ctrl_3 = {CTRL_WIDTH{1'b0}};
    assign out_wr_3 = 1'b0;
    assign out_data_4 = {DATA_WIDTH{1'b0}};
    assign out_ctrl_4 = {CTRL_WIDTH{1'b0}};
    assign out_wr_4 = 1'b0;
    assign out_data_5 = {DATA_WIDTH{1'b0}};
    assign out_ctrl_5 = {CTRL_WIDTH{1'b0}};
    assign out_wr_5 = 1'b0;
    assign out_data_6 = {DATA_WIDTH{1'b0}};
    assign out_ctrl_6 = {CTRL_WIDTH{1'b0}};
    assign out_wr_6 = 1'b0;
    assign out_data_7 = {DATA_WIDTH{1'b0}};
    assign out_ctrl_7 = {CTRL_WIDTH{1'b0}};
    assign out_wr_7 = 1'b0;
    assign in_rdy = out_rdy_0;

    assign reg_req_out = reg_req_in;
    assign reg_ack_out = reg_ack_in;
    assign reg_rd_wr_L_out = reg_rd_wr_L_in;
    assign reg_addr_out = reg_addr_in;
    assign reg_data_out = reg_data_in;
    assign reg_src_out = reg_src_in;

    assign wr_0_addr = {SRAM_ADDR_WIDTH{1'b0}};
    assign wr_0_req = 1'b0;
    assign wr_0_data = {(DATA_WIDTH+CTRL_WIDTH){1'b0}};
    assign rd_0_addr = {SRAM_ADDR_WIDTH{1'b0}};
    assign rd_0_req = 1'b0;
endmodule

module udp_reg_master
  #(parameter UDP_REG_SRC_WIDTH = 2)
   (
    input core_reg_req,
    output core_reg_ack,
    input core_reg_rd_wr_L,
    input [`UDP_REG_ADDR_WIDTH-1:0] core_reg_addr,
    output [`CPCI_NF2_DATA_WIDTH-1:0] core_reg_rd_data,
    input [`CPCI_NF2_DATA_WIDTH-1:0] core_reg_wr_data,
    output reg_req_out,
    output reg_ack_out,
    output reg_rd_wr_L_out,
    output [`UDP_REG_ADDR_WIDTH-1:0] reg_addr_out,
    output [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_out,
    output [UDP_REG_SRC_WIDTH-1:0] reg_src_out,
    input reg_req_in,
    input reg_ack_in,
    input reg_rd_wr_L_in,
    input [`UDP_REG_ADDR_WIDTH-1:0] reg_addr_in,
    input [`CPCI_NF2_DATA_WIDTH-1:0] reg_data_in,
    input [UDP_REG_SRC_WIDTH-1:0] reg_src_in,
    input clk,
    input reset
    );

    assign reg_req_out = core_reg_req;
    assign reg_ack_out = 1'b0;
    assign reg_rd_wr_L_out = core_reg_rd_wr_L;
    assign reg_addr_out = core_reg_addr;
    assign reg_data_out = core_reg_wr_data;
    assign reg_src_out = {UDP_REG_SRC_WIDTH{1'b0}};
    assign core_reg_ack = reg_ack_in;
    assign core_reg_rd_data = reg_data_in;
endmodule

module tb_codex_user_data_path_smoke;
    reg clk;
    reg reset;
    integer pass_count;
    integer fail_count;

    reg [63:0] in_data_0;
    reg [7:0] in_ctrl_0;
    reg in_wr_0;
    wire in_rdy_0;
    wire in_rdy_1;
    wire in_rdy_2;
    wire in_rdy_3;
    wire in_rdy_4;
    wire in_rdy_5;
    wire in_rdy_6;
    wire in_rdy_7;

    wire [63:0] out_data_0;
    wire [7:0] out_ctrl_0;
    wire out_wr_0;
    wire [63:0] out_data_1;
    wire [7:0] out_ctrl_1;
    wire out_wr_1;
    wire [63:0] out_data_2;
    wire [7:0] out_ctrl_2;
    wire out_wr_2;
    wire [63:0] out_data_3;
    wire [7:0] out_ctrl_3;
    wire out_wr_3;
    wire [63:0] out_data_4;
    wire [7:0] out_ctrl_4;
    wire out_wr_4;
    wire [63:0] out_data_5;
    wire [7:0] out_ctrl_5;
    wire out_wr_5;
    wire [63:0] out_data_6;
    wire [7:0] out_ctrl_6;
    wire out_wr_6;
    wire [63:0] out_data_7;
    wire [7:0] out_ctrl_7;
    wire out_wr_7;

    wire [18:0] wr_0_addr;
    wire wr_0_req;
    reg wr_0_ack;
    wire [71:0] wr_0_data;
    reg rd_0_ack;
    reg [71:0] rd_0_data;
    reg rd_0_vld;
    wire [18:0] rd_0_addr;
    wire rd_0_req;

    reg reg_req;
    wire reg_ack;
    reg reg_rd_wr_L;
    reg [`UDP_REG_ADDR_WIDTH-1:0] reg_addr;
    wire [`CPCI_NF2_DATA_WIDTH-1:0] reg_rd_data;
    reg [`CPCI_NF2_DATA_WIDTH-1:0] reg_wr_data;

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

    user_data_path dut (
        .in_data_0(in_data_0),
        .in_ctrl_0(in_ctrl_0),
        .in_wr_0(in_wr_0),
        .in_rdy_0(in_rdy_0),
        .in_data_1(64'd0),
        .in_ctrl_1(8'd0),
        .in_wr_1(1'b0),
        .in_rdy_1(in_rdy_1),
        .in_data_2(64'd0),
        .in_ctrl_2(8'd0),
        .in_wr_2(1'b0),
        .in_rdy_2(in_rdy_2),
        .in_data_3(64'd0),
        .in_ctrl_3(8'd0),
        .in_wr_3(1'b0),
        .in_rdy_3(in_rdy_3),
        .in_data_4(64'd0),
        .in_ctrl_4(8'd0),
        .in_wr_4(1'b0),
        .in_rdy_4(in_rdy_4),
        .in_data_5(64'd0),
        .in_ctrl_5(8'd0),
        .in_wr_5(1'b0),
        .in_rdy_5(in_rdy_5),
        .in_data_6(64'd0),
        .in_ctrl_6(8'd0),
        .in_wr_6(1'b0),
        .in_rdy_6(in_rdy_6),
        .in_data_7(64'd0),
        .in_ctrl_7(8'd0),
        .in_wr_7(1'b0),
        .in_rdy_7(in_rdy_7),
        .out_data_0(out_data_0),
        .out_ctrl_0(out_ctrl_0),
        .out_wr_0(out_wr_0),
        .out_rdy_0(1'b1),
        .out_data_1(out_data_1),
        .out_ctrl_1(out_ctrl_1),
        .out_wr_1(out_wr_1),
        .out_rdy_1(1'b1),
        .out_data_2(out_data_2),
        .out_ctrl_2(out_ctrl_2),
        .out_wr_2(out_wr_2),
        .out_rdy_2(1'b1),
        .out_data_3(out_data_3),
        .out_ctrl_3(out_ctrl_3),
        .out_wr_3(out_wr_3),
        .out_rdy_3(1'b1),
        .out_data_4(out_data_4),
        .out_ctrl_4(out_ctrl_4),
        .out_wr_4(out_wr_4),
        .out_rdy_4(1'b1),
        .out_data_5(out_data_5),
        .out_ctrl_5(out_ctrl_5),
        .out_wr_5(out_wr_5),
        .out_rdy_5(1'b1),
        .out_data_6(out_data_6),
        .out_ctrl_6(out_ctrl_6),
        .out_wr_6(out_wr_6),
        .out_rdy_6(1'b1),
        .out_data_7(out_data_7),
        .out_ctrl_7(out_ctrl_7),
        .out_wr_7(out_wr_7),
        .out_rdy_7(1'b1),
        .wr_0_addr(wr_0_addr),
        .wr_0_req(wr_0_req),
        .wr_0_ack(wr_0_ack),
        .wr_0_data(wr_0_data),
        .rd_0_ack(rd_0_ack),
        .rd_0_data(rd_0_data),
        .rd_0_vld(rd_0_vld),
        .rd_0_addr(rd_0_addr),
        .rd_0_req(rd_0_req),
        .reg_req(reg_req),
        .reg_ack(reg_ack),
        .reg_rd_wr_L(reg_rd_wr_L),
        .reg_addr(reg_addr),
        .reg_rd_data(reg_rd_data),
        .reg_wr_data(reg_wr_data),
        .reset(reset),
        .clk(clk)
    );

    initial begin
        pass_count = 0;
        fail_count = 0;
        reset = 1'b1;
        in_data_0 = 64'd0;
        in_ctrl_0 = 8'd0;
        in_wr_0 = 1'b0;
        wr_0_ack = 1'b0;
        rd_0_ack = 1'b0;
        rd_0_data = 72'd0;
        rd_0_vld = 1'b0;
        reg_req = 1'b0;
        reg_rd_wr_L = 1'b1;
        reg_addr = {`UDP_REG_ADDR_WIDTH{1'b0}};
        reg_wr_data = 32'd0;

        repeat (4) @(posedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);
        #1;

        check(in_rdy_0 === 1'b1, "stubbed user_data_path exposes ingress ready");
        check(out_wr_0 === 1'b0, "stubbed user_data_path idle output write is low");
        check(wr_0_req === 1'b0 && rd_0_req === 1'b0,
              "stubbed output queues leave SRAM idle");

        $display("Results: %0d PASS, %0d FAIL", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end
endmodule
