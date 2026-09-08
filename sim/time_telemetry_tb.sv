`timescale 1ns/1ps

module time_telemetry_tb;
    localparam integer FRAME_BYTES = 39;
    logic clk = 0;
    logic rst = 1;
    logic frame_request = 0;
    logic [15:0] year_bcd = 16'h2026;
    logic [7:0] month_bcd = 8'h09;
    logic [7:0] day_bcd = 8'h08;
    logic [7:0] hour_bcd = 8'h18;
    logic [7:0] minute_bcd = 8'h12;
    logic [7:0] second_bcd = 8'h34;
    logic utc_offset_negative = 0;
    logic [15:0] utc_offset_bcd = 16'h0200;
    logic [1:0] receiver_state = 1;
    logic [11:0] quality_bcd = 12'h087;
    logic [7:0] tx_data;
    logic tx_valid;
    logic tx_ready = 1;
    logic busy;
    logic frame_done;
    logic [7:0] received [0:FRAME_BYTES-1];
    logic [FRAME_BYTES*8-1:0] expected;
    integer count = 0;
    integer i;

    time_telemetry dut (.*);
    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (tx_valid && tx_ready) begin
            received[count] = tx_data;
            count = count + 1;
        end
    end

    initial begin
        expected = "$DCF77,20260908,181234,+0200,L,087*3D\r\n";
        repeat (2) @(posedge clk);
        rst <= 0;
        @(posedge clk);
        frame_request <= 1;
        @(posedge clk);
        frame_request <= 0;

        // Prove that a frame uses the snapshot taken at frame_request.
        year_bcd <= 16'h9999;
        wait (frame_done);
        #1;

        if (count != FRAME_BYTES)
            $fatal(1, "frame length mismatch: %0d", count);
        for (i = 0; i < FRAME_BYTES; i = i + 1)
            if (received[i] !== expected[(FRAME_BYTES-i)*8-1 -: 8])
                $fatal(1, "byte %0d mismatch: got %02x", i, received[i]);

        @(posedge clk);
        if (frame_done || busy || tx_valid)
            $fatal(1, "formatter did not return idle cleanly");

        $display("time_telemetry_tb: PASS");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "timeout");
    end
endmodule
