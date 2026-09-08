// SPDX-License-Identifier: MIT
// Time-shared soft maximum-likelihood search over DCF77 minute values 00..59.
//
// Eight evidence values correspond to transmitted frame bits 21..28:
// units weights 1,2,4,8; tens weights 10,20,40; even parity. One candidate is
// evaluated per clk, avoiding 60 parallel correlators.

module minute_candidate_search #(
    parameter int SOFT_BITS = 24,
    parameter int SCORE_BITS = SOFT_BITS + 4,
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
);

    logic signed [SOFT_BITS-1:0] evidence [0:7];
    logic [5:0] candidate;
    logic [7:0] candidate_bits;
    logic signed [SCORE_BITS-1:0] candidate_score;
    logic signed [SCORE_BITS-1:0] best_q, second_q;
    logic signed [SCORE_BITS-1:0] updated_best, updated_second;
    logic [5:0] best_minute_q, updated_minute;
    logic [3:0] units;
    logic [2:0] tens;
    integer i;

    always_comb begin
        // Explicit decimal split avoids inferring generic divider/modulo logic.
        if (candidate >= 50) begin
            tens = 5; units = candidate - 50;
        end else if (candidate >= 40) begin
            tens = 4; units = candidate - 40;
        end else if (candidate >= 30) begin
            tens = 3; units = candidate - 30;
        end else if (candidate >= 20) begin
            tens = 2; units = candidate - 20;
        end else if (candidate >= 10) begin
            tens = 1; units = candidate - 10;
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

        candidate_score = '0;
        for (i = 0; i < 8; i = i + 1) begin
            if (candidate_bits[i])
                candidate_score = candidate_score + evidence[i];
            else
                candidate_score = candidate_score - evidence[i];
        end

        updated_best = best_q;
        updated_second = second_q;
        updated_minute = best_minute_q;
        if (candidate_score > best_q) begin
            updated_second = best_q;
            updated_best = candidate_score;
            updated_minute = candidate;
        end else if (candidate_score > second_q) begin
            updated_second = candidate_score;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 8; i = i + 1)
                evidence[i] <= '0;
            candidate      <= '0;
            best_q         <= {1'b1, {(SCORE_BITS-1){1'b0}}};
            second_q       <= {1'b1, {(SCORE_BITS-1){1'b0}}};
            best_minute_q  <= '0;
            busy           <= 1'b0;
            result_valid   <= 1'b0;
            confident      <= 1'b0;
            minute         <= '0;
            best_score     <= '0;
            quality_gap    <= '0;
        end else begin
            result_valid <= 1'b0;
            if (load_valid && !busy)
                evidence[load_index] <= soft_bit;

            if (start && !busy) begin
                candidate     <= '0;
                best_q        <= {1'b1, {(SCORE_BITS-1){1'b0}}};
                second_q      <= {1'b1, {(SCORE_BITS-1){1'b0}}};
                best_minute_q <= '0;
                busy          <= 1'b1;
            end else if (busy) begin
                if (candidate == 6'd59) begin
                    minute       <= updated_minute;
                    best_score   <= updated_best;
                    quality_gap  <= updated_best - updated_second;
                    confident    <= (updated_best >= MIN_SCORE) &&
                                    ((updated_best - updated_second) >= MIN_GAP);
                    result_valid <= 1'b1;
                    busy         <= 1'b0;
                end else begin
                    candidate     <= candidate + 1'b1;
                    best_q        <= updated_best;
                    second_q      <= updated_second;
                    best_minute_q <= updated_minute;
                end
            end
        end
    end

    initial begin
        if (SOFT_BITS < 2 || SCORE_BITS < SOFT_BITS + 4)
            $error("minute_candidate_search: score width is too small");
    end

endmodule
