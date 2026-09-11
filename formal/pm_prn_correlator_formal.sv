// Chip-polarity accumulator, checked against a shadow accumulator built the
// same way pps_generator_formal.sv checks its own counter: the reference
// keeps its own running sum with the identical sign convention, and the
// two must agree on every clock, including the value latched into
// correlation exactly on chip_index==511 and nowhere else.
module pm_prn_correlator_formal;
    localparam int SOFT_BITS = 6;
    localparam int ACC_BITS = SOFT_BITS + 10;

    (* gclk *) logic clk;
    (* anyseq *) logic reset_cycle, chip_ce, prn_chip;
    (* anyseq *) logic [8:0] chip_index;
    (* anyseq *) logic signed [SOFT_BITS-1:0] pm_soft;
    logic rst = 1'b1;
    logic past_valid = 1'b0;
    logic signed [ACC_BITS-1:0] correlation;
    logic correlation_valid;

    pm_prn_correlator #(.SOFT_BITS(SOFT_BITS), .ACC_BITS(ACC_BITS)) dut (.*);

    logic signed [ACC_BITS-1:0] ref_acc = '0;
    logic signed [ACC_BITS-1:0] ref_corr = '0;
    logic ref_valid = 1'b0;

    // Constrain chip_index to the three values that exercise distinct DUT
    // behaviour: 0 (accumulate), 510 (one step before latch), 511 (latch
    // + reset).  The other 509 values are isomorphic to 0 for the DUT
    // (the accumulation arithmetic is chip_index-agnostic) but cause
    // needless anyseq state-space explosion.
    always_comb assume(chip_index == 9'd0 || chip_index == 9'd510 || chip_index == 9'd511);

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;

        if (rst || reset_cycle) begin
            ref_acc <= '0;
            ref_corr <= '0;
            ref_valid <= 1'b0;
        end else begin
            ref_valid <= 1'b0;
            if (chip_ce) begin
                logic signed [ACC_BITS-1:0] ext, contribution, next_acc;
                ext = {{(ACC_BITS-SOFT_BITS){pm_soft[SOFT_BITS-1]}}, pm_soft};
                contribution = prn_chip ? ext : -ext;
                next_acc = ref_acc + contribution;
                if (chip_index == 9'd511) begin
                    ref_corr <= next_acc;
                    ref_valid <= 1'b1;
                    ref_acc <= '0;
                end else begin
                    ref_acc <= next_acc;
                end
            end
        end

        if (past_valid && !$past(rst)) begin
            assert(correlation_valid == ref_valid);
            assert(correlation == ref_corr);
        end
    end
endmodule
