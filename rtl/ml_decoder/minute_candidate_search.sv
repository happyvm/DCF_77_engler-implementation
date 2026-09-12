// SPDX-License-Identifier: MIT
// Time-shared soft maximum-likelihood search over DCF77 minute values 00..59.
//
// Eight evidence values correspond to transmitted frame bits 21..28:
// units weights 1,2,4,8; tens weights 10,20,40; even parity. One candidate is
// evaluated per pass, avoiding 60 parallel correlators.
//
// Cycle budget (docs/37-timing-closure-plan.md §8): the search runs once per
// DCF77 minute, i.e. ~10^8 idle clk_sys cycles at 125 MHz between searches, so
// spreading each candidate over two cycles costs nothing observable.  The
// single-cycle variant put the whole cone
//   candidate -> decimal split -> +-evidence tree -> compare -> confident
// on one 26.7 ns path at the top (docs/37 §7).  It is now a four-state
// sequencer:
//
//   S_IDLE   -- nothing pending
//   S_SCORE  -- candidate -> decimal split -> +-evidence balanced tree -> score_q
//   S_SELECT -- score_q vs best_q / second_q -> best/second/minute update
//   S_EMIT   -- qualification floors -> confident/quality_gap/result_valid
//
// One arithmetic reduction per state.  `candidate` is the index of the score
// currently being selected and only advances when leaving S_SELECT, so during
// S_SCORE(c) and S_SELECT(c) it is exactly c.  The arithmetic is bit-identical
// to the previous single-cycle form: same expressions, widths, constants, sign
// conventions, tie-break order and sentinel values; only the register
// boundaries between independent reductions have moved.  Latency is
// 2*60 + 1 = 121 cycles from an accepted `start` to `result_valid` (documented;
// `busy` is asserted for the whole search and a `start` presented during `busy`
// is ignored, as before).

module minute_candidate_search #(
    parameter int SOFT_BITS = 24,
    parameter int SCORE_BITS = SOFT_BITS + 4,
    parameter bit QUALIFICATION_ENABLED = 1'b0,
    parameter logic signed [SCORE_BITS-1:0] MIN_SCORE = '0,
    parameter logic [SCORE_BITS-1:0] MIN_GAP = '0
) (
    input  logic clk,
    input  logic rst,
    input  logic load_valid,
    input  logic [2:0] load_index,
    input  logic signed [SOFT_BITS-1:0] soft_bit,
    input  logic start,
    output logic busy,
    output logic result_valid,
    output logic confident,
    output logic [5:0] minute,
    output logic signed [SCORE_BITS-1:0] best_score,
    output logic [SCORE_BITS-1:0] quality_gap
`ifdef FORMAL
    // Formal-only observability: the search loop index, the retained
    // best-minute register and the sequencer state are exposed so a proof can
    // state the reachability invariants that make the 121-cycle search
    // k-inductive instead of needing a 121-step BMC (see
    // formal/minute_candidate_search.sby).  `candidate_o` counts candidates
    // scored so far, `state_o` encodes S_IDLE/S_SCORE/S_SELECT/S_EMIT.
    , output logic [5:0] candidate_o
    , output logic [5:0] best_minute_o
    , output logic [1:0] state_o
`endif
);

    localparam logic [1:0] S_IDLE   = 2'd0;
    localparam logic [1:0] S_SCORE  = 2'd1;
    localparam logic [1:0] S_SELECT = 2'd2;
    localparam logic [1:0] S_EMIT   = 2'd3;

    logic [1:0] state;
    logic [5:0] candidate;
`ifdef FORMAL
    assign state_o = state;
    assign candidate_o = candidate;
`endif

    logic signed [SOFT_BITS-1:0] evidence [0:7];
    logic [7:0] candidate_bits;
    logic signed [SCORE_BITS-1:0] candidate_score;
    logic signed [SCORE_BITS-1:0] score_q;
    logic signed [SCORE_BITS-1:0] best_q, second_q;
    logic signed [SCORE_BITS-1:0] updated_best, updated_second;
    logic [5:0] best_minute_q, updated_minute;
`ifdef FORMAL
    assign best_minute_o = best_minute_q;
`endif
    logic [3:0] units;
    logic [2:0] tens;
    // Balanced-tree score accumulation (see calendar_candidate_search.sv and
    // docs/37-timing-closure-plan.md): the straight serial loop produced an
    // eight-deep carry chain on the ECP5 critical path.  Two's-complement
    // addition is associative under modular wrap, so the tree is bit-identical.
    logic signed [SCORE_BITS-1:0] t0, t1, t2, t3, t4, t5, t6, t7;
    logic signed [SCORE_BITS-1:0] p0, p1, p2, p3;

    // Pure address decode + balanced tree: no register boundary inside.
    always_comb begin
        // Explicit decimal split avoids inferring generic divider/modulo logic.
        if (candidate >= 50) begin
            tens = 5; units = 4'(candidate - 6'd50);
        end else if (candidate >= 40) begin
            tens = 4; units = 4'(candidate - 6'd40);
        end else if (candidate >= 30) begin
            tens = 3; units = 4'(candidate - 6'd30);
        end else if (candidate >= 20) begin
            tens = 2; units = 4'(candidate - 6'd20);
        end else if (candidate >= 10) begin
            tens = 1; units = 4'(candidate - 6'd10);
        end else begin
            tens = 0; units = candidate[3:0];
        end
        candidate_bits[0] = units[0];
        candidate_bits[1] = units[1];
        candidate_bits[2] = units[2];
        candidate_bits[3] = units[3];
        candidate_bits[4] = tens[0];
        candidate_bits[5] = tens[1];
        candidate_bits[6] = tens[2];
        candidate_bits[7] = ^candidate_bits[6:0];

        t0 = candidate_bits[0] ? SCORE_BITS'(evidence[0]) : SCORE_BITS'(-evidence[0]);
        t1 = candidate_bits[1] ? SCORE_BITS'(evidence[1]) : SCORE_BITS'(-evidence[1]);
        t2 = candidate_bits[2] ? SCORE_BITS'(evidence[2]) : SCORE_BITS'(-evidence[2]);
        t3 = candidate_bits[3] ? SCORE_BITS'(evidence[3]) : SCORE_BITS'(-evidence[3]);
        t4 = candidate_bits[4] ? SCORE_BITS'(evidence[4]) : SCORE_BITS'(-evidence[4]);
        t5 = candidate_bits[5] ? SCORE_BITS'(evidence[5]) : SCORE_BITS'(-evidence[5]);
        t6 = candidate_bits[6] ? SCORE_BITS'(evidence[6]) : SCORE_BITS'(-evidence[6]);
        t7 = candidate_bits[7] ? SCORE_BITS'(evidence[7]) : SCORE_BITS'(-evidence[7]);
        p0 = t0 + t1;
        p1 = t2 + t3;
        p2 = t4 + t5;
        p3 = t6 + t7;
        candidate_score = (p0 + p1) + (p2 + p3);
    end

    // Top-2 selection on the *registered* score of the current candidate.
    // Bit-identical to the previous single-cycle `updated_*` cone (same
    // comparisons, same tie-break order, same sentinel initialisation) -- only
    // score_q now comes from a register instead of the live tree output.
    always_comb begin
        updated_best = best_q;
        updated_second = second_q;
        updated_minute = best_minute_q;
        if (score_q > best_q) begin
            updated_second = best_q;
            updated_best = score_q;
            updated_minute = candidate;
        end else if (score_q > second_q) begin
            updated_second = score_q;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < 8; i = i + 1)
                evidence[i] <= '0;
            candidate      <= '0;
            score_q        <= '0;
            best_q         <= {1'b1, {(SCORE_BITS-1){1'b0}}};
            second_q       <= {1'b1, {(SCORE_BITS-1){1'b0}}};
            best_minute_q  <= '0;
            busy           <= 1'b0;
            result_valid   <= 1'b0;
            confident      <= 1'b0;
            minute         <= '0;
            best_score     <= '0;
            quality_gap    <= '0;
            state          <= S_IDLE;
        end else begin
            result_valid <= 1'b0;
            if (load_valid && !busy)
                evidence[load_index] <= soft_bit;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        candidate     <= '0;
                        best_q        <= {1'b1, {(SCORE_BITS-1){1'b0}}};
                        second_q      <= {1'b1, {(SCORE_BITS-1){1'b0}}};
                        best_minute_q <= '0;
                        busy          <= 1'b1;
                        state         <= S_SCORE;
                    end
                end

                S_SCORE: begin
                    score_q <= candidate_score;
                    state   <= S_SELECT;
                end

                S_SELECT: begin
                    best_q        <= updated_best;
                    second_q      <= updated_second;
                    best_minute_q <= updated_minute;
                    if (candidate == 6'd59) begin
                        state <= S_EMIT;
                    end else begin
                        candidate <= candidate + 6'd1;
                        state     <= S_SCORE;
                    end
                end

                S_EMIT: begin
                    minute        <= best_minute_q;
                    best_score    <= best_q;
                    quality_gap   <= best_q - second_q;
                    confident     <= QUALIFICATION_ENABLED &&
                                     (best_q >= MIN_SCORE) &&
                                     ((best_q - second_q) >= MIN_GAP);
                    result_valid  <= 1'b1;
                    busy          <= 1'b0;
                    state         <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    initial begin
        if (SOFT_BITS < 2 || SCORE_BITS < SOFT_BITS + 4)
            $error("minute_candidate_search: score width is too small");
    end

endmodule
