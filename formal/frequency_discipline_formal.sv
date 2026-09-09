// Frequency discipline actuator: trim_inc is always inside +-MAX_TRIM,
// never moves by more than MAX_TRIM_STEP per measurement, only moves on
// an accepted measurement, and a rejection is only ever reported for a
// measurement that was actually presented.
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
    logic frequency_locked, measurement_rejected;
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
            if (!$past(measurement_ce))
                assert(trim_inc == $past(trim_inc) && frequency_locked == $past(frequency_locked));
            if (measurement_rejected)
                assert($past(measurement_ce && measurement_valid));
            if (frequency_locked && !$past(frequency_locked))
                assert($past(measurement_ce && measurement_valid));
        end
    end
endmodule
