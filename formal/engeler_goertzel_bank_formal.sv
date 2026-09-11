// Three resonators sharing one sample_ce and one CYCLE_SAMPLES: they stay in
// lockstep, so the bank's cycle_valid (the AND of all three) is exactly the
// same period a single resonator publishes, and overflow is the sticky OR of
// three independent saturating channels (so it is itself sticky).
//
// BEA-36: the resonator is now a multi-cycle sequencer. A new sample_ce may
// only be presented while `busy` is low (assumed here; proven for the real
// 930 kS/s scheduler in sim/sample_cadence_tb.sv and enforced in simulation by
// sim/goertzel_sample_contract.sv). The period-completing accepted sample is
// tracked with a shift register whose tap reconstructs the bank's registered
// cycle_valid one full pipeline latency later (S_IDLE -> S_REC -> S_SCALE ->
// S_COMMIT). CYCLE_SAMPLES is shrunk to 4 to keep the bounded proof tractable;
// production keeps the resonator default of 12.
module engeler_goertzel_bank_formal;
    localparam int SAMPLE_BITS = 6;
    localparam int STATE_BITS = 12;
    localparam int CYCLE_SAMPLES = 4;
    localparam int CV_LATENCY = 4;   // bank cycle_valid after the accept edge

    (* gclk *) logic clk;
    (* anyseq *) logic sample_ce;
    (* anyseq *) logic signed [SAMPLE_BITS-1:0] sample;
    logic rst = 1'b1;
    logic past_valid = 1'b0;
    logic signed [STATE_BITS-1:0] carrier_s1, carrier_s2, am_s1, am_s2, pm_s1, pm_s2;
    logic cycle_valid, overflow, busy, done;

    engeler_goertzel_bank #(
        .SAMPLE_BITS(SAMPLE_BITS), .STATE_BITS(STATE_BITS),
        .CYCLE_SAMPLES(CYCLE_SAMPLES)
    ) dut (.*);

    logic [1:0] ref_count = '0;
    logic [CV_LATENCY-1:0] valid_delay = '0;

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;

        // Sample-cadence contract (see module header).
        assume(!(busy && sample_ce));

        if (rst) begin
            ref_count <= '0;
            valid_delay <= '0;
        end else if (sample_ce && !busy) begin
            if (ref_count == 2'(CYCLE_SAMPLES - 1)) begin
                ref_count <= '0;
                valid_delay <= {valid_delay[CV_LATENCY-2:0], 1'b1};
            end else begin
                ref_count <= ref_count + 1'b1;
                valid_delay <= {valid_delay[CV_LATENCY-2:0], 1'b0};
            end
        end else begin
            valid_delay <= {valid_delay[CV_LATENCY-2:0], 1'b0};
        end

        if (past_valid && !$past(rst)) begin
            if ($past(overflow))
                assert(overflow);
            if ($past(done))
                assert(!$past(busy));

            // cycle_valid pulses exactly on the commit of every
            // CYCLE_SAMPLES-th accepted sample.
            assert(cycle_valid == valid_delay[CV_LATENCY-1]);
        end
    end
endmodule
