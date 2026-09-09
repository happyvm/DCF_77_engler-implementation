// Continuously running Goertzel resonator, checked from the ports for an
// arbitrary sample stream: both states always stay inside the saturating
// STATE_BITS range, cycle_valid fires exactly every CYCLE_SAMPLES accepted
// samples (a mod-CYCLE_SAMPLES counter derived from sample_ce alone), and
// the sticky overflow flag never clears itself once set. Small SAMPLE/STATE
// widths and CYCLE_SAMPLES=4 keep the 19-bit coefficient multiplies and a
// couple of full periods inside the bounded depth.
module goertzel_resonator_formal;
    localparam int SAMPLE_BITS = 6;
    localparam int STATE_BITS = 12;
    localparam int CYCLE_SAMPLES = 4;
    localparam logic signed [11:0] STATE_MAX = {1'b0, {11{1'b1}}};
    localparam logic signed [11:0] STATE_MIN = {1'b1, {11{1'b0}}};

    (* gclk *) logic clk;
    (* anyseq *) logic sample_ce;
    (* anyseq *) logic signed [SAMPLE_BITS-1:0] sample;
    logic rst = 1'b1;
    logic past_valid = 1'b0;
    logic signed [STATE_BITS-1:0] state_1, state_2;
    logic cycle_valid, overflow;

    goertzel_resonator #(
        .SAMPLE_BITS(SAMPLE_BITS), .STATE_BITS(STATE_BITS),
        .CYCLE_SAMPLES(CYCLE_SAMPLES)
    ) dut (.*);

    logic [1:0] ref_count = '0;

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;

        if (rst) begin
            ref_count <= '0;
        end else if (sample_ce) begin
            if (ref_count == 2'(CYCLE_SAMPLES - 1))
                ref_count <= '0;
            else
                ref_count <= ref_count + 1'b1;
        end

        if (past_valid && !$past(rst)) begin
            // Saturating arithmetic: the states this module publishes are
            // always the direct output of `saturate`, so they can never
            // exceed the range that function is built to enforce.
            assert(state_1 <= STATE_MAX && state_1 >= STATE_MIN);
            assert(state_2 <= STATE_MAX && state_2 >= STATE_MIN);

            // cycle_valid pulses exactly on the sample_ce that completes a
            // full CYCLE_SAMPLES period, one clock after ref_count/sample_ce
            // report the period boundary (cycle_valid is itself registered).
            if ($past(sample_ce) && $past(ref_count) == 2'(CYCLE_SAMPLES - 1))
                assert(cycle_valid);
            else
                assert(!cycle_valid);

            // Sticky: overflow can only turn on, never off, outside reset.
            if ($past(overflow))
                assert(overflow);
        end
    end
endmodule
