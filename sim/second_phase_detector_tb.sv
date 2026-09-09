`timescale 1ns/1ps
module second_phase_detector_tb;
    localparam integer SECOND_CYCLES = 20;
    logic clk = 0, rst = 1, carrier_ce = 1;
    logic signed [11:0] am_envelope = 100;
    logic pm_measurement_valid = 0;
    logic signed [5:0] pm_phase_error_cycles = 0;
    logic [7:0] pm_quality = 0;
    logic second_ce, measurement_outlier;
    logic signed [5:0] phase_error_cycles;
    logic [7:0] quality;
    logic [7:0] measurement_age;
    logic [1:0] state;
    integer cycles = 0, last_tick = -1, tick_count = 0, gap;

    second_phase_detector #(
        .INPUT_BITS(12), .SECOND_CYCLES(SECOND_CYCLES),
        .AM_EDGE_THRESHOLD(20), .SEARCH_TOLERANCE(2), .TRACK_WINDOW(3),
        .ACQUIRE_HITS(2), .HOLDOVER_AFTER(2), .AGE_BITS(8)
    ) dut (.*);

    always #5 clk = ~clk;
    always @(posedge clk) begin
        cycles = cycles + 1;
        if (second_ce) begin
            if (last_tick >= 0) begin
                gap = cycles-last_tick;
                if (gap < SECOND_CYCLES-1 || gap > SECOND_CYCLES+1)
                    $fatal(1, "discontinuous second ticks, gap=%0d", gap);
            end
            last_tick = cycles; tick_count = tick_count + 1;
        end
    end

    // A one-carrier notch; the extra clock covers the detector's registered
    // input stage so the edge's effects are visible when the task returns.
    task automatic am_notch(input bit inverted);
        begin
            am_envelope <= inverted ? -12'sd20 : 12'sd20;
            @(posedge clk); #1;
            am_envelope <= inverted ? -12'sd100 : 12'sd100;
            @(posedge clk); #1;
        end
    endtask

    task automatic wait_carriers(input integer count);
        integer i;
        begin for (i=0; i<count; i=i+1) @(posedge clk); #1; end
    endtask

    initial begin
        wait_carriers(3); rst <= 0;
        // Arbitrary initial phase, then two one-second-spaced AM reductions.
        wait_carriers(7); am_notch(0);
        wait_carriers(SECOND_CYCLES-1); am_notch(0);
        #1;
        if (state != 2'd1 || !second_ce)
            $fatal(1, "arbitrary-phase SEARCH did not acquire");

        // PZF fine timing controls only a one-cycle slew and sets its quality.
        wait_carriers(5);
        pm_phase_error_cycles <= 2; pm_quality <= 8'd180;
        pm_measurement_valid <= 1; @(posedge clk); #1;
        pm_measurement_valid <= 0;
        if (phase_error_cycles != 2 || quality != 180)
            $fatal(1, "PZF refinement was not accepted");

        // An RF impulse away from the tracking aperture is flagged, not used.
        wait_carriers(4); am_notch(0);
        if (!measurement_outlier)
            $fatal(1, "off-window AM impulse was not rejected");

        // Temporary loss enters HOLDOVER while the internally generated cadence
        // continues.  No missing RF sample may alter the phase estimate.
        wait_carriers(3*SECOND_CYCLES+3);
        if (state != 2'd2 || measurement_age < 2)
            $fatal(1, "signal loss did not enter HOLDOVER");

        // Polarity-inverted AM returns near the predicted epoch and relocks
        // without inserting a second tick.
        wait (dut.position >= SECOND_CYCLES-2);
        am_notch(1);
        wait_carriers(2);
        if (state != 2'd1)
            $fatal(1, "inverted-polarity RF did not leave HOLDOVER");
        if (tick_count < 3)
            $fatal(1, "insufficient internally generated seconds");

        // Late slew reversal inside one second: an early edge (+3, slew +1)
        // followed by an edge in the last cycles (-1, slew -1). The former
        // exact-match wrap test then never matched again and the position
        // counter ran through a second period (found by the bounded proof
        // in formal/second_phase_detector_formal.sv); the tick-gap monitor
        // above catches the missing second.
        wait (dut.position == 2); am_notch(0);
        wait (dut.position == SECOND_CYCLES - 2); am_notch(0);
        wait_carriers(2 * SECOND_CYCLES + 4);
        if (phase_error_cycles > 3 || phase_error_cycles < -3)
            $fatal(1, "phase error %0d left the tracking aperture", phase_error_cycles);
        $display("second_phase_detector_tb: PASS");
        $finish;
    end
endmodule
