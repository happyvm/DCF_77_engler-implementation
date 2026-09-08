// SPDX-License-Identifier: MIT
//
// Fixed-point, continuously running Goertzel resonator.
//
// recurrence: s[n] = x[n] + 2*cos(w)*s[n-1] - s[n-2]
// Every CYCLE_SAMPLES accepted samples, both states are multiplied by k.  This
// is the periodic state scaling used by Engeler to obtain an exponentially
// weighted detector without storing a sliding input window.
//
// COEFF and SCALE_COEFF use COEFF_FRAC fractional bits. State arithmetic
// saturates; it never wraps. cycle_valid is one clk wide and marks the updated,
// scaled states corresponding to one complete carrier cycle.

module goertzel_resonator #(
    parameter int SAMPLE_BITS = 14,
    parameter int STATE_BITS = 32,
    parameter int COEFF_BITS = 19,
    parameter int COEFF_FRAC = 17,
    parameter int CYCLE_SAMPLES = 12,
    parameter logic signed [COEFF_BITS-1:0] RESONATOR_COEFF = 19'sd227023,
    parameter logic signed [COEFF_BITS-1:0] SCALE_COEFF = 19'sd131000
) (
    input  logic clk,
    input  logic rst,
    input  logic sample_ce,
    input  logic signed [SAMPLE_BITS-1:0] sample,
    output logic signed [STATE_BITS-1:0] state_1,
    output logic signed [STATE_BITS-1:0] state_2,
    output logic cycle_valid,
    output logic overflow
);

    localparam int PRODUCT_BITS = STATE_BITS + COEFF_BITS;
    localparam int CYCLE_COUNT_W =
        (CYCLE_SAMPLES <= 1) ? 1 : $clog2(CYCLE_SAMPLES);

    localparam logic signed [STATE_BITS-1:0] STATE_MAX =
        {1'b0, {(STATE_BITS-1){1'b1}}};
    localparam logic signed [STATE_BITS-1:0] STATE_MIN =
        {1'b1, {(STATE_BITS-1){1'b0}}};

    logic [CYCLE_COUNT_W-1:0] cycle_count;
    logic signed [PRODUCT_BITS-1:0] feedback_product;
    logic signed [PRODUCT_BITS-1:0] scale_product_1;
    logic signed [PRODUCT_BITS-1:0] scale_product_2;
    logic signed [PRODUCT_BITS:0] recurrence_wide;
    logic signed [PRODUCT_BITS:0] scaled_wide_1;
    logic signed [PRODUCT_BITS:0] scaled_wide_2;
    logic signed [STATE_BITS-1:0] recurrence_sat;
    logic signed [STATE_BITS-1:0] scaled_sat_1;
    logic signed [STATE_BITS-1:0] scaled_sat_2;
    logic recurrence_overflow;
    logic scale_overflow_1;
    logic scale_overflow_2;

    // Sign extension relies on ordinary Verilog signed-context widening
    // (assigning/comparing a narrower signed value against a wider signed
    // one) rather than an explicit {{N{x[msb]}}, x} replication: this
    // project's pinned Icarus Verilog release (oss-cad-suite 2025-02-13,
    // "sorry: constant selects in always_* processes are not currently
    // supported") silently substitutes the whole parent vector for such a
    // replicated bit-select inside always_comb/always_ff when it is mixed
    // with a plain (non-select) operand, corrupting the arithmetic result
    // even though it only warns. Plain signed widening needs no bit-select
    // at all, so it never hits that fallback.
    function automatic logic signed [STATE_BITS-1:0] saturate(
        input logic signed [PRODUCT_BITS:0] value
    );
        logic signed [PRODUCT_BITS:0] maximum;
        logic signed [PRODUCT_BITS:0] minimum;
        begin
            maximum = STATE_MAX;
            minimum = STATE_MIN;
            if (value > maximum)
                saturate = STATE_MAX;
            else if (value < minimum)
                saturate = STATE_MIN;
            else
                saturate = value[STATE_BITS-1:0];
        end
    endfunction

    always_comb begin
        feedback_product = state_1 * RESONATOR_COEFF;
        recurrence_wide = sample + (feedback_product >>> COEFF_FRAC) - state_2;
        recurrence_sat = saturate(recurrence_wide);
        recurrence_overflow = (recurrence_wide != recurrence_sat);

        scale_product_1 = recurrence_sat * SCALE_COEFF;
        scale_product_2 = state_1 * SCALE_COEFF;
        scaled_wide_1 = scale_product_1 >>> COEFF_FRAC;
        scaled_wide_2 = scale_product_2 >>> COEFF_FRAC;
        scaled_sat_1 = saturate(scaled_wide_1);
        scaled_sat_2 = saturate(scaled_wide_2);
        scale_overflow_1 = (scaled_wide_1 != scaled_sat_1);
        scale_overflow_2 = (scaled_wide_2 != scaled_sat_2);
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state_1     <= '0;
            state_2     <= '0;
            cycle_count <= '0;
            cycle_valid <= 1'b0;
            overflow    <= 1'b0;
        end else begin
            cycle_valid <= 1'b0;
            if (sample_ce) begin
                overflow <= overflow | recurrence_overflow;
                if (cycle_count == CYCLE_SAMPLES - 1) begin
                    state_1     <= scaled_sat_1;
                    state_2     <= scaled_sat_2;
                    cycle_count <= '0;
                    cycle_valid <= 1'b1;
                    overflow    <= overflow | recurrence_overflow |
                                   scale_overflow_1 | scale_overflow_2;
                end else begin
                    state_1     <= recurrence_sat;
                    state_2     <= state_1;
                    cycle_count <= cycle_count + 1'b1;
                end
            end
        end
    end

    initial begin
        if (SAMPLE_BITS < 2 || STATE_BITS < SAMPLE_BITS)
            $error("goertzel_resonator: invalid sample/state width");
        if (COEFF_BITS <= COEFF_FRAC)
            $error("goertzel_resonator: coefficient needs integer/sign bits");
        if (CYCLE_SAMPLES < 1)
            $error("goertzel_resonator: CYCLE_SAMPLES must be positive");
        if (SCALE_COEFF < 0 || SCALE_COEFF > (1 <<< COEFF_FRAC))
            $error("goertzel_resonator: SCALE_COEFF must represent 0..1");
    end

endmodule
