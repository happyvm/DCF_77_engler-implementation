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
    // Qualification is deliberately opt-in: zero thresholds must never turn
    // an unconfigured detector (or an all-zero input stream) into a lock.
    parameter bit QUALIFICATION_ENABLED = 1'b0,
    parameter logic [INPUT_BITS+4:0] MIN_SCORE = '0,
    parameter logic [INPUT_BITS+4:0] MIN_GAP = '0,
    // Scale-free part of the qualification. Data seconds carry
    // full-magnitude correlations just like the marker, so with the
    // marker absent (dropout) the best of the ~45 data windows still
    // clears any absolute floor; and the runner-up is always the marker
    // shifted by one second (14 of 15 terms shared), so best/second gaps
    // cannot separate the two cases either. What does separate them is
    // the winner against the signal level: a real marker sums 15 aligned
    // terms, ~15x the mean |correlation| over the search, while the best
    // of 45 random-sign 15-term sums lands around 8-10x. Require
    // best >= MARKER_MIN_MEANS x mean|correlation|, i.e.
    // 60*best >= MARKER_MIN_MEANS*sum|correlation| over the 60 samples.
    parameter int MARKER_MIN_MEANS = 11 // < 64, see the shift-add below
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
`ifdef FORMAL
    // Formal-only observability: the search loop index, exposed so a
    // proof can discharge the 60-position search by k-induction instead
    // of 74-step BMC (see formal/pm_minute_sync.sby).
    , output logic [5:0] search_index_o
    , output logic [5:0] best_index_o
    , output logic [INPUT_BITS+5-1:0] best_score_o
    , output logic [INPUT_BITS+5-1:0] second_score_o
`endif
);

    localparam int SCORE_BITS = INPUT_BITS + 5;

    logic signed [INPUT_BITS-1:0] history [0:13];
    logic [3:0] history_count;
    logic [5:0] search_index;
`ifdef FORMAL
    assign search_index_o = search_index;
`endif
    logic signed [SCORE_BITS-1:0] candidate_score;
    logic [SCORE_BITS-1:0] candidate_magnitude;
    logic [SCORE_BITS-1:0] best_score_q, second_score_q;
`ifdef FORMAL
    assign best_score_o = best_score_q;
    assign second_score_o = second_score_q;
`endif
    logic [5:0] best_index_q;
`ifdef FORMAL
    assign best_index_o = best_index_q;
`endif
    logic best_polarity_q;
    logic [SCORE_BITS-1:0] updated_best, updated_second;
    logic [5:0] updated_index;
    logic updated_polarity;
    // Sum of |pm_second_soft| over the current 60-sample search (6 extra
    // bits: 60 < 64 terms of INPUT_BITS-1 magnitude bits each).
    logic [INPUT_BITS+5:0] abs_sum_q, abs_sum_next;
    logic [INPUT_BITS-1:0] sample_magnitude;
    // 60*best vs MARKER_MIN_MEANS*sum: both fit in SCORE_BITS+6 bits.
    logic [SCORE_BITS+5:0] best_scaled, sum_scaled;
    logic marker_dominant;

    always_comb begin
        candidate_score = '0;
        // Existing entries are the previous 14 samples, oldest first.
        // Each loop uses its own scoped index: sharing one module-level
        // variable between this always_comb and the always_ff below
        // would violate single-driver expectations for a combinational
        // process (IEEE 1800-2023 9.2.2.2).
        for (int i = 0; i < 10; i = i + 1)
            candidate_score = candidate_score - SCORE_BITS'(history[i]);
        for (int i = 10; i < 14; i = i + 1)
            candidate_score = candidate_score + SCORE_BITS'(history[i]);
        candidate_score = candidate_score + SCORE_BITS'(pm_second_soft);
        candidate_magnitude = candidate_score[SCORE_BITS-1]
                            ? (~candidate_score + 1'b1) : candidate_score;

        if (pm_second_soft < 0)
            sample_magnitude = INPUT_BITS'(-pm_second_soft);
        else
            sample_magnitude = INPUT_BITS'(pm_second_soft);
        abs_sum_next = abs_sum_q + (INPUT_BITS+6)'(sample_magnitude);

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

        // Constant scalings as shift-adds (60 = 64 - 4, MARKER_MIN_MEANS
        // unrolled over its bits): a plain `*` on these 47-bit values
        // pulled six MULT18X18D tiles out of an already over-budget pool.
        best_scaled = ((SCORE_BITS+6)'(updated_best) << 6) - ((SCORE_BITS+6)'(updated_best) << 2);
        sum_scaled = '0;
        for (int b = 0; b < 6; b = b + 1)
            if (MARKER_MIN_MEANS[b])
                sum_scaled = sum_scaled + ((SCORE_BITS+6)'(abs_sum_next) << b);
        marker_dominant = (best_scaled >= sum_scaled);
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < 14; i = i + 1)
                history[i] <= '0;
            history_count        <= '0;
            search_index         <= '0;
            best_score_q         <= '0;
            second_score_q       <= '0;
            best_index_q         <= '0;
            best_polarity_q      <= 1'b0;
            abs_sum_q            <= '0;
            result_valid         <= 1'b0;
            locked               <= 1'b0;
            best_window_end      <= '0;
            pm_polarity_inverted <= 1'b0;
            best_magnitude       <= '0;
            quality_gap          <= '0;
        end else begin
            result_valid <= 1'b0;
            if (pm_second_valid) begin
                for (int i = 0; i < 13; i = i + 1)
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
                    locked <= QUALIFICATION_ENABLED &&
                              (updated_best >= MIN_SCORE) &&
                              ((updated_best - updated_second) >= MIN_GAP) &&
                              marker_dominant;
                    search_index    <= '0;
                    best_score_q    <= '0;
                    second_score_q  <= '0;
                    best_index_q    <= '0;
                    best_polarity_q <= 1'b0;
                    abs_sum_q       <= '0;
                end else begin
                    search_index    <= search_index + 1'b1;
                    best_score_q    <= updated_best;
                    second_score_q  <= updated_second;
                    best_index_q    <= updated_index;
                    best_polarity_q <= updated_polarity;
                    abs_sum_q       <= abs_sum_next;
                end
            end
        end
    end

endmodule
