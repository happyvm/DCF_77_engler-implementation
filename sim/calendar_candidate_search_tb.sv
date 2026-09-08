`timescale 1ns/1ps
// Exercises all four BCD-like fields the shared calendar_candidate_search
// engine is time-multiplexed across (day, weekday, month, year); the
// zone/announcement field (4) is handled directly by ml_field_sequencer
// via a hard sign threshold instead, so it is not exercised here.
module calendar_candidate_search_tb;
    logic clk = 0, rst = 1;
    logic load_valid;
    logic [3:0] load_index;
    logic signed [15:0] soft_bit;
    logic [2:0] field;
    logic start;
    logic busy, result_valid;
    logic [7:0] best_value;
    logic signed [19:0] best_score, second_score;
    logic [19:0] quality_gap;

    calendar_candidate_search #(.SOFT_BITS(16)) dut (.*);
    always #5 clk = ~clk;

    task automatic load(input logic [3:0] idx, input logic signed [15:0] val);
        begin
            load_index <= idx; soft_bit <= val; load_valid <= 1;
            @(posedge clk);
            load_valid <= 0;
        end
    endtask

    task automatic run_field(
        input logic [2:0] fld,
        // evidence[0..8], sign convention: positive means "this BCD/direct
        // bit is 1". Indices with no real transmitted bit for this field
        // must be passed as 0 so they cannot bias the score.
        input logic signed [15:0] ev0, input logic signed [15:0] ev1,
        input logic signed [15:0] ev2, input logic signed [15:0] ev3,
        input logic signed [15:0] ev4, input logic signed [15:0] ev5,
        input logic signed [15:0] ev6, input logic signed [15:0] ev7,
        input logic signed [15:0] ev8
    );
        begin
            field <= fld;
            load(0, ev0); load(1, ev1); load(2, ev2); load(3, ev3);
            load(4, ev4); load(5, ev5); load(6, ev6); load(7, ev7);
            load(8, ev8);
            start <= 1; @(posedge clk); start <= 0;
            wait (result_valid);
            #1;
        end
    endtask

    initial begin
        load_valid = 0; start = 0; field = 0;
        repeat (2) @(posedge clk); rst <= 0; @(posedge clk);

        // Day 15 = units 5 (0101), tens 1 (01). Strong evidence, correct
        // sign per bit; indices 6,7,8 have no real day bit and are 0.
        run_field(3'd0, 16'sd100, -16'sd100, 16'sd100, -16'sd100,
                          16'sd100, -16'sd100, 16'sd0, 16'sd0, 16'sd0);
        if (best_value !== 8'd15)
            $fatal(1, "day field mismatch: got %0d, expected 15", best_value);

        // Weekday 3 (Wednesday), 3-bit direct binary (011). Indices 3..8
        // have no real weekday bit and are 0.
        run_field(3'd1, 16'sd100, 16'sd100, -16'sd100, 16'sd0, 16'sd0,
                          16'sd0, 16'sd0, 16'sd0, 16'sd0);
        if (best_value !== 8'd3)
            $fatal(1, "weekday field mismatch: got %0d, expected 3", best_value);

        // Month 11 = units 1 (0001), tens 1 (single bit, index 4).
        // Indices 5,6,7,8 have no real month bit and are 0.
        run_field(3'd2, 16'sd100, -16'sd100, -16'sd100, -16'sd100,
                          16'sd100, 16'sd0, 16'sd0, 16'sd0, 16'sd0);
        if (best_value !== 8'd11)
            $fatal(1, "month field mismatch: got %0d, expected 11", best_value);

        // Year 24 = units 4 (0100), tens 2 (0010). Index 8 has no real
        // year bit here and is 0.
        run_field(3'd3, -16'sd100, -16'sd100, 16'sd100, -16'sd100,
                          -16'sd100, 16'sd100, -16'sd100, -16'sd100, 16'sd0);
        if (best_value !== 8'd24)
            $fatal(1, "year field mismatch: got %0d, expected 24", best_value);

        // A field switch must not let a previous field's stale evidence
        // (e.g. day's now-unused indices 6,7,8) bias the next search: the
        // day-15 evidence loaded index 2 to +100 (day units bit 2), which
        // would corrupt weekday's own index 2 if left unrefreshed. Confirm
        // the just-completed weekday-3 result was not disturbed by day's
        // leftovers -- already implied by weekday matching above, but
        // re-run once more with an independent value for extra assurance.
        run_field(3'd1, -16'sd100, 16'sd100, 16'sd100, 16'sd0, 16'sd0,
                          16'sd0, 16'sd0, 16'sd0, 16'sd0);
        if (best_value !== 8'd6)
            $fatal(1, "weekday re-run mismatch: got %0d, expected 6", best_value);

        $display("calendar_candidate_search_tb: PASS");
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "timeout");
    end
endmodule
