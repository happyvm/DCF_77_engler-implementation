// SPDX-License-Identifier: MIT
// Engeler Goertzel bank with carrier-relative AM and PM observables.
//
// The dot and cross products rotate the AM/PM bins into the carrier frame
// without first calculating an angle:
//   AM raw = AM . carrier
//   PM raw = PM x carrier
// Both are intentionally unnormalised soft metrics. Normalisation and output
// saturation belong after SNR/range measurements with reference vectors.

module engeler_observables #(
    parameter int SAMPLE_BITS = 14,
    parameter int STATE_BITS = 32,
    // Bank scaling constants, exposed so a time-compressed simulation can
    // widen the bins in proportion to a shortened second; hardware keeps
    // the bank's own defaults.
    parameter logic signed [18:0] CARRIER_SCALE = 19'sd131059,
    parameter logic signed [18:0] AM_SCALE      = 19'sd130993,
    parameter logic signed [18:0] PM_SCALE      = 19'sd126157
) (
    input  logic clk,
    input  logic rst,
    input  logic sample_ce,
    input  logic signed [SAMPLE_BITS-1:0] sample,
    output logic signed [STATE_BITS:0] carrier_real,
    output logic signed [STATE_BITS:0] carrier_imag,
    output logic signed [(2*STATE_BITS)+2:0] am_inphase_raw,
    output logic signed [(2*STATE_BITS)+2:0] pm_quadrature_raw,
    output logic observable_valid,
    output logic overflow
);

    localparam int COMPLEX_BITS = STATE_BITS + 1;
    localparam int PRODUCT_BITS = 2 * COMPLEX_BITS;

    logic signed [STATE_BITS-1:0] carrier_s1, carrier_s2;
    logic signed [STATE_BITS-1:0] am_s1, am_s2;
    logic signed [STATE_BITS-1:0] pm_s1, pm_s2;
    logic signed [STATE_BITS:0] am_real, am_imag;
    logic signed [STATE_BITS:0] pm_real, pm_imag;
    logic cycle_valid;
    logic signed [PRODUCT_BITS-1:0] am_rr, am_ii;
    logic signed [PRODUCT_BITS-1:0] pm_ir, pm_ri;

    engeler_goertzel_bank #(
        .SAMPLE_BITS(SAMPLE_BITS), .STATE_BITS(STATE_BITS),
        .CARRIER_SCALE(CARRIER_SCALE), .AM_SCALE(AM_SCALE), .PM_SCALE(PM_SCALE)
    ) detector_i (
        .clk(clk), .rst(rst), .sample_ce(sample_ce), .sample(sample),
        .carrier_s1(carrier_s1), .carrier_s2(carrier_s2),
        .am_s1(am_s1), .am_s2(am_s2), .pm_s1(pm_s1), .pm_s2(pm_s2),
        .cycle_valid(cycle_valid), .overflow(overflow)
    );

    goertzel_complex_12 #(.STATE_BITS(STATE_BITS)) carrier_complex_i (
        .state_1(carrier_s1), .state_2(carrier_s2),
        .bin_real(carrier_real), .bin_imag(carrier_imag)
    );

    goertzel_complex_12 #(.STATE_BITS(STATE_BITS)) am_complex_i (
        .state_1(am_s1), .state_2(am_s2),
        .bin_real(am_real), .bin_imag(am_imag)
    );

    goertzel_complex_12 #(.STATE_BITS(STATE_BITS)) pm_complex_i (
        .state_1(pm_s1), .state_2(pm_s2),
        .bin_real(pm_real), .bin_imag(pm_imag)
    );

    always_comb begin
        am_rr = am_real * carrier_real;
        am_ii = am_imag * carrier_imag;
        pm_ir = pm_imag * carrier_real;
        pm_ri = pm_real * carrier_imag;
        am_inphase_raw =
            {am_rr[PRODUCT_BITS-1], am_rr} + {am_ii[PRODUCT_BITS-1], am_ii};
        pm_quadrature_raw =
            {pm_ir[PRODUCT_BITS-1], pm_ir} - {pm_ri[PRODUCT_BITS-1], pm_ri};
    end

    // Register validity so the combinational observables have settled after
    // the detector states are updated on cycle_valid.
    always_ff @(posedge clk) begin
        if (rst)
            observable_valid <= 1'b0;
        else
            observable_valid <= cycle_valid;
    end

endmodule
