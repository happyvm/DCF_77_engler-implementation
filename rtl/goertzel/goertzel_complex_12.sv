// SPDX-License-Identifier: MIT
// Convert the two final Goertzel states into one complex DFT-bin value.
//
// For w = 2*pi/12:
//   real = s1 - cos(w)*s2
//   imag = sin(w)*s2
// cos(pi/6) and sin(pi/6) are represented in Q1.17. Outputs retain one guard
// bit. The sign of imag follows the exp(-j*w*n) DFT convention used here.

module goertzel_complex_12 #(
    parameter int STATE_BITS = 32,
    parameter int COEFF_BITS = 19,
    parameter int COEFF_FRAC = 17,
    parameter logic signed [COEFF_BITS-1:0] COS_COEFF = 19'sd113512,
    parameter logic signed [COEFF_BITS-1:0] SIN_COEFF = 19'sd65536
) (
    input  logic signed [STATE_BITS-1:0] state_1,
    input  logic signed [STATE_BITS-1:0] state_2,
    output logic signed [STATE_BITS:0] bin_real,
    output logic signed [STATE_BITS:0] bin_imag
);

    localparam int PRODUCT_BITS = STATE_BITS + COEFF_BITS;

    logic signed [PRODUCT_BITS-1:0] cos_product;
    logic signed [PRODUCT_BITS-1:0] sin_product;
    logic signed [PRODUCT_BITS-1:0] cos_scaled;
    logic signed [PRODUCT_BITS-1:0] sin_scaled;

    always_comb begin
        cos_product = state_2 * COS_COEFF;
        sin_product = state_2 * SIN_COEFF;
        cos_scaled = cos_product >>> COEFF_FRAC;
        sin_scaled = sin_product >>> COEFF_FRAC;

        bin_real = {state_1[STATE_BITS-1], state_1}
                 - cos_scaled[STATE_BITS:0];
        bin_imag = sin_scaled[STATE_BITS:0];
    end

    initial begin
        if (STATE_BITS < 2 || COEFF_BITS <= COEFF_FRAC)
            $error("goertzel_complex_12: invalid fixed-point widths");
    end

endmodule
