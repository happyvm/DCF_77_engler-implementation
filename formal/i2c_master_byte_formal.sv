// I2C byte engine. Contract (see the RTL header): a byte issued with
// do_start begins with a START from a released bus; a byte issued without
// do_start continues a transfer the engine already owns, i.e. SCL is held
// low and SDA released after the previous ACK. Under that contract:
//  - done is a single-cycle pulse ending a busy period;
//  - after a byte with do_stop both lines are released, after one without
//    do_stop SCL stays held low and SDA released (bus kept), and neither
//    line moves while idle;
//  - SDA changes while SCL is released happen exactly once for a START
//    and once for a STOP, never otherwise;
//  - every byte drives nine SCL rising edges (8 data + ACK) plus one for
//    the STOP release.
module i2c_master_byte_formal;
    (* gclk *) logic clk;
    (* anyseq *) logic start, do_start, do_stop, sda_in;
    (* anyseq *) logic [7:0] data;
    logic rst = 1'b1;
    logic past_valid = 1'b0;
    logic busy, done, ack_error, scl_drive_low, sda_drive_low;

    // QUARTER = 1 keeps two consecutive bytes inside the bounded depth.
    i2c_master_byte #(.CLK_HZ(4), .SCL_HZ(1)) dut (.*);

    // Environment: the caller respects the bus-ownership contract.
    always_comb begin
        if (start && !busy) begin
            if (do_start) assume(!scl_drive_low && !sda_drive_low);
            else          assume(scl_drive_low && !sda_drive_low);
        end
    end

    logic [1:0] sda_moves_scl_high = '0;
    logic [3:0] scl_pulses = '0;
    logic framed_start = 1'b0, framed_stop = 1'b0;

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;

        if (past_valid && !$past(rst)) begin
            assert(!(done && $past(done)));
            if (done) assert($past(busy) && !busy);
            if (!busy && $past(!busy)) begin
                assert(scl_drive_low == $past(scl_drive_low));
                assert(sda_drive_low == $past(sda_drive_low));
            end

            if ($past(start) && !$past(busy)) begin
                sda_moves_scl_high <= '0; scl_pulses <= '0;
                framed_start <= $past(do_start); framed_stop <= $past(do_stop);
            end else if (busy) begin
                if (sda_drive_low != $past(sda_drive_low) && !scl_drive_low && !$past(scl_drive_low))
                    sda_moves_scl_high <= sda_moves_scl_high + 1'b1;
                if (!scl_drive_low && $past(scl_drive_low))
                    scl_pulses <= scl_pulses + 1'b1;
            end
            if (done) begin
                assert(scl_pulses == 4'd9 + {3'b0, framed_stop});
                assert(sda_moves_scl_high == {1'b0, framed_start} + {1'b0, framed_stop});
                assert(!sda_drive_low);
                assert(scl_drive_low == !framed_stop);
            end
        end
    end
endmodule
