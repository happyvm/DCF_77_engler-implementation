// PM chip integrator: carrier_position wraps mod SECOND_CYCLES, prn_active
// brackets exactly CHIP_COUNT chip windows of CYCLES_PER_CHIP carrier_ce's
// starting PRN_START_CYCLE after second_ce, chip_valid pulses once per chip
// window, prn_done coincides with the CHIP_COUNT-th chip_valid, and
// prn_cycle_reset is a one-cycle pulse the cycle after second_ce. Checked
// against an independent reference model of the same timeline. Small
// SECOND_CYCLES/CYCLES_PER_CHIP/CHIP_COUNT (2 chips of 3 cycles each,
// starting at cycle 4 of an 11-cycle second) keep several seconds inside
// the bounded depth.
module pm_chip_integrator_formal;
    localparam int SC = 11;
    localparam int PS = 4;
    localparam int CPC = 3;
    localparam int CC = 2;
    localparam int IB = 6;
    localparam int OB = 8;
    localparam int OSFT = 1;
    localparam int SUM_BITS = IB + $clog2(CPC);
    localparam int POS_BITS = $clog2(SC);
    localparam int CYCLE_W = $clog2(CPC);
    localparam int INDEX_W = $clog2(CC);
    localparam logic signed [OB-1:0] OUTPUT_MAX = {1'b0, {(OB-1){1'b1}}};
    localparam logic signed [OB-1:0] OUTPUT_MIN = {1'b1, {(OB-1){1'b0}}};

    (* gclk *) logic clk;
    (* anyseq *) logic second_ce, carrier_ce;
    (* anyseq *) logic signed [IB-1:0] pm_observable;
    logic rst = 1'b1;
    logic past_valid = 1'b0;
    logic signed [OB-1:0] chip_soft;
    logic chip_valid, prn_cycle_reset, prn_active, prn_done;
    logic [POS_BITS-1:0] carrier_position;

    pm_chip_integrator #(
        .INPUT_BITS(IB), .OUTPUT_BITS(OB), .OUTPUT_SHIFT(OSFT),
        .SECOND_CYCLES(SC), .PRN_START_CYCLE(PS), .CYCLES_PER_CHIP(CPC),
        .CHIP_COUNT(CC)
    ) dut (.*);

    function automatic logic signed [OB-1:0] ref_saturate(
        input logic signed [SUM_BITS-1:0] value
    );
        logic signed [SUM_BITS-1:0] maximum, minimum;
        begin
            maximum = {{(SUM_BITS-OB){1'b0}}, OUTPUT_MAX};
            minimum = {{(SUM_BITS-OB){1'b1}}, OUTPUT_MIN};
            if (value > maximum) ref_saturate = OUTPUT_MAX;
            else if (value < minimum) ref_saturate = OUTPUT_MIN;
            else ref_saturate = value[OB-1:0];
        end
    endfunction

    logic [POS_BITS-1:0] ref_position = '0;
    logic [CYCLE_W-1:0] ref_chip_cycle = '0;
    logic [INDEX_W-1:0] ref_chip_index = '0;
    logic signed [SUM_BITS-1:0] ref_acc = '0;
    logic ref_active = 1'b0;
    logic ref_valid = 1'b0, ref_reset = 1'b0, ref_done = 1'b0;
    logic signed [OB-1:0] ref_soft = '0;

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;

        if (rst) begin
            ref_position <= '0; ref_chip_cycle <= '0; ref_chip_index <= '0;
            ref_acc <= '0; ref_active <= 1'b0;
            ref_valid <= 1'b0; ref_reset <= 1'b0; ref_done <= 1'b0;
        end else begin
            ref_valid <= 1'b0; ref_reset <= 1'b0; ref_done <= 1'b0;

            if (second_ce) begin
                ref_position <= '0; ref_chip_cycle <= '0; ref_chip_index <= '0;
                ref_acc <= '0; ref_active <= 1'b0; ref_reset <= 1'b1;
            end else if (carrier_ce) begin
                logic signed [SUM_BITS-1:0] ext, next_sum;
                ext = {{(SUM_BITS-IB){pm_observable[IB-1]}}, pm_observable};
                next_sum = ref_acc + ext;

                if (ref_position == POS_BITS'(SC - 1))
                    ref_position <= '0;
                else
                    ref_position <= ref_position + 1'b1;

                if (!ref_active) begin
                    if (ref_position == POS_BITS'(PS - 1)) begin
                        ref_active <= 1'b1;
                        ref_chip_cycle <= '0; ref_chip_index <= '0; ref_acc <= '0;
                    end
                end else if (ref_chip_cycle == CYCLE_W'(CPC - 1)) begin
                    ref_valid <= 1'b1;
                    ref_soft <= ref_saturate(next_sum >>> OSFT);
                    ref_chip_cycle <= '0; ref_acc <= '0;
                    if (ref_chip_index == INDEX_W'(CC - 1)) begin
                        ref_chip_index <= '0; ref_active <= 1'b0; ref_done <= 1'b1;
                    end else begin
                        ref_chip_index <= ref_chip_index + 1'b1;
                    end
                end else begin
                    ref_acc <= next_sum;
                    ref_chip_cycle <= ref_chip_cycle + 1'b1;
                end
            end
        end

        if (past_valid && !$past(rst)) begin
            assert(carrier_position == ref_position);
            assert(prn_active == ref_active);
            assert(chip_valid == ref_valid);
            assert(prn_cycle_reset == ref_reset);
            assert(prn_done == ref_done);
            if (chip_valid) assert(chip_soft == ref_soft);
            // done only ever accompanies the CHIP_COUNT-th chip_valid.
            if (prn_done) assert(chip_valid);
        end
    end
endmodule
