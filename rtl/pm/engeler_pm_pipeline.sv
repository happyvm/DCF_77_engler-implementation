// SPDX-License-Identifier: MIT
// Carrier-cycle integration plus one complete DCF77 PRN correlation.

module engeler_pm_pipeline #(
    parameter int OBSERVABLE_BITS = 67,
    parameter int CHIP_SOFT_BITS = 32,
    parameter int OUTPUT_SHIFT = 24,
    // Overridable so pm_phase_discriminator can instantiate early/late
    // taps a few carrier cycles either side of the nominal PRN start,
    // without duplicating this pipeline's wiring.
    parameter int PRN_START_CYCLE = 15_500
) (
    input  logic clk,
    input  logic rst,
    input  logic second_ce,
    input  logic carrier_ce,
    input  logic signed [OBSERVABLE_BITS-1:0] pm_observable,
    output logic signed [CHIP_SOFT_BITS+9:0] correlation,
    output logic correlation_valid,
    output logic prn_active,
    output logic prn_done
);

    logic signed [CHIP_SOFT_BITS-1:0] chip_soft;
    logic chip_valid;
    logic prn_reset;
    logic [8:0] unused_chip_index;
    logic [16:0] unused_carrier_position;

    pm_chip_integrator #(
        .INPUT_BITS(OBSERVABLE_BITS), .OUTPUT_BITS(CHIP_SOFT_BITS),
        .OUTPUT_SHIFT(OUTPUT_SHIFT), .PRN_START_CYCLE(PRN_START_CYCLE)
    ) integrator_i (
        .clk(clk), .rst(rst), .second_ce(second_ce), .carrier_ce(carrier_ce),
        .pm_observable(pm_observable), .chip_soft(chip_soft),
        .chip_valid(chip_valid), .prn_cycle_reset(prn_reset),
        .prn_active(prn_active), .prn_done(prn_done),
        .carrier_position(unused_carrier_position)
    );

    engeler_pm_correlator #(
        .SOFT_BITS(CHIP_SOFT_BITS), .ACC_BITS(CHIP_SOFT_BITS + 10)
    ) correlator_i (
        .clk(clk), .rst(rst), .reset_cycle(prn_reset), .chip_ce(chip_valid),
        .pm_soft(chip_soft), .correlation(correlation),
        .correlation_valid(correlation_valid), .chip_index(unused_chip_index)
    );

endmodule
