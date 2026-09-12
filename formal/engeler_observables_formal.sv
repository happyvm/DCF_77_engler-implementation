// engeler_observables' output pipeline is a fixed state sequencer driven by
// the bank's own cycle_valid: after cycle_valid the bins are latched and each
// of the four products is decomposed into four exact 18x18 limb sub-products
// (S_LOAD -> S_MA -> S_MB -> S_ACC) before the dot/cross sums are registered.
// observable_valid must therefore be cycle_valid delayed by exactly 18 clocks
// (1 snapshot + 4 products x 4 states + 1 sum), on every clock (not just on
// sample_ce), since the sequencer runs unconditionally.
//
// BEA-36: the resonator is now a multi-cycle sequencer, so the bank's
// cycle_valid is no longer one clock after the period-completing accepted
// sample but four (S_IDLE -> S_REC -> S_SCALE -> S_COMMIT). sample_ce is
// driven here at the minimum permitted spacing (4 clk, == GOERTZEL_MAX_CYCLES)
// so every pulse is accepted; the period-completing sample is modelled the
// same way as in engeler_goertzel_bank_formal.sv and a matching 4-deep shift
// reconstructs the bank's registered cycle_valid before the 18-deep
// output-latency shift. CYCLE_SAMPLES is raised from the minimum to 8 so the
// 32-clk cycle_valid spacing stays larger than the 18-clk observables latency
// (otherwise a cycle_valid would arrive mid-sequencer and be dropped).
module engeler_observables_formal;
    localparam int SAMPLE_BITS = 6;
    localparam int STATE_BITS = 12;
    localparam int CYCLE_SAMPLES = 8;
    localparam int LATENCY = 18;
    localparam int CV_LATENCY = 4;   // bank cycle_valid after the accept edge

    (* gclk *) logic clk;
    logic sample_ce;
    (* anyseq *) logic signed [SAMPLE_BITS-1:0] sample;
    logic rst = 1'b1;
    logic past_valid = 1'b0;
    logic signed [STATE_BITS:0] carrier_real, carrier_imag;
    logic signed [(2*STATE_BITS)+2:0] am_inphase_raw, pm_quadrature_raw;
    logic observable_valid, overflow;

    engeler_observables #(
        .SAMPLE_BITS(SAMPLE_BITS), .STATE_BITS(STATE_BITS),
        .CYCLE_SAMPLES(CYCLE_SAMPLES)
    ) dut (.*);

    // Minimum spaced cadence: one sample every GOERTZEL_MAX_CYCLES clk.
    logic [1:0] ce_phase = '0;
    always_ff @(posedge clk) begin
        if (rst) ce_phase <= '0;
        else ce_phase <= ce_phase + 1'b1;
    end
    assign sample_ce = (ce_phase == 2'd0);

    logic [3:0] ref_count = '0;
    logic ref_cycle_valid;
    logic [CV_LATENCY-1:0] cv_sr = '0;
    logic [LATENCY-1:0] valid_sr = '0;

    assign ref_cycle_valid = sample_ce && (ref_count == 4'(CYCLE_SAMPLES - 1));

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;

        if (rst) begin
            ref_count <= '0;
            cv_sr <= '0;
            valid_sr <= '0;
        end else begin
            if (sample_ce) begin
                if (ref_count == 4'(CYCLE_SAMPLES - 1))
                    ref_count <= '0;
                else
                    ref_count <= ref_count + 1'b1;
            end
            // cv_sr[CV_LATENCY-1] is the bank's registered cycle_valid.
            cv_sr <= {cv_sr[CV_LATENCY-2:0], ref_cycle_valid};
            valid_sr <= {valid_sr[LATENCY-2:0], cv_sr[CV_LATENCY-1]};
        end

        if (past_valid && !$past(rst))
            assert(observable_valid == valid_sr[LATENCY-1]);
    end
endmodule
