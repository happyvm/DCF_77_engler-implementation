`timescale 1ns/1ps
module engeler_pm_pipeline_tb;
    logic clk = 0, rst = 1, second_ce = 0, carrier_ce = 0;
    logic signed [15:0] pm_observable = 0;
    // CHIP_SOFT_BITS must not exceed pm_chip_integrator's internal
    // SUM_BITS (OBSERVABLE_BITS + clog2(120) = 16 + 7 = 23 here); 16
    // keeps ample headroom for this test's per-chip sums of +-1200.
    logic signed [25:0] correlation;
    logic correlation_valid, prn_active, prn_done;
    integer carrier_cycle;
    integer done_count = 0;

    engeler_pm_pipeline #(
        .OBSERVABLE_BITS(16), .CHIP_SOFT_BITS(16), .OUTPUT_SHIFT(0)
    ) dut (.*);
    always #5 clk = ~clk;
    always @(posedge clk)
        if (prn_done) done_count = done_count + 1;

    // Independent reference model of the 9-stage Galois PRN generator
    // (rtl/pm/dcf77_prn_generator.sv). The DUT only learns a chip
    // boundary has passed one full clock cycle after
    // pm_chip_integrator's own accumulator window resets (chip_valid is
    // a registered pulse consumed by a second always_ff block one edge
    // later), so peeking the DUT's live prn_chip to build pm_observable
    // raced that boundary and fed the wrong polarity for the first
    // sample of every chip whose polarity differs from the previous
    // one. Tracking the same LFSR locally, on our own schedule, removes
    // the race.
    localparam integer PRN_START_CYCLE = 15_500;
    localparam integer CYCLES_PER_CHIP = 120;
    logic [8:0] ref_lfsr;
    integer ref_sample_in_chip;

    function automatic logic [8:0] next_ref_lfsr(input logic [8:0] l);
        logic [8:0] shifted;
        begin
            shifted = {1'b0, l[8:1]};
            if (l[0] || (shifted == 9'b0))
                shifted = shifted ^ 9'h110;
            next_ref_lfsr = shifted;
        end
    endfunction

    initial begin
        repeat (2) @(posedge clk);
        rst <= 0; second_ce <= 1;
        @(posedge clk); second_ce <= 0;
        ref_lfsr = '0;
        ref_sample_in_chip = 0;
        for (carrier_cycle = 0; carrier_cycle < 76940; carrier_cycle = carrier_cycle + 1) begin
            if (carrier_cycle >= PRN_START_CYCLE) begin
                if (ref_sample_in_chip == CYCLES_PER_CHIP) begin
                    ref_lfsr = next_ref_lfsr(ref_lfsr);
                    ref_sample_in_chip = 0;
                end
                pm_observable <= ref_lfsr[0] ? 16'sd10 : -16'sd10;
                ref_sample_in_chip = ref_sample_in_chip + 1;
            end else begin
                pm_observable <= -16'sd10;
            end
            carrier_ce <= 1; @(posedge clk);
            carrier_ce <= 0; @(posedge clk);
        end
        #1;
        if (!correlation_valid || correlation !== 26'sd614400)
            $fatal(1, "pipeline correlation mismatch: valid=%0b score=%0d",
                   correlation_valid, correlation);
        if (done_count != 1 || prn_active)
            $fatal(1, "PRN interval completion mismatch");
        $display("engeler_pm_pipeline_tb: PASS");
        $finish;
    end

    initial begin
        #3000000; $fatal(1, "timeout");
    end
endmodule
