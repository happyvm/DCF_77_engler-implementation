`timescale 1ns/1ps
module second_evidence_aggregator_tb;
    logic clk = 0, rst = 1;
    logic second_ce;
    logic [5:0] second_position;
    logic am_valid;
    logic signed [15:0] am_evidence_in;
    logic pm_valid;
    logic signed [15:0] pm_evidence_in;
    logic [7:0] quality_in;
    logic write_valid;
    logic signed [15:0] am_evidence, pm_evidence;
    logic sample_valid;
    logic [7:0] quality;
    logic [5:0] second_position_out;

    second_evidence_aggregator dut (.*);
    always #5 clk = ~clk;

    task automatic clear_pulses;
        begin
            second_ce <= 0; am_valid <= 0; pm_valid <= 0;
        end
    endtask

    // Drives one full second: optionally pulses am_valid/pm_valid partway
    // through (in either order), then pulses second_ce to flush it, and
    // reports the emitted record.
    //
    // All pulses use nonblocking assignment: clearing a pulse signal with
    // a blocking assignment right after @(posedge clk) races the DUT's
    // own always_ff for that same edge (whether the DUT reads the pulse
    // as still asserted or already cleared becomes scheduling-order
    // dependent), which silently dropped every am_valid/pm_valid pulse in
    // an earlier version of this testbench.
    task automatic run_second(
        input logic do_am, input logic signed [15:0] am_val,
        input logic do_pm, input logic signed [15:0] pm_val,
        input logic am_first,
        input logic [5:0] pos, input logic [7:0] q
    );
        begin
            clear_pulses();
            second_position <= pos;
            quality_in <= q;
            if (am_first && do_am) begin
                am_evidence_in <= am_val; am_valid <= 1; @(posedge clk); am_valid <= 0;
            end
            if (do_pm) begin
                pm_evidence_in <= pm_val; pm_valid <= 1; @(posedge clk); pm_valid <= 0;
            end
            if (!am_first && do_am) begin
                am_evidence_in <= am_val; am_valid <= 1; @(posedge clk); am_valid <= 0;
            end
            @(posedge clk);
            second_ce <= 1; @(posedge clk); second_ce <= 0;
            #1;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk); rst <= 0; @(posedge clk);

        // AM arrives before PM within the second.
        run_second(1, 16'sd100, 1, -16'sd50, 1, 6'd21, 8'd200);
        if (!write_valid || !sample_valid || am_evidence !== 16'sd100 ||
            pm_evidence !== -16'sd50 || quality !== 8'd200 || second_position_out !== 6'd21)
            $fatal(1, "AM-then-PM record mismatch");

        // PM arrives before AM within the second.
        run_second(1, 16'sd7, 1, 16'sd9, 0, 6'd22, 8'd201);
        if (!write_valid || !sample_valid || am_evidence !== 16'sd7 || pm_evidence !== 16'sd9)
            $fatal(1, "PM-then-AM record mismatch");

        // AM dropout: PM arrives, AM does not. Record is still emitted
        // (no hole in history) but flagged unusable.
        run_second(0, 16'sd0, 1, 16'sd42, 0, 6'd23, 8'd50);
        if (!write_valid || sample_valid || pm_evidence !== 16'sd42 || am_evidence !== 16'sd0)
            $fatal(1, "AM-dropout record mismatch");

        // PM dropout: AM arrives, PM does not.
        run_second(1, -16'sd8, 0, 16'sd0, 1, 6'd24, 8'd51);
        if (!write_valid || sample_valid || am_evidence !== -16'sd8 || pm_evidence !== 16'sd0)
            $fatal(1, "PM-dropout record mismatch");

        // Total dropout: neither channel reports. Position/quality still
        // recorded so the minute's bit positions stay contiguous.
        run_second(0, 16'sd0, 0, 16'sd0, 1, 6'd25, 8'd0);
        if (!write_valid || sample_valid || second_position_out !== 6'd25)
            $fatal(1, "total-dropout record mismatch");

        // A stale latch from a prior second must not leak into the next
        // one: this second reports only AM, and must not echo the
        // previous second's PM value.
        run_second(1, 16'sd11, 0, 16'sd0, 1, 6'd26, 8'd10);
        if (pm_evidence !== 16'sd0)
            $fatal(1, "stale PM evidence leaked across seconds: %0d", pm_evidence);

        // write_valid must be exactly one clk cycle wide.
        @(posedge clk);
        #1;
        if (write_valid)
            $fatal(1, "write_valid was wider than one clock");

        $display("second_evidence_aggregator_tb: PASS");
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "timeout");
    end
endmodule
