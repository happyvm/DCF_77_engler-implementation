`timescale 1ns/1ps
module pm_minute_sync_tb;
    logic clk = 0, rst = 1;
    logic signed [15:0] pm_second_soft = 0;
    logic pm_second_valid = 0;
    logic busy, result_valid, locked, pm_polarity_inverted;
    logic [5:0] best_window_end;
    logic [20:0] best_magnitude, quality_gap;
    integer sample_index;
    integer result_count = 0;
    // BEA-36: the sequencer is documented as a 4-cycle latency; verified here.
    integer busy_run = 0;
    integer busy_run_bad = 0;

    pm_minute_sync #(
        .INPUT_BITS(16), .QUALIFICATION_ENABLED(1'b1),
        .MIN_SCORE(21'd1000), .MIN_GAP(21'd100)
    ) dut (.*);

    // Contract: never strobe pm_second_valid while busy.
    pm_minute_sync_contract contract_i (
        .clk(clk), .rst(rst), .pm_second_valid(pm_second_valid), .busy(busy));

    always #5 clk = ~clk;
    always @(posedge clk)
        if (result_valid) result_count = result_count + 1;

    // Latency check: every accepted sample holds `busy` for exactly 4 cycles.
    always @(posedge clk) begin
        if (busy) begin
            busy_run = busy_run + 1;
        end else begin
            if (busy_run != 0 && busy_run != 4)
                busy_run_bad = busy_run_bad + 1;
            busy_run = 0;
        end
    end

    initial begin
        repeat (2) @(posedge clk); rst <= 0;
        // One exact 111111111100000 minute marker ends at stream sample 20.
        // Search index zero corresponds to stream sample 14, hence winner 6.
        for (sample_index = 0; sample_index < 74; sample_index = sample_index + 1) begin
            if (sample_index >= 6 && sample_index < 16)
                pm_second_soft <= -16'sd100;
            else if (sample_index >= 16 && sample_index <= 20)
                pm_second_soft <= 16'sd100;
            else
                pm_second_soft <= 16'sd0;
            pm_second_valid <= 1; @(posedge clk);
            pm_second_valid <= 0; @(posedge clk);
            // Respect the multi-cycle contract before the next strobe.
            while (busy) @(posedge clk);
        end
        #1;
        if (!locked || result_count != 1)
            $fatal(1, "minute synchronizer did not lock");
        if (best_window_end != 6 || pm_polarity_inverted)
            $fatal(1, "wrong minute candidate: %0d polarity=%0b",
                   best_window_end, pm_polarity_inverted);
        if (best_magnitude != 21'd1500 || quality_gap < 21'd100)
            $fatal(1, "unexpected peak metrics: best=%0d gap=%0d",
                   best_magnitude, quality_gap);
        if (busy_run_bad != 0)
            $fatal(1, "busy asserted for a run != 4 cycles %0d times", busy_run_bad);
        $display("pm_minute_sync_tb: PASS");
        $finish;
    end
endmodule