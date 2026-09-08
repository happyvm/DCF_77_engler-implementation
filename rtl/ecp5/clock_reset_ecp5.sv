// SPDX-License-Identifier: MIT
// ECP5 clock/reset island.  All Lattice primitives are deliberately confined
// to rtl/ecp5; simulations use the portable clock bypass below.
module clock_reset_ecp5 #(
    parameter bit SIM_BYPASS = 1'b0,
    parameter int unsigned RESET_CYCLES = 16
) (
    input  logic clk_25mhz,
    input  logic ext_reset_n,
    output logic clk_125mhz,
    output logic rst
);
    logic pll_clock, pll_locked;
    localparam int RESET_BITS = (RESET_CYCLES < 2) ? 1 : $clog2(RESET_CYCLES + 1);
    logic [RESET_BITS-1:0] reset_count = '0;

    generate if (SIM_BYPASS) begin : portable_bypass
        // The testbench supplies its system clock directly on clk_25mhz.
        always_comb begin
            pll_clock = clk_25mhz;
            pll_locked = ext_reset_n;
        end
    end else begin : ecp5_pll
        wire clkfb;
        EHXPLLL #(
            .CLKI_DIV(1), .CLKFB_DIV(5), .CLKOP_DIV(5),
            .CLKOP_ENABLE("ENABLED"), .FEEDBK_PATH("INT_OP"),
            .CLKI_FREQ("25.000000"), .CLKOP_FREQ("125.000000")
        ) pll_i (
            .CLKI(clk_25mhz), .CLKFB(clkfb), .CLKINTFB(clkfb),
            .CLKOP(pll_clock), .LOCK(pll_locked),
            .RST(1'b0), .STDBY(1'b0), .PHASESEL0(1'b0),
            .PHASESEL1(1'b0), .PHASEDIR(1'b0), .PHASESTEP(1'b0),
            .PLLWAKESYNC(1'b0), .ENCLKOP(1'b0)
        );
    end endgenerate

    assign clk_125mhz = pll_clock;
    always_ff @(posedge pll_clock or negedge ext_reset_n) begin
        if (!ext_reset_n) begin reset_count <= '0; rst <= 1'b1; end
        else if (!pll_locked) begin reset_count <= '0; rst <= 1'b1; end
        else if (reset_count < RESET_CYCLES) begin
            reset_count <= reset_count + 1'b1; rst <= 1'b1;
        end else rst <= 1'b0;
    end
endmodule
