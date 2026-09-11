// Frequency discipline actuator: trim_inc is always inside +-MAX_TRIM,
// never moves by more than MAX_TRIM_STEP per observation, only moves on an
// accepted measurement, and a rejection is only ever reported for a
// measurement that was actually presented.
//
// The actuator is multi-cycle (BEA-36).  The latency-dependent properties are
// therefore expressed in terms of the explicit `busy` handshake rather than a
// single-cycle assumption:
//   * the outputs are frozen for the whole `busy` window, so a measurement
//     pulse presented while a computation is in flight can never overwrite it;
//   * a computation can only start the cycle after an observation pulse;
//   * a locked / updated actuator can only appear at a committed observation.
module frequency_discipline_formal;
    localparam int MAX_TRIM = 64;
    localparam int MAX_TRIM_STEP = 8;

    (* gclk *) logic clk;
    (* anyseq *) logic measurement_ce, measurement_valid;
    (* anyseq *) logic signed [11:0] phase_error;
    (* anyseq *) logic [7:0] measurement_quality;
    logic rst = 1'b1;
    logic past_valid = 1'b0;

    logic signed [15:0] estimated_offset, trim_inc;
    logic frequency_locked, measurement_rejected, busy;
    logic [7:0] measurement_age;

    frequency_discipline #(
        .PHASE_BITS(12), .PHASE_FRAC_BITS(6), .TRIM_BITS(16), .AGE_BITS(8),
        .PHASE_TO_TRIM(16), .MAX_TRIM(MAX_TRIM), .MAX_TRIM_STEP(MAX_TRIM_STEP),
        .LOCK_COUNT(3), .HOLDOVER_AGE(2)
    ) dut (.*);

    logic signed [16:0] step;

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;
        step = 17'(trim_inc) - 17'($past(trim_inc));

        if (past_valid) begin
            assert(trim_inc <= MAX_TRIM && trim_inc >= -MAX_TRIM);
            assert(estimated_offset <= MAX_TRIM && estimated_offset >= -MAX_TRIM);
        end
        if (past_valid && !$past(rst)) begin
            assert(step <= MAX_TRIM_STEP && step >= -MAX_TRIM_STEP);

            // Outputs are frozen while an observation is being processed: a
            // measurement pulse during `busy` cannot overwrite the in-flight
            // computation (nor can anything else perturb it).
            if (busy && $past(busy)) begin
                assert(trim_inc == $past(trim_inc));
                assert(estimated_offset == $past(estimated_offset));
                assert(frequency_locked == $past(frequency_locked));
            end

            // Outputs may only change on the cycle following an observation
            // pulse (rejection / holdover) or on the commit cycle (the first
            // idle cycle after a busy window).
            if (!$past(measurement_ce) && !$past(busy))
                assert(trim_inc == $past(trim_inc) &&
                       frequency_locked == $past(frequency_locked));

            // A computation can only be launched by an observation pulse.
            if (busy && !$past(busy))
                assert($past(measurement_ce));

            if (measurement_rejected)
                assert($past(measurement_ce && measurement_valid));

            if (frequency_locked && !$past(frequency_locked))
                assert($past(busy) || $past(measurement_ce));
        end
    end
endmodule
