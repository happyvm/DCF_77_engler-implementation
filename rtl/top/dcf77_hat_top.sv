// SPDX-License-Identifier: MIT
// Complete DCF77 Raspberry Pi HAT integration top: ECP5 clocking, the
// fractional sample scheduler and the LTC1407A serial interface wrapped
// around the board-independent dcf77_receiver_core.
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
    // The release profile (this default) runs real qualification end to
    // end: pm_minute_sync's PM-marker lock, the ML minute/hour decode
    // confidence gates, and receiver_lock_controller's own
    // acquire/exit-hysteresis and holdover all gate on this, each against
    // thresholds derived (not left at an all-pass zero) in the modules
    // they belong to. A build that must publish time unconditionally for
    // bench debugging can still override this to 1'b0 explicitly.
    parameter bit QUALIFICATION_ENABLED = 1'b1,
    // Consecutive fully-qualified minutes ml_decoder_controller requires
    // before publish_valid, and receiver_lock_controller's own
    // acquire/exit/holdover hysteresis. Exposed so a system-level test can
    // shorten acquisition without touching either module's own default,
    // which stays the real hardware value.
    parameter int CONSISTENT_FRAMES = 3,
    parameter int unsigned ACQUIRE_RESULTS = 3,
    parameter int unsigned EXIT_FAILURES = 2,
    parameter bit HOLDOVER_ENABLED = 1'b1,
    parameter int unsigned HOLDOVER_TICKS = 60,
    // LTC6912-1 gain nibbles programmed once after reset (docs/22): channel
    // A is the receive path at the power-up gain of 100 V/V (0111), channel
    // B is unused and held in software shutdown (1000). No AGC yet: the
    // gain is fixed and deterministic.
    parameter logic [3:0] PGA_GAIN_A = 4'b0111,
    parameter logic [3:0] PGA_GAIN_B = 4'b1000,
    parameter int unsigned PGA_SCK_HZ = 100_000,
    parameter int unsigned CLK_HZ = 125_000_000,
    // Reported in the HAT SPI register map (major.minor).
    parameter logic [15:0] RTL_VERSION = 16'h0001
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
    logic clk, rst, sample_ce, adc_valid, adc_busy;
    logic signed [13:0] adc_ch0, adc_ch1;
    logic signed [23:0] trim_inc;
    logic [PHASE_BITS-1:0] sample_phase;
    logic second_ce, time_valid, pps_valid, minute_result_valid, detector_overflow;
    logic ml_locked, minute_locked, frequency_locked;
    logic telemetry_done;
    logic [5:0] second_number;
    logic [7:0] phase_quality;
    logic [5:0] decoded_minute; logic [4:0] decoded_hour;
    logic [5:0] decoded_day; logic [2:0] decoded_weekday;
    logic [3:0] decoded_month; logic [7:0] decoded_year;
    logic decoded_cest;

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
    dcf77_receiver_core #(
        .SECOND_CYCLES(SECOND_CYCLES),
        .SECOND_SEARCH_TOLERANCE(SECOND_SEARCH_TOLERANCE),
        .SECOND_TRACK_WINDOW(SECOND_TRACK_WINDOW),
        .SECOND_ACQUIRE_HITS(SECOND_ACQUIRE_HITS),
        .PPS_PULSE_CYCLES(PPS_PULSE_CYCLES), .HISTORY_DEPTH(HISTORY_DEPTH),
        .QUALIFICATION_ENABLED(QUALIFICATION_ENABLED),
        .CONSISTENT_FRAMES(CONSISTENT_FRAMES), .ACQUIRE_RESULTS(ACQUIRE_RESULTS),
        .EXIT_FAILURES(EXIT_FAILURES), .HOLDOVER_ENABLED(HOLDOVER_ENABLED),
        .HOLDOVER_TICKS(HOLDOVER_TICKS)
    ) core_i (
        .clk(clk), .rst(rst), .sample_ce(adc_valid), .sample(adc_ch0),
        .trim_inc(trim_inc), .second_ce(second_ce), .second_number(second_number),
        .time_valid(time_valid), .pps_valid(pps_valid), .lock_state(diag_lock_state),
        .ml_locked(ml_locked), .minute_locked(minute_locked), .frequency_locked(frequency_locked),
        .detector_overflow(detector_overflow), .minute_result_valid(minute_result_valid),
        .phase_quality(phase_quality),
        .decoded_minute(decoded_minute), .decoded_hour(decoded_hour),
        .decoded_day(decoded_day), .decoded_weekday(decoded_weekday),
        .decoded_month(decoded_month), .decoded_year(decoded_year),
        .decoded_cest(decoded_cest),
        .uart_tx(hat_uart_tx), .pps(hat_pps), .pps_ref(pps_ref),
        .telemetry_done(telemetry_done));

    logic pga_busy, pga_done;
    pga_spi_master #(.CLK_HZ(CLK_HZ), .SCK_HZ(PGA_SCK_HZ)) pga_i (
        .clk(clk), .rst(rst), .send(1'b0), .gain_a(PGA_GAIN_A), .gain_b(PGA_GAIN_B),
        .pga_sck(pga_sck), .pga_mosi(pga_mosi), .pga_cs_n(pga_cs_n),
        .busy(pga_busy), .done(pga_done));

    // Raspberry Pi status/time register map (see hat_spi_slave for the
    // layout). UART remains the primary time channel; this is control and
    // diagnostics.
    logic [7:0] hat_control;
    logic hat_transaction_done;
    hat_spi_slave #(.RTL_VERSION(RTL_VERSION)) hat_spi_i (
        .clk(clk), .rst(rst),
        .spi_sclk(hat_spi_sclk), .spi_mosi(hat_spi_mosi), .spi_cs_n(hat_spi_cs_n),
        .spi_miso(hat_spi_miso),
        .lock_state(diag_lock_state), .time_valid(time_valid), .pps_valid(pps_valid),
        .ml_locked(ml_locked), .minute_locked(minute_locked),
        .frequency_locked(frequency_locked), .adc_fault(diag_adc_fault),
        .detector_overflow(detector_overflow), .phase_quality(phase_quality),
        .second(second_number), .minute(decoded_minute), .hour(decoded_hour),
        .day(decoded_day), .weekday(decoded_weekday), .month(decoded_month),
        .year(decoded_year), .cest(decoded_cest), .trim_inc(trim_inc),
        .control(hat_control), .transaction_done(hat_transaction_done));

    assign lcd_scl = 1'bz; assign lcd_sda = 1'bz;
    assign lcd_rst_n = !rst; assign lcd_bl_en = time_valid;
    assign hat_irq = minute_result_valid | diag_adc_fault;
    assign diag_sample_ce = sample_ce; assign diag_sample_valid = adc_valid;
    assign diag_second_ce = second_ce;
    assign diag_ch1_activity = |adc_ch1;
    wire unused_inputs = hat_uart_rx ^ adc_busy ^ sample_phase[0] ^
                         pga_busy ^ pga_done ^ telemetry_done ^
                         hat_control[0] ^ hat_transaction_done;
endmodule
