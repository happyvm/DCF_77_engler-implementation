// SPDX-License-Identifier: MIT
//
// LTC1407A dual-channel serial capture interface.
//
// The converter returns two 14-bit samples in one 32-clock frame:
//   { channel 0, 2 padding bits, channel 1, 2 padding bits }
// Data are shifted MSB first and sampled on the rising edge of adc_sck.

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

                        if (!adc_sck) begin
                            // adc_sck is about to rise: capture one input bit.
                            shift_reg <= {shift_reg[30:0], adc_sdo};
                            bit_count <= bit_count + 1'b1;
                        end else if (bit_count == 6'd32) begin
                            // The final sampled bit is already present because
                            // this is the following falling edge.
                            ch0_sample   <= normalize_sample(shift_reg[31:18]);
                            ch1_sample   <= normalize_sample(shift_reg[15:2]);
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
