// SPDX-License-Identifier: MIT
// Complete single-hypothesis DCF77 PM code correlator.

module engeler_pm_correlator #(
    parameter int SOFT_BITS = 24,
    parameter int ACC_BITS = SOFT_BITS + 10
) (
    input  logic clk,
    input  logic rst,
    input  logic reset_cycle,
    input  logic chip_ce,
    input  logic signed [SOFT_BITS-1:0] pm_soft,
    output logic signed [ACC_BITS-1:0] correlation,
    output logic correlation_valid,
    output logic [8:0] chip_index
);

    logic prn_chip;
    logic unused_inverted;
    logic unused_cycle_done;

    dcf77_prn_generator generator_i (
        .clk(clk), .rst(rst), .reset_cycle(reset_cycle), .chip_ce(chip_ce),
        .prn_chip(prn_chip), .prn_chip_inverted(unused_inverted),
        .chip_index(chip_index), .cycle_done(unused_cycle_done)
    );

    pm_prn_correlator #(.SOFT_BITS(SOFT_BITS), .ACC_BITS(ACC_BITS)) correlator_i (
        .clk(clk), .rst(rst), .reset_cycle(reset_cycle), .chip_ce(chip_ce),
        .prn_chip(prn_chip), .chip_index(chip_index), .pm_soft(pm_soft),
        .correlation(correlation), .correlation_valid(correlation_valid)
    );

endmodule
