// SPDX-License-Identifier: MIT
// Slow, vendor-neutral frequency discipline for the fractional sample scheduler.
//
// Units and sign conventions
// --------------------------
// phase_error is a signed Q(PHASE_BITS-PHASE_FRAC_BITS).PHASE_FRAC_BITS
// number of carrier (or one-second) cycles.  For example, with 16 fractional
// bits, 16'sh4000 is +0.25 cycle.  Positive means that the received reference
// is later than the local epoch.  A positive slope therefore requests a
// positive trim (a faster local sample schedule).
//
// estimated_offset and trim_inc are signed sample_scheduler accumulator-
// increment LSBs.  PHASE_TO_TRIM converts one cycle of phase change per
// measurement interval to those LSBs.  At the default sample_scheduler point
// one LSB is about 0.000122 ppm; PHASE_TO_TRIM must be set for the selected
// reference and measurement interval.
//
// The loop is a frequency estimator followed by a PI-like actuator.  All gain
// parameters are integer trim-LSB/cycle coefficients.  Separate acquisition
// and tracking values permit a fast initial pull-in and quiet steady tracking.
// The ECP5 PLL is not controlled by this block and remains fixed.

`timescale 1ns/1ps

module frequency_discipline #(
    parameter int PHASE_BITS = 24,
    parameter int PHASE_FRAC_BITS = 16,
    parameter int QUALITY_BITS = 8,
    parameter int TRIM_BITS = 24,
    parameter int AGE_BITS = 16,
    parameter int PHASE_TO_TRIM = 8192,
    parameter int ACQ_EST_SHIFT = 1,
    parameter int TRACK_EST_SHIFT = 4,
    parameter int ACQ_KP = 1024,
    parameter int ACQ_KI = 128,
    parameter int TRACK_KP = 128,
    parameter int TRACK_KI = 8,
    parameter int MAX_TRIM = 32768,
    parameter int MAX_TRIM_STEP = 2048,
    parameter int OUTLIER_LIMIT = (1 << (PHASE_FRAC_BITS-1)),
    parameter int DELTA_LIMIT = (1 << (PHASE_FRAC_BITS-2)),
    parameter int ACQ_QUALITY_MIN = 32,
    parameter int TRACK_QUALITY_MIN = 64,
    parameter int LOCK_COUNT = 8,
    parameter int HOLDOVER_AGE = 4
) (
    input  logic clk,
    input  logic rst,
    // One pulse per nominal observation interval (normally one second).
    input  logic measurement_ce,
    input  logic measurement_valid,
    input  logic signed [PHASE_BITS-1:0] phase_error,
    input  logic [QUALITY_BITS-1:0] measurement_quality,
    output logic signed [TRIM_BITS-1:0] estimated_offset,
    output logic signed [TRIM_BITS-1:0] trim_inc,
    output logic frequency_locked,
    output logic measurement_rejected,
    // Saturating count of observation intervals since the last accepted point.
    output logic [AGE_BITS-1:0] measurement_age
);
    localparam int COUNT_BITS = (LOCK_COUNT < 2) ? 1 : $clog2(LOCK_COUNT + 1);
    localparam logic signed [63:0] MAX_TRIM_64 = MAX_TRIM;
    localparam logic signed [63:0] MIN_TRIM_64 = -MAX_TRIM;

    logic signed [PHASE_BITS-1:0] previous_phase;
    logic have_previous;
    logic [COUNT_BITS-1:0] accepted_count;
    logic signed [63:0] integrator;

    function automatic logic signed [TRIM_BITS-1:0] trim_clip(input logic signed [63:0] value);
        if (value > MAX_TRIM_64)
            trim_clip = MAX_TRIM;
        else if (value < MIN_TRIM_64)
            trim_clip = -MAX_TRIM;
        else
            trim_clip = value[TRIM_BITS-1:0];
    endfunction

    function automatic logic signed [63:0] abs64(input logic signed [63:0] value);
        abs64 = value < 0 ? -value : value;
    endfunction

    always_ff @(posedge clk) begin : discipline_process
        logic signed [63:0] phase64, delta64, raw_frequency;
        logic signed [63:0] estimate_next, i_delta, integrator_candidate;
        logic signed [63:0] proportional, requested, bounded_request;
        logic signed [63:0] step;
        logic quality_ok, phase_ok, delta_ok, accepted;

        if (rst) begin
            estimated_offset <= '0;
            trim_inc <= '0;
            frequency_locked <= 1'b0;
            measurement_rejected <= 1'b0;
            measurement_age <= {AGE_BITS{1'b1}};
            previous_phase <= '0;
            have_previous <= 1'b0;
            accepted_count <= '0;
            integrator <= '0;
        end else begin
            measurement_rejected <= 1'b0;
            if (measurement_ce) begin
                if (measurement_age != {AGE_BITS{1'b1}})
                    measurement_age <= measurement_age + 1'b1;

                phase64 = $signed(phase_error);
                delta64 = phase64 - $signed(previous_phase);
                quality_ok = measurement_quality >=
                             (frequency_locked ? TRACK_QUALITY_MIN : ACQ_QUALITY_MIN);
                phase_ok = abs64(phase64) <= OUTLIER_LIMIT;
                delta_ok = !have_previous || (abs64(delta64) <= DELTA_LIMIT);
                accepted = measurement_valid && quality_ok && phase_ok && delta_ok;

                if (!accepted) begin
                    // Missing data enters holdover silently; present but unsafe
                    // data is explicitly reported as rejected.
                    measurement_rejected <= measurement_valid;
                    if (measurement_age >= HOLDOVER_AGE-1) begin
                        frequency_locked <= 1'b0;
                        accepted_count <= '0;
                    end
                    // trim_inc and the integrator intentionally hold here.
                end else begin
                    measurement_age <= '0;
                    previous_phase <= phase_error;
                    have_previous <= 1'b1;

                    // The gain and estimator constants are parameters.  Keeping
                    // them as compile-time constants on each branch of the
                    // frequency_locked test -- rather than selecting them into a
                    // variable first -- avoids inferring a general 18x18
                    // multiplier and a barrel shifter on the critical path
                    // (see docs/37-timing-closure-plan.md).  The selected value
                    // and the arithmetic are otherwise unchanged.
                    estimate_next = $signed(estimated_offset);
                    if (have_previous) begin
                        raw_frequency = (delta64 * PHASE_TO_TRIM) >>> PHASE_FRAC_BITS;
                        if (frequency_locked)
                            estimate_next = $signed(estimated_offset) +
                                            ((raw_frequency - $signed(estimated_offset)) >>> TRACK_EST_SHIFT);
                        else
                            estimate_next = $signed(estimated_offset) +
                                            ((raw_frequency - $signed(estimated_offset)) >>> ACQ_EST_SHIFT);
                    end
                    estimated_offset <= trim_clip(estimate_next);

                    if (frequency_locked) begin
                        proportional = (phase64 * TRACK_KP) >>> PHASE_FRAC_BITS;
                        i_delta = (phase64 * TRACK_KI) >>> PHASE_FRAC_BITS;
                    end else begin
                        proportional = (phase64 * ACQ_KP) >>> PHASE_FRAC_BITS;
                        i_delta = (phase64 * ACQ_KI) >>> PHASE_FRAC_BITS;
                    end
                    integrator_candidate = integrator + i_delta;
                    requested = estimate_next + integrator_candidate + proportional;

                    // Conditional integration is anti-windup: when saturated,
                    // retain only an update which drives back toward the range.
                    if (((requested > MAX_TRIM_64) && (i_delta > 0)) ||
                        ((requested < MIN_TRIM_64) && (i_delta < 0))) begin
                        integrator_candidate = integrator;
                        requested = estimate_next + integrator + proportional;
                    end
                    if (requested > MAX_TRIM_64)
                        bounded_request = MAX_TRIM_64;
                    else if (requested < MIN_TRIM_64)
                        bounded_request = MIN_TRIM_64;
                    else
                        bounded_request = requested;
                    integrator <= integrator_candidate;

                    // Slew limiting also makes holdover recovery bumpless.
                    step = bounded_request - $signed(trim_inc);
                    if (step > MAX_TRIM_STEP)
                        trim_inc <= trim_clip($signed(trim_inc) + MAX_TRIM_STEP);
                    else if (step < -MAX_TRIM_STEP)
                        trim_inc <= trim_clip($signed(trim_inc) - MAX_TRIM_STEP);
                    else
                        trim_inc <= trim_clip(bounded_request);

                    if (!frequency_locked) begin
                        if ((LOCK_COUNT <= 1) || (accepted_count >= LOCK_COUNT-2)) begin
                            frequency_locked <= 1'b1;
                            accepted_count <= accepted_count;
                        end else
                            accepted_count <= accepted_count + 1'b1;
                    end
                end
            end
        end
    end

    initial begin
        if (PHASE_BITS < 2 || PHASE_FRAC_BITS < 2 || PHASE_FRAC_BITS >= PHASE_BITS)
            $error("frequency_discipline: invalid phase format");
        if (TRIM_BITS < 3 || MAX_TRIM < 1 || MAX_TRIM_STEP < 1 || MAX_TRIM_STEP > MAX_TRIM)
            $error("frequency_discipline: invalid trim limits");
        if (LOCK_COUNT < 1 || HOLDOVER_AGE < 1 || ACQ_EST_SHIFT < 0 || TRACK_EST_SHIFT < 0)
            $error("frequency_discipline: invalid loop parameters");
    end
endmodule
