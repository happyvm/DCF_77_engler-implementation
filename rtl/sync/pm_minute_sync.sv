// SPDX-License-Identifier: MIT
// Streaming PM minute-pattern search using soft per-second correlations.
//
// Normal DCF77 PM minute identification is ten logical ones followed by five
// logical zeroes at seconds 0..14. This block evaluates that 15-second matched
// filter at every received second, then selects the strongest and second
// strongest candidates over 60 positions. Absolute score permits acquisition
// through an unknown analog polarity; pm_polarity_inverted records its sign.

module pm_minute_sync #(
    parameter int INPUT_BITS = 34,
    parameter logic [INPUT_BITS+4:0] MIN_SCORE = '0,
    parameter logic [INPUT_BITS+4:0] MIN_GAP = '0
) (
    input  logic clk,
    input  logic rst,
    input  logic signed [INPUT_BITS-1:0] pm_second_soft,
    input  logic pm_second_valid,
    output logic result_valid,
    output logic locked,
    // Position, within the just-completed 60-candidate search, at which the
    // winning 15-second window ended (DCF77 second 14 when aligned).
    output logic [5:0] best_window_end,
    output logic pm_polarity_inverted,
    output logic [INPUT_BITS+4:0] best_magnitude,
    output logic [INPUT_BITS+4:0] quality_gap
);

    localparam int SCORE_BITS = INPUT_BITS + 5;

    logic signed [INPUT_BITS-1:0] history [0:13];
    logic [3:0] history_count;
    logic [5:0] search_index;
    logic signed [SCORE_BITS-1:0] candidate_score;
    logic [SCORE_BITS-1:0] candidate_magnitude;
    logic [SCORE_BITS-1:0] best_score_q, second_score_q;
    logic [5:0] best_index_q;
    logic best_polarity_q;
    logic [SCORE_BITS-1:0] updated_best, updated_second;
    logic [5:0] updated_index;
    logic updated_polarity;
    integer i;

    always_comb begin
        candidate_score = '0;
        // Existing entries are the previous 14 samples, oldest first.
        for (i = 0; i < 10; i = i + 1)
            candidate_score = candidate_score - history[i];
        for (i = 10; i < 14; i = i + 1)
            candidate_score = candidate_score + history[i];
        candidate_score = candidate_score + pm_second_soft;
        candidate_magnitude = candidate_score[SCORE_BITS-1]
                            ? (~candidate_score + 1'b1) : candidate_score;

        updated_best = best_score_q;
        updated_second = second_score_q;
        updated_index = best_index_q;
        updated_polarity = best_polarity_q;
        if (candidate_magnitude > best_score_q) begin
            updated_second = best_score_q;
            updated_best = candidate_magnitude;
            updated_index = search_index;
            updated_polarity = candidate_score[SCORE_BITS-1];
        end else if (candidate_magnitude > second_score_q) begin
            updated_second = candidate_magnitude;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 14; i = i + 1)
                history[i] <= '0;
            history_count        <= '0;
            search_index         <= '0;
            best_score_q         <= '0;
            second_score_q       <= '0;
            best_index_q         <= '0;
            best_polarity_q      <= 1'b0;
            result_valid         <= 1'b0;
            locked               <= 1'b0;
            best_window_end      <= '0;
            pm_polarity_inverted <= 1'b0;
            best_magnitude       <= '0;
            quality_gap          <= '0;
        end else begin
            result_valid <= 1'b0;
            if (pm_second_valid) begin
                for (i = 0; i < 13; i = i + 1)
                    history[i] <= history[i+1];
                history[13] <= pm_second_soft;

                if (history_count < 14) begin
                    history_count <= history_count + 1'b1;
                end else if (search_index == 6'd59) begin
                    result_valid         <= 1'b1;
                    best_window_end      <= updated_index;
                    pm_polarity_inverted <= updated_polarity;
                    best_magnitude       <= updated_best;
                    quality_gap          <= updated_best - updated_second;
                    locked <= (updated_best >= MIN_SCORE) &&
                              ((updated_best - updated_second) >= MIN_GAP);
                    search_index    <= '0;
                    best_score_q    <= '0;
                    second_score_q  <= '0;
                    best_index_q    <= '0;
                    best_polarity_q <= 1'b0;
                end else begin
                    search_index    <= search_index + 1'b1;
                    best_score_q    <= updated_best;
                    second_score_q  <= updated_second;
                    best_index_q    <= updated_index;
                    best_polarity_q <= updated_polarity;
                end
            end
        end
    end

endmodule
