// PM minute-marker search: the reported window end is a legal search
// position, the runner-up gap never exceeds the winner, result_valid is a
// single-cycle pulse, and a lock is never declared below the absolute
// floor. Bounded: the first result needs 14 + 60 samples.
module pm_minute_sync_formal;
    localparam int INPUT_BITS = 4;
    localparam logic [INPUT_BITS+4:0] MIN_SCORE = 9'd20;

    (* gclk *) logic clk;
    (* anyseq *) logic pm_second_valid;
    (* anyseq *) logic signed [INPUT_BITS-1:0] pm_second_soft;
    logic rst = 1'b1;
    logic past_valid = 1'b0;

    logic result_valid, locked, pm_polarity_inverted;
    logic [5:0] best_window_end;
    logic [INPUT_BITS+4:0] best_magnitude, quality_gap;

    pm_minute_sync #(
        .INPUT_BITS(INPUT_BITS), .QUALIFICATION_ENABLED(1'b1),
        .MIN_SCORE(MIN_SCORE), .MIN_GAP(9'd2)
    ) dut (.*);

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;

        if (past_valid) begin
            assert(best_window_end < 60);
            assert(quality_gap <= best_magnitude);
        end
        if (past_valid && !$past(rst)) begin
            assert(!(result_valid && $past(result_valid)));
            if (result_valid)
                assert($past(pm_second_valid));
            if (locked && result_valid)
                assert(best_magnitude >= MIN_SCORE);
            if (!$past(pm_second_valid))
                assert(!result_valid && locked == $past(locked));
        end
    end
endmodule
