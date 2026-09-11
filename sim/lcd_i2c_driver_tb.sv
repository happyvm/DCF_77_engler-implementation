`timescale 1ns/1ps
// I2C bus monitor / acknowledging slave around lcd_i2c_driver. Checks the
// reset pulse, the ST7036 initialization transactions byte for byte, the
// SCL rate, that the first refresh paints exactly the two expected lines
// (address + data per cell, via a DDRAM model fed from the bus), and that a
// second refresh with one changed digit rewrites exactly one cell.
module lcd_i2c_driver_tb;
    localparam int unsigned CLK_HZ = 125_000_000;
    localparam int unsigned SCL_HZ = 1_250_000;     // sped up for simulation
    localparam int QUARTER = CLK_HZ / (4 * SCL_HZ); // 25 clocks

    logic clk = 0, rst = 1, tick = 0;
    always #4 clk = ~clk;
    logic [5:0] second = 6'd56, minute = 6'd34, day = 6'd8;
    logic [4:0] hour = 5'd12;
    logic [3:0] month = 4'd9;
    logic [7:0] year = 8'd26, quality = 8'd87;
    logic [2:0] lock_state = 3'd2;
    logic minute_locked = 1;
    logic lcd_rst_n, scl_drive_low, sda_drive_low, ready, ack_error;

    // Open-drain bus with pull-ups and an acknowledging slave.
    logic slave_ack_low = 0;
    wire scl = !scl_drive_low;
    wire sda = !(sda_drive_low || slave_ack_low);

    lcd_i2c_driver #(
        .CLK_HZ(CLK_HZ), .SCL_HZ(SCL_HZ), .POWERUP_WAIT(4000), .CMD_WAIT(600)
    ) dut (.*, .sda_in(sda));

    // --- Monitor ----------------------------------------------------------
    logic [7:0] bytes [0:4095];
    logic       starts [0:4095];   // byte was the first after a START
    integer nbytes = 0, bitn = 0, stops = 0;
    logic [7:0] cur; logic after_start = 0, in_frame = 0;
    integer last_rise = -1, now = 0, min_p = 1 << 30, max_p = 0;
    always @(posedge clk) now = now + 1;

    always @(negedge sda) if (scl) begin in_frame = 1; after_start = 1; bitn = 0; last_rise = -1; end
    always @(posedge sda) if (scl && in_frame) begin in_frame = 0; stops = stops + 1; end
    always @(posedge scl) if (in_frame) begin
        if (last_rise >= 0 && bitn > 0 && bitn < 8) begin
            if (now - last_rise < min_p) min_p = now - last_rise;
            if (now - last_rise > max_p) max_p = now - last_rise;
        end
        last_rise = now;
        if (bitn < 8) begin
            cur[7 - bitn] = sda; bitn = bitn + 1;
        end else begin
            // ACK clock: slave is driving low here; record the byte.
            bytes[nbytes] = cur; starts[nbytes] = after_start; nbytes = nbytes + 1;
            after_start = 0; bitn = 0;
        end
    end
    // Drive ACK from the falling edge after the 8th data bit until the next.
    always @(negedge scl) if (in_frame) begin
        if (bitn == 8) slave_ack_low = 1; else slave_ack_low = 0;
    end

    // DDRAM model built from the byte stream: [0x78 0x00 addr] then [0x78 0x40 data].
    logic [7:0] ddram [0:127];
    integer i, addr_ptr = 0, b, cells_written;
    task automatic replay_from(input integer from, output integer written);
        begin
            written = 0; b = from;
            while (b + 2 < nbytes) begin
                if (bytes[b] != 8'h78) $fatal(1, "byte %0d: unexpected slave address %h", b, bytes[b]);
                if (bytes[b+1] == 8'h00) begin
                    addr_ptr = bytes[b+2][6:0];
                end else if (bytes[b+1] == 8'h40) begin
                    ddram[addr_ptr] = bytes[b+2]; written = written + 1;
                end else $fatal(1, "byte %0d: bad control byte %h", b+1, bytes[b+1]);
                b = b + 3;
            end
        end
    endtask

    logic [7:0] expected_init_vals [0:8];
    initial begin
        expected_init_vals[0] = 8'h38; expected_init_vals[1] = 8'h39;
        expected_init_vals[2] = 8'h14; expected_init_vals[3] = 8'h78;
        expected_init_vals[4] = 8'h5E; expected_init_vals[5] = 8'h6D;
        expected_init_vals[6] = 8'h0C; expected_init_vals[7] = 8'h01;
        expected_init_vals[8] = 8'h06;
    end
    string line1, line2;
    integer init_bytes, after_first, k;

    initial begin
        repeat (3) @(posedge clk); rst <= 0; @(posedge clk);
        if (lcd_rst_n !== 1'b0) $fatal(1, "RST not asserted after reset");
        wait (ready);
        init_bytes = nbytes;
        if (init_bytes != 27) $fatal(1, "init sent %0d bytes, expected 27", init_bytes);
        for (i = 0; i < 9; i = i + 1) begin
            if (!starts[3*i] || bytes[3*i] != 8'h78 || bytes[3*i+1] != 8'h00 || bytes[3*i+2] != expected_init_vals[i])
                $fatal(1, "init transaction %0d: %h %h %h", i, bytes[3*i], bytes[3*i+1], bytes[3*i+2]);
        end
        if (stops != 9) $fatal(1, "init produced %0d STOPs", stops);
        if (min_p != 4 * QUARTER || max_p != 4 * QUARTER)
            $fatal(1, "SCL period %0d..%0d clocks, expected %0d", min_p, max_p, 4 * QUARTER);
        if (ack_error) $fatal(1, "ack_error raised although every byte was acknowledged");

        // First refresh paints every cell.
        tick <= 1; @(posedge clk); tick <= 0;
        wait (dut.state == dut.SCAN); wait (dut.state == dut.IDLE); repeat (10) @(posedge clk);
        replay_from(init_bytes, cells_written);
        if (cells_written != 40) $fatal(1, "first refresh wrote %0d cells, expected 40", cells_written);
        line1 = ""; line2 = "";
        for (k = 0; k < 20; k = k + 1) begin
            line1 = {line1, string'(ddram[k])};
            line2 = {line2, string'(ddram[8'h40 + k])};
        end
        if (line1 != "12:34:56  DCF LOCK  ") $fatal(1, "line 1 = '%s'", line1);
        if (line2 != "08-09-26  Q:087 PM  ") $fatal(1, "line 2 = '%s'", line2);
        after_first = nbytes;

        // Second refresh: only the seconds' units digit changed.
        second = 6'd57;
        tick <= 1; @(posedge clk); tick <= 0;
        wait (dut.state == dut.SCAN); wait (dut.state == dut.IDLE); repeat (10) @(posedge clk);
        replay_from(after_first, cells_written);
        if (cells_written != 1) $fatal(1, "second refresh rewrote %0d cells, expected 1", cells_written);
        if (ddram[7] != "7") $fatal(1, "changed cell holds '%c'", ddram[7]);

        // Lock lost: status word (LOCK->HOLD changes 3 of 4 letters) and PM flag (2 cells).
        lock_state = 3'd3; minute_locked = 0;
        tick <= 1; @(posedge clk); tick <= 0;
        wait (dut.state == dut.SCAN); wait (dut.state == dut.IDLE); repeat (10) @(posedge clk);
        replay_from(after_first, cells_written);
        if (cells_written != 1 + 5) $fatal(1, "status refresh rewrote %0d cells, expected 6 (LOCK->HOLD keeps the O)", cells_written);
        line1 = ""; for (k = 0; k < 20; k = k + 1) line1 = {line1, string'(ddram[k])};
        if (line1 != "12:34:57  DCF HOLD  ") $fatal(1, "line 1 after holdover = '%s'", line1);

        $display("lcd_i2c_driver_tb: PASS");
        $finish;
    end

    initial begin #50_000_000; $fatal(1, "timeout"); end
endmodule
