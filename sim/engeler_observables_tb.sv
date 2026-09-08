`timescale 1ns/1ps

module engeler_observables_tb;
    logic clk = 0;
    logic rst = 1;
    logic sample_ce = 0;
    logic signed [13:0] sample = 0;
    logic signed [32:0] carrier_real, carrier_imag;
    logic signed [66:0] am_inphase_raw, pm_quadrature_raw;
    logic observable_valid;
    logic overflow;
    integer sample_index;
    integer valid_count = 0;

    engeler_observables dut (.*);
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
        if (observable_valid)
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

        wait (observable_valid);
        #1;
        if (carrier_real !== -33'sd11998 || carrier_imag !== -33'sd20783)
            $fatal(1, "carrier complex mismatch: %0d %0d", carrier_real, carrier_imag);
        if (am_inphase_raw !== 67'sd575140769)
            $fatal(1, "AM dot-product mismatch: %0d", am_inphase_raw);
        if (pm_quadrature_raw !== 67'sd71729)
            $fatal(1, "PM cross-product mismatch: %0d", pm_quadrature_raw);
        if (overflow)
            $fatal(1, "unexpected overflow");

        @(posedge clk);
        #1;
        if (observable_valid)
            $fatal(1, "observable_valid was wider than one clock");
        if (valid_count != 4)
            $fatal(1, "observable_valid count mismatch: %0d", valid_count);

        $display("engeler_observables_tb: PASS");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "timeout");
    end
endmodule
