// SPDX-License-Identifier: MIT
// Integrated detector datapath from signed ADC samples to AM/PM soft evidence.
//
// second_ce must be aligned so the first observable_valid after it represents
// carrier cycle zero of the new DCF77 second. Minute synchronization will
// eventually generate this alignment; during bring-up it may come from a test
// timebase.

module engeler_detector #(
    parameter int SAMPLE_BITS = 14,
    parameter int STATE_BITS = 32,
    parameter int SOFT_BITS = 32,
    parameter int AM_OUTPUT_SHIFT = 20,
    parameter int PM_OUTPUT_SHIFT = 24,
    parameter logic [SOFT_BITS+14:0] MINUTE_MIN_SCORE = '0,
    parameter logic [SOFT_BITS+14:0] MINUTE_MIN_GAP = '0
) (
    input  logic clk,
    input  logic rst,
    input  logic sample_ce,
    input  logic signed [SAMPLE_BITS-1:0] sample,
    input  logic second_ce,
    output logic signed [SOFT_BITS-1:0] am_soft_bit,
    output logic am_bit_valid,
    output logic signed [SOFT_BITS+9:0] pm_correlation,
    output logic pm_correlation_valid,
    output logic minute_result_valid,
    output logic minute_locked,
    output logic [5:0] minute_window_end,
    output logic pm_polarity_inverted,
    output logic [SOFT_BITS+14:0] minute_best_magnitude,
    output logic [SOFT_BITS+14:0] minute_quality_gap,
    output logic signed [STATE_BITS:0] carrier_real,
    output logic signed [STATE_BITS:0] carrier_imag,
    output logic detector_overflow
);

    localparam int OBSERVABLE_BITS = (2 * STATE_BITS) + 3;

    logic signed [OBSERVABLE_BITS-1:0] am_observable;
    logic signed [OBSERVABLE_BITS-1:0] pm_observable;
    logic observable_valid;
    logic unused_prn_active;
    logic unused_prn_done;
    logic [16:0] unused_am_position;

    engeler_observables #(
        .SAMPLE_BITS(SAMPLE_BITS), .STATE_BITS(STATE_BITS)
    ) observables_i (
        .clk(clk), .rst(rst), .sample_ce(sample_ce), .sample(sample),
        .carrier_real(carrier_real), .carrier_imag(carrier_imag),
        .am_inphase_raw(am_observable), .pm_quadrature_raw(pm_observable),
        .observable_valid(observable_valid), .overflow(detector_overflow)
    );

    am_bit_extractor #(
        .INPUT_BITS(OBSERVABLE_BITS), .OUTPUT_BITS(SOFT_BITS),
        .OUTPUT_SHIFT(AM_OUTPUT_SHIFT)
    ) am_i (
        .clk(clk), .rst(rst), .second_ce(second_ce),
        .carrier_ce(observable_valid), .am_observable(am_observable),
        .am_soft_bit(am_soft_bit), .bit_valid(am_bit_valid),
        .carrier_position(unused_am_position)
    );

    engeler_pm_pipeline #(
        .OBSERVABLE_BITS(OBSERVABLE_BITS), .CHIP_SOFT_BITS(SOFT_BITS),
        .OUTPUT_SHIFT(PM_OUTPUT_SHIFT)
    ) pm_i (
        .clk(clk), .rst(rst), .second_ce(second_ce),
        .carrier_ce(observable_valid), .pm_observable(pm_observable),
        .correlation(pm_correlation),
        .correlation_valid(pm_correlation_valid),
        .prn_active(unused_prn_active), .prn_done(unused_prn_done)
    );

    pm_minute_sync #(
        .INPUT_BITS(SOFT_BITS + 10),
        .MIN_SCORE(MINUTE_MIN_SCORE), .MIN_GAP(MINUTE_MIN_GAP)
    ) minute_sync_i (
        .clk(clk), .rst(rst), .pm_second_soft(pm_correlation),
        .pm_second_valid(pm_correlation_valid),
        .result_valid(minute_result_valid), .locked(minute_locked),
        .best_window_end(minute_window_end),
        .pm_polarity_inverted(pm_polarity_inverted),
        .best_magnitude(minute_best_magnitude),
        .quality_gap(minute_quality_gap)
    );

endmodule
