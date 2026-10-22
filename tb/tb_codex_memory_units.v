`timescale 1ns / 1ps
`include "gpu_params.vh"

module tb_codex_memory_units;
    reg clk;
    integer pass_count;
    integer fail_count;

    initial clk = 1'b0;
    always #5 clk = ~clk;

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

    task check72;
        input [71:0] actual;
        input [71:0] expected;
        input [1023:0] label;
        begin
            if (actual === expected) begin
                pass_count = pass_count + 1;
                $display("PASS: %0s = 0x%018h", label, actual);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: %0s got 0x%018h expected 0x%018h", label, actual, expected);
            end
        end
    endtask

    // FIFO 72-bit BRAM.
    reg [7:0] fifo_addr_a;
    reg [71:0] fifo_din_a;
    reg fifo_we_a;
    wire [71:0] fifo_dout_a;
    reg [7:0] fifo_addr_b;
    reg [71:0] fifo_din_b;
    reg fifo_we_b;
    wire [71:0] fifo_dout_b;

    fifo_bram u_fifo_bram (
        .clk(clk),
        .addr_a(fifo_addr_a),
        .din_a(fifo_din_a),
        .we_a(fifo_we_a),
        .dout_a(fifo_dout_a),
        .addr_b(fifo_addr_b),
        .din_b(fifo_din_b),
        .we_b(fifo_we_b),
        .dout_b(fifo_dout_b)
    );

    // GPU instruction memory.
    reg imem_rd_en;
    reg [`IMEM_ADDR_W-1:0] imem_addr;
    wire [`INSTR_WIDTH-1:0] imem_rd_data;
    reg [`IMEM_ADDR_W-1:0] imem_addr_b;
    reg imem_wr_en_b;
    reg [`INSTR_WIDTH-1:0] imem_wr_data_b;
    wire [`INSTR_WIDTH-1:0] imem_rd_data_b;

    instruction_memory u_gpu_imem (
        .clk(clk),
        .rd_en(imem_rd_en),
        .addr(imem_addr),
        .rd_data(imem_rd_data),
        .addr_b(imem_addr_b),
        .wr_en_b(imem_wr_en_b),
        .wr_data_b(imem_wr_data_b),
        .rd_data_b(imem_rd_data_b)
    );

    // GPU data memory.
    reg [`DMEM_ADDR_W-1:0] gdmem_addr;
    reg gdmem_wr_en;
    reg [`DATA_WIDTH-1:0] gdmem_wr_data;
    wire [`DATA_WIDTH-1:0] gdmem_rd_data;
    reg [`DMEM_ADDR_W-1:0] gdmem_addr_b;
    reg gdmem_wr_en_b;
    reg [`DATA_WIDTH-1:0] gdmem_wr_data_b;
    wire [`DATA_WIDTH-1:0] gdmem_rd_data_b;

    data_memory u_gpu_dmem (
        .clk(clk),
        .addr(gdmem_addr),
        .wr_en(gdmem_wr_en),
        .wr_data(gdmem_wr_data),
        .rd_data(gdmem_rd_data),
        .addr_b(gdmem_addr_b),
        .wr_en_b(gdmem_wr_en_b),
        .wr_data_b(gdmem_wr_data_b),
        .rd_data_b(gdmem_rd_data_b)
    );

    // ARM instruction memory.
    reg [8:0] arm_imem_addra;
    reg [31:0] arm_imem_dina;
    reg arm_imem_wea;
    wire [31:0] arm_imem_douta;
    reg [8:0] arm_imem_addrb;
    reg [31:0] arm_imem_dinb;
    reg arm_imem_web;
    wire [31:0] arm_imem_doutb;

    inst_mem u_arm_imem (
        .clk(clk),
        .addra(arm_imem_addra),
        .dina(arm_imem_dina),
        .wea(arm_imem_wea),
        .douta(arm_imem_douta),
        .addrb(arm_imem_addrb),
        .dinb(arm_imem_dinb),
        .web(arm_imem_web),
        .doutb(arm_imem_doutb)
    );

    // ARM logic analyzer memory.
    reg [10:0] la_addra;
    reg [63:0] la_dina;
    reg la_wea;
    reg [10:0] la_addrb;
    wire [63:0] la_doutb;

    logic_analyzer u_la (
        .clk(clk),
        .addra(la_addra),
        .dina(la_dina),
        .wea(la_wea),
        .addrb(la_addrb),
        .doutb(la_doutb)
    );

    initial begin
        pass_count = 0;
        fail_count = 0;

        fifo_addr_a = 8'd0;
        fifo_din_a = 72'd0;
        fifo_we_a = 1'b0;
        fifo_addr_b = 8'd0;
        fifo_din_b = 72'd0;
        fifo_we_b = 1'b0;

        imem_rd_en = 1'b0;
        imem_addr = 10'd0;
        imem_addr_b = 10'd0;
        imem_wr_en_b = 1'b0;
        imem_wr_data_b = 32'd0;

        gdmem_addr = 10'd0;
        gdmem_wr_en = 1'b0;
        gdmem_wr_data = 64'd0;
        gdmem_addr_b = 10'd0;
        gdmem_wr_en_b = 1'b0;
        gdmem_wr_data_b = 64'd0;

        arm_imem_addra = 9'd0;
        arm_imem_dina = 32'd0;
        arm_imem_wea = 1'b0;
        arm_imem_addrb = 9'd0;
        arm_imem_dinb = 32'd0;
        arm_imem_web = 1'b0;

        la_addra = 11'd0;
        la_dina = 64'd0;
        la_wea = 1'b0;
        la_addrb = 11'd0;

        // fifo_bram cross-port write/read.
        @(negedge clk);
        fifo_addr_a = 8'h12;
        fifo_din_a = 72'hff_0123456789abcdef;
        fifo_we_a = 1'b1;
        @(negedge clk);
        fifo_we_a = 1'b0;
        fifo_addr_b = 8'h12;
        @(posedge clk); #1;
        check72(fifo_dout_b, 72'hff_0123456789abcdef, "fifo_bram port B reads port A write");

        @(negedge clk);
        fifo_addr_b = 8'h34;
        fifo_din_b = 72'h00_fedcba9876543210;
        fifo_we_b = 1'b1;
        @(negedge clk);
        fifo_we_b = 1'b0;
        fifo_addr_a = 8'h34;
        @(posedge clk); #1;
        check72(fifo_dout_a, 72'h00_fedcba9876543210, "fifo_bram port A reads port B write");

        // GPU instruction memory host write, core read, and rd_en hold.
        @(negedge clk);
        imem_addr_b = 10'd17;
        imem_wr_data_b = 32'hdeadbeef;
        imem_wr_en_b = 1'b1;
        @(negedge clk);
        imem_wr_en_b = 1'b0;
        imem_addr = 10'd17;
        imem_rd_en = 1'b1;
        @(posedge clk); #1;
        check32(imem_rd_data, 32'hdeadbeef, "instruction_memory core reads host write");
        imem_rd_en = 1'b0;
        imem_addr = 10'd18;
        @(posedge clk); #1;
        check32(imem_rd_data, 32'hdeadbeef, "instruction_memory rd_en holds output");

        // GPU data memory both ports.
        @(negedge clk);
        gdmem_addr_b = 10'd21;
        gdmem_wr_data_b = 64'h1111222233334444;
        gdmem_wr_en_b = 1'b1;
        @(negedge clk);
        gdmem_wr_en_b = 1'b0;
        gdmem_addr = 10'd21;
        @(posedge clk); #1;
        check64(gdmem_rd_data, 64'h1111222233334444, "data_memory port A reads port B write");
        @(negedge clk);
        gdmem_addr = 10'd22;
        gdmem_wr_data = 64'h5555666677778888;
        gdmem_wr_en = 1'b1;
        @(negedge clk);
        gdmem_wr_en = 1'b0;
        gdmem_addr_b = 10'd22;
        @(posedge clk); #1;
        check64(gdmem_rd_data_b, 64'h5555666677778888, "data_memory port B reads port A write");

        // ARM instruction memory.
        @(negedge clk);
        arm_imem_addrb = 9'd31;
        arm_imem_dinb = 32'he3a00001;
        arm_imem_web = 1'b1;
        @(negedge clk);
        arm_imem_web = 1'b0;
        arm_imem_addra = 9'd31;
        @(posedge clk); #1;
        check32(arm_imem_douta, 32'he3a00001, "inst_mem fetch reads port B write");

        // Logic analyzer RAM.
        @(negedge clk);
        la_addra = 11'd100;
        la_dina = 64'h123456789abcdef0;
        la_wea = 1'b1;
        @(negedge clk);
        la_wea = 1'b0;
        la_addrb = 11'd100;
        @(posedge clk); #1;
        check64(la_doutb, 64'h123456789abcdef0, "logic_analyzer readback");

        $display("Results: %0d PASS, %0d FAIL", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end
endmodule
