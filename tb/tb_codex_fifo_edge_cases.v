`timescale 1ns / 1ps

module tb_codex_fifo_edge_cases;
    reg clk;
    reg reset;

    reg [63:0] in_data;
    reg [7:0] in_ctrl;
    reg in_wr;
    wire in_rdy;

    wire [63:0] out_data;
    wire [7:0] out_ctrl;
    wire out_wr;
    reg out_rdy;

    reg [7:0] proc_addr;
    reg [71:0] proc_din;
    reg proc_we;
    wire [71:0] proc_dout;

    reg [1:0] mode;
    reg drain_start;
    wire pkt_ready;
    wire fifo_full;
    wire fifo_empty;
    wire [7:0] pkt_word_cnt;
    wire [7:0] head_rd;
    wire [7:0] tail_rd;

    integer pass_count;
    integer fail_count;
    integer captured_count;
    integer guard_count;
    reg [71:0] captured [0:15];

    initial clk = 1'b0;
    always #5 clk = ~clk;

    convertible_fifo u_fifo (
        .clk(clk),
        .reset(reset),
        .in_data(in_data),
        .in_ctrl(in_ctrl),
        .in_wr(in_wr),
        .in_rdy(in_rdy),
        .out_data(out_data),
        .out_ctrl(out_ctrl),
        .out_wr(out_wr),
        .out_rdy(out_rdy),
        .proc_addr(proc_addr),
        .proc_din(proc_din),
        .proc_we(proc_we),
        .proc_dout(proc_dout),
        .mode(mode),
        .drain_start(drain_start),
        .pkt_ready(pkt_ready),
        .fifo_full(fifo_full),
        .fifo_empty(fifo_empty),
        .pkt_word_cnt(pkt_word_cnt),
        .head_wr_val(8'd0),
        .head_wr_en(1'b0),
        .tail_wr_val(8'd0),
        .tail_wr_en(1'b0),
        .head_rd(head_rd),
        .tail_rd(tail_rd)
    );

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

    task send_word;
        input [7:0] ctrl;
        input [63:0] data;
        begin
            @(negedge clk);
            in_ctrl = ctrl;
            in_data = data;
            in_wr = 1'b1;
            @(negedge clk);
            in_wr = 1'b0;
            in_ctrl = 8'd0;
            in_data = 64'd0;
        end
    endtask

    task pulse_reset;
        begin
            @(negedge clk);
            reset = 1'b1;
            drain_start = 1'b0;
            in_wr = 1'b0;
            out_rdy = 1'b0;
            mode = 2'd0;
            proc_addr = 8'd0;
            proc_din = 72'd0;
            proc_we = 1'b0;
            repeat (2) @(negedge clk);
            reset = 1'b0;
            @(negedge clk);
        end
    endtask

    task drain_packet;
        integer guard;
        begin
            captured_count = 0;
            drain_start = 1'b1;
            @(negedge clk);
            drain_start = 1'b0;
            guard = 0;
            while (guard < 40 && captured_count < 16) begin
                @(posedge clk);
                if (out_wr && out_rdy) begin
                    captured[captured_count] = {out_ctrl, out_data};
                    captured_count = captured_count + 1;
                end
                #1;
                guard = guard + 1;
                if (fifo_empty)
                    guard = 40;
            end
            @(negedge clk);
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        reset = 1'b1;
        in_data = 64'd0;
        in_ctrl = 8'd0;
        in_wr = 1'b0;
        out_rdy = 1'b0;
        proc_addr = 8'd0;
        proc_din = 72'd0;
        proc_we = 1'b0;
        mode = 2'd0;
        drain_start = 1'b0;

        pulse_reset();

        $display("=== Backpressure drain check ===");
        send_word(8'hff, {16'h0001, 16'h0003, 16'h0002, 16'h0018});
        send_word(8'h00, 64'h1111222233334444);
        send_word(8'h00, 64'h5555666677778888);
        repeat (2) @(posedge clk);
        #1;
        check(pkt_ready === 1'b1 && pkt_word_cnt === 8'd3, "3-word packet buffered");

        @(negedge clk);
        drain_start = 1'b1;
        @(posedge clk);
        #1;
        @(negedge clk);
        drain_start = 1'b0;
        out_rdy = 1'b0;
        repeat (6) @(posedge clk);
        #1;
        check(pkt_ready === 1'b1 && fifo_full === 1'b1,
              "FIFO holds packet while out_rdy is low");

        @(negedge clk);
        out_rdy = 1'b1;
        captured_count = 0;
        guard_count = 0;
        while (guard_count < 40 && captured_count < 3) begin
            if (out_wr && out_rdy) begin
                captured[captured_count] = {out_ctrl, out_data};
                captured_count = captured_count + 1;
            end
            @(posedge clk);
            #1;
            @(negedge clk);
            guard_count = guard_count + 1;
        end
        $display("Captured after backpressure release: count=%0d first=0x%018h last=0x%018h",
                 captured_count, captured[0], captured[2]);
        out_rdy = 1'b0;
        repeat (2) @(posedge clk);
        #1;
        check(captured_count === 3, "drain completes after backpressure release");
        check(captured[0] === {8'hff, 16'h0001, 16'h0003, 16'h0002, 16'h0018},
              "drain preserves header after backpressure");
        check(captured[2] === {8'h00, 64'h5555666677778888},
              "drain preserves final data word after backpressure");

        pulse_reset();

        $display("=== 16-bit word_length edge check ===");
        send_word(8'hff, {16'h0001, 16'h0100, 16'h0002, 16'h0800});
        repeat (2) @(posedge clk);
        #1;
        check(pkt_ready === 1'b0,
              "256-word packet must not complete after header only");
        check(pkt_word_cnt !== 8'd0,
              "256-word packet length must not truncate to zero");

        $display("Results: %0d PASS, %0d FAIL", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end
endmodule
