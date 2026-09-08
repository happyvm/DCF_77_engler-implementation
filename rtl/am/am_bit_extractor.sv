// SPDX-License-Identifier: MIT
// Carrier-synchronous soft AM bit extraction for an aligned DCF77 second.
//
// DCF77 amplitude is reduced through 100 ms for bit 0 and through 200 ms for
// bit 1. Equal 100 ms windows compare the ambiguous 100..200 ms interval with
// the always-reduced 0..100 ms interval and a normal-amplitude 200..300 ms
// reference:
//   soft evidence = reference_sum + reduced_sum - 2*data_sum
// Positive evidence indicates bit 1 and negative evidence bit 0.

module am_bit_extractor #(
    parameter int INPUT_BITS = 67,
    parameter int OUTPUT_BITS = 32,
    parameter int OUTPUT_SHIFT = 20,
    parameter int SECOND_CYCLES = 77_500,
    parameter int REDUCED_START_CYCLE = 0,
    parameter int DATA_START_CYCLE = 7_750,
    parameter int REFERENCE_START_CYCLE = 15_500,
    parameter int WINDOW_CYCLES = 7_750
) (
    input  logic clk,
    input  logic rst,
    input  logic second_ce,
    input  logic carrier_ce,
    input  logic signed [INPUT_BITS-1:0] am_observable,
    output logic signed [OUTPUT_BITS-1:0] am_soft_bit,
    output logic bit_valid,
    output logic [$clog2(SECOND_CYCLES)-1:0] carrier_position
);

    // Two guard bits cover reference + reduced - 2*data for full-scale
    // signed inputs; the three-term discriminator must not wrap.
    localparam int SUM_BITS = INPUT_BITS + $clog2(WINDOW_CYCLES) + 2;
    localparam logic signed [OUTPUT_BITS-1:0] OUTPUT_MAX =
        {1'b0, {(OUTPUT_BITS-1){1'b1}}};
    localparam logic signed [OUTPUT_BITS-1:0] OUTPUT_MIN =
        {1'b1, {(OUTPUT_BITS-1){1'b0}}};

    logic signed [SUM_BITS-1:0] data_sum;
    logic signed [SUM_BITS-1:0] reduced_sum;
    logic signed [SUM_BITS-1:0] reference_sum;
    logic signed [SUM_BITS-1:0] observable_extended;
    logic signed [SUM_BITS-1:0] next_data_sum;
    logic signed [SUM_BITS-1:0] next_reduced_sum;
    logic signed [SUM_BITS-1:0] next_reference_sum;
    logic signed [SUM_BITS-1:0] evidence_shifted;

    function automatic logic signed [OUTPUT_BITS-1:0] saturate_output(
        input logic signed [SUM_BITS-1:0] value
    );
        logic signed [SUM_BITS-1:0] maximum;
        logic signed [SUM_BITS-1:0] minimum;
        begin
            maximum = {{(SUM_BITS-OUTPUT_BITS){1'b0}}, OUTPUT_MAX};
            minimum = {{(SUM_BITS-OUTPUT_BITS){1'b1}}, OUTPUT_MIN};
            if (value > maximum)
                saturate_output = OUTPUT_MAX;
            else if (value < minimum)
                saturate_output = OUTPUT_MIN;
            else
                saturate_output = value[OUTPUT_BITS-1:0];
        end
    endfunction

    always_comb begin
        observable_extended =
            {{(SUM_BITS-INPUT_BITS){am_observable[INPUT_BITS-1]}}, am_observable};
        next_data_sum = data_sum + observable_extended;
        next_reduced_sum = reduced_sum + observable_extended;
        next_reference_sum = reference_sum + observable_extended;
        evidence_shifted = (next_reference_sum + reduced_sum - (data_sum <<< 1))
                           >>> OUTPUT_SHIFT;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            carrier_position <= '0;
            data_sum          <= '0;
            reduced_sum       <= '0;
            reference_sum     <= '0;
            am_soft_bit       <= '0;
            bit_valid         <= 1'b0;
        end else begin
            bit_valid <= 1'b0;
            if (second_ce) begin
                carrier_position <= '0;
                data_sum          <= '0;
                reduced_sum       <= '0;
                reference_sum     <= '0;
            end else if (carrier_ce) begin
                if (carrier_position == SECOND_CYCLES - 1)
                    carrier_position <= '0;
                else
                    carrier_position <= carrier_position + 1'b1;

                if ((carrier_position >= REDUCED_START_CYCLE) &&
                    (carrier_position < REDUCED_START_CYCLE + WINDOW_CYCLES))
                    reduced_sum <= next_reduced_sum;

                if ((carrier_position >= DATA_START_CYCLE) &&
                    (carrier_position < DATA_START_CYCLE + WINDOW_CYCLES))
                    data_sum <= next_data_sum;

                if ((carrier_position >= REFERENCE_START_CYCLE) &&
                    (carrier_position < REFERENCE_START_CYCLE + WINDOW_CYCLES)) begin
                    reference_sum <= next_reference_sum;
                    if (carrier_position == REFERENCE_START_CYCLE + WINDOW_CYCLES - 1) begin
                        am_soft_bit <= saturate_output(evidence_shifted);
                        bit_valid   <= 1'b1;
                    end
                end
            end
        end
    end

    initial begin
        if (INPUT_BITS < 2 || OUTPUT_BITS < 2 || OUTPUT_BITS > SUM_BITS)
            $error("am_bit_extractor: invalid data widths");
        if (OUTPUT_SHIFT < 0 || OUTPUT_SHIFT >= SUM_BITS)
            $error("am_bit_extractor: invalid OUTPUT_SHIFT");
        if (REDUCED_START_CYCLE < 0 || DATA_START_CYCLE < 0 ||
            REFERENCE_START_CYCLE < 0 || WINDOW_CYCLES < 1)
            $error("am_bit_extractor: invalid window parameter");
        if (REDUCED_START_CYCLE + WINDOW_CYCLES > DATA_START_CYCLE ||
            DATA_START_CYCLE + WINDOW_CYCLES > REFERENCE_START_CYCLE ||
            REFERENCE_START_CYCLE + WINDOW_CYCLES > SECOND_CYCLES)
            $error("am_bit_extractor: windows overlap or exceed one second");
    end

endmodule
