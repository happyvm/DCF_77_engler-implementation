// 512-chip Galois LFSR sequencer: chip_index always stays a legal 0..511
// count, it only ever advances by one (mod 512) on an accepted chip_ce and
// otherwise holds, cycle_done is a single-cycle pulse exactly on the
// chip_ce that wraps chip_index from 511 back to 0, and rst/reset_cycle
// both force the same synchronous restart to index 0.
module dcf77_prn_generator_formal;
    (* gclk *) logic clk;
    (* anyseq *) logic reset_cycle, chip_ce;
    logic rst = 1'b1;
    logic past_valid = 1'b0;
    logic prn_chip, prn_chip_inverted, cycle_done;
    logic [8:0] chip_index;

    dcf77_prn_generator dut (.*);

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;

        if (past_valid) begin
            assert(chip_index <= 9'd511);
            assert(prn_chip_inverted == !prn_chip);
        end

        if (past_valid && !$past(rst)) begin
            if ($past(reset_cycle))
                assert(chip_index == 9'd0 && !cycle_done);
            else if ($past(chip_ce)) begin
                if ($past(chip_index) == 9'd511) begin
                    assert(chip_index == 9'd0);
                    assert(cycle_done);
                end else begin
                    assert(chip_index == $past(chip_index) + 9'd1);
                    assert(!cycle_done);
                end
            end else begin
                assert(chip_index == $past(chip_index));
                assert(!cycle_done);
            end
        end
    end
endmodule
