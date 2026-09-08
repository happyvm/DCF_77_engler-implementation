// SPDX-License-Identifier: MIT
// Time-shared soft maximum-likelihood search over DCF77 hours 00..23.
//
// Seven evidence values correspond to frame bits 29..35: four BCD unit bits,
// two BCD tens bits and even parity. One legal candidate is scored per clk.

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
);

    logic signed [SOFT_BITS-1:0] evidence [0:6];
    logic [4:0] candidate;
    logic [6:0] candidate_bits;
    logic [3:0] units;
    logic [1:0] tens;
    logic signed [SCORE_BITS-1:0] candidate_score;
    logic signed [SCORE_BITS-1:0] best_q, second_q;
    logic signed [SCORE_BITS-1:0] updated_best, updated_second;
    logic [4:0] best_hour_q, updated_hour;

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

        candidate_score = '0;
        for (int i = 0; i < 7; i = i + 1) begin
            if (candidate_bits[i])
                candidate_score = candidate_score + SCORE_BITS'(evidence[i]);
            else
                candidate_score = candidate_score - SCORE_BITS'(evidence[i]);
        end

        updated_best = best_q;
        updated_second = second_q;
        updated_hour = best_hour_q;
        if (candidate_score > best_q) begin
            updated_second = best_q;
            updated_best = candidate_score;
            updated_hour = candidate;
        end else if (candidate_score > second_q) begin
            updated_second = candidate_score;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < 7; i = i + 1)
                evidence[i] <= '0;
            candidate    <= '0;
            best_q       <= {1'b1, {(SCORE_BITS-1){1'b0}}};
            second_q     <= {1'b1, {(SCORE_BITS-1){1'b0}}};
            best_hour_q  <= '0;
            busy         <= 1'b0;
            result_valid <= 1'b0;
            confident    <= 1'b0;
            hour          <= '0;
            best_score   <= '0;
            quality_gap  <= '0;
        end else begin
            result_valid <= 1'b0;
            if (load_valid && !busy && load_index < 7)
                evidence[load_index] <= soft_bit;

            if (start && !busy) begin
                candidate   <= '0;
                best_q      <= {1'b1, {(SCORE_BITS-1){1'b0}}};
                second_q    <= {1'b1, {(SCORE_BITS-1){1'b0}}};
                best_hour_q <= '0;
                busy        <= 1'b1;
            end else if (busy) begin
                if (candidate == 5'd23) begin
                    hour         <= updated_hour;
                    best_score   <= updated_best;
                    quality_gap  <= updated_best - updated_second;
                    confident    <= QUALIFICATION_ENABLED &&
                                    (updated_best >= MIN_SCORE) &&
                                    ((updated_best - updated_second) >= MIN_GAP);
                    result_valid <= 1'b1;
                    busy         <= 1'b0;
                end else begin
                    candidate   <= candidate + 1'b1;
                    best_q      <= updated_best;
                    second_q    <= updated_second;
                    best_hour_q <= updated_hour;
                end
            end
        end
    end

    initial begin
        if (SOFT_BITS < 2 || SCORE_BITS < SOFT_BITS + 3)
            $error("hour_candidate_search: score width is too small");
    end

endmodule
