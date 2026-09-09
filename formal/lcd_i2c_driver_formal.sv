// LCD driver plus its byte engine, checked as an I2C master at the pins,
// which also discharges the bus-ownership assumption the byte-engine proof
// makes: SDA moves while SCL is released only as a START (from an idle
// bus) or a STOP (inside a transaction), SCL is only driven inside a
// transaction, every transaction carries whole bytes (9 SCL pulses each,
// plus the STOP's release), the first byte after every START is the
// ST7036 write address 0x78 and the second a control byte (0x00 command
// or 0x40 data), RST is released once and stays released, and no
// transaction starts before that.
module lcd_i2c_driver_formal;
    (* gclk *) logic clk;
    (* anyseq *) logic tick, minute_locked, sda_in;
    (* anyseq *) logic [5:0] second, minute, day;
    (* anyseq *) logic [4:0] hour;
    (* anyseq *) logic [3:0] month;
    (* anyseq *) logic [7:0] year, quality;
    (* anyseq *) logic [2:0] lock_state;
    logic rst = 1'b1;
    logic past_valid = 1'b0;
    logic lcd_rst_n, scl_drive_low, sda_drive_low, ready, ack_error;

    // QUARTER = 1 and short waits keep a whole three-byte transaction
    // inside the bounded depth.
    lcd_i2c_driver #(.CLK_HZ(4), .SCL_HZ(1), .POWERUP_WAIT(2), .CMD_WAIT(2)) dut (.*);

    wire scl = !scl_drive_low;
    wire sda = !sda_drive_low;
    logic in_txn = 1'b0;
    logic [5:0] pulses = '0;
    logic [3:0] bit_count = '0;
    logic [7:0] shift = '0;
    logic [1:0] byte_index = '0;

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;

        if (past_valid && !$past(rst)) begin
            if ($past(lcd_rst_n)) assert(lcd_rst_n);
            if (scl_drive_low) assert(in_txn || ($past(sda) && !sda && scl));

            // SDA transitions while SCL is (and was) released.
            if (scl && $past(scl) && sda != $past(sda)) begin
                if (!sda) begin                    // START
                    assert(!in_txn);
                    assert(lcd_rst_n);
                    in_txn <= 1'b1; pulses <= '0; bit_count <= '0; byte_index <= '0;
                end else begin                     // STOP
                    assert(in_txn);
                    assert(pulses >= 6'd19 && (pulses - 6'd1) % 9 == 0);
                    in_txn <= 1'b0;
                end
            end
            if (in_txn && scl && !$past(scl)) begin
                if (pulses != 6'd63) pulses <= pulses + 1'b1;
                // Sample the master's data on the rising edge, 8 bits + ACK.
                if (bit_count < 4'd8) begin
                    shift <= {shift[6:0], sda};
                    bit_count <= bit_count + 1'b1;
                    if (bit_count == 4'd7) begin
                        if (byte_index == 2'd0) assert({shift[6:0], sda} == 8'h78);
                        if (byte_index == 2'd1)
                            assert({shift[6:0], sda} == 8'h00 || {shift[6:0], sda} == 8'h40);
                    end
                end else begin                     // ACK clock
                    assert(sda);                   // master released SDA
                    bit_count <= '0;
                    if (byte_index != 2'd3) byte_index <= byte_index + 1'b1;
                end
            end
            // Inside a transaction SDA only moves while SCL is low, except
            // for the STOP handled above.
            if (in_txn && sda != $past(sda) && $past(scl) && scl) assert(sda);

            // One complete transaction (its STOP) lies inside the bound; the
            // end of the nine-command initialization (ready) does not.
            cover(in_txn && $past(in_txn) && !$past(sda) && sda && scl); // a STOP
        end
    end
endmodule
