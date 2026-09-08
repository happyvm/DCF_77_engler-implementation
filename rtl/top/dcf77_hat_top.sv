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
    parameter int unsigned HOLDOVER_TICKS = 60
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
        .detector_overflow(detector_overflow), .minute_result_valid(minute_result_valid),
        .phase_quality(phase_quality),
        .decoded_minute(decoded_minute), .decoded_hour(decoded_hour),
        .decoded_day(decoded_day), .decoded_weekday(decoded_weekday),
        .decoded_month(decoded_month), .decoded_year(decoded_year),
        .decoded_cest(decoded_cest),
        .uart_tx(hat_uart_tx), .pps(hat_pps), .pps_ref(pps_ref),
        .telemetry_done(telemetry_done));

    assign pga_sck = 1'b0; assign pga_mosi = 1'b0; assign pga_cs_n = 1'b1;
    assign lcd_scl = 1'bz; assign lcd_sda = 1'bz;
    assign lcd_rst_n = !rst; assign lcd_bl_en = time_valid;
    assign hat_spi_miso = hat_spi_cs_n ? 1'b0 :
                          (hat_spi_mosi ? detector_overflow : diag_lock_state[0]);
    assign hat_irq = minute_result_valid | diag_adc_fault;
    assign diag_sample_ce = sample_ce; assign diag_sample_valid = adc_valid;
    assign diag_second_ce = second_ce;
    assign diag_ch1_activity = |adc_ch1;
    // Decoded fields, second counter and quality are exported by the core
    // for the future SPI HAT register map; until that lands they have no
    // consumer at this level beyond the UART/PPS the core already drives.
    wire unused_inputs = hat_spi_sclk ^ hat_uart_rx ^ adc_busy ^ sample_phase[0] ^
                         pps_valid ^ telemetry_done ^ second_number[0] ^
                         phase_quality[0] ^ decoded_minute[0] ^ decoded_hour[0] ^
                         decoded_day[0] ^ decoded_weekday[0] ^ decoded_month[0] ^
                         decoded_year[0] ^ decoded_cest;
endmodule
