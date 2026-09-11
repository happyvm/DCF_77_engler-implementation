// SPDX-License-Identifier: MIT
// Slow, vendor-neutral frequency discipline for the fractional sample scheduler.
//
// Units and sign conventions
// --------------------------
// phase_error is a signed Q(PHASE_BITS-PHASE_FRAC_BITS).PHASE_FRAC_BITS
// number of carrier (or one-second) cycles.  For example, with 16 fractional
// bits, 16'sh4000 is +0.25 cycle.  Positive means that the received reference
// is later than the local epoch.  A positive slope therefore requests a
// positive trim (a faster local sample schedule).
//
// estimated_offset and trim_inc are signed sample_scheduler accumulator-
// increment LSBs.  PHASE_TO_TRIM converts one cycle of phase change per
// measurement interval to those LSBs.  At the default sample_scheduler point
// one LSB is about 0.000122 ppm; PHASE_TO_TRIM must be set for the selected
// reference and measurement interval.
//
// The loop is a frequency estimator followed by a PI-like actuator.  All gain
// parameters are integer trim-LSB/cycle coefficients.  Separate acquisition
// and tracking values permit a fast initial pull-in and quiet steady tracking.
// The ECP5 PLL is not controlled by this block and remains fixed.
//
// Multi-cycle architecture (BEA-36)
// ---------------------------------
// The observation cadence is ~1 Hz while clk_sys runs at 125 MHz, i.e. an
// accepted measurement has ~10^8 idle cycles to complete.  Computing the whole
// PI actuator in a single clock put a chain of ~7 serial 64-bit additions
// (estimate_next, integrator_candidate, requested, anti-windup, bounding and
// slew limiting) on one register-to-register path, which dominated the
// receiver critical path (~27.5 ns of a 39.1 ns worst path).
//
// The actuator is therefore executed by an explicit finite state machine that
// performs **one 64-bit reduction per cycle**.  The algorithm, operand widths,
// constants, sign conventions, saturation, anti-windup and slew limits are
// byte-for-byte the same expressions as the original single-cycle version; the
// only change is that each independent 64-bit reduction is registered between
// stages.  `estimated_offset`, `trim_inc`, `integrator`, the lock counter and
// the observation bookkeeping are committed atomically in the terminal state.
//
//   LATENCY: 10 clk cycles from the observation edge (`measurement_ce`) to the
//   committed outputs.  The real cadence is one observation per second, so the
//   added latency is unobservable: `trim_inc` is consumed by `sample_scheduler`
//   as a continuously-applied accumulator increment, not sampled on a pulse.
//
//   THROUGHPUT / NON-OVERWRITE: while `busy` is high the FSM ignores
//   `measurement_ce` entirely, so a new observation can never overwrite an
//   in-flight computation.  A measurement presented during `busy` is dropped
//   (the ~1 Hz cadence makes this unreachable in the integration).  This is
//   asserted in `formal/frequency_discipline_formal.sv` and exercised by
//   `sim/frequency_discipline_tb.sv`.
//
// The rejection / holdover path performs no 64-bit arithmetic and stays a
// single-cycle action in the IDLE state, exactly as before.

`timescale 1ns/1ps

module frequency_discipline #(
    parameter int PHASE_BITS = 24,
    parameter int PHASE_FRAC_BITS = 16,
    parameter int QUALITY_BITS = 8,
    parameter int TRIM_BITS = 24,
    parameter int AGE_BITS = 16,
    parameter int PHASE_TO_TRIM = 8192,
    parameter int ACQ_EST_SHIFT = 1,
    parameter int TRACK_EST_SHIFT = 4,
    parameter int ACQ_KP = 1024,
    parameter int ACQ_KI = 128,
    parameter int TRACK_KP = 128,
    parameter int TRACK_KI = 8,
    parameter int MAX_TRIM = 32768,
    parameter int MAX_TRIM_STEP = 2048,
    parameter int OUTLIER_LIMIT = (1 << (PHASE_FRAC_BITS-1)),
    parameter int DELTA_LIMIT = (1 << (PHASE_FRAC_BITS-2)),
    parameter int ACQ_QUALITY_MIN = 32,
    parameter int TRACK_QUALITY_MIN = 64,
    parameter int LOCK_COUNT = 8,
    parameter int HOLDOVER_AGE = 4
) (
    input  logic clk,
    input  logic rst,
    // One pulse per nominal observation interval (normally one second).
    input  logic measurement_ce,
    input  logic measurement_valid,
    input  logic signed [PHASE_BITS-1:0] phase_error,
    input  logic [QUALITY_BITS-1:0] measurement_quality,
    output logic signed [TRIM_BITS-1:0] estimated_offset,
    output logic signed [TRIM_BITS-1:0] trim_inc,
    output logic frequency_locked,
    output logic measurement_rejected,
    // Saturating count of observation intervals since the last accepted point.
    output logic [AGE_BITS-1:0] measurement_age,
    // High while an accepted observation is being processed (see latency note).
    output logic busy
);
    localparam int COUNT_BITS = (LOCK_COUNT < 2) ? 1 : $clog2(LOCK_COUNT + 1);
    localparam logic signed [63:0] MAX_TRIM_64 = MAX_TRIM;
    localparam logic signed [63:0] MIN_TRIM_64 = -MAX_TRIM;
    localparam logic signed [63:0] MAX_TRIM_STEP_64 = MAX_TRIM_STEP;

    // One 64-bit reduction per state.  See the header for the latency budget.
    localparam logic [3:0] S_IDLE     = 4'd0;   // observation capture / rejection
    localparam logic [3:0] S_RAW      = 4'd1;   // raw_frequency + proportional/i_delta
    localparam logic [3:0] S_EST_SUB  = 4'd2;   // (raw_frequency - estimate)
    localparam logic [3:0] S_EST_ADD  = 4'd3;   // estimate_next
    localparam logic [3:0] S_ICAND    = 4'd4;   // integrator_candidate
    localparam logic [3:0] S_SUM      = 4'd5;   // estimate_next + (i_cand | int)
    localparam logic [3:0] S_REQ      = 4'd6;   // requested (+ anti-windup alternate)
    localparam logic [3:0] S_AW       = 4'd7;   // anti-windup select
    localparam logic [3:0] S_BOUND    = 4'd8;   // saturation bound
    localparam logic [3:0] S_SLEW     = 4'd9;   // slew limit
    localparam logic [3:0] S_COMMIT   = 4'd10;  // atomic commit

    logic signed [PHASE_BITS-1:0] previous_phase;
    logic have_previous;
    logic [COUNT_BITS-1:0] accepted_count;
    logic signed [63:0] integrator;

    // FSM state and latched observation operands / prior state.
    logic [3:0] state;
    logic signed [63:0] p_phase, p_delta, p_est, p_trim, p_int;
    logic signed [63:0] w_rawf, w_estt, w_estnext, w_prop, w_idelta;
    logic signed [63:0] w_icand, w_icand_sel, w_sum, w_altsum, w_req, w_alt;
    logic signed [63:0] w_sel, w_bounded;
    logic signed [TRIM_BITS-1:0] w_newtrim;
    logic p_have, p_locked;
    logic [COUNT_BITS-1:0] p_acnt;

    assign busy = (state != S_IDLE);

    function automatic logic signed [TRIM_BITS-1:0] trim_clip(input logic signed [63:0] value);
        if (value > MAX_TRIM_64)
            trim_clip = MAX_TRIM;
        else if (value < MIN_TRIM_64)
            trim_clip = -MAX_TRIM;
        else
            trim_clip = value[TRIM_BITS-1:0];
    endfunction

    function automatic logic signed [63:0] abs64(input logic signed [63:0] value);
        abs64 = value < 0 ? -value : value;
    endfunction

    always_ff @(posedge clk) begin : discipline_process
        logic signed [63:0] phase64, delta64;
        logic quality_ok, phase_ok, delta_ok, accepted;
        logic signed [63:0] step;

        if (rst) begin
            estimated_offset <= '0;
            trim_inc <= '0;
            frequency_locked <= 1'b0;
            measurement_rejected <= 1'b0;
            measurement_age <= {AGE_BITS{1'b1}};
            previous_phase <= '0;
            have_previous <= 1'b0;
            accepted_count <= '0;
            integrator <= '0;
            state <= S_IDLE;
            p_phase <= '0; p_delta <= '0; p_est <= '0; p_trim <= '0; p_int <= '0;
            p_have <= 1'b0; p_locked <= 1'b0; p_acnt <= '0;
            w_rawf <= '0; w_estt <= '0; w_estnext <= '0;
            w_prop <= '0; w_idelta <= '0; w_icand <= '0; w_icand_sel <= '0;
            w_sum <= '0; w_altsum <= '0; w_req <= '0; w_alt <= '0;
            w_sel <= '0; w_bounded <= '0; w_newtrim <= '0;
        end else begin
            measurement_rejected <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (measurement_ce) begin
                        if (measurement_age != {AGE_BITS{1'b1}})
                            measurement_age <= measurement_age + 1'b1;

                        phase64 = $signed(phase_error);
                        delta64 = phase64 - $signed(previous_phase);
                        quality_ok = measurement_quality >=
                                     (frequency_locked ? TRACK_QUALITY_MIN : ACQ_QUALITY_MIN);
                        phase_ok = abs64(phase64) <= OUTLIER_LIMIT;
                        delta_ok = !have_previous || (abs64(delta64) <= DELTA_LIMIT);
                        accepted = measurement_valid && quality_ok && phase_ok && delta_ok;

                        if (!accepted) begin
                            // Missing data enters holdover silently; present but
                            // unsafe data is explicitly reported as rejected.
                            measurement_rejected <= measurement_valid;
                            if (measurement_age >= HOLDOVER_AGE-1) begin
                                frequency_locked <= 1'b0;
                                accepted_count <= '0;
                            end
                            // trim_inc and the integrator intentionally hold here.
                        end else begin
                            // Latch the observation and the prior loop state so
                            // that later measurement_ce pulses cannot disturb the
                            // computation in flight.
                            p_phase <= phase64;
                            p_delta <= delta64;
                            p_est <= $signed(estimated_offset);
                            p_trim <= $signed(trim_inc);
                            p_int <= integrator;
                            p_have <= have_previous;
                            p_locked <= frequency_locked;
                            p_acnt <= accepted_count;
                            state <= S_RAW;
                        end
                    end
                end

                S_RAW: begin
                    // raw_frequency only exists once a previous phase is known.
                    if (p_have)
                        w_rawf <= (p_delta * PHASE_TO_TRIM) >>> PHASE_FRAC_BITS;
                    else
                        w_rawf <= '0;
                    // Gains are compile-time constants on each branch, so these
                    // reduce to shifts/adders rather than a general multiplier.
                    if (p_locked) begin
                        w_prop <= (p_phase * TRACK_KP) >>> PHASE_FRAC_BITS;
                        w_idelta <= (p_phase * TRACK_KI) >>> PHASE_FRAC_BITS;
                    end else begin
                        w_prop <= (p_phase * ACQ_KP) >>> PHASE_FRAC_BITS;
                        w_idelta <= (p_phase * ACQ_KI) >>> PHASE_FRAC_BITS;
                    end
                    state <= S_EST_SUB;
                end

                S_EST_SUB: begin
                    w_estt <= w_rawf - p_est;
                    state <= S_EST_ADD;
                end

                S_EST_ADD: begin
                    if (p_have) begin
                        if (p_locked)
                            w_estnext <= p_est + (w_estt >>> TRACK_EST_SHIFT);
                        else
                            w_estnext <= p_est + (w_estt >>> ACQ_EST_SHIFT);
                    end else begin
                        w_estnext <= p_est;
                    end
                    state <= S_ICAND;
                end

                S_ICAND: begin
                    w_icand <= p_int + w_idelta;
                    state <= S_SUM;
                end

                S_SUM: begin
                    // requested = estimate_next + integrator_candidate + proportional
                    // is summed in an (associative, bit-exact) tree; the alternate
                    // estimate_next + integrator + proportional term needed by the
                    // anti-windup branch is produced in parallel.
                    w_sum <= w_estnext + w_icand;
                    w_altsum <= w_estnext + p_int;
                    state <= S_REQ;
                end

                S_REQ: begin
                    w_req <= w_sum + w_prop;
                    w_alt <= w_altsum + w_prop;
                    state <= S_AW;
                end

                S_AW: begin
                    // Conditional integration is anti-windup: when saturated,
                    // retain only an update which drives back toward the range.
                    if (((w_req > MAX_TRIM_64) && (w_idelta > 0)) ||
                        ((w_req < MIN_TRIM_64) && (w_idelta < 0))) begin
                        w_sel <= w_alt;
                        w_icand_sel <= p_int;
                    end else begin
                        w_sel <= w_req;
                        w_icand_sel <= w_icand;
                    end
                    state <= S_BOUND;
                end

                S_BOUND: begin
                    if (w_sel > MAX_TRIM_64)
                        w_bounded <= MAX_TRIM_64;
                    else if (w_sel < MIN_TRIM_64)
                        w_bounded <= MIN_TRIM_64;
                    else
                        w_bounded <= w_sel;
                    state <= S_SLEW;
                end

                S_SLEW: begin
                    // Slew limiting also makes holdover recovery bumpless.
                    step = w_bounded - p_trim;
                    if (step > MAX_TRIM_STEP_64)
                        w_newtrim <= trim_clip(p_trim + MAX_TRIM_STEP);
                    else if (step < -MAX_TRIM_STEP_64)
                        w_newtrim <= trim_clip(p_trim - MAX_TRIM_STEP);
                    else
                        w_newtrim <= trim_clip(w_bounded);
                    state <= S_COMMIT;
                end

                S_COMMIT: begin
                    estimated_offset <= trim_clip(w_estnext);
                    trim_inc <= w_newtrim;
                    integrator <= w_icand_sel;
                    previous_phase <= p_phase[PHASE_BITS-1:0];
                    have_previous <= 1'b1;
                    measurement_age <= '0;

                    if (!p_locked) begin
                        if ((LOCK_COUNT <= 1) || (p_acnt >= LOCK_COUNT-2)) begin
                            frequency_locked <= 1'b1;
                            accepted_count <= p_acnt;
                        end else begin
                            accepted_count <= p_acnt + 1'b1;
                        end
                    end
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    initial begin
        if (PHASE_BITS < 2 || PHASE_FRAC_BITS < 2 || PHASE_FRAC_BITS >= PHASE_BITS)
            $error("frequency_discipline: invalid phase format");
        if (TRIM_BITS < 3 || MAX_TRIM < 1 || MAX_TRIM_STEP < 1 || MAX_TRIM_STEP > MAX_TRIM)
            $error("frequency_discipline: invalid trim limits");
        if (LOCK_COUNT < 1 || HOLDOVER_AGE < 1 || ACQ_EST_SHIFT < 0 || TRACK_EST_SHIFT < 0)
            $error("frequency_discipline: invalid loop parameters");
    end
endmodule
