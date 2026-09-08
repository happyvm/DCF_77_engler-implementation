`timescale 1ns/1ps
module receiver_lock_controller_tb;
    logic clk = 0, rst = 1;
    logic qualification_valid = 0, result_consistent = 0;
    logic ml_qualified = 0, minute_qualified = 0, frequency_qualified = 0;
    logic holdover_tick = 0;
    logic time_valid, pps_valid, ml_locked, minute_locked, frequency_locked;
    logic [2:0] state_code;

    receiver_lock_controller #(
        .QUALIFICATION_ENABLED(1'b1), .ACQUIRE_RESULTS(3),
        .EXIT_FAILURES(2), .HOLDOVER_TICKS(3)
    ) dut (.*);
    always #5 clk = ~clk;

    task automatic result(input logic good);
        begin
            result_consistent = good;
            ml_qualified = good;
            minute_qualified = good;
            frequency_qualified = good;
            qualification_valid = 1;
            @(posedge clk); #1;
            qualification_valid = 0;
        end
    endtask

    task automatic tick;
        begin
            holdover_tick = 1; @(posedge clk); #1; holdover_tick = 0;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk); rst = 0; #1;
        if (state_code != 0 || pps_valid || time_valid)
            $fatal(1, "valid output asserted at reset");

        result(1);
        if (state_code != 1 || pps_valid)
            $fatal(1, "PPS asserted before acquisition qualification");
        result(1);
        if (state_code != 1 || pps_valid)
            $fatal(1, "PPS asserted before three coherent results");
        result(1);
        if (state_code != 2 || !pps_valid || !time_valid ||
            !ml_locked || !minute_locked || !frequency_locked)
            $fatal(1, "failed to enter LOCKED");

        result(0);
        if (state_code != 2 || !pps_valid)
            $fatal(1, "exit hysteresis did not tolerate one failure");
        result(1);
        result(0);
        result(0);
        if (state_code != 3 || !pps_valid)
            $fatal(1, "loss did not enter qualified HOLDOVER");

        tick(); tick();
        if (state_code != 3 || !pps_valid)
            $fatal(1, "HOLDOVER ended early");
        result(1);
        if (state_code != 2 || !pps_valid)
            $fatal(1, "qualified recovery did not restore LOCKED");

        result(0); result(0);
        tick(); tick(); tick();
        if (state_code != 0 || pps_valid || time_valid)
            $fatal(1, "expired HOLDOVER did not return to UNSYNC");
        $display("receiver_lock_controller_tb: PASS");
        $finish;
    end
endmodule
