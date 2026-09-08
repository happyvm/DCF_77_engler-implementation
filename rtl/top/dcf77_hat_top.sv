// SPDX-License-Identifier: MIT
// Complete DCF77 Raspberry Pi HAT integration top.
module dcf77_hat_top #(
    parameter bit SIM_CLOCK_BYPASS = 1'b0,
    parameter int unsigned RESET_CYCLES = 16,
    parameter int PHASE_BITS = 40,
    parameter logic [PHASE_BITS-1:0] SAMPLE_NOMINAL_INC = 40'd8180366511,
    parameter int ADC_CONV_CYCLES = 2,
    parameter int ADC_SCK_HALF_CYCLES = 1,
    parameter int SECOND_CYCLES = 77_500,
    parameter int SECOND_SEARCH_TOLERANCE = 1_000,
    parameter int SECOND_TRACK_WINDOW = 2_000,
    parameter int SECOND_ACQUIRE_HITS = 2,
    parameter int PPS_PULSE_CYCLES = 12_500_000,
    parameter int HISTORY_DEPTH = 3600,
    parameter bit QUALIFICATION_ENABLED = 1'b0
) (
    input  logic clk_25m, input logic reset_n,
    output logic adc_conv, output logic adc_sck, input logic adc_sdo,
    output logic pga_sck, output logic pga_mosi, output logic pga_cs_n,
    input  logic hat_spi_mosi, output logic hat_spi_miso,
    input  logic hat_spi_sclk, input logic hat_spi_cs_n,
    output logic hat_irq, input logic hat_reset_n,
    output logic hat_uart_tx, input logic hat_uart_rx,
    output logic hat_pps, output logic pps_ref,
    inout  wire lcd_scl, inout wire lcd_sda,
    output logic lcd_rst_n, output logic lcd_bl_en,
    output logic diag_sample_ce, output logic diag_sample_valid,
    output logic diag_second_ce, output logic [2:0] diag_lock_state,
    output logic diag_adc_fault, output logic diag_ch1_activity
);
    localparam int HIST_AW = (HISTORY_DEPTH < 2) ? 1 : $clog2(HISTORY_DEPTH);
    logic clk, rst, sample_ce, adc_valid, adc_busy;
    logic signed [13:0] adc_ch0, adc_ch1;
    logic signed [23:0] trim_inc, estimated_offset;
    logic [PHASE_BITS-1:0] sample_phase;
    logic second_ce, am_valid, pm_valid, minute_result_valid, detector_minute_locked;
    logic signed [17:0] phase_error;
    logic [7:0] phase_quality;
    logic phase_outlier, detector_overflow, pm_inverted;
    logic [15:0] detector_measurement_age;
    logic [1:0] sync_state;
    logic signed [31:0] am_soft;
    logic signed [41:0] pm_soft;
    logic [5:0] minute_window_end;
    logic [46:0] minute_best, minute_gap;
    logic signed [32:0] carrier_real, carrier_imag;
    logic discipline_locked, discipline_rejected;
    logic [15:0] discipline_age;
    logic time_valid, pps_valid, ml_locked, minute_locked, frequency_locked;
    logic [HIST_AW-1:0] history_wp, history_ra;
    logic history_full, history_re, history_rv, history_sample_valid;
    logic signed [15:0] history_am, history_pm;
    logic [7:0] history_quality;
    logic [5:0] history_second;
    logic ml_scan_busy, ml_publish;
    logic [5:0] decoded_minute; logic [4:0] decoded_hour;
    logic [5:0] decoded_day; logic [2:0] decoded_weekday;
    logic [3:0] decoded_month; logic [7:0] decoded_year;
    logic decoded_cest, decoded_dst, decoded_leap;
    logic [19:0] ml_gap; logic [1:0] consistent_count;
    logic telemetry_busy, telemetry_done;
    logic [5:0] second_number;

    clock_reset_ecp5 #(.SIM_BYPASS(SIM_CLOCK_BYPASS), .RESET_CYCLES(RESET_CYCLES)) clocks_i (
        .clk_25mhz(clk_25m), .ext_reset_n(reset_n & hat_reset_n),
        .clk_125mhz(clk), .rst(rst));

    sample_scheduler #(.PHASE_BITS(PHASE_BITS), .NOMINAL_INC(SAMPLE_NOMINAL_INC)) scheduler_i (
        .clk(clk), .rst(rst), .trim_inc(trim_inc), .sample_ce(sample_ce),
        .sample_phase(sample_phase));
    adc_if #(.CONV_CYCLES(ADC_CONV_CYCLES), .SCK_HALF_CYCLES(ADC_SCK_HALF_CYCLES)) adc_i (
        .clk(clk), .rst(rst), .sample_ce(sample_ce), .adc_conv(adc_conv),
        .adc_sck(adc_sck), .adc_sdo(adc_sdo), .ch0_sample(adc_ch0),
        .ch1_sample(adc_ch1), .sample_valid(adc_valid), .busy(adc_busy),
        .adc_fault(diag_adc_fault));

    // CH0 is the receiver input. CH1 never enters the control path and remains
    // available as a low-cost analogue diagnostic.
    engeler_detector #(.SECOND_CYCLES(SECOND_CYCLES),
        .SECOND_SEARCH_TOLERANCE(SECOND_SEARCH_TOLERANCE),
        .SECOND_TRACK_WINDOW(SECOND_TRACK_WINDOW),
        .SECOND_ACQUIRE_HITS(SECOND_ACQUIRE_HITS)) detector_i (
        .clk(clk), .rst(rst), .sample_ce(adc_valid), .sample(adc_ch0),
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

    always_ff @(posedge clk) begin
        if (rst) second_number <= 0;
        else if (second_ce) second_number <= second_number == 59 ? 0 : second_number + 1'b1;
    end
    soft_history #(.DEPTH(HISTORY_DEPTH), .EVIDENCE_BITS(16), .ADDR_BITS(HIST_AW)) history_i (
        .clk(clk), .rst(rst), .write_valid(am_valid), .am_evidence(am_soft[31:16]),
        .pm_evidence(pm_soft[41:26]), .sample_valid(am_valid && pm_valid),
        .quality(phase_quality), .second_position(second_number),
        .write_pointer(history_wp), .history_full(history_full),
        .read_enable(history_re), .read_address(history_ra), .read_valid(history_rv),
        .read_am_evidence(history_am), .read_pm_evidence(history_pm),
        .read_sample_valid(history_sample_valid), .read_quality(history_quality),
        .read_second_position(history_second));

    ml_decoder_controller #(.HISTORY_DEPTH(HISTORY_DEPTH), .HISTORY_ADDR_BITS(HIST_AW)) ml_i (
        .clk(clk), .rst(rst), .scan_start(minute_result_valid),
        .history_write_pointer(history_wp), .history_read_valid(history_rv),
        .history_read_enable(history_re), .history_read_address(history_ra), .scan_busy(ml_scan_busy),
        .frame_valid(minute_result_valid), .candidate_minute(minute_window_end),
        .candidate_hour(5'd0), .candidate_day(6'd1), .candidate_weekday(3'd1),
        .candidate_month(4'd1), .candidate_year(8'd24), .candidate_cest(1'b0),
        .candidate_dst_announcement(1'b0), .candidate_leap_announcement(1'b0),
        .candidate_leap_second(1'b0), .level_best_score(minute_best[19:0]),
        .level_second_score(minute_best[19:0]-minute_gap[19:0]),
        .publish_valid(ml_publish), .minute(decoded_minute), .hour(decoded_hour),
        .day(decoded_day), .weekday(decoded_weekday), .month(decoded_month),
        .year(decoded_year), .cest(decoded_cest), .dst_announcement(decoded_dst),
        .leap_announcement(decoded_leap), .score_gap(ml_gap),
        .consistent_count(consistent_count));

    receiver_lock_controller #(.QUALIFICATION_ENABLED(QUALIFICATION_ENABLED)) lock_i (
        .clk(clk), .rst(rst), .qualification_valid(minute_result_valid),
        .result_consistent(ml_publish), .ml_qualified(ml_publish),
        .minute_qualified(detector_minute_locked), .frequency_qualified(discipline_locked),
        .holdover_tick(second_ce), .time_valid(time_valid), .pps_valid(pps_valid),
        .ml_locked(ml_locked), .minute_locked(minute_locked),
        .frequency_locked(frequency_locked), .state_code(diag_lock_state));

    pps_uart #(.PPS_PULSE_CYCLES(PPS_PULSE_CYCLES)) user_i (
        .clk(clk), .rst(rst), .second_ce(second_ce), .time_valid(pps_valid),
        .telemetry_request(second_ce && !telemetry_busy), .year_bcd({8'h20,decoded_year}),
        .month_bcd({4'h0,decoded_month}), .day_bcd({2'b0,decoded_day}),
        .hour_bcd({3'b0,decoded_hour}), .minute_bcd({2'b0,decoded_minute}),
        .second_bcd({2'b0,second_number}), .utc_offset_negative(1'b0),
        .utc_offset_bcd(decoded_cest ? 16'h0200 : 16'h0100),
        .receiver_state(diag_lock_state[1:0]), .quality_bcd({4'h0,phase_quality}),
        .pps_ref(pps_ref), .hat_pps(hat_pps), .hat_uart_tx(hat_uart_tx),
        .telemetry_busy(telemetry_busy), .telemetry_done(telemetry_done));

    assign pga_sck = 1'b0; assign pga_mosi = 1'b0; assign pga_cs_n = 1'b1;
    assign lcd_scl = 1'bz; assign lcd_sda = 1'bz;
    assign lcd_rst_n = !rst; assign lcd_bl_en = time_valid;
    assign hat_spi_miso = hat_spi_cs_n ? 1'b0 :
                          (hat_spi_mosi ? detector_overflow : diag_lock_state[0]);
    assign hat_irq = minute_result_valid | diag_adc_fault;
    assign diag_sample_ce = sample_ce; assign diag_sample_valid = adc_valid;
    assign diag_second_ce = second_ce;
    assign diag_ch1_activity = |adc_ch1;
    wire unused_inputs = hat_spi_sclk ^ hat_uart_rx ^ adc_busy ^ history_full ^
                         discipline_rejected ^ discipline_age[0] ^ sample_phase[0] ^
                         detector_measurement_age[0] ^ pm_inverted ^ carrier_real[0] ^
                         carrier_imag[0] ^ history_am[0] ^ history_pm[0] ^
                         history_sample_valid ^ history_quality[0] ^ history_second[0] ^
                         ml_scan_busy ^ telemetry_done;
endmodule
