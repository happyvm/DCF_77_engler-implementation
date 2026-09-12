// SPDX-License-Identifier: MIT
// BEA-36 bit-exactness evidence for the engeler_observables signed-limb
// multiplier.
//
// The observables' four 33x33 products are no longer formed by a single
// `a * b`: each is decomposed into four 18x18 signed sub-products and summed
// with constant shifts over a longer sequencer. That re-association must be
// bit-identical to the single-cycle product truncated to PRODUCT_BITS.
//
// This test drives the real module with pseudo-random samples so its internal
// operand snapshots sweep a wide range of 33-bit values, and at every
// observable_valid it recomputes the AM dot / PM cross products from the DUT's
// own snap_* registers using the original full-width `*` expression. Any
// mismatch in any bit of any observable fails the run. Using the DUT's frozen
// snapshots as the golden operands makes this a direct equivalence check of
// the multiply path, independent of the resonator's own arithmetic.
module engeler_observables_equiv_tb;
    localparam int SAMPLE_PERIOD = 4;   // goertzel_resonator GOERTZEL_MAX_CYCLES
    localparam int STATE_BITS = 32;
    localparam int COMPLEX_BITS = STATE_BITS + 1;
    localparam int PRODUCT_BITS = 2 * COMPLEX_BITS;   // 66-bit product
    localparam int OBS_BITS = (2 * STATE_BITS) + 3;   // 67-bit observable

    logic clk = 0;
    logic rst = 1;
    logic sample_ce = 0;
    logic signed [13:0] sample = 0;
    logic signed [STATE_BITS:0] carrier_real, carrier_imag;
    logic signed [OBS_BITS-1:0] am_inphase_raw, pm_quadrature_raw;
    logic observable_valid;
    logic overflow;

    engeler_observables dut (.*);
    always #5 clk = ~clk;

    // 32-bit xorshift PRNG: reproducible, no external seeds.
    logic [31:0] rng = 32'h1234_5678;
    function automatic logic [31:0] next_rand;
        rng = rng ^ (rng << 13);
        rng = rng ^ (rng >> 17);
        rng = rng ^ (rng << 5);
        next_rand = rng;
    endfunction

    integer accepted = 0;
    integer observables_checked = 0;

    // Golden products recomputed from the DUT's frozen snapshots with the
    // original single-cycle full-width multiply, then the original +/-
    // combination widened to the observable width.
    logic signed [PRODUCT_BITS-1:0] golden_am_rr, golden_am_ii;
    logic signed [PRODUCT_BITS-1:0] golden_pm_ir, golden_pm_ri;
    logic signed [OBS_BITS-1:0] golden_am, golden_pm;
    always_comb begin
        golden_am_rr = PRODUCT_BITS'($signed(dut.snap_am_real))
                     * PRODUCT_BITS'($signed(dut.snap_carrier_real));
        golden_am_ii = PRODUCT_BITS'($signed(dut.snap_am_imag))
                     * PRODUCT_BITS'($signed(dut.snap_carrier_imag));
        golden_pm_ir = PRODUCT_BITS'($signed(dut.snap_pm_imag))
                     * PRODUCT_BITS'($signed(dut.snap_carrier_real));
        golden_pm_ri = PRODUCT_BITS'($signed(dut.snap_pm_real))
                     * PRODUCT_BITS'($signed(dut.snap_carrier_imag));
        golden_am = OBS_BITS'($signed(golden_am_rr)) + OBS_BITS'($signed(golden_am_ii));
        golden_pm = OBS_BITS'($signed(golden_pm_ir)) - OBS_BITS'($signed(golden_pm_ri));
    end

    always @(posedge clk) begin
        if (observable_valid) begin
            observables_checked = observables_checked + 1;
            if (am_inphase_raw !== golden_am)
                $fatal(1, "AM observable mismatch: got %0d want %0d",
                       am_inphase_raw, golden_am);
            if (pm_quadrature_raw !== golden_pm)
                $fatal(1, "PM observable mismatch: got %0d want %0d",
                       pm_quadrature_raw, golden_pm);
        end
    end

    integer i;
    logic [31:0] rnd;
    initial begin
        repeat (4) @(posedge clk);
        rst <= 0;
        // ~600 carrier cycles (12 samples each): enough random 33-bit operand
        // pairs to exercise every limb and sign combination many times over.
        for (i = 0; i < 7200; i = i + 1) begin
            rnd = next_rand();
            sample <= rnd[13:0];
            sample_ce <= 1;
            @(posedge clk);
            sample_ce <= 0;
            repeat (SAMPLE_PERIOD - 1) @(posedge clk);
            accepted = accepted + 1;
        end

        if (observables_checked < 500)
            $fatal(1, "too few observables checked: %0d", observables_checked);
        $display("engeler_observables_equiv_tb: PASS (%0d observables over %0d samples, bit-exact)",
                 observables_checked, accepted);
        $finish;
    end

    initial begin
        #4000000;
        $fatal(1, "timeout");
    end
endmodule
