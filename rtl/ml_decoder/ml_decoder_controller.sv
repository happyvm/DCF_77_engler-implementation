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
    localparam int COUNT_BITS = $clog2(CONSISTENT_FRAMES + 1);
    // Calendar helpers are called with an explicit dcf77_calendar_pkg::
    // qualifier rather than "import dcf77_calendar_pkg::*": this
    // project's pinned Yosys (0.50+1) accepts scoped package function
    // calls but its Verilog-2005-based frontend does not parse the
    // "import pkg::*;" declaration ("unexpected TOK_PACKAGESEP").

    // Civil time one minute after the given state, packed as
    // {minute, hour, day, weekday, month, year}. A leap insertion has a
    // labelled second 60, but the following frame is still exactly the
    // next minute: never duplicate or skip its timestamp. The DST steps
    // need the announcement and the candidate's own zone bit.
    function automatic logic [31:0] next_minute_of(
        input logic [5:0] m, input logic [4:0] h, input logic [5:0] d,
        input logic [2:0] wd, input logic [3:0] mo, input logic [7:0] y,
        input logic dst, input logic z, input logic cand_z
    );
        logic [5:0] em, ed; logic [4:0] eh; logic [2:0] ewd; logic [3:0] emo; logic [7:0] ey;
        begin
            em = m; eh = h; ed = d; ewd = wd; emo = mo; ey = y;
            if (m == 59) begin
                em = 0;
                if (dst && !z && cand_z && mo == 3 && wd == 7 && d >= 25 && h == 1)
                    eh = 3; // 01:59 CET -> 03:00 CEST
                else if (dst && z && !cand_z && mo == 10 && wd == 7 && d >= 25 && h == 2)
                    eh = 2; // 02:59 CEST -> 02:00 CET
                else if (h == 23) begin
                    eh = 0;
                    if (d == dcf77_calendar_pkg::month_length(y, mo)) begin
                        ed = 1;
                        if (mo == 12) begin emo = 1; ey = y + 1'b1; end
                        else emo = mo + 1'b1;
                    end else ed = d + 1'b1;
                    ewd = (wd == 7) ? 1 : wd + 1'b1;
                end else eh = h + 1'b1;
            end else em = m + 1'b1;
            next_minute_of = {em, eh, ed, ewd, emo, ey};
        end
    endfunction

    // Shadow candidate: a frame that broke continuity with the published
    // state does not overwrite it (one corrupted minute would otherwise
    // cost two more minutes of continuity); it is remembered here, and
    // the state is re-based on it only if the next frame continues it.
    logic alt_valid;
    logic [5:0] alt_minute, alt_day; logic [4:0] alt_hour;
    logic [2:0] alt_weekday; logic [3:0] alt_month; logic [7:0] alt_year;
    logic alt_cest, alt_dst;

    logic [31:0] expected_main, expected_alt, candidate_packed;
    logic date_ok, continuity, continuity_alt;
    logic [HISTORY_ADDR_BITS:0] scan_remaining;

    always_comb begin
        expected_main = next_minute_of(minute, hour, day, weekday, month, year,
                                       dst_announcement, cest, candidate_cest);
        expected_alt = next_minute_of(alt_minute, alt_hour, alt_day, alt_weekday, alt_month,
                                      alt_year, alt_dst, alt_cest, candidate_cest);
        candidate_packed = {candidate_minute, candidate_hour, candidate_day, candidate_weekday,
                            candidate_month, candidate_year};
        date_ok = dcf77_calendar_pkg::valid_date(candidate_year, candidate_month, candidate_day);
        continuity = (candidate_packed == expected_main) && date_ok &&
                     (cest == candidate_cest || dst_announcement);
        continuity_alt = alt_valid && (candidate_packed == expected_alt) && date_ok &&
                         (alt_cest == candidate_cest || alt_dst);
    end

    task automatic adopt_candidate;
        begin
            minute <= candidate_minute; hour <= candidate_hour; day <= candidate_day;
            weekday <= candidate_weekday; month <= candidate_month; year <= candidate_year;
            cest <= candidate_cest;
            dst_announcement <= candidate_dst_announcement;
            leap_announcement <= candidate_leap_announcement;
            score_gap <= level_best_score - level_second_score;
        end
    endtask

    always_ff @(posedge clk) begin
        if (rst) begin
            publish_valid <= 0; consistent_count <= 0;
            minute <= 0; hour <= 0; day <= 0; weekday <= 0; month <= 0; year <= 0;
            cest <= 0; dst_announcement <= 0; leap_announcement <= 0; score_gap <= 0;
            alt_valid <= 0; alt_minute <= 0; alt_hour <= 0; alt_day <= 0; alt_weekday <= 0;
            alt_month <= 0; alt_year <= 0; alt_cest <= 0; alt_dst <= 0;
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
            if (frame_valid && date_ok) begin
                if (candidate_leap_second && !candidate_leap_announcement) begin
                    // Announcement authorises second 60; an insertion without
                    // A2 breaks qualification rather than changing civil-time
                    // stepping.
                    consistent_count <= 0;
                    alt_valid <= 0;
                end else if (consistent_count == 0) begin
                    // No baseline yet: the candidate becomes it.
                    adopt_candidate();
                    consistent_count <= 1;
                    alt_valid <= 0;
                end else if (continuity) begin
                    adopt_candidate();
                    alt_valid <= 0;
                    if (consistent_count < COUNT_BITS'(CONSISTENT_FRAMES))
                        consistent_count <= consistent_count + 1'b1;
                    if (consistent_count >= COUNT_BITS'(CONSISTENT_FRAMES-1))
                        publish_valid <= 1;
                end else if (continuity_alt) begin
                    // Two consecutive frames agree on a time the published
                    // state does not continue: re-base on them. They count as
                    // two consistent frames; publication still waits for
                    // CONSISTENT_FRAMES of them.
                    adopt_candidate();
                    alt_valid <= 0;
                    consistent_count <= (CONSISTENT_FRAMES < 2) ?
                                        COUNT_BITS'(CONSISTENT_FRAMES) : COUNT_BITS'(2);
                    if (CONSISTENT_FRAMES <= 2)
                        publish_valid <= 1;
                end else begin
                    // Isolated break: coast the published state forward by
                    // the minute that has elapsed (the clock keeps running
                    // through a corrupted frame), remember the stranger, and
                    // drop back to a one-frame run so the next continuous
                    // frame must rebuild confidence.
                    {minute, hour, day, weekday, month, year} <= expected_main;
                    alt_valid <= 1;
                    alt_minute <= candidate_minute; alt_hour <= candidate_hour;
                    alt_day <= candidate_day; alt_weekday <= candidate_weekday;
                    alt_month <= candidate_month; alt_year <= candidate_year;
                    alt_cest <= candidate_cest; alt_dst <= candidate_dst_announcement;
                    consistent_count <= 1;
                end
            end
        end
    end
endmodule
