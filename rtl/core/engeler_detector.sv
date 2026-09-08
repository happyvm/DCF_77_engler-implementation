// SPDX-License-Identifier: MIT
// Integrated detector datapath from signed ADC samples to AM/PM soft evidence.
//
// The second epoch is recovered internally from AM and then refined by PZF.

module engeler_detector #(
    parameter int SAMPLE_BITS = 14,
    parameter int STATE_BITS = 32,
    parameter int SOFT_BITS = 32,
    parameter int AM_OUTPUT_SHIFT = 20,
    parameter int PM_OUTPUT_SHIFT = 24,
    // Floor below which the PM early/late/prompt correlation triple is too
    // weak to carry real sub-chip timing information (pure noise, or PM
    // dropout) and must not be forwarded to frequency discipline at all.
    // Chip-level soft values saturate at +-2^(SOFT_BITS-1) regardless of
    // analog front-end gain (pm_chip_integrator's own saturating output),
    // so the threshold is expressed relative to SOFT_BITS rather than as
    // an absolute constant: a real (even weak) carrier reaching just
    // 1/16 of one chip's full range, integrated coherently over the
    // 512-chip PRN, sits far above the sqrt(512)-scaled random walk that
    // equivalent-amplitude noise would produce with no fixed phase
    // relationship to chip boundaries. Still a calibration constant, not
    // a measured one -- re-validate once real receiver noise floor is
    // characterized on hardware.
    parameter int PM_MIN_PROMPT_MAGNITUDE = (SOFT_BITS > 4) ? (1 << (SOFT_BITS - 4)) : 1,
    parameter bit QUALIFICATION_ENABLED = 1'b0,
    parameter logic [SOFT_BITS+14:0] MINUTE_MIN_SCORE = '0,
    parameter logic [SOFT_BITS+14:0] MINUTE_MIN_GAP = '0,
    parameter int AM_SYNC_THRESHOLD = 1,
    parameter int SECOND_CYCLES = 77_500,
    parameter int SECOND_SEARCH_TOLERANCE = 1_000,
    parameter int SECOND_TRACK_WINDOW = 2_000,
    parameter int SECOND_ACQUIRE_HITS = 2
) (
    input  logic clk,
    input  logic rst,
    input  logic sample_ce,
    input  logic signed [SAMPLE_BITS-1:0] sample,
    output logic second_ce,
    output logic signed [17:0] second_phase_error,
    output logic [7:0] second_phase_quality,
    output logic second_measurement_outlier,
    output logic [15:0] second_measurement_age,
    output logic [1:0] second_sync_state,
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
    logic signed [17:0] pm_phase_error_cycles;
    logic pm_phase_error_valid;
    logic [7:0] pm_timing_quality;

    always_comb begin
        if (pm_correlation[SOFT_BITS+9])
            pm_timing_quality = (~pm_correlation[SOFT_BITS+8 -: 8]);
        else
            pm_timing_quality = pm_correlation[SOFT_BITS+8 -: 8];
    end

    engeler_observables #(
        .SAMPLE_BITS(SAMPLE_BITS), .STATE_BITS(STATE_BITS)
    ) observables_i (
        .clk(clk), .rst(rst), .sample_ce(sample_ce), .sample(sample),
        .carrier_real(carrier_real), .carrier_imag(carrier_imag),
        .am_inphase_raw(am_observable), .pm_quadrature_raw(pm_observable),
        .observable_valid(observable_valid), .overflow(detector_overflow)
    );

    second_phase_detector #(
        .INPUT_BITS(OBSERVABLE_BITS), .SECOND_CYCLES(SECOND_CYCLES),
        .AM_EDGE_THRESHOLD(AM_SYNC_THRESHOLD),
        .SEARCH_TOLERANCE(SECOND_SEARCH_TOLERANCE),
        .TRACK_WINDOW(SECOND_TRACK_WINDOW), .ACQUIRE_HITS(SECOND_ACQUIRE_HITS)
    ) second_sync_i (
        .clk(clk), .rst(rst), .carrier_ce(observable_valid),
        .am_envelope(am_observable),
        .pm_measurement_valid(pm_phase_error_valid),
        .pm_phase_error_cycles(pm_phase_error_cycles), .pm_quality(pm_timing_quality),
        .second_ce(second_ce), .phase_error_cycles(second_phase_error),
        .quality(second_phase_quality),
        .measurement_outlier(second_measurement_outlier),
        .measurement_age(second_measurement_age), .state(second_sync_state)
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

    // Closes the PM/PZF second-phase loop: derives a signed sub-chip
    // timing error from early/late correlator taps around the same PRN
    // start the prompt tap above uses, feeding second_phase_detector so
    // frequency_discipline can actually discipline from PM structure
    // instead of the former always-zero stub.
    pm_phase_discriminator #(
        .OBSERVABLE_BITS(OBSERVABLE_BITS), .CHIP_SOFT_BITS(SOFT_BITS),
        .OUTPUT_SHIFT(PM_OUTPUT_SHIFT),
        .MIN_PROMPT_MAGNITUDE(PM_MIN_PROMPT_MAGNITUDE)
    ) pm_phase_i (
        .clk(clk), .rst(rst), .second_ce(second_ce),
        .carrier_ce(observable_valid), .pm_observable(pm_observable),
        .prompt_correlation(pm_correlation),
        .prompt_correlation_valid(pm_correlation_valid),
        .pm_phase_error_cycles(pm_phase_error_cycles),
        .phase_error_valid(pm_phase_error_valid)
    );

    pm_minute_sync #(
        .INPUT_BITS(SOFT_BITS + 10),
        .QUALIFICATION_ENABLED(QUALIFICATION_ENABLED),
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
