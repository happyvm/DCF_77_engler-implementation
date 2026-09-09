// $DCF77 telemetry formatter, checked on the tx_valid/tx_ready stream
// alone: tx_valid mirrors busy, tx_data holds while a byte waits for
// tx_ready, a frame is exactly 39 accepted bytes framed by '$' ... '*',
// two hex digits, CR, LF, the checksum digits equal the XOR of the bytes
// between '$' and '*', the fields are the ones sampled at frame_request,
// frame_done is a single-cycle pulse on the LF acceptance, and a
// frame_request during a frame neither restarts nor lengthens it.
module time_telemetry_formal;
    (* gclk *) logic clk;
    (* anyseq *) logic frame_request, tx_ready, utc_offset_negative;
    (* anyseq *) logic [15:0] year_bcd, utc_offset_bcd;
    (* anyseq *) logic [7:0] month_bcd, day_bcd, hour_bcd, minute_bcd, second_bcd;
    (* anyseq *) logic [1:0] receiver_state;
    (* anyseq *) logic [11:0] quality_bcd;
    logic rst = 1'b1;
    logic past_valid = 1'b0;
    logic [7:0] tx_data;
    logic tx_valid, busy, frame_done;

    time_telemetry dut (.*);

    logic [5:0] accepted = '0;
    logic [7:0] xor_sum = '0;
    logic [7:0] hi_digit = '0;
    logic [15:0] year_s = '0;
    logic [7:0] hour_s = '0, minute_s = '0;
    logic [1:0] state_s = '0;

    function automatic logic [7:0] hex_char(input logic [3:0] n);
        hex_char = (n < 10) ? (8'h30 + n) : (8'h41 + n - 10);
    endfunction

    wire accept = tx_valid && tx_ready;

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;

        if (past_valid && !$past(rst)) begin
            assert(tx_valid == busy);
            assert(!(frame_done && $past(frame_done)));
            if (frame_done) assert($past(busy) && !busy && $past(tx_ready));

            // Data stable while a byte is waiting to be accepted.
            if ($past(tx_valid) && !$past(tx_ready) && tx_valid)
                assert(tx_data == $past(tx_data));

            if ($past(frame_request) && !$past(busy)) begin
                accepted <= '0; xor_sum <= '0;
                year_s <= $past(year_bcd); hour_s <= $past(hour_bcd);
                minute_s <= $past(minute_bcd); state_s <= $past(receiver_state);
                assert(busy);
            end

            if (accept) begin
                accepted <= accepted + 1'b1;
                if (accepted >= 1 && accepted <= 33) xor_sum <= xor_sum ^ tx_data;
                case (accepted)
                    6'd0:  assert(tx_data == "$");
                    6'd1:  assert(tx_data == "D");
                    6'd6, 6'd15, 6'd22, 6'd28, 6'd30: assert(tx_data == ",");
                    6'd7:  assert(tx_data == 8'h30 + {4'd0, year_s[15:12]});
                    6'd10: assert(tx_data == 8'h30 + {4'd0, year_s[3:0]});
                    6'd16: assert(tx_data == 8'h30 + {4'd0, hour_s[7:4]});
                    6'd19: assert(tx_data == 8'h30 + {4'd0, minute_s[3:0]});
                    6'd29: assert(tx_data == (state_s == 2'd1 ? "L" : state_s == 2'd2 ? "H" : "U"));
                    6'd34: assert(tx_data == "*");
                    6'd35: begin
                        assert(tx_data == hex_char(xor_sum[7:4]));
                        hi_digit <= tx_data;
                    end
                    6'd36: assert(tx_data == hex_char(xor_sum[3:0]));
                    6'd37: assert(tx_data == 8'h0d);
                    6'd38: assert(tx_data == 8'h0a);
                    default: ;
                endcase
            end
            // The frame ends exactly on the LF acceptance, and only there.
            if (frame_done) assert($past(accepted) == 6'd38 && $past(accept));
            if ($past(accept) && $past(accepted) == 6'd38) assert(frame_done && !busy);
            if ($past(accept) && $past(accepted) < 6'd38) assert(busy);
        end
    end
endmodule
