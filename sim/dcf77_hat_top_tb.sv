`timescale 1ns/1ps
module dcf77_hat_top_tb;
    logic clk = 0, reset_n = 0, hat_reset_n = 1, adc_sdo = 0;
    logic adc_conv, adc_sck, pga_sck, pga_mosi, pga_cs_n;
    logic spi_miso, irq, uart_tx, hat_pps, pps_ref;
    logic sample_ce, sample_valid, second_ce, adc_fault, ch1_activity;
    logic [2:0] lock_state;
    tri lcd_scl, lcd_sda;
    always #4 clk = !clk;

    dcf77_hat_top #(
        .SIM_CLOCK_BYPASS(1), .RESET_CYCLES(3), .PHASE_BITS(24),
        .SAMPLE_NOMINAL_INC(24'd131072), .ADC_CONV_CYCLES(1),
        .ADC_SCK_HALF_CYCLES(1), .SECOND_CYCLES(8),
        .SECOND_SEARCH_TOLERANCE(2), .SECOND_TRACK_WINDOW(2),
        .SECOND_ACQUIRE_HITS(2), .PPS_PULSE_CYCLES(2), .HISTORY_DEPTH(16)
    ) dut (
        .clk_25m(clk), .reset_n(reset_n), .adc_conv(adc_conv),
        .adc_sck(adc_sck), .adc_sdo(adc_sdo), .pga_sck(pga_sck),
        .pga_mosi(pga_mosi), .pga_cs_n(pga_cs_n), .hat_spi_mosi(1'b0),
        .hat_spi_miso(spi_miso), .hat_spi_sclk(1'b0), .hat_spi_cs_n(1'b1),
        .hat_irq(irq), .hat_reset_n(hat_reset_n), .hat_uart_tx(uart_tx),
        .hat_uart_rx(1'b1), .hat_pps(hat_pps), .pps_ref(pps_ref),
        .lcd_scl(lcd_scl), .lcd_sda(lcd_sda), .lcd_rst_n(), .lcd_bl_en(),
        .diag_sample_ce(sample_ce), .diag_sample_valid(sample_valid),
        .diag_second_ce(second_ce), .diag_lock_state(lock_state),
        .diag_adc_fault(adc_fault), .diag_ch1_activity(ch1_activity));

    integer requests = 0, samples = 0;
    always @(posedge clk) begin
        if (sample_ce) requests <= requests + 1;
        if (sample_valid) samples <= samples + 1;
    end
    initial begin
        repeat (2) @(posedge clk); reset_n <= 1;
        wait (sample_valid); repeat (400) @(posedge clk);
        if (requests < 2 || samples < 1) $fatal(1, "ADC path did not run");
        if (pga_cs_n !== 1'b1 || pga_sck !== 1'b0) $fatal(1, "PGA not idle");
        if (adc_fault !== 1'b0) $fatal(1, "scheduler overran ADC");
        $display("PASS: top reset, scheduler, ADC CH0 path and interfaces");
        $finish;
    end
endmodule
