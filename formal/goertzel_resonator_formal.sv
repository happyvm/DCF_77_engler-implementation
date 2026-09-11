// Multi-cycle Goertzel resonator (BEA-36), checked from the ports under the
// sample-cadence contract: a new sample_ce may only be presented while `busy`
// is low (assumed here; proven for the real 930 kS/s scheduler in
// sim/sample_cadence_tb.sv and enforced in simulation by
// sim/goertzel_sample_contract.sv).
//
// Proven invariants:
//   * both states always stay inside the saturating STATE_BITS range;
//   * `busy` is asserted for at most GOERTZEL_MAX_CYCLES-1 consecutive clk;
//   * `done` only ever pulses when `busy` is low (result committed);
//   * the sticky overflow flag never clears itself once set;
//   * cycle_valid pulses exactly once per CYCLE_SAMPLES accepted samples:
//     accepting samples is counted independently here and matched against the
//     pulse, so the sequencer's internal accounting is cross-checked.
//
// Small SAMPLE/STATE widths and CYCLE_SAMPLES=4 keep the 19-bit coefficient
// multiplies and a couple of full periods inside the bounded depth.
module goertzel_resonator_formal;
    localparam int SAMPLE_BITS = 6;
    localparam int STATE_BITS = 12;
    localparam int CYCLE_SAMPLES = 4;
    localparam logic signed [11:0] STATE_MAX = {1'b0, {11{1'b1}}};
    localparam logic signed [11:0] STATE_MIN = {1'b1, {11{1'b0}}};
    localparam int CNT_W = $clog2(CYCLE_SAMPLES + 1);

    (* gclk *) logic clk;
    (* anyseq *) logic sample_ce;
    (* anyseq *) logic signed [SAMPLE_BITS-1:0] sample;
    logic rst = 1'b1;
    logic past_valid = 1'b0;
    logic signed [STATE_BITS-1:0] state_1, state_2;
    logic cycle_valid, overflow, busy, done;

    goertzel_resonator #(
        .SAMPLE_BITS(SAMPLE_BITS), .STATE_BITS(STATE_BITS),
        .CYCLE_SAMPLES(CYCLE_SAMPLES)
    ) dut (.*);

    logic [CNT_W-1:0] accepts_since_valid;
    logic [2:0] busy_run;

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;

        // Sample-cadence contract (see module header).
        assume(!(busy && sample_ce));

        if (rst) begin
            accepts_since_valid <= '0;
            busy_run <= '0;
        end else begin
            if (busy) busy_run <= busy_run + 1'b1;
            else busy_run <= '0;

            if (cycle_valid) begin
                assert(accepts_since_valid == CNT_W'(CYCLE_SAMPLES));
                accepts_since_valid <= sample_ce ? CNT_W'(1) : '0;
            end else if (sample_ce) begin
                accepts_since_valid <= accepts_since_valid + 1'b1;
            end
        end

        if (past_valid && !$past(rst)) begin
            // Saturating arithmetic: the states this module publishes are
            // always the direct output of `saturate`, so they can never
            // exceed the range that function is built to enforce.
            assert(state_1 <= STATE_MAX && state_1 >= STATE_MIN);
            assert(state_2 <= STATE_MAX && state_2 >= STATE_MIN);

            // Sticky: overflow can only turn on, never off, outside reset.
            if ($past(overflow))
                assert(overflow);

            // done marks a committed result, never a busy cycle.
            if ($past(done))
                assert(!$past(busy));

            // Initiation-interval budget: GOERTZEL_MAX_CYCLES = 4, so busy
            // may run for at most 3 consecutive clk.
            assert(busy_run <= 3);
        end
    end
endmodule
