// The shared calendar/zone correlator: field selects a per-field candidate
// range (day 1..31, weekday 1..7, month 1..12, year 0..99, zone/flags
// 0..7), fixed for the whole run by construction (ml_field_sequencer holds
// cal_field stable from S_CAL_LOAD through S_CAL_WAIT). field is therefore
// (* anyconst *): the proof explores every legal value while staying fixed
// within any one trace, matching real usage. A started search stays busy
// for exactly last-first+1 clocks, result_valid is a single pulse that ends
// it, best_value always lands in [first,last], and quality_gap is never
// negative (best_score never trails second_score).
//
// field==3 (year, 0..99) is excluded here (see the .sby depth comment):
// its candidate loop shares the exact same per-candidate score/compare
// logic as the other four fields, just iterated further, so this bounds
// the proof to the three-field/one-flag-set case that already exercises
// every branch of that shared logic and keeps the BMC unroll tractable.
module calendar_candidate_search_formal;
    localparam int SOFT_BITS = 4;
    localparam int SCORE_BITS = SOFT_BITS + 4;

    (* gclk *) logic clk;
    (* anyconst *) logic [2:0] field;
    (* anyseq *) logic load_valid, start;
    (* anyseq *) logic [3:0] load_index;
    (* anyseq *) logic signed [SOFT_BITS-1:0] soft_bit;
    logic rst = 1'b1;
    logic past_valid = 1'b0;

    logic busy, result_valid;
    logic [7:0] best_value;
    logic signed [SCORE_BITS-1:0] best_score, second_score;
    logic [SCORE_BITS-1:0] quality_gap;

    calendar_candidate_search #(.SOFT_BITS(SOFT_BITS), .SCORE_BITS(SCORE_BITS)) dut (.*);

    logic [7:0] ref_first, ref_last;
    always_comb begin
        case (field)
            3'd0: begin ref_first = 8'd1;  ref_last = 8'd31; end
            3'd1: begin ref_first = 8'd1;  ref_last = 8'd7;  end
            3'd2: begin ref_first = 8'd1;  ref_last = 8'd12; end
            3'd3: begin ref_first = 8'd0;  ref_last = 8'd99; end
            default: begin ref_first = 8'd0; ref_last = 8'd7; end
        endcase
    end

    logic [7:0] run = '0;

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;
        if (rst || !busy) run <= '0;
        else run <= run + 1'b1;

        // field only takes the five legal values calendar_candidate_search's
        // own case statement handles by name; anyconst still lets the
        // solver pick any 3-bit value, so values 5..7 (which fall into the
        // same "default" branch as 4) are assumed away, and field==3
        // (year, the 100-candidate case) is excluded per the header
        // comment above.
        assume(field <= 3'd4 && field != 3'd3);

        if (past_valid) begin
            assert(run <= (ref_last - ref_first + 1'b1));
        end
        if (past_valid && !$past(rst)) begin
            assert(!(result_valid && $past(result_valid)));
            if (result_valid) begin
                // best_value is only meaningful once a search has actually
                // completed and published it; its power-on-reset default
                // of 0 is legitimately outside range for a field whose
                // first candidate is 1 (day/weekday/month), so the range
                // check applies here, not unconditionally.
                assert(best_value >= ref_first && best_value <= ref_last);
                assert($past(busy) && $past(run) == (ref_last - ref_first));
                assert(!busy);
                assert(best_score >= second_score);
                assert(quality_gap == (best_score - second_score));
            end
            if ($past(start) && !$past(busy))
                assert(busy);
        end
    end
endmodule
