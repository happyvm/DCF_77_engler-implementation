// Three resonators sharing one sample_ce and one default CYCLE_SAMPLES: they
// stay in lockstep, so the bank's cycle_valid (the AND of all three) is
// exactly the same mod-CYCLE_SAMPLES period a single resonator publishes,
// and overflow is the sticky OR of three independent saturating channels
// (so it is itself sticky). The bank does not expose CYCLE_SAMPLES, so this
// uses goertzel_resonator's real default of 12 rather than shrinking it.
module engeler_goertzel_bank_formal;
    localparam int SAMPLE_BITS = 6;
    localparam int STATE_BITS = 12;
    localparam int CYCLE_SAMPLES = 12;

    (* gclk *) logic clk;
    (* anyseq *) logic sample_ce;
    (* anyseq *) logic signed [SAMPLE_BITS-1:0] sample;
    logic rst = 1'b1;
    logic past_valid = 1'b0;
    logic signed [STATE_BITS-1:0] carrier_s1, carrier_s2, am_s1, am_s2, pm_s1, pm_s2;
    logic cycle_valid, overflow;

    engeler_goertzel_bank #(
        .SAMPLE_BITS(SAMPLE_BITS), .STATE_BITS(STATE_BITS)
    ) dut (.*);

    logic [3:0] ref_count = '0;

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;

        if (rst) ref_count <= '0;
        else if (sample_ce) begin
            if (ref_count == 4'(CYCLE_SAMPLES - 1))
                ref_count <= '0;
            else
                ref_count <= ref_count + 1'b1;
        end

        if (past_valid && !$past(rst)) begin
            if ($past(sample_ce) && $past(ref_count) == 4'(CYCLE_SAMPLES - 1))
                assert(cycle_valid);
            else
                assert(!cycle_valid);

            if ($past(overflow))
                assert(overflow);
        end
    end
endmodule
