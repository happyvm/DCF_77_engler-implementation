`timescale 1ns/1ps

module dcf77_prn_generator_tb;
    logic clk = 0;
    logic rst = 1;
    logic reset_cycle = 0;
    logic chip_ce = 0;
    logic prn_chip, prn_chip_inverted;
    logic [8:0] chip_index;
    logic cycle_done;
    logic [34:0] prefix = 0;
    integer index;
    integer ones = 0;
    integer done_count = 0;

    dcf77_prn_generator dut (.*);
    always #5 clk = ~clk;

    always @(posedge clk)
        if (cycle_done)
            done_count = done_count + 1;

    initial begin
        repeat (2) @(posedge clk);
        rst <= 0;

        for (index = 0; index < 512; index = index + 1) begin
            if (chip_index !== index[8:0])
                $fatal(1, "chip index mismatch at %0d", index);
            if (prn_chip_inverted !== !prn_chip)
                $fatal(1, "inverted chip mismatch");
            if (index < 35)
                prefix = {prefix[33:0], prn_chip};
            if (prn_chip)
                ones = ones + 1;
            chip_ce <= 1;
            @(posedge clk);
            chip_ce <= 0;
            @(posedge clk);
        end
        #1;

        if (prefix !== 35'b00000100011000010011100101010110000)
            $fatal(1, "known PRN prefix mismatch");
        if (ones != 256)
            $fatal(1, "PRN is not balanced: %0d ones", ones);
        if (done_count != 1 || chip_index != 0)
            $fatal(1, "PRN cycle completion mismatch");

        $display("dcf77_prn_generator_tb: PASS");
        $finish;
    end
endmodule
