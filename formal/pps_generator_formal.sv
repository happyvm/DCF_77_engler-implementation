module pps_generator_formal;
    (* gclk *) logic clk;
    (* anyseq *) logic second_ce;
    (* anyseq *) logic time_valid;
    logic rst = 1'b1;
    logic pps;
    logic past_valid = 1'b0;
    logic [2:0] expected_remaining = 0;

    pps_generator #(.PULSE_CYCLES(4)) dut (.*);

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;

        if (rst || !time_valid)
            expected_remaining <= 0;
        else if (second_ce)
            expected_remaining <= 4;
        else if (expected_remaining != 0)
            expected_remaining <= expected_remaining - 1'b1;

        if (past_valid) begin
            assert(pps == (expected_remaining != 0));
            // These two spot checks restate the general property above
            // for the specific "just went invalid" / "just requested a
            // pulse" transitions; both must also exclude a previous
            // reset cycle, during which the DUT's rst branch overrides
            // second_ce regardless of time_valid (matching
            // expected_remaining's own rst-aware update above).
            if ($past(!rst) && $past(!time_valid))
                assert(!pps);
            if ($past(!rst) && $past(time_valid && second_ce))
                assert(pps);
        end
    end
endmodule
