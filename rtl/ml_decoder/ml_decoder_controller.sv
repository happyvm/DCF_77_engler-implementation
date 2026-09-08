// SPDX-License-Identifier: MIT
// Calendar/continuity controller for the time-shared ML searches.  The minute
// and hour engines remain single correlators; this block qualifies their output
// against consecutive frames and advances the complete civil-time candidate.
module ml_decoder_controller #(
    parameter int SCORE_BITS = 20,
    parameter int CONSISTENT_FRAMES = 3,
    parameter int HISTORY_DEPTH = 3600,
    parameter int HISTORY_ADDR_BITS = $clog2(HISTORY_DEPTH)
) (
    input logic clk, input logic rst,
    input logic scan_start,
    input logic [HISTORY_ADDR_BITS-1:0] history_write_pointer,
    input logic history_read_valid,
    output logic history_read_enable,
    output logic [HISTORY_ADDR_BITS-1:0] history_read_address,
    output logic scan_busy,
    input logic frame_valid,
    input logic [5:0] candidate_minute,
    input logic [4:0] candidate_hour,
    input logic [5:0] candidate_day,
    input logic [2:0] candidate_weekday,
    input logic [3:0] candidate_month,
    input logic [7:0] candidate_year,
    input logic candidate_cest,
    input logic candidate_dst_announcement,
    input logic candidate_leap_announcement,
    input logic candidate_leap_second,
    input logic signed [SCORE_BITS-1:0] level_best_score,
    input logic signed [SCORE_BITS-1:0] level_second_score,
    output logic publish_valid,
    output logic [5:0] minute,
    output logic [4:0] hour,
    output logic [5:0] day,
    output logic [2:0] weekday,
    output logic [3:0] month,
    output logic [7:0] year,
    output logic cest,
    output logic dst_announcement,
    output logic leap_announcement,
    output logic [SCORE_BITS-1:0] score_gap,
    output logic [$clog2(CONSISTENT_FRAMES+1)-1:0] consistent_count
);
    import dcf77_calendar_pkg::*;
    logic [5:0] exp_minute, exp_day;
    logic [4:0] exp_hour;
    logic [2:0] exp_weekday;
    logic [3:0] exp_month;
    logic [7:0] exp_year;
    logic continuity;
    logic [HISTORY_ADDR_BITS:0] scan_remaining;

    always_comb begin
        exp_minute = minute; exp_hour = hour; exp_day = day;
        exp_weekday = weekday; exp_month = month; exp_year = year;
        // A leap insertion has a labelled second 60, but the following frame is
        // still exactly the next minute: never duplicate or skip its timestamp.
        if (minute == 59) begin
            exp_minute = 0;
            if (dst_announcement && !cest && candidate_cest &&
                month == 3 && weekday == 7 && day >= 25 && hour == 1)
                exp_hour = 3; // 01:59 CET -> 03:00 CEST
            else if (dst_announcement && cest && !candidate_cest &&
                     month == 10 && weekday == 7 && day >= 25 && hour == 2)
                exp_hour = 2; // 02:59 CEST -> 02:00 CET
            else if (hour == 23) begin
                exp_hour = 0;
                if (day == month_length(year, month)) begin
                    exp_day = 1;
                    if (month == 12) begin exp_month = 1; exp_year = year + 1'b1; end
                    else exp_month = month + 1'b1;
                end else exp_day = day + 1'b1;
                exp_weekday = (weekday == 7) ? 1 : weekday + 1'b1;
            end else exp_hour = hour + 1'b1;
        end else exp_minute = minute + 1'b1;
        continuity = candidate_minute == exp_minute && candidate_hour == exp_hour &&
                     candidate_day == exp_day && candidate_weekday == exp_weekday &&
                     candidate_month == exp_month && candidate_year == exp_year &&
                     valid_date(candidate_year, candidate_month, candidate_day) &&
                     (cest == candidate_cest || dst_announcement);
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            publish_valid <= 0; consistent_count <= 0;
            minute <= 0; hour <= 0; day <= 0; weekday <= 0; month <= 0; year <= 0;
            cest <= 0; dst_announcement <= 0; leap_announcement <= 0; score_gap <= 0;
            history_read_enable <= 0; history_read_address <= 0;
            scan_busy <= 0; scan_remaining <= 0;
        end else begin
            publish_valid <= 0;
            history_read_enable <= 0;
            // Walk newest-to-oldest.  The synchronous memory's read_valid is
            // the pacing acknowledgement, so only a small number of scoring
            // engines is needed regardless of the 3600-entry depth.
            if (scan_start && !scan_busy) begin
                history_read_address <= history_write_pointer == 0 ?
                                        HISTORY_DEPTH-1 : history_write_pointer-1'b1;
                scan_remaining <= HISTORY_DEPTH;
                scan_busy <= 1;
                history_read_enable <= 1;
            end else if (scan_busy && history_read_valid) begin
                if (scan_remaining == 1) begin
                    scan_busy <= 0; scan_remaining <= 0;
                end else begin
                    scan_remaining <= scan_remaining-1'b1;
                    history_read_address <= history_read_address == 0 ?
                                            HISTORY_DEPTH-1 : history_read_address-1'b1;
                    history_read_enable <= 1;
                end
            end
            if (frame_valid && valid_date(candidate_year,candidate_month,candidate_day)) begin
                if (consistent_count == 0 || !continuity) consistent_count <= 1;
                else if (consistent_count < CONSISTENT_FRAMES)
                    consistent_count <= consistent_count + 1'b1;
                minute <= candidate_minute; hour <= candidate_hour; day <= candidate_day;
                weekday <= candidate_weekday; month <= candidate_month; year <= candidate_year;
                cest <= candidate_cest;
                dst_announcement <= candidate_dst_announcement;
                leap_announcement <= candidate_leap_announcement;
                score_gap <= level_best_score - level_second_score;
                // Announcement authorises second 60; an insertion without A2
                // breaks qualification rather than changing civil-time stepping.
                if (candidate_leap_second && !candidate_leap_announcement)
                    consistent_count <= 0;
                else if (continuity && consistent_count >= CONSISTENT_FRAMES-1)
                    publish_valid <= 1;
            end
        end
    end
endmodule
