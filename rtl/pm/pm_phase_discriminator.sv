// SPDX-License-Identifier: MIT
// Fine (sub-chip) second-phase error from an early/late PZF discriminator.
//
// engeler_detector's prompt PM/PRN correlator (engeler_pm_pipeline) already
// answers "how well does the received phase modulation match the known
// 512-chip DCF77 sequence, under the current second-boundary hypothesis?"
// as a single scalar per second. That alone carries no *signed* timing
// information: nudging the hypothesis earlier or later both degrade an
// already-good prompt score in roughly the same way. This module adds two
// more full correlator instances -- identical to the prompt one, just with
// their PRN start shifted a fraction of a chip earlier and later -- and
// derives a signed sub-second phase error from the classic early-minus-late
// discriminator, normalized by the prompt magnitude so its scale does not
// depend on signal strength: near lock, whichever tap sits closer to the
// true chip boundary correlates better, and by how much (relative to how
// much the prompt score already indicates a real signal) says how far off
// and in which direction.
module pm_phase_discriminator #(
    parameter int OBSERVABLE_BITS = 67,
    parameter int CHIP_SOFT_BITS = 32,
    parameter int OUTPUT_SHIFT = 24,
    parameter int SECOND_CYCLES = 77_500,
    parameter int PRN_START_CYCLE = 15_500,
    parameter int CYCLES_PER_CHIP = 120,
    parameter int CHIP_COUNT = 512,
    // Sub-chip offset for the early/late taps; must stay well inside one
    // chip so both taps remain in the same correlation lobe as the prompt
    // tap instead of aliasing into an unrelated one (a third of a chip).
    parameter int OFFSET_CYCLES = CYCLES_PER_CHIP / 3,
    parameter int PHASE_ERROR_BITS = 18,
    // A prompt correlation below this magnitude is too weak to steer
    // timing from at all (no real PM signal, or pure noise): the
    // measurement is dropped rather than fed forward as a confident
    // near-zero error. This is a signal-quality floor, distinct from
    // (and always active regardless of) QUALIFICATION_ENABLED, which
    // gates whether the receiver as a whole publishes a qualified time.
    parameter int MIN_PROMPT_MAGNITUDE = 0
) (
    input  logic clk,
    input  logic rst,
    input  logic second_ce,
    input  logic carrier_ce,
    input  logic signed [OBSERVABLE_BITS-1:0] pm_observable,

    // The existing prompt correlation, computed elsewhere (engeler_detector
    // already instantiates its own engeler_pm_pipeline for it).
    input  logic signed [CHIP_SOFT_BITS+9:0] prompt_correlation,
    input  logic prompt_correlation_valid,

    output logic signed [PHASE_ERROR_BITS-1:0] pm_phase_error_cycles,
    output logic phase_error_valid
);
    localparam int CORR_BITS = CHIP_SOFT_BITS + 10;
    localparam int NUM_BITS = CORR_BITS + 2;
    // Headroom for multiplying by OFFSET_CYCLES (<256, asserted below):
    // the true product needs up to NUM_BITS + 8 bits, not just
    // NUM_BITS -- sizing the accumulator at plain NUM_BITS silently wraps
    // for exactly the offsets this module actually uses (e.g. the default
    // 40), which is why this width is carried explicitly rather than
    // inferred from context the way a plain `*` expression would.
    localparam int OFFSET_BITS = 8;
    localparam int PROD_BITS = NUM_BITS + OFFSET_BITS;

    // OFFSET_CYCLES is a small (<256, asserted below) compile-time
    // constant, so scaling by it needs no general multiplier: unrolled
    // shift-add over its set bits synthesizes to at most a handful of
    // LUT-only adders (e.g. one add for the default 40 = 32+8) instead of
    // consuming ECP5 MULT18X18D tiles this receiver's DSP budget can't
    // spare (see rtl/resource_budget.json).
    function automatic logic signed [PROD_BITS-1:0] scale_by_offset_cycles(
        input logic signed [NUM_BITS-1:0] x
    );
        logic signed [PROD_BITS-1:0] acc;
        logic signed [PROD_BITS-1:0] x_ext;
        begin
            x_ext = PROD_BITS'(x);
            acc = '0;
            for (int b = 0; b < OFFSET_BITS; b++)
                if (OFFSET_CYCLES[b])
                    acc = acc + (x_ext <<< b);
            scale_by_offset_cycles = acc;
        end
    endfunction

    logic signed [CORR_BITS-1:0] early_correlation, late_correlation;
    logic early_correlation_valid, late_correlation_valid;
    logic unused_early_active, unused_early_done;
    logic unused_late_active, unused_late_done;

    engeler_pm_pipeline #(
        .OBSERVABLE_BITS(OBSERVABLE_BITS), .CHIP_SOFT_BITS(CHIP_SOFT_BITS),
        .OUTPUT_SHIFT(OUTPUT_SHIFT), .SECOND_CYCLES(SECOND_CYCLES),
        .PRN_START_CYCLE(PRN_START_CYCLE - OFFSET_CYCLES),
        .CYCLES_PER_CHIP(CYCLES_PER_CHIP), .CHIP_COUNT(CHIP_COUNT)
    ) early_i (
        .clk(clk), .rst(rst), .second_ce(second_ce), .carrier_ce(carrier_ce),
        .pm_observable(pm_observable), .correlation(early_correlation),
        .correlation_valid(early_correlation_valid),
        .prn_active(unused_early_active), .prn_done(unused_early_done)
    );

    engeler_pm_pipeline #(
        .OBSERVABLE_BITS(OBSERVABLE_BITS), .CHIP_SOFT_BITS(CHIP_SOFT_BITS),
        .OUTPUT_SHIFT(OUTPUT_SHIFT), .SECOND_CYCLES(SECOND_CYCLES),
        .PRN_START_CYCLE(PRN_START_CYCLE + OFFSET_CYCLES),
        .CYCLES_PER_CHIP(CYCLES_PER_CHIP), .CHIP_COUNT(CHIP_COUNT)
    ) late_i (
        .clk(clk), .rst(rst), .second_ce(second_ce), .carrier_ce(carrier_ce),
        .pm_observable(pm_observable), .correlation(late_correlation),
        .correlation_valid(late_correlation_valid),
        .prn_active(unused_late_active), .prn_done(unused_late_done)
    );

    logic prompt_seen, early_seen, late_seen;
    logic signed [CORR_BITS-1:0] prompt_latched, early_latched, late_latched;

    // The final scaling/division runs as a sequential restoring divider,
    // one quotient bit per clock over PROD_BITS clocks: it is needed once
    // per second, and a single-cycle PROD_BITS-wide divider was this
    // design's critical path (~290 ns).
    localparam int DIV_STEP_W = $clog2(PROD_BITS + 1);
    localparam logic [PROD_BITS-1:0] RESULT_MAX = PROD_BITS'((1 << (PHASE_ERROR_BITS - 1)) - 1);
    logic div_busy, div_negative;
    logic [PROD_BITS-1:0] div_dividend, div_divisor;
    // Quotient bits already decided (the last one is composed at the output);
    // the remainder is always below the divisor, so PROD_BITS bits suffice.
    logic [PROD_BITS-2:0] div_quotient;
    logic [PROD_BITS-1:0] div_remainder;
    logic [PROD_BITS-1:0] quotient_now;
    logic [DIV_STEP_W-1:0] div_step;
    logic [PROD_BITS:0] rem_shift;
    always_comb begin
        rem_shift = {div_remainder, div_dividend[PROD_BITS-1]};
        quotient_now = (rem_shift >= {1'b0, div_divisor}) ? {div_quotient, 1'b1} : {div_quotient, 1'b0};
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            prompt_seen <= 1'b0; early_seen <= 1'b0; late_seen <= 1'b0;
            prompt_latched <= '0; early_latched <= '0; late_latched <= '0;
            pm_phase_error_cycles <= '0;
            phase_error_valid <= 1'b0;
            div_busy <= 1'b0; div_negative <= 1'b0; div_step <= '0;
            div_dividend <= '0; div_divisor <= '0; div_quotient <= '0; div_remainder <= '0;
        end else begin
            phase_error_valid <= 1'b0;

            if (second_ce) begin
                prompt_seen <= 1'b0; early_seen <= 1'b0; late_seen <= 1'b0;
            end

            if (prompt_correlation_valid) begin
                prompt_seen <= 1'b1;
                prompt_latched <= prompt_correlation;
            end
            if (early_correlation_valid) begin
                early_seen <= 1'b1;
                early_latched <= early_correlation;
            end
            if (late_correlation_valid) begin
                late_seen <= 1'b1;
                late_latched <= late_correlation;
            end

            if (div_busy) begin
                div_dividend <= div_dividend << 1;
                if (rem_shift >= {1'b0, div_divisor})
                    div_remainder <= PROD_BITS'(rem_shift - {1'b0, div_divisor});
                else
                    div_remainder <= PROD_BITS'(rem_shift);
                div_quotient <= quotient_now[PROD_BITS-2:0];
                if (div_step == DIV_STEP_W'(1)) begin
                    div_busy <= 1'b0;
                    // Bring the quotient computed above into this cycle's
                    // result: last bit decided by the comparison just made.
                    phase_error_valid <= 1'b1;
                    if (quotient_now > RESULT_MAX)
                        // Parenthesised casts: an unparenthesised
                        // "-N'(x)" is read by Yosys as a cast of size -N.
                        pm_phase_error_cycles <= div_negative ?
                            -(PHASE_ERROR_BITS'(RESULT_MAX)) : PHASE_ERROR_BITS'(RESULT_MAX);
                    else if (div_negative)
                        pm_phase_error_cycles <= -(PHASE_ERROR_BITS'(quotient_now));
                    else
                        pm_phase_error_cycles <= PHASE_ERROR_BITS'(quotient_now);
                end else begin
                    div_step <= div_step - 1'b1;
                end
            end

            // Fire once every tap has reported for this second. Since
            // second_ce always clears all three *_seen flags together,
            // a channel that never reports (e.g. simulated total PM
            // dropout) simply never lets this condition become true
            // again -- no stale latch from an earlier second can leak
            // through as a false "all seen".
            if ((prompt_correlation_valid || prompt_seen) &&
                (early_correlation_valid || early_seen) &&
                (late_correlation_valid || late_seen)) begin
                logic signed [CORR_BITS-1:0] prompt_v;
                logic signed [CORR_BITS-1:0] early_v;
                logic signed [CORR_BITS-1:0] late_v;
                logic prompt_negative;
                logic signed [CORR_BITS-1:0] prompt_mag;
                logic signed [CORR_BITS-1:0] early_aligned;
                logic signed [CORR_BITS-1:0] late_aligned;
                logic signed [CORR_BITS+1:0] numerator;
                logic signed [CORR_BITS+1:0] denominator;
                logic signed [PROD_BITS-1:0] scaled;

                prompt_v = prompt_correlation_valid ? prompt_correlation : prompt_latched;
                early_v = early_correlation_valid ? early_correlation : early_latched;
                late_v = late_correlation_valid ? late_correlation : late_latched;
                prompt_negative = prompt_v[CORR_BITS-1];
                prompt_mag = prompt_negative ? -prompt_v : prompt_v;
                early_aligned = prompt_negative ? -early_v : early_v;
                late_aligned = prompt_negative ? -late_v : late_v;
                numerator = (CORR_BITS+2)'(late_aligned) - (CORR_BITS+2)'(early_aligned);
                denominator = ((CORR_BITS+2)'(prompt_mag) <<< 1) + 1;
                scaled = scale_by_offset_cycles(numerator);

                prompt_seen <= 1'b0; early_seen <= 1'b0; late_seen <= 1'b0;

                // A measurement below the floor is dropped; one arriving
                // while the previous division still runs (impossible at
                // one measurement per second) is dropped too.
                if ((prompt_mag >= CORR_BITS'(MIN_PROMPT_MAGNITUDE)) && !div_busy) begin
                    div_negative <= scaled[PROD_BITS-1];
                    div_dividend <= scaled[PROD_BITS-1] ? PROD_BITS'(-scaled) : PROD_BITS'(scaled);
                    div_divisor <= PROD_BITS'(denominator);
                    div_quotient <= '0;
                    div_remainder <= '0;
                    div_step <= DIV_STEP_W'(PROD_BITS);
                    div_busy <= 1'b1;
                end
            end
        end
    end

    initial begin
        if (OFFSET_CYCLES < 1 || OFFSET_CYCLES >= CYCLES_PER_CHIP || OFFSET_CYCLES >= 256)
            $error("pm_phase_discriminator: OFFSET_CYCLES must stay within one chip");
    end

endmodule
