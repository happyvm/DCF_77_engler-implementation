// SPDX-License-Identifier: MIT
// Raspberry Pi HAT SPI slave exposing a read-only status/time register map.
//
// The Pi is the SPI master in mode 0 (CPOL = 0, CPHA = 0: both sides shift
// on the falling SCLK edge and sample on the rising edge, CS_N active low,
// MSB first). Every transaction is: one command byte from the Pi
// {rw, addr[6:0]}, then any number of data bytes; on a read (rw = 0) the
// slave returns register[addr], register[addr+1], ... on MISO. Writes
// (rw = 1) are accepted for the single control register only and ignored
// elsewhere. All register values are sampled into a snapshot on the CS_N
// falling edge, so a multi-byte read of the time fields is coherent even
// though the receiver keeps running underneath.
//
// Everything runs in the FPGA clock domain: SCLK/MOSI/CS_N are passed
// through two-stage synchronizers and edges are detected from the
// synchronized copies, which supports SCLK up to a few MHz at 125 MHz
// (at least ~20 clocks per half period at 3 MHz) -- ample for a status
// map; raw sample streaming is explicitly not this interface's job.
//
// Register map (byte address, read-only unless noted):
//   0x00 ID_HI      0xDC             0x01 ID_LO      0x77
//   0x02 VER_MAJOR  RTL_VERSION[15:8] 0x03 VER_MINOR  RTL_VERSION[7:0]
//   0x04 LOCK       {3'b0, pps_valid, time_valid, lock_state[2:0]}
//   0x05 STATUS     {4'b0, frequency_locked, minute_locked, ml_locked,
//                    adc_fault}
//   0x06 FAULTS     {6'b0, detector_overflow, adc_fault}
//   0x07 QUALITY    phase_quality
//   0x08 SECOND     0x09 MINUTE   0x0A HOUR   0x0B DAY   0x0C WEEKDAY
//   0x0D MONTH      0x0E YEAR     0x0F ZONE   {7'b0, cest}
//   0x10..0x12 TRIM frequency-discipline trim_inc, little-endian, two's
//                    complement (sample-scheduler increment LSBs)
//   0x13 CONTROL    read/write byte exported on `control` (reserved for
//                    future host-driven features, e.g. a diagnostic mode);
//                    reads back as written
//   others          0x00
module hat_spi_slave #(
    parameter logic [15:0] RTL_VERSION = 16'h0001
) (
    input  logic clk,
    input  logic rst,

    input  logic spi_sclk,
    input  logic spi_mosi,
    input  logic spi_cs_n,
    output logic spi_miso,

    input  logic [2:0] lock_state,
    input  logic time_valid,
    input  logic pps_valid,
    input  logic ml_locked,
    input  logic minute_locked,
    input  logic frequency_locked,
    input  logic adc_fault,
    input  logic detector_overflow,
    input  logic [7:0] phase_quality,
    input  logic [5:0] second,
    input  logic [5:0] minute,
    input  logic [4:0] hour,
    input  logic [5:0] day,
    input  logic [2:0] weekday,
    input  logic [3:0] month,
    input  logic [7:0] year,
    input  logic cest,
    input  logic signed [23:0] trim_inc,

    output logic [7:0] control,
    // One-cycle pulse after each completed transaction (diagnostics).
    output logic transaction_done
);
    // --- Input synchronization and edge detection --------------------------
    logic [1:0] sclk_sync, mosi_sync, cs_sync;
    always_ff @(posedge clk) begin
        if (rst) begin
            sclk_sync <= 2'b00; mosi_sync <= 2'b00; cs_sync <= 2'b11;
        end else begin
            sclk_sync <= {sclk_sync[0], spi_sclk};
            mosi_sync <= {mosi_sync[0], spi_mosi};
            cs_sync <= {cs_sync[0], spi_cs_n};
        end
    end
    logic sclk_q, cs_q;
    wire sclk_rise = sclk_sync[1] && !sclk_q;
    wire sclk_fall = !sclk_sync[1] && sclk_q;
    wire cs_fall = !cs_sync[1] && cs_q;
    wire cs_rise = cs_sync[1] && !cs_q;
    wire selected = !cs_sync[1];

    // --- Coherent snapshot taken when the Pi asserts CS_N -----------------
    logic [2:0] s_lock_state;
    logic s_time_valid, s_pps_valid, s_ml_locked, s_minute_locked, s_frequency_locked;
    logic s_adc_fault, s_detector_overflow, s_cest;
    logic [7:0] s_phase_quality, s_year;
    logic [5:0] s_second, s_minute, s_day;
    logic [4:0] s_hour;
    logic [2:0] s_weekday;
    logic [3:0] s_month;
    logic signed [23:0] s_trim_inc;

    function automatic logic [7:0] register_value(input logic [6:0] addr);
        case (addr)
            7'h00: register_value = 8'hDC;
            7'h01: register_value = 8'h77;
            7'h02: register_value = RTL_VERSION[15:8];
            7'h03: register_value = RTL_VERSION[7:0];
            7'h04: register_value = {3'b0, s_pps_valid, s_time_valid, s_lock_state};
            7'h05: register_value = {4'b0, s_frequency_locked, s_minute_locked, s_ml_locked,
                                     s_adc_fault};
            7'h06: register_value = {6'b0, s_detector_overflow, s_adc_fault};
            7'h07: register_value = s_phase_quality;
            7'h08: register_value = {2'b0, s_second};
            7'h09: register_value = {2'b0, s_minute};
            7'h0A: register_value = {3'b0, s_hour};
            7'h0B: register_value = {2'b0, s_day};
            7'h0C: register_value = {5'b0, s_weekday};
            7'h0D: register_value = {4'b0, s_month};
            7'h0E: register_value = s_year;
            7'h0F: register_value = {7'b0, s_cest};
            7'h10: register_value = s_trim_inc[7:0];
            7'h11: register_value = s_trim_inc[15:8];
            7'h12: register_value = s_trim_inc[23:16];
            7'h13: register_value = control;
            default: register_value = 8'h00;
        endcase
    endfunction

    // --- Shift engine ------------------------------------------------------
    logic [2:0] bit_count;      // bits received in the current byte
    logic [6:0] rx_shift;       // bits 7..1 of the byte in flight (bit 0 is MOSI at the last edge)
    logic [7:0] tx_shift;
    logic command_phase;        // first byte of the transaction
    logic write_transaction;
    logic [6:0] address;
    logic transaction_active;

    always_ff @(posedge clk) begin
        if (rst) begin
            sclk_q <= 1'b0; cs_q <= 1'b1;
            bit_count <= '0; rx_shift <= '0; tx_shift <= '0;
            command_phase <= 1'b1; write_transaction <= 1'b0; address <= '0;
            transaction_active <= 1'b0; transaction_done <= 1'b0;
            spi_miso <= 1'b0; control <= '0;
            s_lock_state <= '0; s_time_valid <= 1'b0; s_pps_valid <= 1'b0;
            s_ml_locked <= 1'b0; s_minute_locked <= 1'b0; s_frequency_locked <= 1'b0;
            s_adc_fault <= 1'b0; s_detector_overflow <= 1'b0; s_cest <= 1'b0;
            s_phase_quality <= '0; s_year <= '0; s_second <= '0; s_minute <= '0;
            s_day <= '0; s_hour <= '0; s_weekday <= '0; s_month <= '0; s_trim_inc <= '0;
        end else begin
            sclk_q <= sclk_sync[1];
            cs_q <= cs_sync[1];
            transaction_done <= 1'b0;

            if (cs_fall) begin
                // Snapshot, then arm for the command byte.
                s_lock_state <= lock_state; s_time_valid <= time_valid;
                s_pps_valid <= pps_valid; s_ml_locked <= ml_locked;
                s_minute_locked <= minute_locked; s_frequency_locked <= frequency_locked;
                s_adc_fault <= adc_fault; s_detector_overflow <= detector_overflow;
                s_phase_quality <= phase_quality; s_second <= second; s_minute <= minute;
                s_hour <= hour; s_day <= day; s_weekday <= weekday; s_month <= month;
                s_year <= year; s_cest <= cest; s_trim_inc <= trim_inc;
                bit_count <= '0;
                command_phase <= 1'b1;
                transaction_active <= 1'b1;
                spi_miso <= 1'b0;   // nothing to say during the command byte
                tx_shift <= '0;
            end else if (cs_rise) begin
                transaction_active <= 1'b0;
                transaction_done <= 1'b1;
                spi_miso <= 1'b0;
            end else if (transaction_active && selected) begin
                if (sclk_rise) begin
                    // Master shifted on the previous falling edge; sample MOSI.
                    rx_shift <= {rx_shift[5:0], mosi_sync[1]};
                    bit_count <= bit_count + 1'b1;
                    if (bit_count == 3'd7) begin
                        if (command_phase) begin
                            command_phase <= 1'b0;
                            write_transaction <= rx_shift[6];
                            address <= {rx_shift[5:0], mosi_sync[1]};
                            // First data byte for a read goes out starting
                            // at the next falling edge.
                            tx_shift <= register_value({rx_shift[5:0], mosi_sync[1]});
                        end else begin
                            if (write_transaction && address == 7'h13)
                                control <= {rx_shift, mosi_sync[1]};
                            address <= address + 1'b1;
                            tx_shift <= register_value(address + 1'b1);
                        end
                    end
                end
                if (sclk_fall && !command_phase) begin
                    // Present the next MISO bit for the master's rising edge.
                    spi_miso <= tx_shift[7];
                    tx_shift <= {tx_shift[6:0], 1'b0};
                end
            end
        end
    end
endmodule
