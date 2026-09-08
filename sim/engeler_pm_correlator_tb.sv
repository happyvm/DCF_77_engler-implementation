`timescale 1ns/1ps

module engeler_pm_correlator_tb;
    logic clk = 0;
    logic rst = 1;
    logic reset_cycle = 0;
    logic chip_ce = 0;
    logic signed [23:0] pm_soft = 0;
    logic signed [33:0] correlation;
    logic correlation_valid;
    logic [8:0] chip_index;
    integer index;
    integer valid_count = 0;
    logic signed [33:0] captured_correlation;

    engeler_pm_correlator dut (.*);
    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (correlation_valid) begin
            captured_correlation = correlation;
            valid_count = valid_count + 1;
        end
    end

    task automatic correlate(input logic inverted);
        begin
            reset_cycle <= 1;
            @(posedge clk);
            reset_cycle <= 0;
            for (index = 0; index < 512; index = index + 1) begin
                // Read the generator's current chip before advancing it.
                pm_soft <= (dut.prn_chip ^ inverted) ? 24'sd100 : -24'sd100;
                chip_ce <= 1;
                @(posedge clk);
                chip_ce <= 0;
                @(posedge clk);
            end
            #1;
            if ((!inverted && captured_correlation !== 34'sd51200) ||
                (inverted && captured_correlation !== -34'sd51200))
                $fatal(1, "correlation mismatch: %0d", captured_correlation);
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        rst <= 0;
        correlate(1'b0);
        correlate(1'b1);
        if (valid_count != 2)
            $fatal(1, "correlation_valid count mismatch: %0d", valid_count);
        $display("engeler_pm_correlator_tb: PASS");
        $finish;
    end

    initial begin
        #50000;
        $fatal(1, "timeout");
    end
endmodule
