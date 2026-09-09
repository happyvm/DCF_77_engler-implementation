// SPDX-License-Identifier: MIT
// DCF77 second-phase acquisition and tracking in carrier-cycle coordinates.
//
// The AM notch supplies the unambiguous, coarse epoch.  Once acquired, an
// early/prompt/late PZF correlator may supply a signed sub-epoch correction.
// Corrections are deliberately slewed at no more than one carrier cycle per
// second; an RF event can therefore never insert or delete a complete second.

module second_phase_detector #(
    parameter int INPUT_BITS = 67,
    parameter int SECOND_CYCLES = 77_500,
    parameter int AM_EDGE_THRESHOLD = 1,
    parameter int SEARCH_TOLERANCE = 1_000,
    parameter int TRACK_WINDOW = 2_000,
    parameter int ACQUIRE_HITS = 2,
    parameter int HOLDOVER_AFTER = 2,
    parameter int AGE_BITS = 16,
    parameter int QUALITY_BITS = 8,
    // AM notch onset = envelope below (1 - 2^-EDGE_DROP_SHIFT) of the
    // remembered full-carrier level. DCF77 reduces the carrier to ~15%
    // (a >95% drop in the amplitude-squared observable), so 1/32 is far
    // inside the notch yet crossed only a few tens of carrier cycles
    // after the true onset given the AM bin's ~1.7k-cycle time constant.
    parameter int EDGE_DROP_SHIFT = 5,
    // Peak-hold decay: 2^15 cycles > one second, so the reference keeps
    // the full level across the 200 ms reduction yet still follows a
    // slowly fading carrier.
    parameter int REF_DECAY_SHIFT = 15
) (
    input  logic clk,
    input  logic rst,
    input  logic carrier_ce,
    input  logic signed [INPUT_BITS-1:0] am_envelope,
    // PM timing error is produced by an early/prompt/late PZF correlation.
    // Positive means that the received epoch is later than the local epoch.
    input  logic pm_measurement_valid,
    input  logic signed [$clog2(SECOND_CYCLES):0] pm_phase_error_cycles,
    input  logic [QUALITY_BITS-1:0] pm_quality,
    output logic second_ce,
    output logic signed [$clog2(SECOND_CYCLES):0] phase_error_cycles,
    output logic [QUALITY_BITS-1:0] quality,
    output logic measurement_outlier,
    output logic [AGE_BITS-1:0] measurement_age,
    output logic [1:0] state
);
    localparam logic [1:0] SEARCH = 2'd0;
    localparam logic [1:0] TRACK = 2'd1;
    localparam logic [1:0] HOLDOVER = 2'd2;
    localparam int POS_BITS = (SECOND_CYCLES <= 2) ? 1 : $clog2(SECOND_CYCLES);
    localparam int HIT_BITS = (ACQUIRE_HITS <= 1) ? 1 : $clog2(ACQUIRE_HITS + 1);
    localparam int MISS_BITS = (HOLDOVER_AFTER <= 1) ? 1 : $clog2(HOLDOVER_AFTER + 1);

    logic [POS_BITS-1:0] position, search_spacing;
    logic [HIT_BITS-1:0] search_hits;
    logic [MISS_BITS-1:0] missed_seconds;
    logic first_edge;
    logic signed [INPUT_BITS:0] envelope_magnitude;
    // Input pipeline stage: the rectified envelope and its carrier_ce are
    // registered together, so the 67-bit negate never shares a clock with
    // the level comparisons below. Everything downstream runs one clock
    // later than the raw carrier_ce; second_ce moves with it.
    logic signed [INPUT_BITS:0] magnitude_q;
    logic ce_q;
    // Slow peak-hold of the envelope magnitude (snaps up, decays with a
    // time constant of 2^REF_DECAY_SHIFT carrier cycles -- longer than a
    // second, so it still remembers the full-carrier level through the
    // 200 ms reduction) and the one-edge-per-notch arming flag.
    logic signed [INPUT_BITS:0] reference_level, reference_next;
    // Shadow registers of the levels derived from reference_level, written
    // from the same next value in the same clock, so each comparison
    // against the magnitude is one carry chain instead of a subtract
    // feeding a compare:
    //   edge_level  = ref - ref/2^EDGE_DROP_SHIFT     (notch onset)
    //   rearm_level = ref - ref/2^(EDGE_DROP_SHIFT+1) (re-arm)
    //   half_level  = ref/2                           (deep-notch witness)
    //   floor_level = ref - AM_EDGE_THRESHOLD         (absolute drop floor)
    logic signed [INPUT_BITS:0] edge_level, rearm_level, half_level, floor_level;
    logic edge_armed, notch_seen;
    logic am_edge;
    logic phase_measurement_seen;
    logic signed [1:0] slew;
    logic signed [POS_BITS:0] am_error;
    // Position at which the running second wraps: SECOND_CYCLES-1 plus the
    // one-cycle slew. Compared with >=, not ==: a measurement can flip the
    // slew from +1 to -1 after the counter has already passed the shorter
    // wrap point, and an exact match would then never fire again until the
    // counter overflowed (bounded proof formal/second_phase_detector.sby
    // found this: a second twice as long and a phase error outside the
    // tracking aperture). With >= the wrap happens on the very next carrier
    // cycle and the second is at most one cycle long or short.
    logic [POS_BITS-1:0] wrap_position;

    // Sign extension/negation relies on ordinary Verilog signed-context
    // widening rather than an explicit {sig[msb], sig} replication: this
    // project's pinned Icarus Verilog release (oss-cad-suite 2025-02-13,
    // "sorry: constant selects in always_* processes are not currently
    // supported") can silently substitute the whole parent vector for a
    // replicated bit-select mixed with a plain operand inside
    // always_comb/always_ff, corrupting the arithmetic while only
    // warning about it. Plain signed widening needs no bit-select.
    always_comb begin
        if (am_envelope[INPUT_BITS-1])
            envelope_magnitude = -((INPUT_BITS + 1)'(am_envelope));
        else
            envelope_magnitude = (INPUT_BITS + 1)'(am_envelope);
        // The envelope leaves the Goertzel AM bin as a first-order response
        // (time constant ~1.7k carrier cycles), so a notch is a long,
        // monotonic ramp rather than a step: comparing only adjacent
        // cycles would fire on every cycle of the ramp and never let the
        // one-second spacing check succeed. Instead detect the onset as
        // the first cycle the magnitude has fallen by EDGE_DROP_SHIFT
        // (1/32) of the remembered full-carrier level, and re-arm only
        // once it has climbed back above that level -- exactly one edge
        // per notch, a few tens of cycles after the true onset.
        // (ref - mag >= T) is evaluated as (mag <= ref - T) on the shadow.
        am_edge = ce_q && edge_armed &&
                  (magnitude_q < edge_level) && (magnitude_q <= floor_level);
        if (magnitude_q > reference_level)
            reference_next = magnitude_q;
        else
            reference_next = reference_level - (reference_level >>> REF_DECAY_SHIFT);
        if (position <= POS_BITS'(TRACK_WINDOW))
            am_error = $signed({1'b0, position});
        else
            am_error = $signed({1'b0, position}) - (POS_BITS + 1)'(SECOND_CYCLES);
        if (slew < 0)
            wrap_position = POS_BITS'(SECOND_CYCLES - 2);
        else if (slew > 0)
            wrap_position = POS_BITS'(SECOND_CYCLES);
        else
            wrap_position = POS_BITS'(SECOND_CYCLES - 1);
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= SEARCH; position <= '0; search_spacing <= '0;
            search_hits <= '0; missed_seconds <= '0; first_edge <= 1'b0;
            reference_level <= '0; edge_armed <= 1'b1; notch_seen <= 1'b0;
            edge_level <= '0; rearm_level <= '0; half_level <= '0;
            floor_level <= -((INPUT_BITS + 1)'(AM_EDGE_THRESHOLD));
            magnitude_q <= '0; ce_q <= 1'b0;
            second_ce <= 1'b0;
            phase_error_cycles <= '0; quality <= '0;
            measurement_outlier <= 1'b0; measurement_age <= {AGE_BITS{1'b1}};
            phase_measurement_seen <= 1'b0; slew <= '0;
        end else begin
            magnitude_q <= envelope_magnitude;
            ce_q <= carrier_ce;
            second_ce <= 1'b0;
            measurement_outlier <= 1'b0;
            if (ce_q) begin
                reference_level <= reference_next;
                edge_level <= reference_next - (reference_next >>> EDGE_DROP_SHIFT);
                rearm_level <= reference_next - (reference_next >>> (EDGE_DROP_SHIFT + 1));
                half_level <= reference_next >>> 1;
                floor_level <= reference_next - (INPUT_BITS + 1)'(AM_EDGE_THRESHOLD);
                // One edge per notch: disarm on the edge, remember that
                // the envelope really went deep (below half the reference,
                // so a shallow wobble cannot re-arm), and re-arm only once
                // it has climbed back above the edge threshold itself --
                // re-arming lower (e.g. at 3/4) would fire a second edge
                // on the rising flank, still below 31/32 of the reference.
                if (am_edge)
                    edge_armed <= 1'b0;
                if (magnitude_q < half_level)
                    notch_seen <= 1'b1;
                else if (!edge_armed && notch_seen && (magnitude_q >= rearm_level)) begin
                    edge_armed <= 1'b1;
                    notch_seen <= 1'b0;
                end
            end

            if (state == SEARCH) begin
                if (ce_q && first_edge)
                    search_spacing <= search_spacing + 1'b1;
                if (am_edge) begin
                    if (!first_edge) begin
                        first_edge <= 1'b1;
                        search_spacing <= '0;
                        search_hits <= 1;
                    end else if ((search_spacing >= POS_BITS'(SECOND_CYCLES-SEARCH_TOLERANCE)) &&
                                 (search_spacing <= POS_BITS'(SECOND_CYCLES+SEARCH_TOLERANCE))) begin
                        search_spacing <= '0;
                        if (search_hits >= HIT_BITS'(ACQUIRE_HITS-1)) begin
                            state <= TRACK; position <= '0; second_ce <= 1'b1;
                            measurement_age <= '0; quality <= {{(QUALITY_BITS-1){1'b0}},1'b1};
                            phase_measurement_seen <= 1'b1; missed_seconds <= '0;
                        end else search_hits <= search_hits + 1'b1;
                    end else begin
                        search_spacing <= '0; search_hits <= 1;
                    end
                end
            end else if (ce_q) begin
                // One-cycle period modulation is the only permitted phase step.
                if (position >= wrap_position) begin
                    position <= '0; second_ce <= 1'b1; slew <= '0;
                    if (measurement_age != {AGE_BITS{1'b1}})
                        measurement_age <= measurement_age + 1'b1;
                    if (!phase_measurement_seen) begin
                        if (missed_seconds < MISS_BITS'(HOLDOVER_AFTER)) missed_seconds <= missed_seconds + 1'b1;
                        if (missed_seconds >= MISS_BITS'(HOLDOVER_AFTER-1)) state <= HOLDOVER;
                        if (quality != 0) quality <= quality - 1'b1;
                    end else missed_seconds <= '0;
                    phase_measurement_seen <= 1'b0;
                end else position <= position + 1'b1;

                if (am_edge) begin
                    if ((position <= POS_BITS'(TRACK_WINDOW)) ||
                        (position >= POS_BITS'(SECOND_CYCLES-TRACK_WINDOW))) begin
                        phase_error_cycles <= am_error;
                        measurement_age <= '0; phase_measurement_seen <= 1'b1;
                        if (am_error > 0) slew <= 1;
                        else if (am_error < 0) slew <= -1;
                        if (quality != {QUALITY_BITS{1'b1}}) quality <= quality + 1'b1;
                        if (state == HOLDOVER) state <= TRACK;
                    end else measurement_outlier <= 1'b1;
                end
            end

            // PM/PZF refines AM only after coarse acquisition.  It is bounded
            // by the same tracking aperture and cannot reset the epoch counter.
            if ((state != SEARCH) && pm_measurement_valid) begin
                if (($signed(pm_phase_error_cycles) <= (POS_BITS + 1)'(TRACK_WINDOW)) &&
                    ($signed(pm_phase_error_cycles) >= -((POS_BITS + 1)'(TRACK_WINDOW)))) begin
                    phase_error_cycles <= pm_phase_error_cycles;
                    measurement_age <= '0; phase_measurement_seen <= 1'b1;
                    quality <= pm_quality;
                    if ($signed(pm_phase_error_cycles) > 0) slew <= 1;
                    else if ($signed(pm_phase_error_cycles) < 0) slew <= -1;
                    if (state == HOLDOVER) state <= TRACK;
                end else measurement_outlier <= 1'b1;
            end
        end
    end

    initial begin
        if (SECOND_CYCLES < 4 || TRACK_WINDOW < 1 || 2*TRACK_WINDOW >= SECOND_CYCLES)
            $error("second_phase_detector: invalid timing parameters");
        // position/search_spacing must hold SECOND_CYCLES + SEARCH_TOLERANCE
        // (and SECOND_CYCLES itself for the +1 slew); a truncated bound
        // would silently make acquisition impossible.
        if ((SECOND_CYCLES + SEARCH_TOLERANCE) >= (1 << POS_BITS))
            $error("second_phase_detector: SECOND_CYCLES + SEARCH_TOLERANCE overflows the position counter");
        if (ACQUIRE_HITS < 2 || HOLDOVER_AFTER < 1)
            $error("second_phase_detector: invalid qualification parameters");
    end
endmodule
