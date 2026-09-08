`timescale 1ns/1ps
// Drives pm_phase_discriminator with a synthetic PM/PRN signal whose true
// chip timing is deliberately offset from the module's own nominal
// PRN_START_CYCLE (15500), and checks the sign/validity of the resulting
// fine phase error across the scenarios required for closing the PM/PZF
// loop: positive error, negative error, zero error, PM polarity inversion,
// noise, an outlier-sized error, total PM absence, and reacquisition after
// a dropout.
module pm_phase_discriminator_tb;
    localparam int OBSERVABLE_BITS = 16;
    localparam int CHIP_SOFT_BITS = 16;
    localparam int PRN_START_CYCLE = 15_500;
    localparam int OFFSET_CYCLES = 40;
    localparam int CYCLES_PER_CHIP = 120;
    localparam int CHIP_COUNT = 512;
    localparam int SECOND_CYCLES_TB = PRN_START_CYCLE + CHIP_COUNT * CYCLES_PER_CHIP + 200;

    logic clk = 0, rst = 1;
    logic second_ce, carrier_ce;
    logic signed [OBSERVABLE_BITS-1:0] pm_observable;
    logic signed [CHIP_SOFT_BITS+9:0] prompt_correlation;
    logic prompt_correlation_valid;
    logic signed [17:0] pm_phase_error_cycles;
    logic phase_error_valid;

    // The prompt tap: identical to the one engeler_detector wires in from
    // its own engeler_pm_pipeline, supplied here as an input matching the
    // real integration rather than re-derived internally by the DUT.
    engeler_pm_pipeline #(
        .OBSERVABLE_BITS(OBSERVABLE_BITS), .CHIP_SOFT_BITS(CHIP_SOFT_BITS),
        .OUTPUT_SHIFT(0), .PRN_START_CYCLE(PRN_START_CYCLE)
    ) prompt_i (
        .clk(clk), .rst(rst), .second_ce(second_ce), .carrier_ce(carrier_ce),
        .pm_observable(pm_observable), .correlation(prompt_correlation),
        .correlation_valid(prompt_correlation_valid),
        .prn_active(), .prn_done()
    );

    pm_phase_discriminator #(
        .OBSERVABLE_BITS(OBSERVABLE_BITS), .CHIP_SOFT_BITS(CHIP_SOFT_BITS),
        .OUTPUT_SHIFT(0), .PRN_START_CYCLE(PRN_START_CYCLE),
        .OFFSET_CYCLES(OFFSET_CYCLES), .MIN_PROMPT_MAGNITUDE(2000)
    ) dut (
        .clk(clk), .rst(rst), .second_ce(second_ce), .carrier_ce(carrier_ce),
        .pm_observable(pm_observable),
        .prompt_correlation(prompt_correlation),
        .prompt_correlation_valid(prompt_correlation_valid),
        .pm_phase_error_cycles(pm_phase_error_cycles),
        .phase_error_valid(phase_error_valid)
    );

    always #5 clk = ~clk;

    // phase_error_valid pulses for exactly one cycle, typically long
    // before the driving loop below finishes clocking out the rest of
    // the (deliberately oversized) second; latch the last pulse's
    // result so it survives to be checked once the loop returns.
    logic result_valid_latched;
    logic signed [17:0] result_error_latched;
    always @(posedge clk) begin
        if (phase_error_valid) begin
            result_valid_latched <= 1'b1;
            result_error_latched <= pm_phase_error_cycles;
        end
    end

    // Independent reference model of the 9-stage Galois PRN generator
    // (rtl/pm/dcf77_prn_generator.sv), advanced on our own schedule so the
    // stimulus never races the DUT's own chip timing (see the equivalent
    // note in sim/engeler_pm_pipeline_tb.sv).
    logic [8:0] ref_lfsr;
    integer ref_sample_in_chip;

    function automatic logic [8:0] next_ref_lfsr(input logic [8:0] l);
        logic [8:0] shifted;
        begin
            shifted = {1'b0, l[8:1]};
            if (l[0] || (shifted == 9'b0))
                shifted = shifted ^ 9'h110;
            next_ref_lfsr = shifted;
        end
    endfunction

    integer true_start;
    integer invert_sign;
    integer noise_amp;
    integer dropout;
    integer seed = 32'hC0FFEE;

    // Drives one full second of carrier cycles. The true PRN sequence
    // starts at (PRN_START_CYCLE + true_start_offset); invert flips the
    // transmitted sign; noise_amplitude adds bounded pseudo-random jitter;
    // drop_signal replaces the whole PRN burst with noise only.
    task automatic run_second(
        input integer true_start_offset,
        input logic do_invert,
        input integer noise_amplitude,
        input logic drop_signal
    );
        integer c;
        integer true_start_local;
        integer chip_num;
        logic signed [OBSERVABLE_BITS-1:0] value;
        integer noise_term;
        begin
            true_start_local = PRN_START_CYCLE + true_start_offset;
            ref_lfsr = '0;
            ref_sample_in_chip = 0;
            result_valid_latched <= 1'b0;
            second_ce <= 1; @(posedge clk); second_ce <= 0;
            for (c = 0; c < SECOND_CYCLES_TB; c = c + 1) begin
                noise_term = noise_amplitude > 0 ?
                    ($urandom(seed) % (2*noise_amplitude+1)) - noise_amplitude : 0;
                seed = seed + 1;
                if (drop_signal) begin
                    value = OBSERVABLE_BITS'(noise_term);
                end else if (c >= true_start_local &&
                             c < true_start_local + CHIP_COUNT * CYCLES_PER_CHIP) begin
                    if (ref_sample_in_chip == CYCLES_PER_CHIP) begin
                        ref_lfsr = next_ref_lfsr(ref_lfsr);
                        ref_sample_in_chip = 0;
                    end
                    value = (ref_lfsr[0] ^ do_invert) ?
                        OBSERVABLE_BITS'(16'sd400 + noise_term) :
                        OBSERVABLE_BITS'(-16'sd400 + noise_term);
                    ref_sample_in_chip = ref_sample_in_chip + 1;
                end else begin
                    value = OBSERVABLE_BITS'(noise_term);
                end
                pm_observable <= value;
                carrier_ce <= 1; @(posedge clk);
                carrier_ce <= 0; @(posedge clk);
            end
            #1;
        end
    endtask

    initial begin
        second_ce = 0; carrier_ce = 0; pm_observable = 0;
        repeat (2) @(posedge clk); rst <= 0; @(posedge clk);

        // Zero error: true timing matches the nominal PRN start exactly.
        run_second(0, 1'b0, 0, 1'b0);
        if (!result_valid_latched)
            $fatal(1, "zero-error scenario did not produce a valid measurement");
        if (result_error_latched > 5 || result_error_latched < -5)
            $fatal(1, "zero-error scenario magnitude too large: %0d", result_error_latched);
        $display("zero-error: %0d", result_error_latched);

        // Positive error: the true epoch is later than the nominal one.
        run_second(15, 1'b0, 0, 1'b0);
        if (!result_valid_latched || result_error_latched <= 0)
            $fatal(1, "positive-error scenario mismatch: valid=%0b error=%0d",
                   result_valid_latched, result_error_latched);
        $display("positive-error (+15): %0d", result_error_latched);

        // Negative error: the true epoch is earlier than the nominal one.
        run_second(-15, 1'b0, 0, 1'b0);
        if (!result_valid_latched || result_error_latched >= 0)
            $fatal(1, "negative-error scenario mismatch: valid=%0b error=%0d",
                   result_valid_latched, result_error_latched);
        $display("negative-error (-15): %0d", result_error_latched);

        // PM polarity inversion: the analog chain's sign convention is
        // flipped, but the discriminator corrects for it via the
        // prompt tap's own (also-inverted) sign, so the same true
        // timing offset must still report the same signed error.
        run_second(15, 1'b1, 0, 1'b0);
        if (!result_valid_latched || result_error_latched <= 0)
            $fatal(1, "inverted-polarity scenario mismatch: valid=%0b error=%0d",
                   result_valid_latched, result_error_latched);
        $display("inverted-polarity (+15): %0d", result_error_latched);

        // Noise: a bounded per-sample perturbation must not flip the sign
        // of an otherwise clear timing offset (512*120 samples average
        // out far smaller noise than this).
        run_second(15, 1'b0, 50, 1'b0);
        if (!result_valid_latched || result_error_latched <= 0)
            $fatal(1, "noisy scenario mismatch: valid=%0b error=%0d",
                   result_valid_latched, result_error_latched);
        $display("noisy (+15): %0d", result_error_latched);

        // Outlier-sized error: a gross timing offset must still report a
        // large, correctly-signed value (second_phase_detector's own
        // existing TRACK_WINDOW check is what actually rejects it as an
        // outlier downstream; this only confirms the discriminator does
        // not produce something nonsensical or wrongly signed for it).
        run_second(100, 1'b0, 0, 1'b0);
        if (!result_valid_latched || result_error_latched <= 15)
            $fatal(1, "outlier-sized scenario mismatch: valid=%0b error=%0d",
                   result_valid_latched, result_error_latched);
        $display("outlier-sized (+100): %0d", result_error_latched);

        // Absence of PM: no real signal at all (noise only) must not
        // produce a confident measurement.
        run_second(0, 1'b0, 5, 1'b1);
        if (result_valid_latched)
            $fatal(1, "PM-absent scenario incorrectly reported valid: error=%0d",
                   result_error_latched);
        $display("PM-absent: valid=%0b (expected 0)", result_valid_latched);

        // Reacquisition: after the dropout above, a normal signal must
        // resume producing correct measurements -- no stuck state.
        run_second(15, 1'b0, 0, 1'b0);
        if (!result_valid_latched || result_error_latched <= 0)
            $fatal(1, "reacquisition scenario mismatch: valid=%0b error=%0d",
                   result_valid_latched, result_error_latched);
        $display("reacquisition (+15): %0d", result_error_latched);

        $display("pm_phase_discriminator_tb: PASS");
        $finish;
    end

    initial begin
        #100_000_000;
        $fatal(1, "timeout");
    end
endmodule
