// SPDX-License-Identifier: MIT
// Integrate the carrier-rate PM observable into DCF77 PRN chip samples.
//
// Nominal timing is entirely integer in carrier-cycle coordinates:
//   second length = 77500 cycles
//   PRN starts     = cycle 15500 (200 ms)
//   chip length    = 120 cycles
//   PRN length     = 512 chips
// chip_valid is delayed from the final carrier sample by registered logic, so
// the downstream correlator consumes a stable chip_soft value.

module pm_chip_integrator #(
    parameter int INPUT_BITS = 67,
    parameter int OUTPUT_BITS = 32,
    parameter int OUTPUT_SHIFT = 24,
    parameter int SECOND_CYCLES = 77_500,
    parameter int PRN_START_CYCLE = 15_500,
    parameter int CYCLES_PER_CHIP = 120,
    parameter int CHIP_COUNT = 512
) (
    input  logic clk,
    input  logic rst,
    input  logic second_ce,
    input  logic carrier_ce,
    input  logic signed [INPUT_BITS-1:0] pm_observable,
    output logic signed [OUTPUT_BITS-1:0] chip_soft,
    output logic chip_valid,
    output logic prn_cycle_reset,
    output logic prn_active,
    output logic prn_done,
    output logic [$clog2(SECOND_CYCLES)-1:0] carrier_position
);

    localparam int SUM_BITS = INPUT_BITS + $clog2(CYCLES_PER_CHIP);
    localparam int CHIP_CYCLE_W =
        (CYCLES_PER_CHIP <= 1) ? 1 : $clog2(CYCLES_PER_CHIP);
    localparam int CHIP_INDEX_W = (CHIP_COUNT <= 1) ? 1 : $clog2(CHIP_COUNT);

    localparam logic signed [OUTPUT_BITS-1:0] OUTPUT_MAX =
        {1'b0, {(OUTPUT_BITS-1){1'b1}}};
    localparam logic signed [OUTPUT_BITS-1:0] OUTPUT_MIN =
        {1'b1, {(OUTPUT_BITS-1){1'b0}}};

    logic [CHIP_CYCLE_W-1:0] chip_cycle_count;
    logic [CHIP_INDEX_W-1:0] chip_index_count;
    logic signed [SUM_BITS-1:0] chip_accumulator;
    logic signed [SUM_BITS-1:0] observable_extended;
    logic signed [SUM_BITS-1:0] next_sum;
    logic signed [SUM_BITS-1:0] shifted_sum;

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
            {{(SUM_BITS-INPUT_BITS){pm_observable[INPUT_BITS-1]}}, pm_observable};
        next_sum = chip_accumulator + observable_extended;
        shifted_sum = next_sum >>> OUTPUT_SHIFT;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            carrier_position <= '0;
            chip_cycle_count <= '0;
            chip_index_count <= '0;
            chip_accumulator <= '0;
            chip_soft        <= '0;
            chip_valid       <= 1'b0;
            prn_cycle_reset  <= 1'b0;
            prn_active       <= 1'b0;
            prn_done         <= 1'b0;
        end else begin
            chip_valid      <= 1'b0;
            prn_cycle_reset <= 1'b0;
            prn_done        <= 1'b0;

            if (second_ce) begin
                carrier_position <= '0;
                chip_cycle_count <= '0;
                chip_index_count <= '0;
                chip_accumulator <= '0;
                prn_active       <= 1'b0;
                prn_cycle_reset  <= 1'b1;
            end else if (carrier_ce) begin
                if (carrier_position == $clog2(SECOND_CYCLES)'(SECOND_CYCLES - 1))
                    carrier_position <= '0;
                else
                    carrier_position <= carrier_position + 1'b1;

                if (!prn_active) begin
                    if (carrier_position == $clog2(SECOND_CYCLES)'(PRN_START_CYCLE - 1)) begin
                        prn_active       <= 1'b1;
                        chip_cycle_count <= '0;
                        chip_index_count <= '0;
                        chip_accumulator <= '0;
                    end
                end else if (chip_cycle_count == CHIP_CYCLE_W'(CYCLES_PER_CHIP - 1)) begin
                    chip_soft        <= saturate_output(shifted_sum);
                    chip_valid       <= 1'b1;
                    chip_cycle_count <= '0;
                    chip_accumulator <= '0;
                    if (chip_index_count == CHIP_INDEX_W'(CHIP_COUNT - 1)) begin
                        chip_index_count <= '0;
                        prn_active       <= 1'b0;
                        prn_done         <= 1'b1;
                    end else begin
                        chip_index_count <= chip_index_count + 1'b1;
                    end
                end else begin
                    chip_accumulator <= next_sum;
                    chip_cycle_count <= chip_cycle_count + 1'b1;
                end
            end
        end
    end

    initial begin
        if (INPUT_BITS < 2 || OUTPUT_BITS < 2 || OUTPUT_BITS > SUM_BITS)
            $error("pm_chip_integrator: invalid data widths");
        if (OUTPUT_SHIFT < 0 || OUTPUT_SHIFT >= SUM_BITS)
            $error("pm_chip_integrator: invalid OUTPUT_SHIFT");
        if (PRN_START_CYCLE < 1 || CYCLES_PER_CHIP < 1 || CHIP_COUNT < 1)
            $error("pm_chip_integrator: invalid timing parameter");
        if (PRN_START_CYCLE + CYCLES_PER_CHIP * CHIP_COUNT > SECOND_CYCLES)
            $error("pm_chip_integrator: PRN interval exceeds one second");
    end

endmodule
