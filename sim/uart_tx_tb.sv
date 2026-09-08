`timescale 1ns/1ps

module uart_tx_tb;
    localparam integer CLKS_PER_BIT = 10;
    logic clk = 0;
    logic rst_n = 0;
    logic [7:0] data = 0;
    logic valid = 0;
    logic ready;
    logic tx;
    integer bit_index;
    logic [9:0] expected;

    uart_tx #(.CLK_HZ(100), .BAUD(10)) dut (.*);
    always #5 clk = ~clk;

    initial begin
        repeat (2) @(posedge clk);
        rst_n <= 1;
        @(posedge clk);
        if (!ready || !tx)
            $fatal(1, "UART not idle after reset");

        data <= 8'ha5;
        valid <= 1;
        @(posedge clk);
        valid <= 0;
        expected = {1'b1, 8'ha5, 1'b0};

        for (bit_index = 0; bit_index < 10; bit_index = bit_index + 1) begin
            #1;
            if (tx !== expected[bit_index])
                $fatal(1, "UART bit %0d mismatch", bit_index);
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
        #1;
        if (!ready || !tx)
            $fatal(1, "UART did not return to idle");

        $display("uart_tx_tb: PASS");
        $finish;
    end
endmodule
