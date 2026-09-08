// SPDX-License-Identifier: MIT
// Accumulate one signed PM soft sample against the 512-chip DCF77 sequence.
// Positive correlation means the received sequence has the configured PRN
// polarity; the inverted data hypothesis produces the opposite score.

module pm_prn_correlator #(
    parameter int SOFT_BITS = 24,
    parameter int ACC_BITS = SOFT_BITS + 10
) (
    input  logic clk,
    input  logic rst,
    input  logic reset_cycle,
    input  logic chip_ce,
    input  logic prn_chip,
    input  logic [8:0] chip_index,
    input  logic signed [SOFT_BITS-1:0] pm_soft,
    output logic signed [ACC_BITS-1:0] correlation,
    output logic correlation_valid
);

    logic signed [ACC_BITS-1:0] accumulator;
    logic signed [ACC_BITS-1:0] soft_extended;
    logic signed [ACC_BITS-1:0] signed_contribution;
    logic signed [ACC_BITS-1:0] next_accumulator;

    always_comb begin
        soft_extended = {{(ACC_BITS-SOFT_BITS){pm_soft[SOFT_BITS-1]}}, pm_soft};
        signed_contribution = prn_chip ? soft_extended : -soft_extended;
        next_accumulator = accumulator + signed_contribution;
    end

    always_ff @(posedge clk) begin
        if (rst || reset_cycle) begin
            accumulator      <= '0;
            correlation      <= '0;
            correlation_valid <= 1'b0;
        end else begin
            correlation_valid <= 1'b0;
            if (chip_ce) begin
                if (chip_index == 9'd511) begin
                    correlation       <= next_accumulator;
                    correlation_valid <= 1'b1;
                    accumulator       <= '0;
                end else begin
                    accumulator <= next_accumulator;
                end
            end
        end
    end

    initial begin
        if (SOFT_BITS < 2 || ACC_BITS < SOFT_BITS + 10)
            $error("pm_prn_correlator: accumulator is too narrow");
    end

endmodule
