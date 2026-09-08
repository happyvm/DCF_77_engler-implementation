// SPDX-License-Identifier: MIT
//
// LTC1407A / LTC1407A-1 dual-channel serial capture interface.
//
// Protocol, per the primary LTC1407-1/LTC1407A-1 data sheet (Analog
// Devices/Linear Technology 14071fb, "Serial Data Output" and pin
// function descriptions for CONV/SCK/SDO):
//
//   * CONV is active high: its rising edge samples both analog inputs
//     and starts a conversion. This module drives it high for
//     CONV_CYCLES clk cycles, comfortably above the data sheet's
//     nominal CONV pulse width and CONV-to-SCK setup time.
//   * SCK is host-generated (this module drives it, idle low). The ADC
//     "sequences the output data on the rising edge" of SCK, i.e. SDO
//     changes shortly after each rising edge; the host must therefore
//     latch SDO on the following falling edge, not the rising edge
//     that produced it.
//   * A complete frame is exactly 32 SCK cycles: SDO is undefined for
//     the first two edges, then channel 0's 14 bits (D13..D0, MSB
//     first), then two more high-impedance edges separating the two
//     words, then channel 1's 14 bits (D13..D0, MSB first). This
//     module discards the four undefined/hi-Z edges and keeps only the
//     28 data bits.
//   * The data sheet's PIN FUNCTIONS table notes SDO "represent[s] the
//     two analog input channels at the start of the previous
//     conversion": the chip pipelines by exactly one conversion. That
//     latency is a fixed, deterministic one-sample group delay (the
//     very first frame after reset reflects an undefined pre-power-up
//     conversion); it needs no compensation here and is accounted for
//     by downstream timing, not this interface.
//   * Output coding is two's complement on the bipolar LTC1407A-1; the
//     pin-compatible unipolar LTC1407A instead outputs offset binary
//     (natural binary with an inverted MSB), handled below by
//     BIPOLAR_OUTPUT.

module adc_if #(
    parameter integer CONV_CYCLES     = 2,
    parameter integer SCK_HALF_CYCLES = 1,
    // The LTC1407A-1 emits two's-complement data.  Set this to zero for the
    // pin-compatible unipolar LTC1407A, whose offset-binary MSB is inverted
    // here so the detector always sees a signed sample.
    parameter integer BIPOLAR_OUTPUT  = 1
) (
    input  wire               clk,
    input  wire               rst,
    input  wire               sample_ce,

    output reg                adc_conv,
    output reg                adc_sck,
    input  wire               adc_sdo,

    output reg signed [13:0]  ch0_sample,
    output reg signed [13:0]  ch1_sample,
    output reg                sample_valid,
    output wire               busy,
    // Sticky indication that a new conversion was requested while the
    // previous serial frame was still being acquired.
    output reg                adc_fault
);

    localparam integer CONV_COUNT_W = (CONV_CYCLES <= 1) ? 1 : $clog2(CONV_CYCLES);
    localparam integer SCK_COUNT_W =
        (SCK_HALF_CYCLES <= 1) ? 1 : $clog2(SCK_HALF_CYCLES);

    // Frame layout: 2 undefined lead-in edges, 14 bits of channel 0,
    // 2 hi-Z separator edges, 14 bits of channel 1.
    localparam integer LEAD_BITS  = 2;
    localparam integer DATA_BITS  = 14;
    localparam integer GAP_BITS   = 2;
    localparam integer FRAME_BITS = LEAD_BITS + DATA_BITS + GAP_BITS + DATA_BITS;

    localparam [1:0] IDLE = 2'd0;
    localparam [1:0] CONVERT = 2'd1;
    localparam [1:0] SHIFT = 2'd2;

    reg [1:0] state;
    reg [CONV_COUNT_W-1:0] conv_count;
    reg [SCK_COUNT_W-1:0] sck_count;
    reg [5:0] bit_count;
    reg [31:0] shift_reg;

    assign busy = (state != IDLE);

    // Convert either ADC coding into a common signed two's-complement value.
    function automatic [13:0] normalize_sample;
        input [13:0] raw;
        begin
            normalize_sample = BIPOLAR_OUTPUT ? raw : {~raw[13], raw[12:0]};
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            state        <= IDLE;
            adc_conv     <= 1'b0;
            adc_sck      <= 1'b0;
            conv_count   <= {CONV_COUNT_W{1'b0}};
            sck_count    <= {SCK_COUNT_W{1'b0}};
            bit_count    <= 6'd0;
            shift_reg    <= 32'd0;
            ch0_sample   <= 14'sd0;
            ch1_sample   <= 14'sd0;
            sample_valid <= 1'b0;
            adc_fault    <= 1'b0;
        end else begin
            sample_valid <= 1'b0;

            if (sample_ce && busy)
                adc_fault <= 1'b1;

            case (state)
                IDLE: begin
                    adc_conv <= 1'b0;
                    adc_sck  <= 1'b0;
                    if (sample_ce) begin
                        adc_conv   <= 1'b1;
                        conv_count <= {CONV_COUNT_W{1'b0}};
                        state      <= CONVERT;
                    end
                end

                CONVERT: begin
                    if (conv_count == CONV_CYCLES - 1) begin
                        adc_conv  <= 1'b0;
                        sck_count <= {SCK_COUNT_W{1'b0}};
                        bit_count <= 6'd0;
                        state     <= SHIFT;
                    end else begin
                        conv_count <= conv_count + 1'b1;
                    end
                end

                SHIFT: begin
                    if (sck_count == SCK_HALF_CYCLES - 1) begin
                        sck_count <= {SCK_COUNT_W{1'b0}};
                        adc_sck   <= ~adc_sck;

                        if (adc_sck) begin
                            // adc_sck is about to fall: the ADC updated
                            // SDO on the rising edge that just occurred,
                            // so it is now stable to latch.
                            shift_reg <= {shift_reg[30:0], adc_sdo};
                            bit_count <= bit_count + 1'b1;
                        end else if (bit_count == FRAME_BITS[5:0]) begin
                            // One half-cycle after the 32nd falling-edge
                            // capture: shift_reg holds the complete frame,
                            // lead-in and hi-Z separator bits included.
                            ch0_sample   <= normalize_sample(
                                shift_reg[FRAME_BITS-1-LEAD_BITS -: DATA_BITS]);
                            ch1_sample   <= normalize_sample(shift_reg[DATA_BITS-1:0]);
                            sample_valid <= 1'b1;
                            adc_sck      <= 1'b0;
                            state        <= IDLE;
                        end
                    end else begin
                        sck_count <= sck_count + 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    initial begin
        if (CONV_CYCLES < 1)
            $error("adc_if: CONV_CYCLES must be at least one");
        if (SCK_HALF_CYCLES < 1)
            $error("adc_if: SCK_HALF_CYCLES must be at least one");
    end

endmodule
