// SPDX-License-Identifier: MIT
// Integration wrapper for the two low-rate timing outputs.

module pps_uart #(
    parameter int unsigned CLK_HZ = 125_000_000,
    parameter int unsigned BAUD = 115_200,
    parameter int unsigned PPS_PULSE_CYCLES = 12_500_000
) (
    input  logic clk,
    input  logic rst,
    input  logic second_ce,
    input  logic time_valid,
    input  logic telemetry_request,
    input  logic [15:0] year_bcd,
    input  logic [7:0] month_bcd,
    input  logic [7:0] day_bcd,
    input  logic [7:0] hour_bcd,
    input  logic [7:0] minute_bcd,
    input  logic [7:0] second_bcd,
    input  logic utc_offset_negative,
    input  logic [15:0] utc_offset_bcd,
    input  logic [1:0] receiver_state,
    input  logic [11:0] quality_bcd,
    output logic pps_ref,
    output logic hat_pps,
    output logic hat_uart_tx,
    output logic telemetry_busy,
    output logic telemetry_done
);

    logic [7:0] uart_data;
    logic uart_valid;
    logic uart_ready;
    logic pps_internal;

    assign pps_ref = pps_internal;
    assign hat_pps = pps_internal;

    pps_generator #(.PULSE_CYCLES(PPS_PULSE_CYCLES)) pps_i (
        .clk(clk), .rst(rst), .second_ce(second_ce),
        .time_valid(time_valid), .pps(pps_internal)
    );

    time_telemetry formatter_i (
        .clk(clk), .rst(rst), .frame_request(telemetry_request),
        .year_bcd(year_bcd), .month_bcd(month_bcd), .day_bcd(day_bcd),
        .hour_bcd(hour_bcd), .minute_bcd(minute_bcd), .second_bcd(second_bcd),
        .utc_offset_negative(utc_offset_negative),
        .utc_offset_bcd(utc_offset_bcd), .receiver_state(receiver_state),
        .quality_bcd(quality_bcd), .tx_data(uart_data),
        .tx_valid(uart_valid), .tx_ready(uart_ready),
        .busy(telemetry_busy), .frame_done(telemetry_done)
    );

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) uart_i (
        .clk(clk), .rst_n(!rst), .data(uart_data), .valid(uart_valid),
        .ready(uart_ready), .tx(hat_uart_tx)
    );

endmodule
