// SPDX-License-Identifier: MIT
// Deterministic serial programmer for the LTC6912 programmable-gain amplifier.
//
// Protocol per the LTC6912 data sheet (Analog Devices 6912fa, "Serial
// Interface"): with CS/LD low the 8-bit word is shifted in MSB first, DIN
// sampled on the rising edge of CLK; the rising edge of CS/LD loads the
// shift register into the gain latch. Upper nibble = channel B, lower
// nibble = channel A. Timing floors are tens of nanoseconds (t1 DIN setup
// 30 ns, t5 CS/LD pulse 40 ns, t7 CS/LD-to-CLK 20 ns); this block runs
// the bus at SCK_HZ (~100 kHz per docs/22-ltc6912-pga.md, deliberately
// slow and sparse to keep switching noise away from the receiver), which
// exceeds every floor by orders of magnitude. DOUT is not used.
//
// The word is sent once after reset and again on every `send` pulse
// (the AGC, when it exists, must only pulse it in the ~995 ms tail of a
// second, see the design note); no gain law lives here.
module pga_spi_master #(
    parameter int unsigned CLK_HZ = 125_000_000,
    parameter int unsigned SCK_HZ = 100_000
) (
    input  logic clk,
    input  logic rst,
    input  logic send,
    // LTC6912 gain nibbles (see docs/22 for the -1 code table).
    input  logic [3:0] gain_a,
    input  logic [3:0] gain_b,
    output logic pga_sck,
    output logic pga_mosi,
    output logic pga_cs_n,
    output logic busy,
    // One-cycle pulse when the word has been latched by the PGA.
    output logic done
);
    localparam int unsigned HALF_CYCLES = (CLK_HZ / (2 * SCK_HZ)) < 2 ? 2 : CLK_HZ / (2 * SCK_HZ);
    localparam int HALF_W = $clog2(HALF_CYCLES + 1);

    typedef enum logic [2:0] {IDLE, LEAD, BIT_LOW, BIT_HIGH, TRAIL, LATCH} state_t;
    state_t state;
    logic [HALF_W-1:0] half_count;
    logic [2:0] bit_index;
    logic [7:0] shift_word;
    logic pending;

    wire half_done = (half_count == HALF_W'(HALF_CYCLES - 1));

    assign busy = (state != IDLE);

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            half_count <= '0;
            bit_index <= '0;
            shift_word <= '0;
            pga_sck <= 1'b0;
            pga_mosi <= 1'b0;
            pga_cs_n <= 1'b1;
            done <= 1'b0;
            // Program the power-up gain as soon as reset is released.
            pending <= 1'b1;
        end else begin
            done <= 1'b0;
            if (send) pending <= 1'b1;

            if (state == IDLE) begin
                half_count <= '0;
                if (pending) begin
                    pending <= 1'b0;
                    shift_word <= {gain_b, gain_a};
                    bit_index <= 3'd7;
                    pga_cs_n <= 1'b0;
                    state <= LEAD;
                end
            end else if (!half_done) begin
                half_count <= half_count + 1'b1;
            end else begin
                half_count <= '0;
                case (state)
                    LEAD: begin
                        pga_mosi <= shift_word[7];
                        state <= BIT_LOW;
                    end
                    // Data has been stable on MOSI for a half period; the
                    // PGA samples it on this rising edge.
                    BIT_LOW: begin
                        pga_sck <= 1'b1;
                        state <= BIT_HIGH;
                    end
                    BIT_HIGH: begin
                        pga_sck <= 1'b0;
                        if (bit_index == 3'd0) begin
                            state <= TRAIL;
                        end else begin
                            shift_word <= {shift_word[6:0], 1'b0};
                            pga_mosi <= shift_word[6];
                            bit_index <= bit_index - 1'b1;
                            state <= BIT_LOW;
                        end
                    end
                    TRAIL: begin
                        pga_cs_n <= 1'b1;   // rising edge loads the latch
                        pga_mosi <= 1'b0;
                        state <= LATCH;
                    end
                    LATCH: begin
                        done <= 1'b1;
                        state <= IDLE;
                    end
                    default: state <= IDLE;
                endcase
            end
        end
    end
endmodule
