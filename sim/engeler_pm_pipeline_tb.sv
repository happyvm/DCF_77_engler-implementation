`timescale 1ns/1ps
module engeler_pm_pipeline_tb;
    logic clk = 0, rst = 1, second_ce = 0, carrier_ce = 0;
    logic signed [15:0] pm_observable = 0;
    logic signed [33:0] correlation;
    logic correlation_valid, prn_active, prn_done;
    integer carrier_cycle;
    integer done_count = 0;

    engeler_pm_pipeline #(
        .OBSERVABLE_BITS(16), .CHIP_SOFT_BITS(24), .OUTPUT_SHIFT(0)
    ) dut (.*);
    always #5 clk = ~clk;
    always @(posedge clk)
        if (prn_done) done_count = done_count + 1;

    initial begin
        repeat (2) @(posedge clk);
        rst <= 0; second_ce <= 1;
        @(posedge clk); second_ce <= 0;
        for (carrier_cycle = 0; carrier_cycle < 76940; carrier_cycle = carrier_cycle + 1) begin
            pm_observable <= dut.correlator_i.prn_chip ? 16'sd10 : -16'sd10;
            carrier_ce <= 1; @(posedge clk);
            carrier_ce <= 0; @(posedge clk);
        end
        #1;
        if (!correlation_valid || correlation !== 34'sd614400)
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
