// SPDX-License-Identifier: MIT
//
// Fractional ADC sample scheduler for the DCF77 receiver.
//
// The FPGA system clock remains fixed.  ADC conversion events are generated
// by phase-accumulator overflow.  A slow carrier-discipline loop may adjust
// trim_inc without touching the FPGA PLL.
//
// Default design point:
//   clk_sys      = 125 MHz
//   PHASE_BITS   = 40
//   NOMINAL_INC  = round(2^40 * 930 kHz / 125 MHz)
//                = 8_180_366_511
//
// One trim_inc count is about 0.000122 ppm at the default frequencies.
// About 8,180 trim counts correspond to 1 ppm.
//
// This module is intentionally vendor-neutral.  ECP5-specific PLL logic
// belongs in rtl/ecp5/, not here.

module sample_scheduler #(
    parameter integer PHASE_BITS = 40,
    parameter [PHASE_BITS-1:0] NOMINAL_INC = 40'd8180366511,
    parameter integer TRIM_BITS = 24
) (
    input  wire                         clk,
    input  wire                         rst,

    // Signed correction in accumulator-increment LSBs.
    // Positive trim makes sample events slightly faster.
    input  wire signed [TRIM_BITS-1:0] trim_inc,

    // One clk-wide pulse for each requested ADC conversion event.
    output reg                          sample_ce,

    // Debug/verification visibility.  This is not required by the ADC.
    output wire [PHASE_BITS-1:0]        sample_phase
);

    reg [PHASE_BITS-1:0] phase_acc;

    // Sign-extend trim_inc to the accumulator carry width.  Two's-complement
    // modular addition gives NOMINAL_INC + signed trim while preserving the
    // carry bit used as the sample event.
    wire [PHASE_BITS:0] trim_ext = {
        {(PHASE_BITS + 1 - TRIM_BITS){trim_inc[TRIM_BITS-1]}},
        trim_inc
    };

    wire [PHASE_BITS:0] increment_ext =
        {1'b0, NOMINAL_INC} + trim_ext;

    wire [PHASE_BITS:0] phase_sum =
        {1'b0, phase_acc} + increment_ext;

    wire sample_fire = phase_sum[PHASE_BITS];

    always @(posedge clk) begin
        if (rst) begin
            phase_acc <= {PHASE_BITS{1'b0}};
            sample_ce <= 1'b0;
        end else begin
            phase_acc <= phase_sum[PHASE_BITS-1:0];
            sample_ce <= sample_fire;
        end
    end

    assign sample_phase = phase_acc;

endmodule
