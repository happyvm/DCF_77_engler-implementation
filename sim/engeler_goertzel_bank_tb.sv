`timescale 1ns/1ps

module engeler_goertzel_bank_tb;
    logic clk = 0;
    logic rst = 1;
    logic sample_ce = 0;
    logic signed [13:0] sample = 0;
    logic signed [31:0] carrier_s1, carrier_s2;
    logic signed [31:0] am_s1, am_s2;
    logic signed [31:0] pm_s1, pm_s2;
    logic cycle_valid;
    logic overflow;
    integer sample_index;
    integer valid_count = 0;

    engeler_goertzel_bank dut (.*);
    always #5 clk = ~clk;

    function automatic logic signed [13:0] carrier_sample(input integer phase);
        case (phase)
            0: carrier_sample = 0;
            1: carrier_sample = 500;
            2: carrier_sample = 866;
            3: carrier_sample = 1000;
            4: carrier_sample = 866;
            5: carrier_sample = 500;
            6: carrier_sample = 0;
            7: carrier_sample = -500;
            8: carrier_sample = -866;
            9: carrier_sample = -1000;
            10: carrier_sample = -866;
            default: carrier_sample = -500;
        endcase
    endfunction

    always @(posedge clk)
        if (cycle_valid)
            valid_count = valid_count + 1;

    initial begin
        repeat (2) @(posedge clk);
        rst <= 0;

        for (sample_index = 0; sample_index < 48; sample_index = sample_index + 1) begin
            sample <= carrier_sample(sample_index % 12);
            sample_ce <= 1;
            @(posedge clk);
            sample_ce <= 0;
            @(posedge clk);
        end
        #1;

        if (valid_count != 4)
            $fatal(1, "cycle_valid count mismatch: %0d", valid_count);
        if (carrier_s1 !== -32'sd47995 || carrier_s2 !== -32'sd41565)
            $fatal(1, "carrier state mismatch: %0d %0d", carrier_s1, carrier_s2);
        if (am_s1 !== -32'sd47934 || am_s2 !== -32'sd41514)
            $fatal(1, "AM state mismatch: %0d %0d", am_s1, am_s2);
        if (pm_s1 !== -32'sd43673 || pm_s2 !== -32'sd37825)
            $fatal(1, "PM state mismatch: %0d %0d", pm_s1, pm_s2);
        if (overflow)
            $fatal(1, "unexpected resonator saturation");

        $display("engeler_goertzel_bank_tb: PASS");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "timeout");
    end
endmodule
