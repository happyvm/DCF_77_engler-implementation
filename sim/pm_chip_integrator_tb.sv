`timescale 1ns/1ps
module pm_chip_integrator_tb;
    logic clk = 0, rst = 1, second_ce = 0, carrier_ce = 0;
    logic signed [15:0] pm_observable = 16'sd10;
    // OUTPUT_BITS must not exceed the module's internal SUM_BITS
    // (INPUT_BITS + clog2(CYCLES_PER_CHIP) = 16 + 2 = 18 here); 16 keeps
    // ample headroom for this test's chip sum of 40.
    logic signed [15:0] chip_soft;
    logic chip_valid, prn_cycle_reset, prn_active, prn_done;
    logic [4:0] carrier_position;
    integer cycle, valid_count = 0, done_count = 0;

    pm_chip_integrator #(
        .INPUT_BITS(16), .OUTPUT_BITS(16), .OUTPUT_SHIFT(0),
        .SECOND_CYCLES(20), .PRN_START_CYCLE(3),
        .CYCLES_PER_CHIP(4), .CHIP_COUNT(3)
    ) dut (.*);
    always #5 clk = ~clk;
    always @(posedge clk) begin
        if (chip_valid) begin
            valid_count = valid_count + 1;
            if (chip_soft !== 16'sd40)
                $fatal(1, "chip sum mismatch: %0d", chip_soft);
        end
        if (prn_done) done_count = done_count + 1;
    end

    initial begin
        repeat (2) @(posedge clk);
        rst <= 0; second_ce <= 1;
        @(posedge clk); second_ce <= 0;
        for (cycle = 0; cycle < 20; cycle = cycle + 1) begin
            carrier_ce <= 1; @(posedge clk);
            carrier_ce <= 0; @(posedge clk);
        end
        #1;
        if (valid_count != 3 || done_count != 1)
            $fatal(1, "chip cadence mismatch: valid=%0d done=%0d", valid_count, done_count);
        if (prn_active || carrier_position != 0)
            $fatal(1, "second wrap state mismatch");
        $display("pm_chip_integrator_tb: PASS");
        $finish;
    end
endmodule
