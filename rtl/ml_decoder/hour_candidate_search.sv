// SPDX-License-Identifier: MIT
// Time-shared soft maximum-likelihood search over DCF77 hours 00..23.
//
// Seven evidence values correspond to frame bits 29..35: four BCD unit bits,
// two BCD tens bits and even parity. One legal candidate is scored per pass.
//
// Same multi-cycle sequencer as minute_candidate_search.sv (see
// docs/37-timing-closure-plan.md §8): the search runs once per minute, so each
// candidate is spread over two cycles -- S_SCORE (address decode + +-evidence
// balanced tree -> score_q) then S_SELECT (score_q vs best_q/second_q) -- plus
// a final S_EMIT phase for the qualification floors.  The previous single-cycle
// form put the whole cone on one ~22 ns path at the top.  Bit-identical
// arithmetic; latency 2*24 + 1 = 49 cycles.
module hour_candidate_search #(
    parameter int SOFT_BITS = 24,
    parameter int SCORE_BITS = SOFT_BITS + 3,
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
    output logic [4:0] hour,
    output logic signed [SCORE_BITS-1:0] best_score,
    output logic [SCORE_BITS-1:0] quality_gap
`ifdef FORMAL
    // Formal-only observability (see formal/hour_candidate_search_formal.sv).
    , output logic [4:0] candidate_o
    , output logic [4:0] best_hour_o
    , output logic [1:0] state_o
`endif
);

    localparam logic [1:0] S_IDLE   = 2'd0;
    localparam logic [1:0] S_SCORE  = 2'd1;
    localparam logic [1:0] S_SELECT = 2'd2;
    localparam logic [1:0] S_EMIT   = 2'd3;

    logic [1:0] state;
    logic [4:0] candidate;
`ifdef FORMAL
    assign state_o = state;
    assign candidate_o = candidate;
`endif

    logic signed [SOFT_BITS-1:0] evidence [0:6];
    logic [6:0] candidate_bits;
    logic [3:0] units;
    logic [1:0] tens;
    logic signed [SCORE_BITS-1:0] candidate_score;
    logic signed [SCORE_BITS-1:0] score_q;
    logic signed [SCORE_BITS-1:0] best_q, second_q;
    logic signed [SCORE_BITS-1:0] updated_best, updated_second;
    logic [4:0] best_hour_q, updated_hour;
`ifdef FORMAL
    assign best_hour_o = best_hour_q;
`endif
    // Balanced-tree score accumulation (see calendar_candidate_search.sv and
    // docs/37-timing-closure-plan.md); bit-identical to the serial loop but
    // three adder levels instead of seven.
    logic signed [SCORE_BITS-1:0] t0, t1, t2, t3, t4, t5, t6;
    logic signed [SCORE_BITS-1:0] p0, p1, p2;

    // Pure address decode + balanced tree: no register boundary inside.
    always_comb begin
        if (candidate >= 20) begin
            tens = 2; units = 4'(candidate - 5'd20);
        end else if (candidate >= 10) begin
            tens = 1; units = 4'(candidate - 5'd10);
        end else begin
            tens = 0; units = candidate[3:0];
        end

        candidate_bits[0] = units[0];
        candidate_bits[1] = units[1];
        candidate_bits[2] = units[2];
        candidate_bits[3] = units[3];
        candidate_bits[4] = tens[0];
        candidate_bits[5] = tens[1];
        candidate_bits[6] = ^candidate_bits[5:0];

        t0 = candidate_bits[0] ? SCORE_BITS'(evidence[0]) : SCORE_BITS'(-evidence[0]);
        t1 = candidate_bits[1] ? SCORE_BITS'(evidence[1]) : SCORE_BITS'(-evidence[1]);
        t2 = candidate_bits[2] ? SCORE_BITS'(evidence[2]) : SCORE_BITS'(-evidence[2]);
        t3 = candidate_bits[3] ? SCORE_BITS'(evidence[3]) : SCORE_BITS'(-evidence[3]);
        t4 = candidate_bits[4] ? SCORE_BITS'(evidence[4]) : SCORE_BITS'(-evidence[4]);
        t5 = candidate_bits[5] ? SCORE_BITS'(evidence[5]) : SCORE_BITS'(-evidence[5]);
        t6 = candidate_bits[6] ? SCORE_BITS'(evidence[6]) : SCORE_BITS'(-evidence[6]);
        p0 = t0 + t1;
        p1 = t2 + t3;
        p2 = t4 + t5;
        candidate_score = (p0 + p1) + (p2 + t6);
    end

    // Top-2 selection on the registered score of the current candidate.
    always_comb begin
        updated_best = best_q;
        updated_second = second_q;
        updated_hour = best_hour_q;
        if (score_q > best_q) begin
            updated_second = best_q;
            updated_best = score_q;
            updated_hour = candidate;
        end else if (score_q > second_q) begin
            updated_second = score_q;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < 7; i = i + 1)
                evidence[i] <= '0;
            candidate     <= '0;
            score_q       <= '0;
            best_q        <= {1'b1, {(SCORE_BITS-1){1'b0}}};
            second_q      <= {1'b1, {(SCORE_BITS-1){1'b0}}};
            best_hour_q   <= '0;
            busy          <= 1'b0;
            result_valid  <= 1'b0;
            confident     <= 1'b0;
            hour          <= '0;
            best_score    <= '0;
            quality_gap   <= '0;
            state         <= S_IDLE;
        end else begin
            result_valid <= 1'b0;
            if (load_valid && !busy && load_index < 7)
                evidence[load_index] <= soft_bit;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        candidate   <= '0;
                        best_q      <= {1'b1, {(SCORE_BITS-1){1'b0}}};
                        second_q    <= {1'b1, {(SCORE_BITS-1){1'b0}}};
                        best_hour_q <= '0;
                        busy        <= 1'b1;
                        state       <= S_SCORE;
                    end
                end

                S_SCORE: begin
                    score_q <= candidate_score;
                    state   <= S_SELECT;
                end

                S_SELECT: begin
                    best_q      <= updated_best;
                    second_q    <= updated_second;
                    best_hour_q <= updated_hour;
                    if (candidate == 5'd23) begin
                        state <= S_EMIT;
                    end else begin
                        candidate <= candidate + 5'd1;
                        state     <= S_SCORE;
                    end
                end

                S_EMIT: begin
                    hour         <= best_hour_q;
                    best_score   <= best_q;
                    quality_gap  <= best_q - second_q;
                    confident    <= QUALIFICATION_ENABLED &&
                                    (best_q >= MIN_SCORE) &&
                                    ((best_q - second_q) >= MIN_GAP);
                    result_valid <= 1'b1;
                    busy         <= 1'b0;
                    state        <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    initial begin
        if (SOFT_BITS < 2 || SCORE_BITS < SOFT_BITS + 3)
            $error("hour_candidate_search: score width is too small");
    end

endmodule
