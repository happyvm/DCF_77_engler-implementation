// SPDX-License-Identifier: MIT
// Three periodically-scaled resonators used by the Engeler detector.
//
// At Fs = 930 kS/s and Fc = 77.5 kHz there are exactly 12 samples per carrier
// cycle and 2*cos(2*pi/12) = sqrt(3). Scaling constants are Q1.17 estimates
// derived from B_3dB ~= 0.32*(1-k)*Fc. The carrier value is intentionally a
// replaceable initial value; the future clock loop will make it adaptive.

module engeler_goertzel_bank #(
    parameter int SAMPLE_BITS = 14,
    parameter int STATE_BITS = 32,
    // Carrier-cycle length; exposed so a formal harness can shrink the period
    // (the resonators' multi-cycle sequencer makes the full default of 12
    // samples per cycle too deep for a bounded proof).  Production keeps 12.
    parameter int CYCLE_SAMPLES = 12,
    parameter logic signed [18:0] CARRIER_SCALE = 19'sd131059,
    parameter logic signed [18:0] AM_SCALE      = 19'sd130993,
    parameter logic signed [18:0] PM_SCALE      = 19'sd126157
) (
    input  logic clk,
    input  logic rst,
    input  logic sample_ce,
    input  logic signed [SAMPLE_BITS-1:0] sample,
    output logic signed [STATE_BITS-1:0] carrier_s1,
    output logic signed [STATE_BITS-1:0] carrier_s2,
    output logic signed [STATE_BITS-1:0] am_s1,
    output logic signed [STATE_BITS-1:0] am_s2,
    output logic signed [STATE_BITS-1:0] pm_s1,
    output logic signed [STATE_BITS-1:0] pm_s2,
    output logic cycle_valid,
    output logic overflow,
    // Sequencer handshake forwarded from the three resonators. They share
    // one sample_ce and stay in lockstep, so a single busy/done pair is
    // enough (busy = carrier busy = am busy = pm busy).
    output logic busy,
    output logic done
);

    logic carrier_valid, am_valid, pm_valid;
    logic carrier_overflow, am_overflow, pm_overflow;
    logic carrier_busy, carrier_done;
    logic am_busy, am_done, pm_busy, pm_done;

    goertzel_resonator #(
        .SAMPLE_BITS(SAMPLE_BITS), .STATE_BITS(STATE_BITS),
        .CYCLE_SAMPLES(CYCLE_SAMPLES), .SCALE_COEFF(CARRIER_SCALE)
    ) carrier_i (
        .clk(clk), .rst(rst), .sample_ce(sample_ce), .sample(sample),
        .state_1(carrier_s1), .state_2(carrier_s2),
        .cycle_valid(carrier_valid), .overflow(carrier_overflow),
        .busy(carrier_busy), .done(carrier_done)
    );

    goertzel_resonator #(
        .SAMPLE_BITS(SAMPLE_BITS), .STATE_BITS(STATE_BITS),
        .CYCLE_SAMPLES(CYCLE_SAMPLES), .SCALE_COEFF(AM_SCALE)
    ) am_i (
        .clk(clk), .rst(rst), .sample_ce(sample_ce), .sample(sample),
        .state_1(am_s1), .state_2(am_s2),
        .cycle_valid(am_valid), .overflow(am_overflow),
        .busy(am_busy), .done(am_done)
    );

    goertzel_resonator #(
        .SAMPLE_BITS(SAMPLE_BITS), .STATE_BITS(STATE_BITS),
        .CYCLE_SAMPLES(CYCLE_SAMPLES), .SCALE_COEFF(PM_SCALE)
    ) pm_i (
        .clk(clk), .rst(rst), .sample_ce(sample_ce), .sample(sample),
        .state_1(pm_s1), .state_2(pm_s2),
        .cycle_valid(pm_valid), .overflow(pm_overflow),
        .busy(pm_busy), .done(pm_done)
    );

    assign cycle_valid = carrier_valid & am_valid & pm_valid;
    assign overflow = carrier_overflow | am_overflow | pm_overflow;
    // The three sequencers share sample_ce and stay in lockstep, so each
    // channel's busy/done tracks the others'; folding them with OR keeps
    // every handshake signal used (and stays correct even if they diverge).
    assign busy = carrier_busy | am_busy | pm_busy;
    assign done = carrier_done | am_done | pm_done;

endmodule
