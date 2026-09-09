// SPDX-License-Identifier: MIT
// Minimal I2C master: byte-level write engine with open-drain SCL/SDA.
//
// Standard-mode (100 kHz) timing derived from CLK_HZ: each SCL quarter
// period is CLK_HZ/(4*SCL_HZ) clocks, so every setup/hold requirement of
// the standard-mode spec (SDA setup 250 ns, hold 0 ns, START/STOP setup
// and hold 4.0/4.7 us) is met with a quarter period of 2.5 us. SDA is
// only ever driven low or released (never driven high); SCL likewise, so
// the pins can be true open-drain outputs with external pull-ups. Clock
// stretching is not supported (the ST7036 does not stretch) and the ACK
// bit is sampled and reported but does not abort the sequence.
//
// Interface: pulse `start` with `do_start`/`do_stop` flags and a byte;
// the engine issues [START] byte [ACK] [STOP] as requested and pulses
// `done`. `ack_error` is set when the slave did not acknowledge.
module i2c_master_byte #(
    parameter int unsigned CLK_HZ = 125_000_000,
    parameter int unsigned SCL_HZ = 100_000
) (
    input  logic clk,
    input  logic rst,
    input  logic start,
    input  logic do_start,
    input  logic do_stop,
    input  logic [7:0] data,
    output logic busy,
    output logic done,
    output logic ack_error,
    // Open-drain pin controls: 1 = drive low, 0 = release.
    output logic scl_drive_low,
    output logic sda_drive_low,
    input  logic sda_in
);
    localparam int unsigned QUARTER = (CLK_HZ / (4 * SCL_HZ)) < 1 ? 1 : CLK_HZ / (4 * SCL_HZ);
    localparam int QW = $clog2(QUARTER + 1);

    typedef enum logic [3:0] {
        IDLE, START_A, START_B, BIT_A, BIT_B, BIT_C, BIT_D,
        ACK_A, ACK_B, ACK_C, ACK_D, STOP_A, STOP_B, STOP_C, FINISH
    } state_t;
    state_t state;
    logic [QW-1:0] q;
    logic [2:0] bit_index;
    logic [7:0] shift;
    logic want_stop;

    wire q_done = (q == QW'(QUARTER - 1));
    assign busy = (state != IDLE);

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE; q <= '0; bit_index <= '0; shift <= '0; want_stop <= 1'b0;
            done <= 1'b0; ack_error <= 1'b0;
            scl_drive_low <= 1'b0; sda_drive_low <= 1'b0;
        end else begin
            done <= 1'b0;
            if (state == IDLE) begin
                q <= '0;
                if (start) begin
                    shift <= data; bit_index <= 3'd7; want_stop <= do_stop;
                    // Without a START the bus is already ours with SCL low.
                    if (do_start) state <= START_A; else state <= BIT_A;
                end
            end else if (!q_done) begin
                q <= q + 1'b1;
            end else begin
                q <= '0;
                case (state)
                    // START: SDA falls while SCL is high, then SCL falls.
                    START_A: begin sda_drive_low <= 1'b1; state <= START_B; end
                    START_B: begin scl_drive_low <= 1'b1; state <= BIT_A; end
                    // One bit: set SDA with SCL low, raise SCL, hold, lower SCL.
                    BIT_A: begin sda_drive_low <= !shift[7]; state <= BIT_B; end
                    BIT_B: begin scl_drive_low <= 1'b0; state <= BIT_C; end
                    BIT_C: begin state <= BIT_D; end
                    BIT_D: begin
                        scl_drive_low <= 1'b1;
                        if (bit_index == 3'd0) state <= ACK_A;
                        else begin shift <= {shift[6:0], 1'b0}; bit_index <= bit_index - 1'b1; state <= BIT_A; end
                    end
                    // ACK: release SDA, raise SCL, sample, lower SCL.
                    ACK_A: begin sda_drive_low <= 1'b0; state <= ACK_B; end
                    ACK_B: begin scl_drive_low <= 1'b0; state <= ACK_C; end
                    ACK_C: begin ack_error <= sda_in; state <= ACK_D; end
                    ACK_D: begin
                        scl_drive_low <= 1'b1;
                        if (want_stop) state <= STOP_A; else state <= FINISH;
                    end
                    // STOP: SDA low, SCL high, SDA released while SCL high.
                    STOP_A: begin sda_drive_low <= 1'b1; state <= STOP_B; end
                    STOP_B: begin scl_drive_low <= 1'b0; state <= STOP_C; end
                    STOP_C: begin sda_drive_low <= 1'b0; state <= FINISH; end
                    FINISH: begin done <= 1'b1; state <= IDLE; end
                    default: state <= IDLE;
                endcase
            end
        end
    end
endmodule
