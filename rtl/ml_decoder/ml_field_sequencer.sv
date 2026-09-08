// SPDX-License-Identifier: MIT
// DCF77 field extraction: walks the last minute of soft_history, sorts each
// second's AM evidence into the field it belongs to per the standard DCF77
// telegram (bits 21-28 minute, 29-35 hour, 36-57 date, 16/17/19 zone and
// announcement flags), and time-shares minute_candidate_search,
// hour_candidate_search and calendar_candidate_search across all of it --
// no field gets its own dedicated correlator.
//
// This module owns soft_history's read port outright; it does not share it
// with ml_decoder_controller's own (currently unused) scan interface.
module ml_field_sequencer #(
    parameter int HISTORY_DEPTH = 3600,
    parameter int HISTORY_ADDR_BITS = $clog2(HISTORY_DEPTH),
    parameter int EVIDENCE_BITS = 16,
    parameter int SCAN_DEPTH = 60,
    parameter bit QUALIFICATION_ENABLED = 1'b0,
    // Each of the 8 minute-field evidence values saturates at
    // +-2^(EVIDENCE_BITS-1) (am_bit_extractor's own saturating output), so
    // a correctly-decoded candidate where every bit agrees could in
    // principle reach 8x that magnitude. Requiring only 1/16 of that
    // theoretical maximum still rejects a candidate whose "win" over the
    // other 59 is really just noise finding the least-bad match, while
    // staying reachable by a real signal nowhere near full-scale
    // confidence per bit. A calibration constant, not a measured one --
    // re-validate once real receiver SNR is characterized on hardware.
    parameter logic signed [EVIDENCE_BITS+3:0] MINUTE_MIN_SCORE =
        (EVIDENCE_BITS > 2) ? (1 << (EVIDENCE_BITS - 2)) : 1,
    // A quarter of the qualifying floor: flipping even one bit swings the
    // score by 2x that bit's own evidence, so the runner-up must trail by
    // more than a single marginal bit's worth of separation.
    parameter logic [EVIDENCE_BITS+3:0] MINUTE_MIN_GAP = MINUTE_MIN_SCORE >> 2,
    // Same derivation as MINUTE_MIN_SCORE, scaled for the hour field's 7
    // evidence bits instead of the minute field's 8.
    parameter logic signed [EVIDENCE_BITS+2:0] HOUR_MIN_SCORE =
        (EVIDENCE_BITS > 1) ? ((7 * (1 << (EVIDENCE_BITS - 1))) >> 4) : 1,
    parameter logic [EVIDENCE_BITS+2:0] HOUR_MIN_GAP = HOUR_MIN_SCORE >> 2
) (
    input  logic clk,
    input  logic rst,

    // Pulses once per completed minute (minute_result_valid).
    input  logic start,
    output logic busy,

    // soft_history read port (this module is its sole reader).
    input  logic [HISTORY_ADDR_BITS-1:0] history_write_pointer,
    output logic history_read_enable,
    output logic [HISTORY_ADDR_BITS-1:0] history_read_address,
    input  logic history_read_valid,
    input  logic signed [EVIDENCE_BITS-1:0] history_am_evidence,
    input  logic history_sample_valid,
    input  logic [5:0] history_second_position,

    output logic result_valid,
    output logic [5:0] out_minute,
    output logic out_minute_confident,
    // Minute-value decode confidence (not to be confused with the
    // second/minute-boundary sync quality tracked elsewhere): how
    // strongly the winning minute candidate beat the runner-up.
    output logic signed [EVIDENCE_BITS+3:0] out_minute_best_score,
    output logic [EVIDENCE_BITS+3:0] out_minute_quality_gap,
    output logic [4:0] out_hour,
    output logic out_hour_confident,
    output logic [5:0] out_day,
    output logic [2:0] out_weekday,
    output logic [3:0] out_month,
    output logic [7:0] out_year,
    output logic out_cest,
    output logic out_dst_announcement,
    output logic out_leap_announcement
);
    localparam int MINUTE_SCORE_BITS = EVIDENCE_BITS + 4;
    localparam int HOUR_SCORE_BITS = EVIDENCE_BITS + 3;

    localparam [3:0] S_IDLE          = 4'd0;
    localparam [3:0] S_SCAN_REQ      = 4'd1;
    localparam [3:0] S_SCAN_WAIT     = 4'd2;
    localparam [3:0] S_MINHOUR_START = 4'd3;
    localparam [3:0] S_MINHOUR_WAIT  = 4'd4;
    localparam [3:0] S_CAL_LOAD      = 4'd5;
    localparam [3:0] S_CAL_START     = 4'd6;
    localparam [3:0] S_CAL_WAIT      = 4'd7;
    localparam [3:0] S_DONE          = 4'd8;

    reg [3:0] state;
    reg [$clog2(SCAN_DEPTH+1)-1:0] scan_count;
    reg [HISTORY_ADDR_BITS-1:0] scan_addr;
    reg [1:0] cal_field;   // 0=day, 1=weekday, 2=month, 3=year
    reg [3:0] cal_load_idx;

    // Per-field evidence caches, indexed by bit-within-field. Real bit
    // counts: day 6 (units 4 + tens 2), weekday 3 (direct binary),
    // month 5 (units 4 + tens 1), year 8 (units 4 + tens 4).
    reg signed [EVIDENCE_BITS-1:0] day_cache     [0:5];
    reg signed [EVIDENCE_BITS-1:0] weekday_cache [0:2];
    reg signed [EVIDENCE_BITS-1:0] month_cache   [0:4];
    reg signed [EVIDENCE_BITS-1:0] year_cache    [0:7];
    reg signed [EVIDENCE_BITS-1:0] z1_evidence, a1_evidence, a2_evidence;

    reg minute_done, hour_done;
    reg [5:0] minute_latched;
    reg minute_confident_latched;
    reg signed [MINUTE_SCORE_BITS-1:0] minute_score_latched;
    reg [MINUTE_SCORE_BITS-1:0] minute_gap_latched;
    reg [4:0] hour_latched;
    reg hour_confident_latched;
    reg [5:0] day_latched;
    reg [2:0] weekday_latched;
    reg [3:0] month_latched;
    reg [7:0] year_latched;

    wire minute_load_valid = history_read_valid && history_sample_valid &&
        (history_second_position >= 6'd21) && (history_second_position <= 6'd28);
    wire hour_load_valid = history_read_valid && history_sample_valid &&
        (history_second_position >= 6'd29) && (history_second_position <= 6'd35);
    // Both offsets are always in [0,7] here (gated by *_load_valid's own
    // range check above), so only the low 3 bits of the 6-bit subtraction
    // are ever meaningful.
    wire [2:0] minute_bit_offset = history_second_position[2:0] - 3'd5;
    wire [2:0] hour_bit_offset = history_second_position[2:0] - 3'd5;

    reg minute_ld_valid, hour_ld_valid;
    reg [2:0] minute_ld_idx, hour_ld_idx;
    reg minute_start_p, hour_start_p;
    wire unused_minute_busy, unused_hour_busy;
    wire minute_result_p, hour_result_p;
    wire minute_confident_p, hour_confident_p;
    wire [5:0] minute_p;
    wire [4:0] hour_p;
    wire signed [MINUTE_SCORE_BITS-1:0] minute_score_p;
    wire [MINUTE_SCORE_BITS-1:0] minute_gap_p;
    wire signed [HOUR_SCORE_BITS-1:0] unused_hour_score;
    wire [HOUR_SCORE_BITS-1:0] unused_hour_gap;

    minute_candidate_search #(
        .SOFT_BITS(EVIDENCE_BITS), .SCORE_BITS(MINUTE_SCORE_BITS),
        .QUALIFICATION_ENABLED(QUALIFICATION_ENABLED),
        .MIN_SCORE(MINUTE_MIN_SCORE), .MIN_GAP(MINUTE_MIN_GAP)
    ) minute_i (
        .clk(clk), .rst(rst), .load_valid(minute_ld_valid), .load_index(minute_ld_idx),
        .soft_bit(history_am_evidence), .start(minute_start_p), .busy(unused_minute_busy),
        .result_valid(minute_result_p), .confident(minute_confident_p),
        .minute(minute_p), .best_score(minute_score_p), .quality_gap(minute_gap_p)
    );

    hour_candidate_search #(
        .SOFT_BITS(EVIDENCE_BITS), .SCORE_BITS(HOUR_SCORE_BITS),
        .QUALIFICATION_ENABLED(QUALIFICATION_ENABLED),
        .MIN_SCORE(HOUR_MIN_SCORE), .MIN_GAP(HOUR_MIN_GAP)
    ) hour_i (
        .clk(clk), .rst(rst), .load_valid(hour_ld_valid), .load_index(hour_ld_idx),
        .soft_bit(history_am_evidence), .start(hour_start_p), .busy(unused_hour_busy),
        .result_valid(hour_result_p), .confident(hour_confident_p),
        .hour(hour_p), .best_score(unused_hour_score), .quality_gap(unused_hour_gap)
    );

    reg cal_load_valid, cal_start_p;
    reg [3:0] cal_load_index;
    // Registered, not combinational: it is captured in the same cycle
    // (and from the same pre-increment cal_load_idx) as cal_load_index,
    // one cycle before calendar_candidate_search actually samples it.
    // Deriving it combinationally from cal_load_idx instead left it one
    // step ahead of cal_load_index by the time the engine used it,
    // loading every evidence slot from its own next-door neighbour.
    reg signed [EVIDENCE_BITS-1:0] cal_soft_bit;
    wire unused_cal_busy, cal_result_p;
    wire [7:0] cal_best_value;
    wire signed [EVIDENCE_BITS+3:0] unused_cal_score, unused_cal_second;
    wire [EVIDENCE_BITS+3:0] unused_cal_gap;

    calendar_candidate_search #(.SOFT_BITS(EVIDENCE_BITS)) calendar_i (
        .clk(clk), .rst(rst), .load_valid(cal_load_valid), .load_index(cal_load_index),
        .soft_bit(cal_soft_bit), .field({1'b0, cal_field}), .start(cal_start_p),
        .busy(unused_cal_busy), .result_valid(cal_result_p), .best_value(cal_best_value),
        .best_score(unused_cal_score), .second_score(unused_cal_second),
        .quality_gap(unused_cal_gap)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            busy <= 1'b0;
            result_valid <= 1'b0;
            history_read_enable <= 1'b0;
            scan_count <= '0;
            minute_done <= 1'b0; hour_done <= 1'b0;
            minute_ld_valid <= 1'b0; hour_ld_valid <= 1'b0;
            minute_start_p <= 1'b0; hour_start_p <= 1'b0;
            cal_load_valid <= 1'b0; cal_start_p <= 1'b0;
            cal_field <= '0; cal_load_idx <= '0;
            out_cest <= 1'b0; out_dst_announcement <= 1'b0; out_leap_announcement <= 1'b0;
        end else begin
            result_valid   <= 1'b0;
            history_read_enable <= 1'b0;
            minute_ld_valid <= 1'b0; hour_ld_valid <= 1'b0;
            minute_start_p  <= 1'b0; hour_start_p  <= 1'b0;
            cal_load_valid  <= 1'b0; cal_start_p   <= 1'b0;

            if (minute_result_p) begin
                minute_done <= 1'b1;
                minute_latched <= minute_p;
                minute_confident_latched <= minute_confident_p;
                minute_score_latched <= minute_score_p;
                minute_gap_latched <= minute_gap_p;
            end
            if (hour_result_p) begin
                hour_done <= 1'b1;
                hour_latched <= hour_p;
                hour_confident_latched <= hour_confident_p;
            end

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy <= 1'b1;
                        scan_count <= '0;
                        scan_addr <= (history_write_pointer == '0) ?
                                     HISTORY_ADDR_BITS'(HISTORY_DEPTH - 1) :
                                     history_write_pointer - 1'b1;
                        minute_done <= 1'b0; hour_done <= 1'b0;
                        state <= S_SCAN_REQ;
                    end
                end

                S_SCAN_REQ: begin
                    history_read_enable <= 1'b1;
                    history_read_address <= scan_addr;
                    state <= S_SCAN_WAIT;
                end

                S_SCAN_WAIT: begin
                    if (history_read_valid) begin
                        if (minute_load_valid) begin
                            minute_ld_valid <= 1'b1;
                            // Bits 21-28 -> index 0-7; the full 6-bit
                            // subtraction result always fits in 3 bits
                            // here since minute_load_valid already
                            // bounds second_position to [21,28].
                            minute_ld_idx <= minute_bit_offset[2:0];
                        end
                        if (hour_load_valid) begin
                            hour_ld_valid <= 1'b1;
                            // Bits 29-35 -> index 0-6, same reasoning.
                            hour_ld_idx <= hour_bit_offset[2:0];
                        end
                        if (history_sample_valid) begin
                            case (history_second_position)
                                6'd16: a1_evidence <= history_am_evidence;
                                6'd17: z1_evidence <= history_am_evidence;
                                6'd19: a2_evidence <= history_am_evidence;
                                6'd36: day_cache[0] <= history_am_evidence;
                                6'd37: day_cache[1] <= history_am_evidence;
                                6'd38: day_cache[2] <= history_am_evidence;
                                6'd39: day_cache[3] <= history_am_evidence;
                                6'd40: day_cache[4] <= history_am_evidence;
                                6'd41: day_cache[5] <= history_am_evidence;
                                6'd42: weekday_cache[0] <= history_am_evidence;
                                6'd43: weekday_cache[1] <= history_am_evidence;
                                6'd44: weekday_cache[2] <= history_am_evidence;
                                6'd45: month_cache[0] <= history_am_evidence;
                                6'd46: month_cache[1] <= history_am_evidence;
                                6'd47: month_cache[2] <= history_am_evidence;
                                6'd48: month_cache[3] <= history_am_evidence;
                                6'd49: month_cache[4] <= history_am_evidence;
                                6'd50: year_cache[0] <= history_am_evidence;
                                6'd51: year_cache[1] <= history_am_evidence;
                                6'd52: year_cache[2] <= history_am_evidence;
                                6'd53: year_cache[3] <= history_am_evidence;
                                6'd54: year_cache[4] <= history_am_evidence;
                                6'd55: year_cache[5] <= history_am_evidence;
                                6'd56: year_cache[6] <= history_am_evidence;
                                6'd57: year_cache[7] <= history_am_evidence;
                                default: ;
                            endcase
                        end

                        if (scan_count == $clog2(SCAN_DEPTH+1)'(SCAN_DEPTH - 1)) begin
                            state <= S_MINHOUR_START;
                        end else begin
                            scan_count <= scan_count + 1'b1;
                            scan_addr <= (scan_addr == '0) ?
                                         HISTORY_ADDR_BITS'(HISTORY_DEPTH - 1) :
                                         scan_addr - 1'b1;
                            state <= S_SCAN_REQ;
                        end
                    end
                end

                S_MINHOUR_START: begin
                    minute_start_p <= 1'b1;
                    hour_start_p   <= 1'b1;
                    state <= S_MINHOUR_WAIT;
                end

                S_MINHOUR_WAIT: begin
                    if (minute_done && hour_done) begin
                        cal_field <= 2'd0;
                        cal_load_idx <= '0;
                        state <= S_CAL_LOAD;
                    end
                end

                S_CAL_LOAD: begin
                    cal_load_valid <= 1'b1;
                    cal_load_index <= cal_load_idx;
                    // Evidence to load for this cal_field/cal_load_idx:
                    // real bits come from the caches above, indices
                    // beyond a field's real bit count are forced to
                    // zero so they cannot bias the score
                    // (calendar_candidate_search's evidence array
                    // persists across field switches and is not reset
                    // by them).
                    case (cal_field)
                        2'd0: cal_soft_bit <=
                            (cal_load_idx < 4'd6) ? day_cache[cal_load_idx[2:0]] : '0;
                        2'd1: cal_soft_bit <=
                            (cal_load_idx < 4'd3) ? weekday_cache[cal_load_idx[1:0]] : '0;
                        2'd2: cal_soft_bit <=
                            (cal_load_idx < 4'd5) ? month_cache[cal_load_idx[2:0]] : '0;
                        default: cal_soft_bit <=
                            (cal_load_idx < 4'd8) ? year_cache[cal_load_idx[2:0]] : '0;
                    endcase
                    if (cal_load_idx == 4'd8) begin
                        state <= S_CAL_START;
                    end else begin
                        cal_load_idx <= cal_load_idx + 1'b1;
                    end
                end

                S_CAL_START: begin
                    cal_start_p <= 1'b1;
                    state <= S_CAL_WAIT;
                end

                S_CAL_WAIT: begin
                    if (cal_result_p) begin
                        case (cal_field)
                            2'd0: day_latched     <= cal_best_value[5:0];
                            2'd1: weekday_latched <= cal_best_value[2:0];
                            2'd2: month_latched   <= cal_best_value[3:0];
                            default: year_latched <= cal_best_value;
                        endcase
                        if (cal_field == 2'd3) begin
                            state <= S_DONE;
                        end else begin
                            cal_field <= cal_field + 1'b1;
                            cal_load_idx <= '0;
                            state <= S_CAL_LOAD;
                        end
                    end
                end

                S_DONE: begin
                    out_minute            <= minute_latched;
                    out_minute_confident  <= minute_confident_latched;
                    out_minute_best_score <= minute_score_latched;
                    out_minute_quality_gap<= minute_gap_latched;
                    out_hour              <= hour_latched;
                    out_hour_confident    <= hour_confident_latched;
                    out_day               <= day_latched[5:0];
                    out_weekday           <= weekday_latched[2:0];
                    out_month             <= month_latched[3:0];
                    out_year              <= year_latched;
                    out_cest              <= (z1_evidence > 0);
                    out_dst_announcement  <= (a1_evidence > 0);
                    out_leap_announcement <= (a2_evidence > 0);
                    result_valid <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    initial begin
        if (SCAN_DEPTH < 59)
            $error("ml_field_sequencer: SCAN_DEPTH must cover at least one minute");
    end

endmodule
