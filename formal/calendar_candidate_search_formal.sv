// The shared calendar/zone correlator (multi-cycle sequencer): field selects a
// per-field candidate range (day 1..31, weekday 1..7, month 1..12, year 0..99,
// zone/flags 0..7), fixed for the whole run by construction (ml_field_sequencer
// holds cal_field stable from S_CAL_LOAD through S_CAL_WAIT). field is therefore
// (* anyconst *): the proof explores every legal value while staying fixed
// within any one trace, matching real usage.
//
// A started search runs 2*(last-first+1)+1 clocks (S_SCORE + S_SELECT per
// candidate, then one S_EMIT phase); result_valid is a single pulse produced by
// S_EMIT, best_value always lands in [first,last], and quality_gap is never
// negative (best_score never trails second_score).
//
// Unlike the previous 40-step BMC, this proof is k-induction and therefore now
// also covers field==3 (year, 0..99, the longest run): the run/candidate phase
// relation below is mutually inductive with the goals, so no long unroll is
// needed.
module calendar_candidate_search_formal;
    localparam int SOFT_BITS = 4;
    localparam int SCORE_BITS = SOFT_BITS + 4;

    // Same sequencer encoding as the DUT.
    localparam logic [1:0] S_IDLE   = 2'd0;
    localparam logic [1:0] S_SCORE  = 2'd1;
    localparam logic [1:0] S_SELECT = 2'd2;
    localparam logic [1:0] S_EMIT   = 2'd3;

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
    // Connected to the FORMAL-only observation ports on the DUT via (.*).
    logic [7:0] candidate_o;
    logic [1:0] state_o;
    logic signed [SCORE_BITS-1:0] best_q_o, second_q_o;
    logic [7:0] best_value_q_o;

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

    logic [8:0] run = '0;

    // Phase offset of the current sequencer state within the 2-cycle-per-
    // candidate cadence.
    logic [1:0] phase_k;
    always_comb begin
        case (state_o)
            S_SELECT: phase_k = 2'd1;
            S_EMIT:   phase_k = 2'd2;
            default:  phase_k = 2'd0;
        endcase
    end

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;
        if (rst || !busy) run <= '0;
        else run <= run + 1'b1;

        // field only takes the five legal values calendar_candidate_search's
        // own case statement handles by name; anyconst still lets the solver
        // pick any 3-bit value, so values 5..7 (which fall into the same
        // "default" branch as 4) are assumed away.
        assume(field <= 3'd4);

        if (past_valid) begin
            assert(busy == (state_o != S_IDLE));
            // while a search is running the candidate cursor stays in range
            assert(!busy || (candidate_o >= ref_first && candidate_o <= ref_last));
            assert(!busy || run == 2*(candidate_o - ref_first) + phase_k);
            assert(run <= 2*(ref_last - ref_first) + 3);
            // top-2 register ordering and the captalized best value stay legal
            assert(best_q_o >= second_q_o);
            assert(!busy || (best_value_q_o >= ref_first && best_value_q_o <= ref_last));
            assert(!result_valid || !busy);
        end
        if (past_valid && !$past(rst)) begin
            assert(!(result_valid && $past(result_valid)));
            if (result_valid) begin
                assert($past(state_o) == S_EMIT);
                // best_value is only meaningful once a search has actually
                // completed and published it; its power-on-reset default
                // of 0 is legitimately outside range for a field whose
                // first candidate is 1 (day/weekday/month).
                assert(best_value >= ref_first && best_value <= ref_last);
                assert(!busy);
                assert(best_score >= second_score);
                assert(quality_gap == (best_score - second_score));
            end
            if ($past(start) && !$past(busy))
                assert(busy);
        end
    end
endmodule
