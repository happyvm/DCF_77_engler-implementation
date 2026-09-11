// PM minute-marker search: the reported window end is a legal search
// position, the runner-up gap never exceeds the winner, result_valid is a
// single-cycle pulse, and a lock is never declared below the absolute
// floor. Bounded: the first result needs 14 + 60 samples.
//
// BEA-36: the block is now a four-stage multi-cycle sequencer (busy for 4
// clk_sys per accepted sample). The proofs below additionally discharge the
// sequencer contract: the state machine only advances along its legal edges,
// busy never runs longer than four consecutive cycles (the documented
// latency), a result can only follow an accepted sample by that latency, and
// `locked` only ever changes on a result pulse.
//
// Helper invariants are mutually inductive with the goals, so the property
// set discharges by k-induction (prove mode) instead of a 74-step BMC
// (see pm_minute_sync.sby).
module pm_minute_sync_formal;
    localparam int INPUT_BITS = 4;
    localparam int SCORE_BITS = INPUT_BITS + 5;
    localparam logic [SCORE_BITS-1:0] MIN_SCORE = 9'd20;

    // Sequencer state encodings (match the DUT enum order).
    localparam logic [2:0] S_IDLE = 3'd0, S_SCORE = 3'd1, S_SELECT = 3'd2,
                           S_MARK = 3'd3, S_COMMIT = 3'd4;

    (* gclk *) logic clk;
    (* anyseq *) logic pm_second_valid;
    (* anyseq *) logic signed [INPUT_BITS-1:0] pm_second_soft;
    logic rst = 1'b1;
    logic past_valid = 1'b0;

    logic busy, result_valid, locked, pm_polarity_inverted;
    logic [5:0] best_window_end;
    logic [SCORE_BITS-1:0] best_magnitude, quality_gap;
    // Connected to the FORMAL-only observation ports on the DUT via (.*).
    logic [5:0] search_index_o;
    logic [5:0] best_index_o;
    logic [SCORE_BITS-1:0] best_score_o;
    logic [SCORE_BITS-1:0] second_score_o;
    logic [2:0] state_o;

    pm_minute_sync #(
        .INPUT_BITS(INPUT_BITS), .QUALIFICATION_ENABLED(1'b1),
        .MIN_SCORE(MIN_SCORE), .MIN_GAP(9'd2)
    ) dut (.*);

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;

        if (past_valid) begin
            assert(search_index_o <= 6'd59);
            assert(best_index_o <= 6'd59);
            // runner-up never exceeds the winner (makes quality_gap inductive)
            assert(second_score_o <= best_score_o);
            assert(best_window_end < 60);
            assert(quality_gap <= best_magnitude);
            // Latency contract: busy never runs longer than the documented
            // four clk_sys (five consecutive busy cycles fail).
            if ($past(busy) && $past(busy, 2) && $past(busy, 3) && $past(busy, 4))
                assert(!busy);
        end
        if (past_valid && !$past(rst)) begin
            // Sequencer advances only along its legal edges; this makes the
            // latency properties below inductive.
            case ($past(state_o))
                S_IDLE:   assert(state_o == S_IDLE || state_o == S_SCORE);
                S_SCORE:  assert(state_o == S_SELECT);
                S_SELECT: assert(state_o == S_MARK);
                S_MARK:   assert(state_o == S_COMMIT);
                default:  assert(state_o == S_IDLE);
            endcase
            assert(!(result_valid && $past(result_valid)));
            if (result_valid) begin
                // A result comes from the terminal commit exactly four
                // cycles (S_SCORE..S_COMMIT) after an accepted sample.
                assert($past(state_o) == S_COMMIT);
                assert($past(pm_second_valid, 5));
            end
            if (locked && result_valid)
                assert(best_magnitude >= MIN_SCORE);
            // `locked` is only assigned in the terminal commit, which also
            // raises result_valid in the same cycle.
            if (locked != $past(locked))
                assert(result_valid);
        end
    end
endmodule