// ML decoder controller, checked from the ports for arbitrary frames:
// publish_valid is a one-clock pulse that only follows a frame, carries
// the candidate of that frame, and only after CONSISTENT_FRAMES frames
// have been seen since reset with the consistent counter saturated; a
// frame with an unannounced leap second or an impossible date never
// publishes; the civil-time outputs change only on a frame and, once a
// baseline exists, always hold a valid calendar date and time; the
// history scan only reads while busy and never addresses beyond the
// history depth.
module ml_decoder_controller_formal;
    localparam int CF = 3;
    localparam int HD = 6;             // not a power of two: address bound is real
    localparam int HAB = $clog2(HD);

    (* gclk *) logic clk;
    (* anyseq *) logic scan_start, history_read_valid, frame_valid;
    (* anyseq *) logic [HAB-1:0] history_write_pointer;
    (* anyseq *) logic [5:0] candidate_minute, candidate_day;
    (* anyseq *) logic [4:0] candidate_hour;
    (* anyseq *) logic [2:0] candidate_weekday;
    (* anyseq *) logic [3:0] candidate_month;
    (* anyseq *) logic [7:0] candidate_year;
    (* anyseq *) logic candidate_cest, candidate_dst_announcement;
    (* anyseq *) logic candidate_leap_announcement, candidate_leap_second;
    (* anyseq *) logic signed [7:0] level_best_score, level_second_score;
    logic rst = 1'b1;
    logic past_valid = 1'b0;
    logic history_read_enable, scan_busy, publish_valid;
    logic [HAB-1:0] history_read_address;
    logic [5:0] minute, day; logic [4:0] hour; logic [2:0] weekday;
    logic [3:0] month; logic [7:0] year;
    logic cest, dst_announcement, leap_announcement;
    logic [7:0] score_gap;
    logic [$clog2(CF+1)-1:0] consistent_count;

    ml_decoder_controller #(
        .SCORE_BITS(8), .CONSISTENT_FRAMES(CF), .HISTORY_DEPTH(HD)
    ) dut (.*);

    // Frames are minute events: never on consecutive clocks; the write
    // pointer stays inside the history.
    always_comb begin
        assume(history_write_pointer < HAB'(HD));
    end
    logic [2:0] frames_seen = '0;

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;
        if (past_valid) assume(!(frame_valid && $past(frame_valid)));

        // Count the frames the DUT acts on (its reset is the current rst).
        if (!rst && frame_valid && frames_seen != 3'd7) frames_seen <= frames_seen + 1'b1;

        if (past_valid && !$past(rst)) begin

            assert(!(publish_valid && $past(publish_valid)));
            if (publish_valid) begin
                assert($past(frame_valid));
                assert(frames_seen >= CF);
                assert(consistent_count == CF);
                assert(minute == $past(candidate_minute) && hour == $past(candidate_hour));
                assert(day == $past(candidate_day) && weekday == $past(candidate_weekday));
                assert(month == $past(candidate_month) && year == $past(candidate_year));
                assert(cest == $past(candidate_cest));
            end
            if ($past(frame_valid) && $past(candidate_leap_second) &&
                !$past(candidate_leap_announcement))
                assert(!publish_valid);
            if ($past(frame_valid) &&
                !dcf77_calendar_pkg::valid_date($past(candidate_year), $past(candidate_month),
                                                $past(candidate_day)))
                assert(!publish_valid);
            if (!$past(frame_valid)) begin
                assert({minute, hour, day, weekday, month, year, cest} ==
                       $past({minute, hour, day, weekday, month, year, cest}));
                assert(consistent_count == $past(consistent_count));
            end
            if (consistent_count != 0) begin
                assert(dcf77_calendar_pkg::valid_date(year, month, day));
                assert(minute < 6'd60 && hour < 5'd24);
                assert(weekday >= 3'd1 && weekday <= 3'd7);
            end

            if (history_read_enable) assert(scan_busy);
            assert(history_read_address < HAB'(HD));
            cover(publish_valid);
            cover($past(scan_busy) && !scan_busy);
        end
    end
endmodule
