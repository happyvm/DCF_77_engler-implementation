`timescale 1ns/1ps
module qualification_disabled_tb;
    logic clk = 0, rst = 1;
    logic load_valid = 0, start = 0, pm_second_valid = 0;
    logic [2:0] load_index = 0;
    logic signed [7:0] soft_bit = 0, pm_second_soft = 0;
    logic minute_busy, minute_valid, minute_confident;
    logic hour_busy, hour_valid, hour_confident;
    logic sync_valid, sync_locked, sync_busy;
    logic minute_seen = 0, hour_seen = 0, sync_seen = 0;
    integer i;

    minute_candidate_search #(.SOFT_BITS(8), .SCORE_BITS(12)) minute_i (
        .clk, .rst, .load_valid, .load_index, .soft_bit, .start,
        .busy(minute_busy), .result_valid(minute_valid),
        .confident(minute_confident), .minute(), .best_score(), .quality_gap());
    hour_candidate_search #(.SOFT_BITS(8), .SCORE_BITS(11)) hour_i (
        .clk, .rst, .load_valid, .load_index, .soft_bit, .start,
        .busy(hour_busy), .result_valid(hour_valid),
        .confident(hour_confident), .hour(), .best_score(), .quality_gap());
    pm_minute_sync #(.INPUT_BITS(8)) sync_i (
        .clk, .rst, .pm_second_soft, .pm_second_valid, .busy(sync_busy),
        .result_valid(sync_valid), .locked(sync_locked), .best_window_end(),
        .pm_polarity_inverted(), .best_magnitude(), .quality_gap());
    pm_minute_sync_contract sync_contract (
        .clk, .rst, .pm_second_valid, .busy(sync_busy));
    always #5 clk = ~clk;
    always @(posedge clk) begin
        if (minute_valid) minute_seen <= 1;
        if (hour_valid) hour_seen <= 1;
        if (sync_valid) sync_seen <= 1;
    end

    initial begin
        repeat (2) @(posedge clk); @(negedge clk); rst = 0;
        // All evidence and all default thresholds are zero.  Qualification is
        // disabled by default, so none of the three blocks may claim a lock.
        start = 1; @(negedge clk); start = 0;
        wait (minute_seen && hour_seen); #1;
        if (minute_confident || hour_confident)
            $fatal(1, "zero-score ML result was accepted");
        for (i = 0; i < 76; i = i + 1) begin
            pm_second_valid = 1; @(negedge clk);
            pm_second_valid = 0; @(negedge clk);
            // Respect the pm_minute_sync multi-cycle (4 clk) contract.
            while (sync_busy) @(negedge clk);
        end
        wait (sync_seen); #1;
        if (sync_locked)
            $fatal(1, "zero-score minute synchronization was accepted");
        $display("qualification_disabled_tb: PASS");
        $finish;
    end
endmodule
