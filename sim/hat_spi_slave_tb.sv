`timescale 1ns/1ps
// Behavioral Raspberry Pi SPI master (mode 0, MSB first) reading and
// writing hat_spi_slave: checks the identity/version registers, a
// coherent multi-byte time read with address auto-increment, that the
// snapshot taken at CS_N assertion is what a long read returns even when
// the live inputs change mid-transaction, the 24-bit trim readback, the
// control register write/readback, an aborted transaction, and that MISO
// is quiet while deselected.
module hat_spi_slave_tb;
    logic clk = 0, rst = 1;
    always #4 clk = ~clk;   // 125 MHz

    logic spi_sclk = 0, spi_mosi = 0, spi_cs_n = 1, spi_miso;
    logic [2:0] lock_state = 3'd2;
    logic time_valid = 1, pps_valid = 1, ml_locked = 1, minute_locked = 1, frequency_locked = 0;
    logic adc_fault = 0, detector_overflow = 1;
    logic [7:0] phase_quality = 8'd200;
    logic [5:0] second = 6'd42, minute = 6'd34, day = 6'd21;
    logic [4:0] hour = 5'd12;
    logic [2:0] weekday = 3'd3;
    logic [3:0] month = 4'd6;
    logic [7:0] year = 8'd24;
    logic cest = 1;
    logic signed [23:0] trim_inc = -24'sd123456;
    logic [7:0] control;
    logic transaction_done;

    hat_spi_slave #(.RTL_VERSION(16'h0102)) dut (.*);

    // ~2 MHz SCLK: 250 ns half period.
    localparam time HALF = 250ns;
    logic [7:0] rx;

    task automatic xfer_byte(input logic [7:0] tx, output logic [7:0] r);
        integer i;
        begin
            r = '0;
            for (i = 7; i >= 0; i = i - 1) begin
                spi_mosi = tx[i];          // master shifts out on the falling edge (or before first rise)
                #HALF;
                spi_sclk = 1;              // both sides sample on the rising edge
                r[i] = spi_miso;
                #HALF;
                spi_sclk = 0;
            end
        end
    endtask

    task automatic select;   begin spi_cs_n = 0; #HALF; end endtask
    task automatic deselect; begin #HALF; spi_cs_n = 1; #(4*HALF); end endtask

    logic [7:0] got [0:15];
    integer i, done_count = 0;
    always @(posedge clk) if (transaction_done) done_count = done_count + 1;

    initial begin
        repeat (4) @(posedge clk); rst <= 0; repeat (4) @(posedge clk);

        // Identity and version, auto-incrementing from 0x00.
        select(); xfer_byte(8'h00, rx);
        for (i = 0; i < 4; i = i + 1) xfer_byte(8'h00, got[i]);
        deselect();
        if (got[0] !== 8'hDC || got[1] !== 8'h77 || got[2] !== 8'h01 || got[3] !== 8'h02)
            $fatal(1, "identity/version read %h %h %h %h", got[0], got[1], got[2], got[3]);

        // Lock/status/time block from 0x04; change the live inputs after
        // CS_N asserts to prove the snapshot is what is returned.
        select();
        second = 6'd43; minute = 6'd35; lock_state = 3'd0; time_valid = 0;
        xfer_byte(8'h04, rx);
        for (i = 0; i < 12; i = i + 1) xfer_byte(8'h00, got[i]);
        deselect();
        if (got[0] !== 8'b0001_1010) $fatal(1, "LOCK register %b", got[0]);      // pps,time,state=2
        if (got[1] !== 8'b0000_0110) $fatal(1, "STATUS register %b", got[1]);    // minute,ml locked
        if (got[2] !== 8'b0000_0010) $fatal(1, "FAULTS register %b", got[2]);    // overflow only
        if (got[3] !== 8'd200) $fatal(1, "QUALITY %0d", got[3]);
        if (got[4] !== 8'd42 || got[5] !== 8'd34 || got[6] !== 8'd12 || got[7] !== 8'd21 ||
            got[8] !== 8'd3 || got[9] !== 8'd6 || got[10] !== 8'd24 || got[11] !== 8'd1)
            $fatal(1, "time block %0d:%0d:%0d %0d/%0d/%0d wd%0d z%0d", got[6], got[5], got[4],
                   got[7], got[9], got[10], got[8], got[11]);

        // Trim, little-endian two's complement.
        select(); xfer_byte(8'h10, rx);
        for (i = 0; i < 3; i = i + 1) xfer_byte(8'h00, got[i]);
        deselect();
        if ($signed({got[2], got[1], got[0]}) !== -24'sd123456)
            $fatal(1, "trim readback %h%h%h", got[2], got[1], got[0]);

        // Control register: write then read back; writes elsewhere ignored.
        select(); xfer_byte(8'h93, rx); xfer_byte(8'hA5, rx); deselect();
        if (control !== 8'hA5) $fatal(1, "control not written (%h)", control);
        select(); xfer_byte(8'h80, rx); xfer_byte(8'hFF, rx); deselect();
        select(); xfer_byte(8'h13, rx); xfer_byte(8'h00, got[0]); xfer_byte(8'h00, got[1]); deselect();
        if (got[0] !== 8'hA5) $fatal(1, "control readback %h", got[0]);
        if (got[1] !== 8'h00) $fatal(1, "register 0x14 should read 0, got %h", got[1]);
        select(); xfer_byte(8'h00, rx); xfer_byte(8'h00, got[0]); deselect();
        if (got[0] !== 8'hDC) $fatal(1, "ID corrupted by a write to a read-only address");

        // Aborted transaction (CS_N released mid-byte) leaves no residue.
        select(); xfer_byte(8'h08, rx);
        spi_mosi = 0; #HALF; spi_sclk = 1; #HALF; spi_sclk = 0; #HALF; spi_sclk = 1; #HALF; spi_sclk = 0;
        deselect();
        select(); xfer_byte(8'h09, rx); xfer_byte(8'h00, got[0]); deselect();
        if (got[0] !== 8'd35) $fatal(1, "read after abort returned %0d", got[0]);

        // MISO idles low while deselected.
        repeat (20) begin @(posedge clk); if (spi_miso !== 1'b0) $fatal(1, "MISO active while deselected"); end
        if (done_count != 9) $fatal(1, "transaction_done pulses: %0d, expected 9", done_count);

        $display("hat_spi_slave_tb: PASS");
        $finish;
    end

    initial begin #5_000_000; $fatal(1, "timeout"); end
endmodule
