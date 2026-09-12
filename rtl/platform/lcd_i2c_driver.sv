// SPDX-License-Identifier: MIT
// 20x2 status display driver for the NHD-C0220BiZ (ST7036, I2C) module.
//
// Protocol per the Newhaven NHD-C0220BiZ-FSW-FBW-3V3M data sheet: slave
// write address 0x78; each write transaction carries a control byte, 0x00
// for a command and 0x40 for DDRAM data, followed by the byte itself. The
// initialization sequence is the data sheet's example (0x38, 0x39 with
// 10 ms waits, 0x14 bias, 0x78/0x5E contrast and power, 0x6D follower,
// 0x0C display on, 0x01 clear, 0x06 entry mode), preceded by a reset
// pulse on RST and a ~40 ms power-up wait. Line 1 starts at DDRAM 0x00,
// line 2 at 0x40.
//
// Per docs/24-lcd-display.md the bus runs at 100 kHz and stays idle except
// for changed characters: on every `tick` (one per second) the two lines
// are re-rendered from the decoded time and lock state, compared with the
// shadow of what is on the glass, and only differing cells are written
// (set-address then data). The driver only reads receiver outputs; it can
// neither stall nor perturb the decode chain.
//
//   line 1: "hh:mm:ss  DCF LOCK"   (LOCK | HOLD | ACQ  | SRCH)
//   line 2: "dd-mm-yy  Q:qqq PM"   (PM shown while the PM minute marker is locked)
module lcd_i2c_driver #(
    parameter int unsigned CLK_HZ = 125_000_000,
    parameter int unsigned SCL_HZ = 100_000,
    // Power-up / reset waits in clock cycles (40 ms and 10 ms at 125 MHz).
    parameter int unsigned POWERUP_WAIT = 5_000_000,
    parameter int unsigned CMD_WAIT = 1_250_000
) (
    input  logic clk,
    input  logic rst,
    input  logic tick,
    input  logic [5:0] second,
    input  logic [5:0] minute,
    input  logic [4:0] hour,
    input  logic [5:0] day,
    input  logic [3:0] month,
    input  logic [7:0] year,
    input  logic [2:0] lock_state,
    input  logic minute_locked,
    input  logic [7:0] quality,
    output logic lcd_rst_n,
    output logic scl_drive_low,
    output logic sda_drive_low,
    input  logic sda_in,
    output logic ready,          // initialization finished
    output logic ack_error       // sticky: a byte went unacknowledged
);
    localparam logic [7:0] SLAVE_WRITE = 8'h78;
    localparam logic [7:0] CTRL_COMMAND = 8'h00;
    localparam logic [7:0] CTRL_DATA = 8'h40;
    localparam int WAIT_W = $clog2(POWERUP_WAIT + 1);

    // --- Byte engine -------------------------------------------------------
    logic i2c_start, i2c_do_start, i2c_do_stop, unused_i2c_busy, i2c_done, i2c_ack_error;
    logic [7:0] i2c_data;
    i2c_master_byte #(.CLK_HZ(CLK_HZ), .SCL_HZ(SCL_HZ)) i2c_i (
        .clk(clk), .rst(rst), .start(i2c_start), .do_start(i2c_do_start),
        .do_stop(i2c_do_stop), .data(i2c_data), .busy(unused_i2c_busy), .done(i2c_done),
        .ack_error(i2c_ack_error), .scl_drive_low(scl_drive_low),
        .sda_drive_low(sda_drive_low), .sda_in(sda_in));

    // --- Rendering ---------------------------------------------------------
    function automatic logic [7:0] digit(input logic [3:0] d);
        digit = 8'h30 + {4'b0, d};
    endfunction
    function automatic logic [3:0] tens(input logic [6:0] v);
        tens = 4'(v / 10);
    endfunction
    function automatic logic [3:0] units(input logic [6:0] v);
        units = 4'(v % 10);
    endfunction

    logic [7:0] frame [0:4][0:7];
    always_comb begin
        for (int g = 0; g < 5; g = g + 1)
            for (int k = 0; k < 8; k = k + 1) frame[g][k] = 8'h20;
        // pos 0..7 -> group 0
        frame[0][0] = hh10_q; frame[0][1] = hh1_q;
        frame[0][2] = ":";
        frame[0][3] = mm10_q; frame[0][4] = mm1_q;
        frame[0][5] = ":";
        frame[0][6] = ss10_q; frame[0][7] = ss1_q;
        // pos 8..15 -> group 1 ("DCF" at 10..12, lock word at 14..17)
        frame[1][2] = "D"; frame[1][3] = "C"; frame[1][4] = "F";
        case (lock_state)
            3'd2: begin frame[1][6] = "L"; frame[1][7] = "O"; frame[2][0] = "C"; frame[2][1] = "K"; end
            3'd3: begin frame[1][6] = "H"; frame[1][7] = "O"; frame[2][0] = "L"; frame[2][1] = "D"; end
            3'd1: begin frame[1][6] = "A"; frame[1][7] = "C"; frame[2][0] = "Q"; frame[2][1] = " "; end
            default: begin frame[1][6] = "S"; frame[1][7] = "R"; frame[2][0] = "C"; frame[2][1] = "H"; end
        endcase
        // pos 16..23 -> group 2 (date, 20..27)
        frame[2][4] = dd10_q; frame[2][5] = dd1_q;
        frame[2][6] = "-";
        frame[2][7] = mo10_q;
        // pos 24..31 -> group 3
        frame[3][0] = mo1_q;
        frame[3][1] = "-";
        frame[3][2] = yy10_q; frame[3][3] = yy1_q;
        frame[3][6] = "Q"; frame[3][7] = ":";
        // pos 32..39 -> group 4 (quality, 32..34, "PM" at 36..37)
        frame[4][0] = q100_q;
        frame[4][1] = q10_q;
        frame[4][2] = q1_q;
        if (minute_locked) begin frame[4][4] = "P"; frame[4][5] = "M"; end
    end

    // One-cycle-ahead decimal decomposition (see declaration).  Latency is
    // immaterial: the render only needs to be stable at the next tick, one
    // second — ~10^8 clk_sys cycles — away.
    always_ff @(posedge clk) begin
        if (rst) begin
            year_lo_q <= '0; qual_100_q <= '0; qual_10_q <= '0;
        end else begin
            year_lo_q  <= 7'(year % 8'd100);
            qual_100_q <= 8'(quality / 8'd100);
            qual_10_q  <= 7'(quality / 8'd10);
        end
    end

    // Second render stage: the ASCII digit bytes themselves are registered, so
    // the constant divides (`/10`, `%10`) end at a flop and never reach the
    // frame/scan multiplexers. Without this the top-level critical path was
    // `quality -> %10 -> digit -> frame mux` (18 ns): the divide carry chain
    // shared a cone with the scan read.
    logic [7:0] hh10_q, hh1_q, mm10_q, mm1_q, ss10_q, ss1_q;
    logic [7:0] dd10_q, dd1_q, mo10_q, mo1_q, yy10_q, yy1_q;
    logic [7:0] q100_q, q10_q, q1_q;
    always_ff @(posedge clk) begin
        hh10_q <= digit(tens({2'b0, hour}));   hh1_q <= digit(units({2'b0, hour}));
        mm10_q <= digit(tens({1'b0, minute})); mm1_q <= digit(units({1'b0, minute}));
        ss10_q <= digit(tens({1'b0, second})); ss1_q <= digit(units({1'b0, second}));
        dd10_q <= digit(tens({1'b0, day}));    dd1_q <= digit(units({1'b0, day}));
        mo10_q <= digit(tens({3'b0, month}));  mo1_q <= digit(units({3'b0, month}));
        yy10_q <= digit(tens(year_lo_q));      yy1_q <= digit(units(year_lo_q));
        q100_q <= digit(4'(qual_100_q));
        q10_q  <= digit(4'(qual_10_q % 7'd10));
        q1_q   <= digit(4'(quality % 8'd10));
    end

    // --- Sequencer ---------------------------------------------------------
    // Init command list; index 0 and 1 are followed by CMD_WAIT.
    function automatic logic [7:0] init_command(input logic [3:0] idx);
        case (idx)
            4'd0: init_command = 8'h38; 4'd1: init_command = 8'h39;
            4'd2: init_command = 8'h14; 4'd3: init_command = 8'h78;
            4'd4: init_command = 8'h5E; 4'd5: init_command = 8'h6D;
            4'd6: init_command = 8'h0C; 4'd7: init_command = 8'h01;
            default: init_command = 8'h06;
        endcase
    endfunction
    localparam logic [3:0] INIT_LAST = 4'd8;

    typedef enum logic [4:0] {
        RESET_LOW, POWERUP, INIT_ADDR, INIT_CTRL, INIT_CMD, INIT_WAIT,
        IDLE, SCAN_GRP, SCAN, SCAN_DECIDE, ADDR_A, ADDR_C, ADDR_V, DATA_A, DATA_C, DATA_V, FLUSH
    } state_t;
    state_t state;
    logic [WAIT_W-1:0] wait_count;
    logic [3:0] init_index;
    logic [5:0] pos;                 // 0..39
    logic [7:0] shadow [0:39];
    logic shadow_valid [0:39];
    // Pipelined decimal decomposition: the two-level ones (year%100 then %10,
    // quality/10 then %10, quality/100) are split across a register so the
    // once-per-second render is not a single deep constant-divide chain.
    logic [6:0] year_lo_q;           // year % 100
    logic [7:0] qual_100_q;          // quality / 100
    logic [6:0] qual_10_q;           // quality / 10
    logic pending_tick;
    logic [7:0] addr_q;              // registered DDRAM set-address

    // The cell the sequencer is looking at is read into registers before the
    // dirty decision. Scanning a 40-entry frame/shadow pair combinationally
    // (index mux *and* compare) from `pos` to the next-state logic was the
    // isolated critical path here (pos -> state, 32.7 ns); the registered read
    // cuts the mux out of that path. The scan is off the sample path, so the
    // extra clk per position is free.
    //
    // The frame itself is built as five 8-byte groups read in two register
    // stages (SCAN_GRP -> SCAN): `frame[g][pos[2:0]]` is an 8:1 mux per group
    // and `grp_q[pos[5:3]]` a 5:1 mux. Yosys maps a single flat 40:1 read onto
    // a ~90-cell carry-chain multiplexer (~19 ns at 125 MHz), which was the
    // top-level critical path before this split; two small muxes separated by a
    // register keep each stage to a couple of LUT levels.
    logic [7:0] frame_q, shadow_q;
    logic [7:0] grp_q [0:4];
    logic valid_q;
    wire pos_dirty = !valid_q || (shadow_q != frame_q);
    wire [7:0] ddram_address = (pos < 6'd20) ? 8'h80 + {2'b0, pos} : 8'hC0 + {2'b0, pos - 6'd20};

    task automatic send(input logic first, input logic last, input logic [7:0] byte_value);
        begin
            i2c_start <= 1'b1; i2c_do_start <= first; i2c_do_stop <= last; i2c_data <= byte_value;
        end
    endtask

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= RESET_LOW; wait_count <= '0; init_index <= '0; pos <= '0;
            lcd_rst_n <= 1'b0; ready <= 1'b0; ack_error <= 1'b0; pending_tick <= 1'b0;
            i2c_start <= 1'b0; i2c_do_start <= 1'b0; i2c_do_stop <= 1'b0; i2c_data <= '0;
            frame_q <= '0; shadow_q <= '0; valid_q <= 1'b0; addr_q <= '0;
            for (int i = 0; i < 40; i = i + 1) shadow_valid[i] <= 1'b0;
        end else begin
            i2c_start <= 1'b0;
            if (tick) pending_tick <= 1'b1;
            if (i2c_done && i2c_ack_error) ack_error <= 1'b1;

            case (state)
                RESET_LOW: begin
                    if (wait_count == WAIT_W'(CMD_WAIT - 1)) begin
                        wait_count <= '0; lcd_rst_n <= 1'b1; state <= POWERUP;
                    end else wait_count <= wait_count + 1'b1;
                end
                POWERUP: begin
                    if (wait_count == WAIT_W'(POWERUP_WAIT - 1)) begin
                        wait_count <= '0; init_index <= '0; state <= INIT_ADDR;
                    end else wait_count <= wait_count + 1'b1;
                end
                INIT_ADDR: begin send(1'b1, 1'b0, SLAVE_WRITE); state <= INIT_CTRL; end
                INIT_CTRL: if (i2c_done) begin send(1'b0, 1'b0, CTRL_COMMAND); state <= INIT_CMD; end
                INIT_CMD:  if (i2c_done) begin send(1'b0, 1'b1, init_command(init_index)); state <= INIT_WAIT; end
                INIT_WAIT: if (i2c_done || wait_count != 0) begin
                    // Every command is followed by a settle time; the data
                    // sheet asks for 10 ms after the first two and the last.
                    if (wait_count == WAIT_W'(CMD_WAIT - 1)) begin
                        wait_count <= '0;
                        if (init_index == INIT_LAST) begin
                            ready <= 1'b1; state <= IDLE;
                        end else begin
                            init_index <= init_index + 1'b1; state <= INIT_ADDR;
                        end
                    end else wait_count <= wait_count + 1'b1;
                end
                IDLE: if (pending_tick) begin
                    pending_tick <= 1'b0; pos <= '0; state <= SCAN_GRP;
                end
                SCAN_GRP: begin
                    // Stage 1: the five group bytes for this pos, one 8:1 mux
                    // per group (constant group index keeps them small).
                    for (int g = 0; g < 5; g = g + 1) grp_q[g] <= frame[g][pos[2:0]];
                    state <= SCAN;
                end
                SCAN: begin
                    // Stage 2: registered select of the group, plus the
                    // shadow/valid reads. SCAN_DECIDE then sees a short
                    // registered compare instead of a deep index mux.
                    frame_q  <= grp_q[pos[5:3]];
                    shadow_q <= shadow[pos];
                    valid_q  <= shadow_valid[pos];
                    state    <= SCAN_DECIDE;
                end
                SCAN_DECIDE: begin
                    if (pos_dirty) begin
                        // Register the DDRAM set-address here, off the data
                        // path: ADDR_V then presents a registered byte and the
                        // pos<20 / pos-20 arithmetic never shares a cone with
                        // the frame/shadow cell write.
                        addr_q <= ddram_address;
                        state  <= ADDR_A;
                    end
                    else if (pos == 6'd39) state <= IDLE;
                    else begin pos <= pos + 1'b1; state <= SCAN_GRP; end
                end
                ADDR_A: begin send(1'b1, 1'b0, SLAVE_WRITE); state <= ADDR_C; end
                ADDR_C: if (i2c_done) begin send(1'b0, 1'b0, CTRL_COMMAND); state <= ADDR_V; end
                ADDR_V: if (i2c_done) begin send(1'b0, 1'b1, addr_q); state <= DATA_A; end
                DATA_A: if (i2c_done) begin send(1'b1, 1'b0, SLAVE_WRITE); state <= DATA_C; end
                DATA_C: if (i2c_done) begin send(1'b0, 1'b0, CTRL_DATA); state <= DATA_V; end
                DATA_V: if (i2c_done) begin
                    // frame_q / shadow_q / valid_q were latched for this pos in
                    // SCAN and pos does not move until FLUSH, so frame_q is the
                    // cell under scan.  Using it (instead of the combinational
                    // frame[pos] 40:1 mux) keeps the write-data cone short.
                    send(1'b0, 1'b1, frame_q);
                    shadow[pos] <= frame_q; shadow_valid[pos] <= 1'b1;
                    state <= FLUSH;
                end
                // The byte engine accepts a new request only once idle: wait
                // for the data byte and its STOP before scanning on.
                FLUSH: if (i2c_done) begin
                    if (pos == 6'd39) state <= IDLE;
                    else begin pos <= pos + 1'b1; state <= SCAN_GRP; end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
