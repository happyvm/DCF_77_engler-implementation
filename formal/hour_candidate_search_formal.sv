// Time-shared hour search: a started search is busy for exactly 24 clocks
// (hours 00..23), result_valid is a single-cycle pulse that ends it, the
// result is always a legal hour, the runner-up gap never exceeds the
// winner, and a confident result has really cleared both floors. Mirrors
// minute_candidate_search_formal.sv, the only structural difference being
// the 24-candidate run length and 7-bit evidence vector.
module hour_candidate_search_formal;
    localparam int SOFT_BITS = 4;
    localparam int SCORE_BITS = SOFT_BITS + 3;
    localparam logic signed [SCORE_BITS-1:0] MIN_SCORE = 7'sd10;
    localparam logic [SCORE_BITS-1:0] MIN_GAP = 7'd3;

    (* gclk *) logic clk;
    (* anyseq *) logic load_valid, start;
    (* anyseq *) logic [2:0] load_index;
    (* anyseq *) logic signed [SOFT_BITS-1:0] soft_bit;
    logic rst = 1'b1;
    logic past_valid = 1'b0;

    logic busy, result_valid, confident;
    logic [4:0] hour;
    logic signed [SCORE_BITS-1:0] best_score;
    logic [SCORE_BITS-1:0] quality_gap;

    hour_candidate_search #(
        .SOFT_BITS(SOFT_BITS), .SCORE_BITS(SCORE_BITS), .QUALIFICATION_ENABLED(1'b1),
        .MIN_SCORE(MIN_SCORE), .MIN_GAP(MIN_GAP)
    ) dut (.*);

    logic [4:0] run = '0;

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;
        if (rst || !busy) run <= '0;
        else run <= run + 1'b1;

        if (past_valid) begin
            assert(hour < 24);
            assert(run <= 24);
        end
        if (past_valid && !$past(rst)) begin
            assert(!(result_valid && $past(result_valid)));
            if (result_valid) begin
                assert($past(busy) && $past(run) == 23);
                assert(!busy);
                assert(!confident || (best_score >= MIN_SCORE && quality_gap >= MIN_GAP));
            end
            if ($past(start) && !$past(busy))
                assert(busy);
        end
    end
endmodule
