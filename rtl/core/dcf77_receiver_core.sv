// SPDX-License-Identifier: MIT
// Board-independent DCF77 receiver core: signed ADC samples in, qualified
// civil time, PPS and UART telemetry out.
//
// Everything from the Engeler detector onward lives here so that the HAT
// top (and later a standalone variant) only adds clocking, the ADC serial
// interface and pin mapping around one shared core, and so that a system
// test can drive the whole decode chain at one sample per clock without
// paying for the serial ADC protocol.
module dcf77_receiver_core #(
    parameter int SECOND_CYCLES = 77_500,
    parameter int SECOND_SEARCH_TOLERANCE = 1_000,
    parameter int SECOND_TRACK_WINDOW = 2_000,
    parameter int SECOND_ACQUIRE_HITS = 2,
    // Detector timing/bandwidth knobs (see engeler_detector); defaults are
    // the real 77.5 kHz / 930 kS/s values, overridden only by
    // time-compressed simulation.
    parameter int CYCLES_PER_CHIP = 120,
    parameter int CHIP_COUNT = 512,
    parameter logic signed [18:0] CARRIER_SCALE = 19'sd131059,
    parameter logic signed [18:0] AM_SCALE      = 19'sd130993,
    parameter logic signed [18:0] PM_SCALE      = 19'sd126157,
    parameter int PPS_PULSE_CYCLES = 12_500_000,
    parameter int HISTORY_DEPTH = 3600,
    parameter bit QUALIFICATION_ENABLED = 1'b1,
    parameter int CONSISTENT_FRAMES = 3,
    parameter int unsigned ACQUIRE_RESULTS = 3,
    parameter int unsigned EXIT_FAILURES = 2,
    parameter bit HOLDOVER_ENABLED = 1'b1,
    parameter int unsigned HOLDOVER_TICKS = 60
) (
    input  logic clk,
    input  logic rst,
    input  logic sample_ce,
    input  logic signed [13:0] sample,
    // Frequency-discipline correction for the fractional sample scheduler.
    output logic signed [23:0] trim_inc,
    output logic second_ce,
    output logic [5:0] second_number,
    output logic time_valid,
    output logic pps_valid,
    output logic [2:0] lock_state,
    output logic ml_locked,
    output logic minute_locked,
    output logic frequency_locked,
    output logic detector_overflow,
    output logic minute_result_valid,
    output logic [7:0] phase_quality,
    output logic [5:0] decoded_minute,
    output logic [4:0] decoded_hour,
    output logic [5:0] decoded_day,
    output logic [2:0] decoded_weekday,
    output logic [3:0] decoded_month,
    output logic [7:0] decoded_year,
    output logic decoded_cest,
    output logic uart_tx,
    output logic pps,
    output logic pps_ref,
    output logic telemetry_done
);
    localparam int HIST_AW = (HISTORY_DEPTH < 2) ? 1 : $clog2(HISTORY_DEPTH);
    logic signed [23:0] estimated_offset;
    logic am_valid, pm_valid, detector_minute_locked;
    logic signed [17:0] phase_error;
    logic phase_outlier, pm_inverted;
    logic [15:0] detector_measurement_age;
    logic [1:0] sync_state;
    logic signed [31:0] am_soft;
    logic signed [41:0] pm_soft;
    logic [5:0] minute_window_end;
    logic [46:0] minute_best, minute_gap;
    logic signed [32:0] carrier_real, carrier_imag;
    logic discipline_locked, discipline_rejected;
    logic [15:0] discipline_age;
    logic [HIST_AW-1:0] history_wp, history_ra;
    logic history_full, history_re, history_rv, history_sample_valid;
    logic signed [15:0] history_am, history_pm;
    logic [7:0] history_quality;
    logic [5:0] history_second;
    logic ml_scan_busy, ml_publish;
    logic decoded_dst, decoded_leap;
    logic [19:0] ml_gap; logic [1:0] consistent_count;
    logic telemetry_busy;

    // One coherent AM+PM soft-evidence record per elapsed second, and its
    // field-extraction/time-shared ML decode (see second_evidence_aggregator
    // and ml_field_sequencer for why am_valid/pm_valid cannot drive
    // soft_history directly).
    logic evidence_write_valid, evidence_sample_valid;
    logic signed [15:0] evidence_am, evidence_pm;
    logic [7:0] evidence_quality;
    logic [5:0] evidence_second_position;

    logic fs_busy, fs_result_valid;
    logic [5:0] fs_minute; logic fs_minute_confident;
    logic signed [19:0] fs_minute_best_score; logic [19:0] fs_minute_gap;
    logic [4:0] fs_hour; logic fs_hour_confident;
    logic [5:0] fs_day; logic [2:0] fs_weekday;
    logic [3:0] fs_month; logic [7:0] fs_year;
    logic fs_cest, fs_dst_announcement, fs_leap_announcement;
    // ml_decoder_controller's own history scan interface is not driven
    // by real soft_history data (ml_field_sequencer is its sole reader);
    // these two catch its otherwise-dangling scan address/enable outputs.
    logic history_re_unused;
    logic [HIST_AW-1:0] history_ra_unused;

    engeler_detector #(.SECOND_CYCLES(SECOND_CYCLES),
        .SECOND_SEARCH_TOLERANCE(SECOND_SEARCH_TOLERANCE),
        .SECOND_TRACK_WINDOW(SECOND_TRACK_WINDOW),
        .SECOND_ACQUIRE_HITS(SECOND_ACQUIRE_HITS),
        .CYCLES_PER_CHIP(CYCLES_PER_CHIP), .CHIP_COUNT(CHIP_COUNT),
        .CARRIER_SCALE(CARRIER_SCALE), .AM_SCALE(AM_SCALE), .PM_SCALE(PM_SCALE),
        .QUALIFICATION_ENABLED(QUALIFICATION_ENABLED)) detector_i (
        .clk(clk), .rst(rst), .sample_ce(sample_ce), .sample(sample),
        .second_ce(second_ce), .second_phase_error(phase_error),
        .second_phase_quality(phase_quality), .second_measurement_outlier(phase_outlier),
        .second_measurement_age(detector_measurement_age), .second_sync_state(sync_state),
        .am_soft_bit(am_soft), .am_bit_valid(am_valid), .pm_correlation(pm_soft),
        .pm_correlation_valid(pm_valid), .minute_result_valid(minute_result_valid),
        .minute_locked(detector_minute_locked), .minute_window_end(minute_window_end),
        .pm_polarity_inverted(pm_inverted), .minute_best_magnitude(minute_best),
        .minute_quality_gap(minute_gap), .carrier_real(carrier_real),
        .carrier_imag(carrier_imag), .detector_overflow(detector_overflow));

    frequency_discipline discipline_i (
        .clk(clk), .rst(rst), .measurement_ce(second_ce),
        .measurement_valid(!phase_outlier && sync_state != 0),
        .phase_error({{6{phase_error[17]}},phase_error}),
        .measurement_quality(phase_quality), .estimated_offset(estimated_offset),
        .trim_inc(trim_inc), .frequency_locked(discipline_locked),
        .measurement_rejected(discipline_rejected), .measurement_age(discipline_age));

    // second_number is the DCF77 second index stamped on every history
    // record, so the field sequencer can sort evidence into telegram
    // fields. It is a free-running counter aligned by pm_minute_sync: that
    // block reports, once per 60 PM seconds, the search position at which
    // the 15-second minute-marker window ended -- DCF77 second 14 -- and
    // its result lands while the PM sample of search position 59 is being
    // processed, i.e. during second (14 + 59 - end) mod 60. The next
    // second_ce therefore starts second (74 - end) mod 60. Only a
    // qualified marker (or an unqualified build) may realign, and a
    // change to an established alignment must be confirmed by two
    // consecutive results: when one minute's marker is damaged (dropout),
    // the search's best window can be the next marker shifted by a
    // second -- still strong enough to qualify -- and a single such
    // result would otherwise move every history record off by one.
    logic realign_pending;
    logic [5:0] realign_value;
    logic [6:0] realign_raw;
    logic [5:0] realign_now, expected_next;
    logic candidate_valid;
    logic [5:0] candidate_value;
    always_comb begin
        realign_raw = 7'd74 - 7'(minute_window_end);
        realign_now = (realign_raw >= 7'd60) ? 6'(realign_raw - 7'd60) : 6'(realign_raw);
        expected_next = (second_number == 6'd59) ? 6'd0 : second_number + 1'b1;
    end
    wire result_qualified = minute_result_valid &&
                            (detector_minute_locked || !QUALIFICATION_ENABLED);
    wire realign_allowed = result_qualified && (realign_now != expected_next) &&
                           candidate_valid && (candidate_value == realign_now);

    always_ff @(posedge clk) begin
        if (rst) begin
            second_number <= 0;
            realign_pending <= 1'b0;
            realign_value <= '0;
            candidate_valid <= 1'b0;
            candidate_value <= '0;
        end else begin
            if (result_qualified) begin
                if (realign_now == expected_next || realign_allowed) begin
                    candidate_valid <= 1'b0;
                end else begin
                    candidate_valid <= 1'b1;
                    candidate_value <= realign_now;
                end
            end
            if (realign_allowed) begin
                realign_pending <= 1'b1;
                realign_value <= realign_now;
            end
            if (second_ce) begin
                realign_pending <= 1'b0;
                if (realign_allowed)
                    second_number <= realign_now;
                else if (realign_pending)
                    second_number <= realign_value;
                else
                    second_number <= expected_next;
            end
        end
    end
    // soft_history is a RAM: after reset (or power-up) it still holds
    // whatever was there before, including records flagged valid. Only
    // decode once a full minute of records has been written since reset,
    // so a frame can never be assembled from stale or random memory.
    logic [5:0] records_written;
    always_ff @(posedge clk) begin
        if (rst)
            records_written <= '0;
        else if (evidence_write_valid && records_written != 6'd60)
            records_written <= records_written + 1'b1;
    end
    // Decode one telegram per aligned minute: the second_ce that closes
    // second 1 guarantees the records for seconds 16..58 of the telegram
    // that just ended are all written (second 59's write, and second 0's,
    // may still be in flight but carry no telegram fields).
    wire frame_start = second_ce && (second_number == 6'd1) &&
                       (records_written == 6'd60);
    // am_bit_valid and pm_correlation_valid never pulse on the same
    // carrier cycle (AM resolves ~300 ms into the second, PM near its
    // end): aggregate both into one coherent per-second record before
    // it ever reaches soft_history.
    second_evidence_aggregator evidence_i (
        .clk(clk), .rst(rst), .second_ce(second_ce),
        .second_position(second_number),
        .am_valid(am_valid), .am_evidence_in(am_soft[31:16]),
        .pm_valid(pm_valid), .pm_evidence_in(pm_soft[41:26]),
        .quality_in(phase_quality),
        .write_valid(evidence_write_valid), .am_evidence(evidence_am),
        .pm_evidence(evidence_pm), .sample_valid(evidence_sample_valid),
        .quality(evidence_quality), .second_position_out(evidence_second_position));

    soft_history #(.DEPTH(HISTORY_DEPTH), .EVIDENCE_BITS(16), .ADDR_BITS(HIST_AW)) history_i (
        .clk(clk), .rst(rst), .write_valid(evidence_write_valid), .am_evidence(evidence_am),
        .pm_evidence(evidence_pm), .sample_valid(evidence_sample_valid),
        .quality(evidence_quality), .second_position(evidence_second_position),
        .write_pointer(history_wp), .history_full(history_full),
        .read_enable(history_re), .read_address(history_ra), .read_valid(history_rv),
        .read_am_evidence(history_am), .read_pm_evidence(history_pm),
        .read_sample_valid(history_sample_valid), .read_quality(history_quality),
        .read_second_position(history_second));

    // Sole reader of soft_history: sorts one minute's worth of AM
    // evidence into its DCF77 telegram fields and time-shares the three
    // ML search engines across all of them. ml_decoder_controller's own
    // scan interface below is therefore left unconnected to real history
    // data (see its history_read_valid tie-off).
    ml_field_sequencer #(.HISTORY_DEPTH(HISTORY_DEPTH), .HISTORY_ADDR_BITS(HIST_AW),
        .QUALIFICATION_ENABLED(QUALIFICATION_ENABLED)) field_seq_i (
        .clk(clk), .rst(rst), .start(frame_start), .busy(fs_busy),
        .history_write_pointer(history_wp), .history_read_enable(history_re),
        .history_read_address(history_ra), .history_read_valid(history_rv),
        .history_am_evidence(history_am), .history_sample_valid(history_sample_valid),
        .history_second_position(history_second),
        .result_valid(fs_result_valid), .out_minute(fs_minute),
        .out_minute_confident(fs_minute_confident),
        .out_minute_best_score(fs_minute_best_score), .out_minute_quality_gap(fs_minute_gap),
        .out_hour(fs_hour), .out_hour_confident(fs_hour_confident),
        .out_day(fs_day), .out_weekday(fs_weekday), .out_month(fs_month), .out_year(fs_year),
        .out_cest(fs_cest), .out_dst_announcement(fs_dst_announcement),
        .out_leap_announcement(fs_leap_announcement));

    // fs_result_valid alone only means "the sequencer finished sorting one
    // minute's worth of evidence" -- it says nothing about whether the
    // winning minute/hour candidates actually cleared their own MIN_SCORE
    // /MIN_GAP floors. Gating on the confidence flags too is what makes
    // QUALIFICATION_ENABLED and those thresholds (see ml_field_sequencer)
    // actually block a noise-driven frame from ever reaching the
    // continuity/consistent-frame check below.
    wire ml_frame_valid = fs_result_valid && fs_minute_confident && fs_hour_confident;

    ml_decoder_controller #(.HISTORY_DEPTH(HISTORY_DEPTH), .HISTORY_ADDR_BITS(HIST_AW),
        .CONSISTENT_FRAMES(CONSISTENT_FRAMES)) ml_i (
        .clk(clk), .rst(rst), .scan_start(1'b0),
        .history_write_pointer(history_wp), .history_read_valid(1'b0),
        .history_read_enable(history_re_unused), .history_read_address(history_ra_unused),
        .scan_busy(ml_scan_busy),
        .frame_valid(ml_frame_valid), .candidate_minute(fs_minute),
        .candidate_hour(fs_hour), .candidate_day(fs_day), .candidate_weekday(fs_weekday),
        .candidate_month(fs_month), .candidate_year(fs_year), .candidate_cest(fs_cest),
        .candidate_dst_announcement(fs_dst_announcement),
        .candidate_leap_announcement(fs_leap_announcement),
        // Leap-second insertion is signalled by A2 for a full hour before
        // the event but detected by observing a 61-second minute; no
        // block currently tracks minute length to confirm the insertion
        // itself, so this stays a known, documented gap rather than a
        // silently wrong guess.
        .candidate_leap_second(1'b0), .level_best_score(fs_minute_best_score),
        .level_second_score(fs_minute_best_score - $signed(fs_minute_gap)),
        .publish_valid(ml_publish), .minute(decoded_minute), .hour(decoded_hour),
        .day(decoded_day), .weekday(decoded_weekday), .month(decoded_month),
        .year(decoded_year), .cest(decoded_cest), .dst_announcement(decoded_dst),
        .leap_announcement(decoded_leap), .score_gap(ml_gap),
        .consistent_count(consistent_count));

    // ml_publish is a one-cycle pulse two cycles after the sequencer's
    // result; the lock controller samples ml_qualified only on
    // qualification_valid, so it needs a level that holds this frame's
    // verdict, evaluated once the verdict exists -- not the PM search's
    // unrelated once-a-minute pulse, which never coincided with it.
    logic ml_qualified_q;
    logic [1:0] frame_eval_delay;
    always_ff @(posedge clk) begin
        if (rst) begin
            ml_qualified_q <= 1'b0;
            frame_eval_delay <= '0;
        end else begin
            frame_eval_delay <= {frame_eval_delay[0], fs_result_valid};
            if (fs_result_valid) ml_qualified_q <= 1'b0;
            else if (ml_publish) ml_qualified_q <= 1'b1;
        end
    end

    receiver_lock_controller #(.QUALIFICATION_ENABLED(QUALIFICATION_ENABLED),
        .ACQUIRE_RESULTS(ACQUIRE_RESULTS), .EXIT_FAILURES(EXIT_FAILURES),
        .HOLDOVER_ENABLED(HOLDOVER_ENABLED), .HOLDOVER_TICKS(HOLDOVER_TICKS)) lock_i (
        .clk(clk), .rst(rst), .qualification_valid(frame_eval_delay[1]),
        .result_consistent(ml_qualified_q), .ml_qualified(ml_qualified_q),
        .minute_qualified(detector_minute_locked), .frequency_qualified(discipline_locked),
        .holdover_tick(second_ce), .time_valid(time_valid), .pps_valid(pps_valid),
        .ml_locked(ml_locked), .minute_locked(minute_locked),
        .frequency_locked(frequency_locked), .state_code(lock_state));

    pps_uart #(.PPS_PULSE_CYCLES(PPS_PULSE_CYCLES)) user_i (
        .clk(clk), .rst(rst), .second_ce(second_ce), .time_valid(pps_valid),
        .telemetry_request(second_ce && !telemetry_busy), .year_bcd({8'h20,decoded_year}),
        .month_bcd({4'h0,decoded_month}), .day_bcd({2'b0,decoded_day}),
        .hour_bcd({3'b0,decoded_hour}), .minute_bcd({2'b0,decoded_minute}),
        .second_bcd({2'b0,second_number}), .utc_offset_negative(1'b0),
        .utc_offset_bcd(decoded_cest ? 16'h0200 : 16'h0100),
        .receiver_state(lock_state[1:0]), .quality_bcd({4'h0,phase_quality}),
        .pps_ref(pps_ref), .hat_pps(pps), .hat_uart_tx(uart_tx),
        .telemetry_busy(telemetry_busy), .telemetry_done(telemetry_done));

    // minute_best/minute_gap are pm_minute_sync's second/minute-boundary
    // sync confidence (distinct from fs_minute_best_score/fs_minute_gap,
    // the decoded minute *value*'s own confidence, which is what
    // ml_decoder_controller actually needs) -- kept available here for
    // future diagnostics rather than driving anything today.
    wire unused_inputs = history_full ^ discipline_rejected ^ discipline_age[0] ^
                         detector_measurement_age[0] ^ pm_inverted ^ carrier_real[0] ^
                         carrier_imag[0] ^ history_pm[0] ^ history_quality[0] ^
                         ml_scan_busy ^ fs_busy ^ minute_best[0] ^ minute_gap[0] ^
                         estimated_offset[0] ^
                         ml_gap[0] ^ consistent_count[0] ^ decoded_dst ^ decoded_leap ^
                         history_re_unused ^ history_ra_unused[0];
endmodule
