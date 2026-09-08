// SPDX-License-Identifier: MIT
//
// Pulse-per-second output driven by the disciplined one-cycle second strobe.
// The output is forced low whenever the receiver timebase is not valid.

module pps_generator #(
    parameter int unsigned PULSE_CYCLES = 12_500_000
) (
    input  logic clk,
    input  logic rst,
    input  logic second_ce,
    input  logic time_valid,
    output logic pps
);

    localparam int unsigned COUNT_W =
        (PULSE_CYCLES <= 1) ? 1 : $clog2(PULSE_CYCLES);

    logic [COUNT_W-1:0] pulse_count;

    always_ff @(posedge clk) begin
        if (rst || !time_valid) begin
            pps         <= 1'b0;
            pulse_count <= '0;
        end else if (second_ce) begin
            pps         <= 1'b1;
            pulse_count <= PULSE_CYCLES - 1;
        end else if (pps) begin
            if (pulse_count == 0) begin
                pps <= 1'b0;
            end else begin
                pulse_count <= pulse_count - 1'b1;
            end
        end
    end

    initial begin
        if (PULSE_CYCLES < 1)
            $error("pps_generator: PULSE_CYCLES must be at least one");
    end

endmodule
