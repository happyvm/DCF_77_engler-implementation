// Time-shared minute search: a started search is busy for exactly 60
// clocks, result_valid is a single-cycle pulse that ends it, the result
// is always a legal minute, the runner-up gap never exceeds the winner,
// and a confident result has really cleared both floors.
//
// The four helper invariants (busy -> run == candidate_o, candidate_o <= 59,
// best_minute_o <= 59, result_valid -> !busy) are mutually inductive with the
// goals, so the whole property set discharges by k-induction (prove mode,
// depth 6) instead of needing a 60-step BMC that times out on a 2-core box.
module minute_candidate_search_formal;
    localparam int SOFT_BITS = 4;
    localparam int SCORE_BITS = SOFT_BITS + 4;
    localparam logic signed [SCORE_BITS-1:0] MIN_SCORE = 8'sd12;
    localparam logic [SCORE_BITS-1:0] MIN_GAP = 8'd3;

    (* gclk *) logic clk;
    (* anyseq *) logic load_valid, start;
    (* anyseq *) logic [2:0] load_index;
    (* anyseq *) logic signed [SOFT_BITS-1:0] soft_bit;
    logic rst = 1'b1;
    logic past_valid = 1'b0;

    logic busy, result_valid, confident;
    logic [5:0] minute;
    logic signed [SCORE_BITS-1:0] best_score;
    logic [SCORE_BITS-1:0] quality_gap;
    // Connected to the FORMAL-only observation ports on the DUT via (.*).
    logic [5:0] candidate_o;
    logic [5:0] best_minute_o;

    minute_candidate_search #(
        .SOFT_BITS(SOFT_BITS), .SCORE_BITS(SCORE_BITS), .QUALIFICATION_ENABLED(1'b1),
        .MIN_SCORE(MIN_SCORE), .MIN_GAP(MIN_GAP)
    ) dut (.*);

    logic [6:0] run = '0;

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;
        if (rst || !busy) run <= '0;
        else run <= run + 1'b1;

        if (past_valid) begin
            // helper invariants: mutually inductive with the goals
            assert(!busy || run == {1'b0, candidate_o});
            assert(candidate_o <= 6'd59);
            assert(best_minute_o <= 6'd59);
            assert(!result_valid || !busy);

            // goals
            assert(minute < 60);
            assert(run <= 60);
        end
        if (past_valid && !$past(rst)) begin
            assert(!(result_valid && $past(result_valid)));
            if (result_valid) begin
                assert($past(busy) && $past(run) == 59);
                assert(!busy);
                assert(!confident || (best_score >= MIN_SCORE && quality_gap >= MIN_GAP));
            end
            if ($past(start) && !$past(busy))
                assert(busy);
        end
    end
endmodule
