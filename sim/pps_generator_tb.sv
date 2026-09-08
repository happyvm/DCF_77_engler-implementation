`timescale 1ns/1ps

module pps_generator_tb;
    logic clk = 0;
    logic rst = 1;
    logic second_ce = 0;
    logic time_valid = 0;
    logic pps;
    integer high_cycles;

    pps_generator #(.PULSE_CYCLES(4)) dut (.*);
    always #5 clk = ~clk;

    initial begin
        repeat (2) @(posedge clk);
        rst <= 0;
        time_valid <= 1;
        @(posedge clk);
        second_ce <= 1;
        @(posedge clk);
        second_ce <= 0;
        #1;

        high_cycles = 0;
        while (pps) begin
            high_cycles = high_cycles + 1;
            @(posedge clk);
            #1;
        end
        if (high_cycles != 4)
            $fatal(1, "PPS width mismatch: %0d", high_cycles);

        second_ce <= 1;
        @(posedge clk);
        second_ce <= 0;
        #1;
        if (!pps)
            $fatal(1, "PPS did not start");
        time_valid <= 0;
        @(posedge clk);
        #1;
        if (pps)
            $fatal(1, "PPS remained high with invalid time");

        $display("pps_generator_tb: PASS");
        $finish;
    end
endmodule
