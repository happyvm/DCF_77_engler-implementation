// SPDX-License-Identifier: MIT
// DCF77 512-chip phase-modulation sequence generator.
//
// This is the right-shifting Galois equivalent of the PTB nine-stage
// generator, including the auxiliary zero-state escape. The current chip is
// visible before chip_ce; chip_ce advances to the following chip.

module dcf77_prn_generator (
    input  logic clk,
    input  logic rst,
    input  logic reset_cycle,
    input  logic chip_ce,
    output logic prn_chip,
    output logic prn_chip_inverted,
    output logic [8:0] chip_index,
    output logic cycle_done
);

    localparam logic [8:0] GALOIS_MASK = 9'h110;

    logic [8:0] lfsr;
    logic [8:0] shifted_lfsr;

    assign prn_chip = lfsr[0];
    assign prn_chip_inverted = ~lfsr[0];

    always_comb begin
        shifted_lfsr = {1'b0, lfsr[8:1]};
        if (lfsr[0] || (shifted_lfsr == 0))
            shifted_lfsr = shifted_lfsr ^ GALOIS_MASK;
    end

    always_ff @(posedge clk) begin
        if (rst || reset_cycle) begin
            lfsr       <= '0;
            chip_index <= '0;
            cycle_done <= 1'b0;
        end else begin
            cycle_done <= 1'b0;
            if (chip_ce) begin
                lfsr <= shifted_lfsr;
                if (chip_index == 9'd511) begin
                    chip_index <= '0;
                    cycle_done <= 1'b1;
                end else begin
                    chip_index <= chip_index + 1'b1;
                end
            end
        end
    end

endmodule
