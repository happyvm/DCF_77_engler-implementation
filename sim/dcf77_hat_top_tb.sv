`timescale 1ns/1ps
module dcf77_hat_top_tb;
    logic clk = 0, reset_n = 0, hat_reset_n = 1, adc_sdo = 0;
    logic adc_conv, adc_sck, pga_sck, pga_mosi, pga_cs_n;
    logic spi_miso, irq, uart_tx, hat_pps, pps_ref;
    logic hat_sclk = 0, hat_mosi = 0, hat_cs_n = 1;
    logic sample_ce, sample_valid, second_ce, adc_fault, ch1_activity;
    logic [2:0] lock_state;
    tri lcd_scl, lcd_sda;
    pullup (lcd_scl); pullup (lcd_sda);
    always #4 clk = !clk;

    dcf77_hat_top #(
        .SIM_CLOCK_BYPASS(1), .RESET_CYCLES(3), .PHASE_BITS(24),
        .SAMPLE_NOMINAL_INC(24'd131072), .ADC_CONV_CYCLES(1),
        .ADC_SCK_HALF_CYCLES(1), .SECOND_CYCLES(24),
        .SECOND_SEARCH_TOLERANCE(2), .SECOND_TRACK_WINDOW(2),
        .SECOND_ACQUIRE_HITS(2), .CYCLES_PER_CHIP(4), .CHIP_COUNT(1),
        .PPS_PULSE_CYCLES(2), .HISTORY_DEPTH(16),
        .CLK_HZ(1_000_000), .PGA_SCK_HZ(125_000),
        .LCD_SCL_HZ(125_000), .LCD_POWERUP_WAIT(64), .LCD_CMD_WAIT(16)
    ) dut (
        .clk_25m(clk), .reset_n(reset_n), .adc_conv(adc_conv),
        .adc_sck(adc_sck), .adc_sdo(adc_sdo), .pga_sck(pga_sck),
        .pga_mosi(pga_mosi), .pga_cs_n(pga_cs_n), .hat_spi_mosi(hat_mosi),
        .hat_spi_miso(spi_miso), .hat_spi_sclk(hat_sclk), .hat_spi_cs_n(hat_cs_n),
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
    // LTC6912 model: the power-up gain word must be latched once.
    // Only a CS/LD rising edge that closes an 8-clock frame counts: the pin's
    // X->1 transition when the FPGA reset asserts is not a transfer.
    logic [7:0] pga_shift = '0, pga_latched = '0;
    integer pga_latches = 0, pga_clocks = 0;
    always @(posedge pga_sck) if (!pga_cs_n) begin
        pga_shift = {pga_shift[6:0], pga_mosi}; pga_clocks = pga_clocks + 1;
    end
    always @(posedge pga_cs_n) begin
        if (pga_clocks == 8) begin pga_latched = pga_shift; pga_latches = pga_latches + 1; end
        pga_clocks = 0;
    end
    // Mode-0 master byte: shift out on/before the falling edge, sample on rising.
    logic [7:0] spi_rx, spi_id [0:3];
    task automatic spi_byte(input logic [7:0] tx, output logic [7:0] r);
        integer b;
        begin
            r = '0;
            for (b = 7; b >= 0; b = b - 1) begin
                hat_mosi = tx[b]; #200; hat_sclk = 1; r[b] = spi_miso; #200; hat_sclk = 0;
            end
        end
    endtask
    initial begin
        repeat (2) @(posedge clk); reset_n <= 1;
        wait (sample_valid); repeat (400) @(posedge clk);
        if (requests < 2 || samples < 1) $fatal(1, "ADC path did not run");
        if (adc_fault !== 1'b0) $fatal(1, "scheduler overran ADC");
        wait (pga_latches == 1); repeat (4) @(posedge clk);
        if (pga_latched !== 8'b1000_0111) $fatal(1, "PGA programmed with %b", pga_latched);
        if (pga_cs_n !== 1'b1 || pga_sck !== 1'b0) $fatal(1, "PGA bus not idle after programming");
        // Raspberry Pi reads the identity/version block over the HAT SPI.
        hat_cs_n = 0; #200;
        spi_byte(8'h00, spi_rx);
        spi_byte(8'h00, spi_id[0]); spi_byte(8'h00, spi_id[1]);
        spi_byte(8'h00, spi_id[2]); spi_byte(8'h00, spi_id[3]);
        #200; hat_cs_n = 1;
        if (spi_id[0] !== 8'hDC || spi_id[1] !== 8'h77 || spi_id[2] !== 8'h00 || spi_id[3] !== 8'h01)
            $fatal(1, "HAT SPI identity read %h %h %h %h", spi_id[0], spi_id[1], spi_id[2], spi_id[3]);
        // LCD initialization completes on the open-drain bus with pull-ups.
        // (No ST7036 model here, so nothing acknowledges; the unit test covers that.)
        wait (dut.lcd_ready);
        if (lcd_scl !== 1'b1 || lcd_sda !== 1'b1) $fatal(1, "LCD bus not released after init");
        $display("PASS: top reset, scheduler, ADC CH0 path, PGA programming, HAT SPI, LCD init and interfaces");
        $finish;
    end

endmodule
