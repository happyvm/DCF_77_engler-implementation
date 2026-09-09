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
    // Combinational bin rotations (state -> complex), then a three-stage
    // register pipeline: bins, products, sums. Each stage holds one
    // multiply or one add of the dot/cross products, so no clock has to
    // absorb the coefficient multiply, the 33x33 product and the 67-bit
    // sum back to back (that chain alone was ~40 ns on the ECP5).
    logic signed [STATE_BITS:0] am_real, am_imag;
    logic signed [STATE_BITS:0] pm_real, pm_imag;
    logic signed [STATE_BITS:0] carrier_real_c, carrier_imag_c;
    logic signed [STATE_BITS:0] am_real_q, am_imag_q;
    logic signed [STATE_BITS:0] pm_real_q, pm_imag_q;
    logic cycle_valid;
    logic signed [PRODUCT_BITS-1:0] am_rr, am_ii;
    logic signed [PRODUCT_BITS-1:0] pm_ir, pm_ri;
    logic valid_s1, valid_s2;

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
        .bin_real(carrier_real_c), .bin_imag(carrier_imag_c)
    );

    goertzel_complex_12 #(.STATE_BITS(STATE_BITS)) am_complex_i (
        .state_1(am_s1), .state_2(am_s2),
        .bin_real(am_real), .bin_imag(am_imag)
    );

    goertzel_complex_12 #(.STATE_BITS(STATE_BITS)) pm_complex_i (
        .state_1(pm_s1), .state_2(pm_s2),
        .bin_real(pm_real), .bin_imag(pm_imag)
    );

    // observable_valid marks am_inphase_raw/pm_quadrature_raw three clocks
    // after the bank's cycle_valid (bins, products, sums). The pipeline
    // runs every clock, so it is correct for any sample_ce cadence,
    // including one sample per clock in simulation. carrier_real/imag are
    // the stage-1 registers (two clocks ahead of observable_valid); they
    // are diagnostic outputs, not sampled against observable_valid.
    always_ff @(posedge clk) begin
        if (rst) begin
            am_real_q <= '0; am_imag_q <= '0; pm_real_q <= '0; pm_imag_q <= '0;
            carrier_real <= '0; carrier_imag <= '0;
            am_rr <= '0; am_ii <= '0; pm_ir <= '0; pm_ri <= '0;
            am_inphase_raw <= '0; pm_quadrature_raw <= '0;
            valid_s1 <= 1'b0; valid_s2 <= 1'b0; observable_valid <= 1'b0;
        end else begin
            // Stage 1: complex bins.
            am_real_q <= am_real; am_imag_q <= am_imag;
            pm_real_q <= pm_real; pm_imag_q <= pm_imag;
            carrier_real <= carrier_real_c; carrier_imag <= carrier_imag_c;
            valid_s1 <= cycle_valid;
            // Stage 2: the four products.
            am_rr <= am_real_q * carrier_real;
            am_ii <= am_imag_q * carrier_imag;
            pm_ir <= pm_imag_q * carrier_real;
            pm_ri <= pm_real_q * carrier_imag;
            valid_s2 <= valid_s1;
            // Stage 3: dot and cross products.
            am_inphase_raw <=
                {am_rr[PRODUCT_BITS-1], am_rr} + {am_ii[PRODUCT_BITS-1], am_ii};
            pm_quadrature_raw <=
                {pm_ir[PRODUCT_BITS-1], pm_ir} - {pm_ri[PRODUCT_BITS-1], pm_ri};
            observable_valid <= valid_s2;
        end
    end

endmodule
