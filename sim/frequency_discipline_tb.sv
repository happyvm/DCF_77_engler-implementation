`timescale 1ns/1ps

module frequency_discipline_tb;
    localparam int FRAC = 8;
    logic clk = 0;
    logic rst = 1;
    logic measurement_ce, measurement_valid;
    logic signed [15:0] phase_error;
    logic [7:0] measurement_quality;
    logic signed [15:0] estimated_offset, trim_inc;
    logic frequency_locked, measurement_rejected;
    logic [7:0] measurement_age;

    always #5 clk = ~clk;

    frequency_discipline #(
        .PHASE_BITS(16), .PHASE_FRAC_BITS(FRAC), .TRIM_BITS(16), .AGE_BITS(8),
        .PHASE_TO_TRIM(1024), .ACQ_EST_SHIFT(1), .TRACK_EST_SHIFT(3),
        .ACQ_KP(256), .ACQ_KI(128), .TRACK_KP(32), .TRACK_KI(16),
        .MAX_TRIM(1000), .MAX_TRIM_STEP(100),
        .OUTLIER_LIMIT(256), .DELTA_LIMIT(64),
        .ACQ_QUALITY_MIN(32), .TRACK_QUALITY_MIN(64),
        .LOCK_COUNT(4), .HOLDOVER_AGE(3)
    ) dut (.*);

    task automatic reset_dut;
        begin
            rst = 1; measurement_ce = 0; measurement_valid = 0;
            phase_error = 0; measurement_quality = 0;
            repeat (2) @(posedge clk); #1 rst = 0;
        end
    endtask

    task automatic measure(input integer phase, input bit valid, input integer quality);
        begin
            @(negedge clk);
            phase_error = phase; measurement_valid = valid;
            measurement_quality = quality; measurement_ce = 1;
            @(posedge clk); #1;
            measurement_ce = 0;
        end
    endtask

    task automatic check_condition(input bit condition, input string message);
        if (!condition) begin
            $display("FAIL: %s (trim=%0d estimate=%0d age=%0d locked=%0b rejected=%0b)",
                     message, trim_inc, estimated_offset, measurement_age,
                     frequency_locked, measurement_rejected);
            $fatal(1);
        end
    endtask

    integer i;
    integer held_trim;
    integer pre_recovery_trim;
    initial begin
        // Frequency convergence and bounded response to representative noise.
        reset_dut();
        for (i = 0; i < 10; i = i + 1)
            measure(i * 16, 1, 100); // +1/16 cycle per observation
        check_condition(frequency_locked, "loop did not acquire lock");
        check_condition(estimated_offset > 35 && estimated_offset < 80,
               "frequency estimate did not converge to +64 trim LSB");
        held_trim = trim_inc;
        for (i = 0; i < 12; i = i + 1)
            measure(144 + ((i & 1) ? 3 : -3), 1, 100);
        check_condition(trim_inc <= 1000 && trim_inc >= -1000, "noise escaped correction bounds");
        check_condition((trim_inc-held_trim < 250) && (held_trim-trim_inc < 250),
               "tracking gain chased small phase noise");

        // An impulsive point and a low-quality point must be hole-punched.
        held_trim = trim_inc;
        measure(2000, 1, 100);
        check_condition(measurement_rejected && trim_inc == held_trim,
               "phase outlier was not rejected");
        measure(144, 1, 1);
        check_condition(measurement_rejected && trim_inc == held_trim,
               "low-quality measurement was not rejected");

        // Missing observations age into holdover without changing the actuator.
        for (i = 0; i < 3; i = i + 1)
            measure(0, 0, 0);
        check_condition(!frequency_locked && measurement_age >= 3,
               "measurement loss did not enter holdover");
        check_condition(trim_inc == held_trim, "holdover did not retain last trim");

        // A valid return is accepted and cannot jump by more than the slew limit.
        pre_recovery_trim = trim_inc;
        measure(150, 1, 100);
        check_condition(!measurement_rejected && measurement_age == 0,
               "valid measurement was not accepted after holdover");
        check_condition((trim_inc-pre_recovery_trim <= 100) &&
               (pre_recovery_trim-trim_inc <= 100),
               "holdover recovery made an abrupt trim jump");

        // Positive and negative integrator saturation, independently reset.
        reset_dut();
        for (i = 0; i < 120; i = i + 1) measure(128, 1, 100);
        check_condition(trim_inc == 1000, "positive correction did not saturate");
        for (i = 0; i < 8; i = i + 1) measure(0, 1, 100);
        check_condition(trim_inc <= 1000, "positive anti-windup violated output limit");

        reset_dut();
        for (i = 0; i < 120; i = i + 1) measure(-128, 1, 100);
        check_condition(trim_inc == -1000, "negative correction did not saturate");
        for (i = 0; i < 8; i = i + 1) measure(0, 1, 100);
        check_condition(trim_inc >= -1000, "negative anti-windup violated output limit");

        $display("PASS: frequency_discipline convergence, limits, noise, outlier, holdover and recovery");
        $finish;
    end
endmodule
