`timescale 1ns/1ps
// The AM envelope reaching second_phase_detector is not a step: it comes
// out of a first-order Goertzel bin, so every notch is a long monotonic
// ramp down and back up. This bench models that ramp and requires exactly
// one edge per notch, landing within a few cycles of the true onset, with
// acquisition and a steady one-second cadence following from it. The
// original adjacent-cycle comparison fired on every cycle of the ramp and
// could never satisfy the one-second spacing check.
module second_phase_ramp_tb;
    localparam int SECOND_CYCLES = 600;
    localparam int NOTCH_CYCLES = 120;
    localparam int FULL = 20000;
    localparam int REDUCED = 1250;

    logic clk = 0, rst = 1, carrier_ce = 0;
    logic signed [15:0] am_envelope = 16'(FULL);
    logic pm_measurement_valid = 0;
    logic signed [10:0] pm_phase_error_cycles = 0;
    logic [7:0] pm_quality = 0;
    logic second_ce, measurement_outlier;
    logic signed [10:0] phase_error_cycles;
    logic [7:0] quality;
    logic [15:0] measurement_age;
    logic [1:0] state;

    second_phase_detector #(
        .INPUT_BITS(16), .SECOND_CYCLES(SECOND_CYCLES),
        .AM_EDGE_THRESHOLD(1), .SEARCH_TOLERANCE(10), .TRACK_WINDOW(20),
        .ACQUIRE_HITS(2), .HOLDOVER_AFTER(2), .REF_DECAY_SHIFT(12)
    ) dut (.*);

    always #5 clk = ~clk;

    integer edges_this_second = 0, edge_cycle = -1, cycle_in_second = 0;
    integer seconds_run = 0, ticks = 0, last_tick_cycle = -1, tick_gap;
    integer bad_gaps = 0;
    integer total_cycles = 0;
    real level;

    always @(posedge clk) begin
        total_cycles = total_cycles + 1;
        if (dut.am_edge) begin
            edges_this_second = edges_this_second + 1;
            edge_cycle = cycle_in_second;
        end
        if (second_ce) begin
            if (last_tick_cycle >= 0) begin
                tick_gap = total_cycles - last_tick_cycle;
                if (tick_gap < SECOND_CYCLES - 1 || tick_gap > SECOND_CYCLES + 1)
                    bad_gaps = bad_gaps + 1;
            end
            last_tick_cycle = total_cycles;
            ticks = ticks + 1;
        end
    end

    // One carrier cycle per clock: envelope relaxes toward its target with
    // a 1/64-per-cycle first-order step, the shape a scaled Goertzel bin
    // produces.
    task automatic run_second;
        integer c;
        begin
            edges_this_second = 0; edge_cycle = -1;
            for (c = 0; c < SECOND_CYCLES; c = c + 1) begin
                cycle_in_second = c;
                if (c < NOTCH_CYCLES)
                    level = level + (real'(REDUCED) - level) / 64.0;
                else
                    level = level + (real'(FULL) - level) / 64.0;
                am_envelope <= 16'($rtoi(level));
                carrier_ce <= 1; @(posedge clk); #1;
            end
            seconds_run = seconds_run + 1;
        end
    endtask

    integer s;
    initial begin
        level = real'(FULL);
        repeat (3) @(posedge clk); rst <= 0; @(posedge clk); #1;
        // Settle the peak-hold reference on a full carrier first.
        for (s = 0; s < 300; s = s + 1) begin
            am_envelope <= 16'(FULL); carrier_ce <= 1; @(posedge clk); #1;
        end
        for (s = 0; s < 8; s = s + 1) begin
            run_second();
            if (edges_this_second != 1)
                $fatal(1, "second %0d produced %0d AM edges, expected exactly 1",
                       s, edges_this_second);
            if (edge_cycle > 8)
                $fatal(1, "second %0d: edge detected %0d cycles after onset",
                       s, edge_cycle);
        end
        if (state != 2'd1)
            $fatal(1, "ramped notches did not acquire TRACK (state=%0d)", state);
        if (ticks < 5)
            $fatal(1, "too few second ticks: %0d", ticks);
        if (bad_gaps != 0)
            $fatal(1, "%0d second ticks were not one second apart", bad_gaps);
        $display("second_phase_ramp_tb: PASS (edge %0d cycles after onset)", edge_cycle);
        $finish;
    end

    initial begin
        #100_000_000;
        $fatal(1, "timeout");
    end
endmodule
