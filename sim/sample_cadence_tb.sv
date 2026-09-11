`timescale 1ns/1ps
// BEA-36 sample-cadence (throughput) test.
//
// Separate from the functional tests: this one does NOT check the Goertzel
// arithmetic, it checks the temporal contract between the *real* fractional
// sample scheduler (930 kS/s at 125 MHz, ~134 clk_sys between samples) and the
// multi-cycle Goertzel bank. It asserts that over a long nominal run, and
// again with the scheduler deliberately trimmed, a new sample_ce is never
// presented while the bank is busy -- and that the measured inter-sample
// spacing is far above the 4-clk initiation interval, which is exactly why
// the contract cannot be violated in hardware.
module sample_cadence_tb;
    localparam int CYCLE_SAMPLES = 12;
    localparam int RUN_CYCLES = 60_000;
    // Minimum permitted spacing == goertzel_resonator GOERTZEL_MAX_CYCLES.
    localparam int MIN_SPACING = 4;

    logic clk = 0, rst = 1;
    logic signed [23:0] trim_inc = 24'sd0;
    logic sample_ce;
    logic [39:0] sample_phase;
    logic signed [13:0] sample = 14'sd0;
    logic signed [31:0] carrier_s1, carrier_s2;
    logic signed [31:0] am_s1, am_s2;
    logic signed [31:0] pm_s1, pm_s2;
    logic cycle_valid, overflow, busy, done;

    sample_scheduler sched (
        .clk(clk), .rst(rst), .trim_inc(trim_inc),
        .sample_ce(sample_ce), .sample_phase(sample_phase)
    );

    engeler_goertzel_bank #(.CYCLE_SAMPLES(CYCLE_SAMPLES)) dut (
        .clk(clk), .rst(rst), .sample_ce(sample_ce), .sample(sample),
        .carrier_s1(carrier_s1), .carrier_s2(carrier_s2),
        .am_s1(am_s1), .am_s2(am_s2), .pm_s1(pm_s1), .pm_s2(pm_s2),
        .cycle_valid(cycle_valid), .overflow(overflow), .busy(busy), .done(done)
    );

    always #4 clk = ~clk;

    integer cyc = 0;
    integer last_ce = -1;
    integer min_gap = 1_000_000;
    integer max_gap = 0;
    integer accepted = 0;
    integer valid_count = 0;
    integer busy_run = 0, busy_max = 0;

    task automatic run_phase(input integer cycles, input string label);
        begin
            repeat (cycles) @(posedge clk);
            if (min_gap < MIN_SPACING)
                $fatal(1, "%s: sample spacing %0d < %0d clk (initiation interval)",
                       label, min_gap, MIN_SPACING);
            $display("  %s: accepted=%0d cycle_valid=%0d min_gap=%0d max_gap=%0d busy_max=%0d",
                     label, accepted, valid_count, min_gap, max_gap, busy_max);
        end
    endtask

    always @(posedge clk) begin
        cyc = cyc + 1;
        if (!rst) begin
            if (sample_ce) begin
                if (last_ce >= 0) begin
                    if (cyc - last_ce < min_gap) min_gap = cyc - last_ce;
                    if (cyc - last_ce > max_gap) max_gap = cyc - last_ce;
                end
                last_ce = cyc;
                accepted = accepted + 1;
                if (busy)
                    $fatal(1, "sample_ce presented while busy (BEA-36 contract)");
            end
            if (busy) busy_run = busy_run + 1;
            else busy_run = 0;
            if (busy_run > busy_max) busy_max = busy_run;
            if (cycle_valid) valid_count = valid_count + 1;
        end
    end

    initial begin
        repeat (4) @(posedge clk);
        rst <= 0;

        // 1. Nominal cadence (trim_inc = 0): the real 930 kS/s rate.
        run_phase(RUN_CYCLES, "nominal");

        // 2. Scheduler trimmed hard in the fast direction (still realistic:
        //    a large correction, ~+/- few ppm in hardware, far below one
        //    sample). Re-check the contract with the period perturbed.
        trim_inc <= 24'sd2_000_000;
        run_phase(RUN_CYCLES, "trim_fast");
        trim_inc <= -24'sd2_000_000;
        run_phase(RUN_CYCLES, "trim_slow");

        // Let any boundary sample in flight finish before accounting.
        repeat (64) @(posedge clk);

        if (accepted < 100)
            $fatal(1, "too few samples accepted: %0d", accepted);
        // Every accepted sample belongs to exactly one carrier cycle;
        // cycle_valid is published once per CYCLE_SAMPLES accepted samples.
        if (valid_count != accepted / CYCLE_SAMPLES)
            $fatal(1, "cycle_valid count %0d != accepted/%0d = %0d",
                   valid_count, CYCLE_SAMPLES, accepted / CYCLE_SAMPLES);
        if (min_gap <= MIN_SPACING)
            $fatal(1, "measured spacing %0d does not clear the initiation interval", min_gap);
        if (busy_max > MIN_SPACING - 1)
            $fatal(1, "busy ran %0d clk, over the budget", busy_max);

        $display("sample_cadence_tb: PASS");
        $finish;
    end

    initial begin
        #2_000_000;
        $fatal(1, "timeout");
    end
endmodule
