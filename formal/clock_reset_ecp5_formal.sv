// Reset synchronizer, checked with SIM_BYPASS=1 (the only configuration
// yosys can elaborate without the ECP5 EHXPLLL vendor primitive): under
// the bypass, clk_125mhz is clk_25mhz directly and pll_locked is
// ext_reset_n, so the reset-count state machine this module wraps around
// the PLL is exercised exactly as it is in every SIM_CLOCK_BYPASS testbench
// in this repository. rst is asserted immediately whenever ext_reset_n is
// low, and deasserts only after RESET_CYCLES consecutive clocks of
// ext_reset_n high -- the "wait for lock" behavior real hardware performs
// against pll_locked once the real PLL is in the loop instead of the
// bypass.
module clock_reset_ecp5_formal;
    localparam int RESET_CYCLES = 4;

    (* gclk *) logic clk_25mhz;
    (* anyseq *) logic ext_reset_n;
    logic clk_125mhz, rst;

    clock_reset_ecp5 #(.SIM_BYPASS(1'b1), .RESET_CYCLES(RESET_CYCLES)) dut (.*);

    logic past_valid = 1'b0;
    logic [2:0] locked_run = '0;

    always_ff @(posedge clk_25mhz) begin
        past_valid <= 1'b1;

        if (!ext_reset_n)
            locked_run <= '0;
        else if (locked_run != 3'(RESET_CYCLES))
            locked_run <= locked_run + 1'b1;

        if (past_valid) begin
            assert(clk_125mhz == clk_25mhz);
            if (!ext_reset_n)
                assert(rst);
            else if ($past(ext_reset_n) && $past(locked_run) < RESET_CYCLES)
                // Still counting: RESET_CYCLES full clocks have not yet
                // elapsed since ext_reset_n rose, so rst must still hold.
                assert(rst);
            else if ($past(ext_reset_n) && $past(locked_run) == RESET_CYCLES)
                // Held ext_reset_n high for RESET_CYCLES full clocks: the
                // reset counter has finished and rst is released.
                assert(!rst);
        end
    end
endmodule
