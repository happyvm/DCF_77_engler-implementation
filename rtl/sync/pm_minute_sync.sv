// SPDX-License-Identifier: MIT
// Streaming PM minute-pattern search using soft per-second correlations.
//
// Normal DCF77 PM minute identification is ten logical ones followed by five
// logical zeros at seconds 0..14. This block evaluates that 15-second matched
// filter at every received second, then selects the strongest and second
// strongest candidates over 60 positions. Absolute score permits acquisition
// through an unknown analog polarity; pm_polarity_inverted records its sign.
//
// BEA-36 timing closure: a new sample arrives once per DCF77 second while
// clk_sys runs far faster (~10^8 cycles of slack per second at 125 MHz), yet
// the original single-cycle form evaluated the whole 15-term matched filter,
// the top-two selection and the qualification logic on one combinational path
// (~34 ns in the routed top). It is now a four-stage sequencer
// (`S_SCORE` -> `S_SELECT` -> `S_MARK` -> `S_COMMIT`) with exactly one
// arithmetic reduction per stage, a `busy` handshake and a documented
// latency of 4 clk_sys. The arithmetic is unchanged bit-for-bit: the same
// expressions, operand widths, constants, saturations and sign conventions,
// only the register boundaries between *independent* reductions moved. The
// caller contract ("never present `pm_second_valid` while `busy`") is proven
// in formal/pm_minute_sync_formal.sv and monitored in simulation by
// sim/pm_minute_sync_contract.sv.

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
    // High while a sample is being processed: a new `pm_second_valid`
    // presented during `busy` is ignored (the caller contract).
    output logic busy,
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
    // of 74-step BMC (see formal/pm_minute_sync.sby), and the sequencer
    // state, exposed so the multi-cycle latency contract is inductive.
    , output logic [5:0] search_index_o
    , output logic [5:0] best_index_o
    , output logic [INPUT_BITS+5-1:0] best_score_o
    , output logic [INPUT_BITS+5-1:0] second_score_o
    , output logic [2:0] state_o
`endif
);

    localparam int SCORE_BITS = INPUT_BITS + 5;

    // Documented latency: S_IDLE accept -> S_SCORE -> S_SELECT -> S_MARK ->
    // S_COMMIT. `busy` is asserted for 4 clk_sys.
    typedef enum logic [2:0] {
        S_IDLE, S_SCORE, S_SELECT, S_MARK, S_COMMIT
    } state_e;
    state_e state;

    logic signed [INPUT_BITS-1:0] history [0:13];
    logic [3:0] history_count;
    logic [5:0] search_index;
`ifdef FORMAL
    assign search_index_o = search_index;
`endif
    logic signed [SCORE_BITS-1:0] best_score_q, second_score_q;
`ifdef FORMAL
    assign best_score_o = best_score_q;
    assign second_score_o = second_score_q;
`endif
    logic [5:0] best_index_q;
`ifdef FORMAL
    assign best_index_o = best_index_q;
`endif
    logic best_polarity_q;
    // Stage registers (one arithmetic reduction each).
    logic signed [INPUT_BITS-1:0] sample_reg;
    logic signed [SCORE_BITS-1:0] cand_score_q;
    logic [INPUT_BITS+5:0] abs_sum_next_q;
    logic signed [SCORE_BITS-1:0] updated_best_q, updated_second_q;
    logic [5:0] updated_index_q;
    logic updated_polarity_q;
    logic [SCORE_BITS-1:0] updated_best_c, updated_second_c;
    logic [5:0] updated_index_c;
    logic updated_polarity_c;
    logic [SCORE_BITS-1:0] candidate_magnitude;
    logic locked_q;
    logic [SCORE_BITS-1:0] gap_q;
    logic [INPUT_BITS-1:0] sample_magnitude;
    // Sum of |pm_second_soft| over the current 60-sample search (6 extra
    // bits: 60 < 64 terms of INPUT_BITS-1 magnitude bits each).
    logic [INPUT_BITS+5:0] abs_sum_q;
    // 60*best vs MARKER_MIN_MEANS*sum: both fit in SCORE_BITS+6 bits.
    logic [SCORE_BITS+5:0] best_scaled, sum_scaled;
    logic marker_dominant;
    logic locked_c;

    assign busy = (state != S_IDLE);
`ifdef FORMAL
    assign state_o = state;
`endif

    always_comb begin
        if (sample_reg < 0)
            sample_magnitude = INPUT_BITS'(-sample_reg);
        else
            sample_magnitude = INPUT_BITS'(sample_reg);
    end


    // ------------------------------------------------------------------
    // Balanced adder tree, bit-identical to the former serial accumulation:
    // two's-complement addition is associative modulo 2^SCORE_BITS, so the
    // same 15 signed terms summed as a tree (depth 4 instead of 15) give the
    // exact same result while cutting the combinational depth.
    // ------------------------------------------------------------------
    logic signed [SCORE_BITS-1:0] term [0:14];
    logic signed [SCORE_BITS-1:0] lvl1 [0:7];
    logic signed [SCORE_BITS-1:0] lvl2 [0:3];
    logic signed [SCORE_BITS-1:0] lvl3 [0:1];
    logic signed [SCORE_BITS-1:0] tree_sum;

    always_comb begin
        // Existing entries are the previous 14 samples, oldest first.
        for (int i = 0; i < 10; i = i + 1)
            term[i] = SCORE_BITS'(0) - SCORE_BITS'(history[i]);
        for (int i = 10; i < 14; i = i + 1)
            term[i] = SCORE_BITS'(history[i]);
        term[14] = SCORE_BITS'(sample_reg);

        for (int i = 0; i < 7; i = i + 1)
            lvl1[i] = term[2*i] + term[2*i+1];
        lvl1[7] = term[14];
        for (int i = 0; i < 4; i = i + 1)
            lvl2[i] = lvl1[2*i] + lvl1[2*i+1];
        for (int i = 0; i < 2; i = i + 1)
            lvl3[i] = lvl2[2*i] + lvl2[2*i+1];
        tree_sum = lvl3[0] + lvl3[1];
    end

    // Stage 2: magnitude + top-two selection (operands from registered score).
    always_comb begin
        candidate_magnitude = cand_score_q[SCORE_BITS-1]
                            ? (~cand_score_q + 1'b1) : cand_score_q;

        updated_best_c     = best_score_q;
        updated_second_c   = second_score_q;
        updated_index_c    = best_index_q;
        updated_polarity_c = best_polarity_q;
        if (candidate_magnitude > best_score_q) begin
            updated_second_c   = best_score_q;
            updated_best_c     = candidate_magnitude;
            updated_index_c    = search_index;
            updated_polarity_c = cand_score_q[SCORE_BITS-1];
        end else if (candidate_magnitude > second_score_q) begin
            updated_second_c = candidate_magnitude;
        end
    end

    // Stage 3: qualification (operands from registered selection).
    always_comb begin
        // Constant scalings as shift-adds (60 = 64 - 4, MARKER_MIN_MEANS
        // unrolled over its bits): a plain `*` on these 47-bit values
        // pulled six MULT18X18D tiles out of an already over-budget pool.
        best_scaled = ((SCORE_BITS+6)'(updated_best_q) << 6)
                    - ((SCORE_BITS+6)'(updated_best_q) << 2);
        sum_scaled = '0;
        for (int b = 0; b < 6; b = b + 1)
            if (MARKER_MIN_MEANS[b])
                sum_scaled = sum_scaled + ((SCORE_BITS+6)'(abs_sum_next_q) << b);
        marker_dominant = (best_scaled >= sum_scaled);

        locked_c = QUALIFICATION_ENABLED &&
                   (updated_best_q >= MIN_SCORE) &&
                   ((updated_best_q - updated_second_q) >= MIN_GAP) &&
                   marker_dominant;
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
            state                <= S_IDLE;
            sample_reg           <= '0;
            cand_score_q         <= '0;
            abs_sum_next_q       <= '0;
            updated_best_q       <= '0;
            updated_second_q     <= '0;
            updated_index_q      <= '0;
            updated_polarity_q   <= 1'b0;
            locked_q             <= 1'b0;
            gap_q                <= '0;
        end else begin
            result_valid <= 1'b0;
            case (state)
                S_IDLE: begin
                    // Contract: a valid presented while busy is ignored, so
                    // it can only be honoured from S_IDLE.
                    if (pm_second_valid) begin
                        sample_reg <= pm_second_soft;
                        state      <= S_SCORE;
                    end
                end
                S_SCORE: begin
                    // Reduction 1: 15-term matched-filter sum (adder tree)
                    // and the running |correlation| accumulator.
                    cand_score_q   <= tree_sum;
                    abs_sum_next_q <= abs_sum_q + (INPUT_BITS+6)'(sample_magnitude);
                    state          <= S_SELECT;
                end
                S_SELECT: begin
                    // Reduction 2: |score| and the top-two selection.
                    updated_best_q     <= updated_best_c;
                    updated_second_q   <= updated_second_c;
                    updated_index_q    <= updated_index_c;
                    updated_polarity_q <= updated_polarity_c;
                    state              <= S_MARK;
                end
                S_MARK: begin
                    // Reduction 3: marker-dominance and qualification.
                    locked_q <= locked_c;
                    gap_q    <= updated_best_q - updated_second_q;
                    state    <= S_COMMIT;
                end
                default: begin // S_COMMIT
                    for (int i = 0; i < 13; i = i + 1)
                        history[i] <= history[i+1];
                    history[13] <= sample_reg;

                    if (history_count < 14) begin
                        history_count <= history_count + 1'b1;
                    end else if (search_index == 6'd59) begin
                        result_valid         <= 1'b1;
                        best_window_end      <= updated_index_q;
                        pm_polarity_inverted <= updated_polarity_q;
                        best_magnitude       <= updated_best_q;
                        quality_gap          <= gap_q;
                        locked               <= locked_q;
                        search_index    <= '0;
                        best_score_q    <= '0;
                        second_score_q  <= '0;
                        best_index_q    <= '0;
                        best_polarity_q <= 1'b0;
                        abs_sum_q       <= '0;
                    end else begin
                        search_index    <= search_index + 1'b1;
                        best_score_q    <= updated_best_q;
                        second_score_q  <= updated_second_q;
                        best_index_q    <= updated_index_q;
                        best_polarity_q <= updated_polarity_q;
                        abs_sum_q       <= abs_sum_next_q;
                    end
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
