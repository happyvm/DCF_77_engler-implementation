// engeler_observables' output pipeline is a fixed state sequencer driven by
// the bank's own cycle_valid: after cycle_valid the bins are latched, four
// products are issued through the shared multiplier, and the dot/cross sums
// are registered. observable_valid must therefore be cycle_valid delayed by
// exactly 6 clocks (1 snapshot + 4 products + 1 sum), on every clock (not
// just on sample_ce), since the sequencer runs unconditionally. The bank's
// cycle_valid period is reconstructed the same way as in
// engeler_goertzel_bank_formal.sv (mod-12, the resonator's real default).
module engeler_observables_formal;
    localparam int SAMPLE_BITS = 6;
    localparam int STATE_BITS = 12;
    localparam int CYCLE_SAMPLES = 12;
    localparam int LATENCY = 6;

    (* gclk *) logic clk;
    (* anyseq *) logic sample_ce;
    (* anyseq *) logic signed [SAMPLE_BITS-1:0] sample;
    logic rst = 1'b1;
    logic past_valid = 1'b0;
    logic signed [STATE_BITS:0] carrier_real, carrier_imag;
    logic signed [(2*STATE_BITS)+2:0] am_inphase_raw, pm_quadrature_raw;
    logic observable_valid, overflow;

    engeler_observables #(
        .SAMPLE_BITS(SAMPLE_BITS), .STATE_BITS(STATE_BITS)
    ) dut (.*);

    logic [3:0] ref_count = '0;
    logic ref_cycle_valid;
    // ref_cycle_valid is the mod-CYCLE_SAMPLES wrap condition itself; the
    // bank/resonator only publish that as their registered cycle_valid one
    // clock later (ref_c below), which is the signal the pipeline actually
    // samples.
    logic ref_c = 1'b0;
    logic [LATENCY-1:0] valid_sr = '0;

    assign ref_cycle_valid = sample_ce && (ref_count == 4'(CYCLE_SAMPLES - 1));

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;

        if (rst) begin
            ref_count <= '0;
            ref_c <= 1'b0;
            valid_sr <= '0;
        end else begin
            if (sample_ce) begin
                if (ref_count == 4'(CYCLE_SAMPLES - 1))
                    ref_count <= '0;
                else
                    ref_count <= ref_count + 1'b1;
            end
            ref_c <= ref_cycle_valid;
            // Six sequencer clocks between the bank's cycle_valid (ref_c) and
            // observable_valid (snapshot, four products, sums).
            valid_sr <= {valid_sr[LATENCY-2:0], ref_c};
        end

        if (past_valid && !$past(rst))
            assert(observable_valid == valid_sr[LATENCY-1]);
    end
endmodule
