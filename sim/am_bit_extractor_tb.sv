`timescale 1ns/1ps
module am_bit_extractor_tb;
    logic clk = 0, rst = 1, second_ce = 0, carrier_ce = 0;
    logic signed [15:0] am_observable = 0;
    logic signed [23:0] am_soft_bit;
    logic bit_valid;
    logic [3:0] carrier_position;
    logic signed [23:0] results [0:1];
    integer cycle, result_count = 0;

    am_bit_extractor #(
        .INPUT_BITS(16), .OUTPUT_BITS(24), .OUTPUT_SHIFT(0),
        .SECOND_CYCLES(10), .DATA_START_CYCLE(2),
        .REFERENCE_START_CYCLE(4), .WINDOW_CYCLES(2)
    ) dut (.*);
    always #5 clk = ~clk;
    always @(posedge clk)
        if (bit_valid) begin
            results[result_count] = am_soft_bit;
            result_count = result_count + 1;
        end

    task automatic send_second(input logic data_one);
        begin
            second_ce <= 1; @(posedge clk); second_ce <= 0;
            for (cycle = 0; cycle < 10; cycle = cycle + 1) begin
                if (cycle < 2)
                    am_observable <= 16'sd10;
                else if (cycle >= 2 && cycle < 4)
                    am_observable <= data_one ? 16'sd10 : 16'sd40;
                else if (cycle >= 4 && cycle < 6)
                    am_observable <= 16'sd40;
                else
                    am_observable <= 16'sd0;
                carrier_ce <= 1; @(posedge clk);
                carrier_ce <= 0; @(posedge clk);
            end
        end
    endtask

    initial begin
        repeat (2) @(posedge clk); rst <= 0;
        send_second(1'b0);
        send_second(1'b1);
        #1;
        if (result_count != 2)
            $fatal(1, "bit_valid count mismatch: %0d", result_count);
        if (results[0] !== -24'sd60 || results[1] !== 24'sd60)
            $fatal(1, "AM evidence mismatch: %0d %0d", results[0], results[1]);
        $display("am_bit_extractor_tb: PASS");
        $finish;
    end
endmodule
