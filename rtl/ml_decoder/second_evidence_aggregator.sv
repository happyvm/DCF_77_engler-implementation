// SPDX-License-Identifier: MIT
// Combine one second's AM and PM soft evidence into one coherent record.
//
// am_bit_valid and pm_correlation_valid do not pulse on the same carrier
// cycle (AM resolves near 300 ms into the second, PM near the end of the
// 512-chip PRN sequence close to 1 s), so writing soft_history directly
// from either pulse alone -- or from "am_valid && pm_valid" -- either
// races the wrong evidence into the record or, since the two pulses never
// coincide, never marks a record valid at all. This module instead
// latches each channel's evidence as it arrives during the second and
// emits exactly one write, at the second boundary (second_ce), covering
// whatever was captured during the second that just ended.
module second_evidence_aggregator #(
    parameter int EVIDENCE_BITS = 16,
    parameter int QUALITY_BITS = 8
) (
    input  logic clk,
    input  logic rst,

    // second_ce marks the boundary between the second that just ended
    // (described by the emitted record below) and the next one.
    input  logic second_ce,
    input  logic [5:0] second_position,

    input  logic am_valid,
    input  logic signed [EVIDENCE_BITS-1:0] am_evidence_in,
    input  logic pm_valid,
    input  logic signed [EVIDENCE_BITS-1:0] pm_evidence_in,
    input  logic [QUALITY_BITS-1:0] quality_in,

    output logic write_valid,
    output logic signed [EVIDENCE_BITS-1:0] am_evidence,
    output logic signed [EVIDENCE_BITS-1:0] pm_evidence,
    // True only when both channels were actually observed this second;
    // a dropout on either channel still produces a record (so history
    // stays aligned to real time with no holes) but flags it unusable.
    output logic sample_valid,
    output logic [QUALITY_BITS-1:0] quality,
    output logic [5:0] second_position_out
);

    logic am_seen, pm_seen;
    logic signed [EVIDENCE_BITS-1:0] am_latched, pm_latched;

    always_ff @(posedge clk) begin
        if (rst) begin
            am_seen      <= 1'b0;
            pm_seen      <= 1'b0;
            am_latched   <= '0;
            pm_latched   <= '0;
            write_valid  <= 1'b0;
            am_evidence  <= '0;
            pm_evidence  <= '0;
            sample_valid <= 1'b0;
            quality      <= '0;
            second_position_out <= '0;
        end else begin
            write_valid <= 1'b0;

            if (am_valid) begin
                am_seen    <= 1'b1;
                am_latched <= am_evidence_in;
            end
            if (pm_valid) begin
                pm_seen    <= 1'b1;
                pm_latched <= pm_evidence_in;
            end

            if (second_ce) begin
                write_valid          <= 1'b1;
                am_evidence          <= am_seen ? am_latched : '0;
                pm_evidence          <= pm_seen ? pm_latched : '0;
                sample_valid         <= am_seen && pm_seen;
                quality              <= quality_in;
                second_position_out  <= second_position;
                am_seen <= 1'b0;
                pm_seen <= 1'b0;
            end
        end
    end

endmodule
