// SPDX-License-Identifier: MIT
//
// DCF77 date/time telemetry formatter.
//
// A frame_request snapshots already-decoded BCD fields and emits:
//   $DCF77,YYYYMMDD,HHMMSS,+HHMM,S,QQQ*CS\r\n
// CS is the XOR of bytes strictly between '$' and '*'.  The caller schedules
// frame_request in the quiet 993..999 ms tail; this block never starts a frame
// unless explicitly requested.  Fields remain stable internally until done.

module time_telemetry (
    input  logic        clk,
    input  logic        rst,
    input  logic        frame_request,

    input  logic [15:0] year_bcd,
    input  logic [7:0]  month_bcd,
    input  logic [7:0]  day_bcd,
    input  logic [7:0]  hour_bcd,
    input  logic [7:0]  minute_bcd,
    input  logic [7:0]  second_bcd,
    input  logic        utc_offset_negative,
    input  logic [15:0] utc_offset_bcd,
    // 0 = unsynchronized, 1 = locked, 2 = holdover.
    input  logic [1:0]  receiver_state,
    input  logic [11:0] quality_bcd,

    output logic [7:0]  tx_data,
    output logic        tx_valid,
    input  logic        tx_ready,
    output logic        busy,
    // One-cycle pulse after the LF byte has been accepted.
    output logic        frame_done
);

    localparam logic [1:0] STATE_UNSYNC   = 2'd0;
    localparam logic [1:0] STATE_LOCKED   = 2'd1;
    localparam logic [1:0] STATE_HOLDOVER = 2'd2;
    localparam int unsigned FRAME_BYTES = 39;

    logic [15:0] year_q;
    logic [7:0] month_q, day_q, hour_q, minute_q, second_q;
    logic offset_negative_q;
    logic [15:0] offset_q;
    logic [1:0] state_q;
    logic [11:0] quality_q;
    logic [5:0] byte_index;
    logic [7:0] checksum;

    function automatic logic [7:0] ascii_digit(input logic [3:0] digit);
        ascii_digit = 8'h30 + {4'd0, digit};
    endfunction

    function automatic logic [7:0] state_character(input logic [1:0] state_value);
        case (state_value)
            STATE_LOCKED:   state_character = "L";
            STATE_HOLDOVER: state_character = "H";
            default:        state_character = "U";
        endcase
    endfunction

    function automatic logic [7:0] hex_character(input logic [3:0] nibble);
        hex_character = (nibble < 10) ? (8'h30 + nibble) : (8'h41 + nibble - 10);
    endfunction

    always_comb begin
        case (byte_index)
            0:  tx_data = "$";
            1:  tx_data = "D";
            2:  tx_data = "C";
            3:  tx_data = "F";
            4, 5: tx_data = "7";
            6, 15, 22, 28, 30: tx_data = ",";
            7:  tx_data = ascii_digit(year_q[15:12]);
            8:  tx_data = ascii_digit(year_q[11:8]);
            9:  tx_data = ascii_digit(year_q[7:4]);
            10: tx_data = ascii_digit(year_q[3:0]);
            11: tx_data = ascii_digit(month_q[7:4]);
            12: tx_data = ascii_digit(month_q[3:0]);
            13: tx_data = ascii_digit(day_q[7:4]);
            14: tx_data = ascii_digit(day_q[3:0]);
            16: tx_data = ascii_digit(hour_q[7:4]);
            17: tx_data = ascii_digit(hour_q[3:0]);
            18: tx_data = ascii_digit(minute_q[7:4]);
            19: tx_data = ascii_digit(minute_q[3:0]);
            20: tx_data = ascii_digit(second_q[7:4]);
            21: tx_data = ascii_digit(second_q[3:0]);
            23: tx_data = offset_negative_q ? "-" : "+";
            24: tx_data = ascii_digit(offset_q[15:12]);
            25: tx_data = ascii_digit(offset_q[11:8]);
            26: tx_data = ascii_digit(offset_q[7:4]);
            27: tx_data = ascii_digit(offset_q[3:0]);
            29: tx_data = state_character(state_q);
            31: tx_data = ascii_digit(quality_q[11:8]);
            32: tx_data = ascii_digit(quality_q[7:4]);
            33: tx_data = ascii_digit(quality_q[3:0]);
            34: tx_data = "*";
            35: tx_data = hex_character(checksum[7:4]);
            36: tx_data = hex_character(checksum[3:0]);
            37: tx_data = 8'h0d;
            38: tx_data = 8'h0a;
            default: tx_data = 8'h00;
        endcase
    end

    assign tx_valid = busy;

    always_ff @(posedge clk) begin
        if (rst) begin
            year_q            <= '0;
            month_q           <= '0;
            day_q             <= '0;
            hour_q            <= '0;
            minute_q          <= '0;
            second_q          <= '0;
            offset_negative_q <= 1'b0;
            offset_q          <= '0;
            state_q           <= STATE_UNSYNC;
            quality_q         <= '0;
            byte_index        <= '0;
            checksum          <= '0;
            busy              <= 1'b0;
            frame_done        <= 1'b0;
        end else begin
            frame_done <= 1'b0;

            if (!busy) begin
                if (frame_request) begin
                    year_q            <= year_bcd;
                    month_q           <= month_bcd;
                    day_q             <= day_bcd;
                    hour_q            <= hour_bcd;
                    minute_q          <= minute_bcd;
                    second_q          <= second_bcd;
                    offset_negative_q <= utc_offset_negative;
                    offset_q          <= utc_offset_bcd;
                    state_q           <= receiver_state;
                    quality_q         <= quality_bcd;
                    byte_index        <= 0;
                    checksum          <= 0;
                    busy              <= 1'b1;
                end
            end else if (tx_ready) begin
                if ((byte_index >= 1) && (byte_index <= 33))
                    checksum <= checksum ^ tx_data;

                if (byte_index == FRAME_BYTES - 1) begin
                    busy       <= 1'b0;
                    frame_done <= 1'b1;
                end else begin
                    byte_index <= byte_index + 1'b1;
                end
            end
        end
    end

endmodule
