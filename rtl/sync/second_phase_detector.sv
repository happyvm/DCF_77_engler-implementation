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
    parameter int QUALITY_BITS = 8
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
    logic signed [INPUT_BITS:0] envelope_magnitude, previous_magnitude;
    logic am_edge;
    logic phase_measurement_seen;
    logic signed [1:0] slew;
    logic signed [POS_BITS:0] am_error;

    always_comb begin
        if (am_envelope[INPUT_BITS-1])
            envelope_magnitude = -$signed({am_envelope[INPUT_BITS-1], am_envelope});
        else
            envelope_magnitude = $signed({1'b0, am_envelope});
        am_edge = carrier_ce &&
                  (previous_magnitude > envelope_magnitude) &&
                  ((previous_magnitude - envelope_magnitude) >= AM_EDGE_THRESHOLD);
        if (position <= TRACK_WINDOW)
            am_error = $signed({1'b0, position});
        else
            am_error = $signed({1'b0, position}) - SECOND_CYCLES;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= SEARCH; position <= '0; search_spacing <= '0;
            search_hits <= '0; missed_seconds <= '0; first_edge <= 1'b0;
            previous_magnitude <= '0; second_ce <= 1'b0;
            phase_error_cycles <= '0; quality <= '0;
            measurement_outlier <= 1'b0; measurement_age <= {AGE_BITS{1'b1}};
            phase_measurement_seen <= 1'b0; slew <= '0;
        end else begin
            second_ce <= 1'b0;
            measurement_outlier <= 1'b0;
            if (carrier_ce)
                previous_magnitude <= envelope_magnitude;

            if (state == SEARCH) begin
                if (carrier_ce && first_edge)
                    search_spacing <= search_spacing + 1'b1;
                if (am_edge) begin
                    if (!first_edge) begin
                        first_edge <= 1'b1;
                        search_spacing <= '0;
                        search_hits <= 1;
                    end else if ((search_spacing >= SECOND_CYCLES-SEARCH_TOLERANCE) &&
                                 (search_spacing <= SECOND_CYCLES+SEARCH_TOLERANCE)) begin
                        search_spacing <= '0;
                        if (search_hits >= ACQUIRE_HITS-1) begin
                            state <= TRACK; position <= '0; second_ce <= 1'b1;
                            measurement_age <= '0; quality <= {{(QUALITY_BITS-1){1'b0}},1'b1};
                            phase_measurement_seen <= 1'b1; missed_seconds <= '0;
                        end else search_hits <= search_hits + 1'b1;
                    end else begin
                        search_spacing <= '0; search_hits <= 1;
                    end
                end
            end else if (carrier_ce) begin
                // One-cycle period modulation is the only permitted phase step.
                if ((slew < 0 && position == SECOND_CYCLES-2) ||
                    (slew == 0 && position == SECOND_CYCLES-1) ||
                    (slew > 0 && position == SECOND_CYCLES)) begin
                    position <= '0; second_ce <= 1'b1; slew <= '0;
                    if (measurement_age != {AGE_BITS{1'b1}})
                        measurement_age <= measurement_age + 1'b1;
                    if (!phase_measurement_seen) begin
                        if (missed_seconds < HOLDOVER_AFTER) missed_seconds <= missed_seconds + 1'b1;
                        if (missed_seconds >= HOLDOVER_AFTER-1) state <= HOLDOVER;
                        if (quality != 0) quality <= quality - 1'b1;
                    end else missed_seconds <= '0;
                    phase_measurement_seen <= 1'b0;
                end else position <= position + 1'b1;

                if (am_edge) begin
                    if ((position <= TRACK_WINDOW) || (position >= SECOND_CYCLES-TRACK_WINDOW)) begin
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
                if (($signed(pm_phase_error_cycles) <= TRACK_WINDOW) &&
                    ($signed(pm_phase_error_cycles) >= -TRACK_WINDOW)) begin
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
        if (ACQUIRE_HITS < 2 || HOLDOVER_AFTER < 1)
            $error("second_phase_detector: invalid qualification parameters");
    end
endmodule
