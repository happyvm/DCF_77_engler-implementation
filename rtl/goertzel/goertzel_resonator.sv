// SPDX-License-Identifier: MIT
//
// Fixed-point Goertzel resonator, multi-cycle sequencer (BEA-36).
//
// recurrence: s[n] = x[n] + 2*cos(w)*s[n-1] - s[n-2]
// Every CYCLE_SAMPLES accepted samples, both states are multiplied by k.  This
// is the periodic state scaling used by Engeler to obtain an exponentially
// weighted detector without storing a sliding input window.
//
// COEFF and SCALE_COEFF use COEFF_FRAC fractional bits. State arithmetic
// saturates; it never wraps. cycle_valid is one clk wide and marks the updated,
// scaled states corresponding to one complete carrier cycle.
//
// ---------------------------------------------------------------------------
// Why a sequencer and not a single combinational cycle (BEA-36)
// ---------------------------------------------------------------------------
// The recurrence s[n] depends on s[n-1], so it cannot be pipelined while
// keeping a 1-sample-per-clock initiation rate. The single-cycle form chains
// two 32x19 constant multiplies (feedback *and* the periodic scale) behind a
// 51-bit adder on one path; on LFE5U-45F that path measured 28-36 ns
// (28.3 ns isolated, 36.3 ns at the top) -- a ~27 MHz ceiling.
//
// At Fs = 930 kS/s and clk_sys = 125 MHz there are ~134 clk_sys per sample, so
// the hardware has ample slack to spend several cycles per sample. This module
// therefore spreads one accepted sample over up to GOERTZEL_MAX_CYCLES clk:
//
//   S_IDLE   accept sample_ce, register feedback product   (1 clk)
//   S_REC    recurrence add/subtract + saturation          (1 clk, always)
//   S_SCALE  register both periodic-scale products         (boundary only)
//   S_COMMIT publish the two scaled states, pulse done     (boundary only)
//
// The arithmetic is bit-identical to the former single-cycle datapath: every
// operand width, shift, saturation and overflow term is unchanged, only the
// register boundaries between independent reductions moved. See
// formal/goertzel_resonator_formal.sv (busy/done contract) and
// sim/engeler_goertzel_bank_tb.sv (equivalence vectors).
//
// ---- Contract (must be PROVEN, not assumed) -------------------------------
// A new sample_ce may only be presented while `busy` is low. Presenting one
// during busy is a caller error: under the configured cadence it can never
// happen, because the real scheduler spaces samples ~134 clk_sys apart while
// GOERTZEL_MAX_CYCLES = 4. The formal harness proves `busy` never lasts longer
// than GOERTZEL_MAX_CYCLES-1 and that it drops before another accepted sample;
// sim/goertzel_sample_contract.sv enforces the spacing in simulation and
// sim/sample_cadence_tb.sv checks the *real* 930 kS/s scheduler never collides.

module goertzel_resonator #(
    parameter int SAMPLE_BITS = 14,
    parameter int STATE_BITS = 32,
    parameter int COEFF_BITS = 19,
    parameter int COEFF_FRAC = 17,
    parameter int CYCLE_SAMPLES = 12,
    parameter logic signed [COEFF_BITS-1:0] RESONATOR_COEFF = 19'sd227023,
    parameter logic signed [COEFF_BITS-1:0] SCALE_COEFF = 19'sd131000
) (
    input  logic clk,
    input  logic rst,
    input  logic sample_ce,
    input  logic signed [SAMPLE_BITS-1:0] sample,
    output logic signed [STATE_BITS-1:0] state_1,
    output logic signed [STATE_BITS-1:0] state_2,
    output logic cycle_valid,
    output logic overflow,
    // Sequencer handshake: busy is high from the clk after a sample is
    // accepted until the states have been published; done is a 1-clk pulse
    // in the cycle the result is committed.
    output logic busy,
    output logic done
);

    localparam int PRODUCT_BITS = STATE_BITS + COEFF_BITS;
    localparam int WIDE_BITS = PRODUCT_BITS + 1;
    localparam int CYCLE_COUNT_W =
        (CYCLE_SAMPLES <= 1) ? 1 : $clog2(CYCLE_SAMPLES);

    // Worst-case clk_sys consumed by one accepted sample (initiation
    // interval). A non-boundary sample needs 2, the once-per-cycle
    // boundary sample needs 4. Callers must keep successive sample_ce
    // pulses at least this many clk apart.
    localparam int GOERTZEL_MAX_CYCLES = 4;

    localparam logic signed [STATE_BITS-1:0] STATE_MAX =
        {1'b0, {(STATE_BITS-1){1'b1}}};
    localparam logic signed [STATE_BITS-1:0] STATE_MIN =
        {1'b1, {(STATE_BITS-1){1'b0}}};

    typedef enum logic [1:0] { S_IDLE, S_REC, S_SCALE, S_COMMIT } state_t;
    state_t state;

    logic [CYCLE_COUNT_W-1:0] cycle_count;
    logic signed [SAMPLE_BITS-1:0] sample_lat;
    logic signed [PRODUCT_BITS-1:0] feedback_product;
    logic signed [STATE_BITS-1:0] recurrence_reg;
    logic recurrence_overflow_reg;
    logic signed [PRODUCT_BITS-1:0] scale_product_1;
    logic signed [PRODUCT_BITS-1:0] scale_product_2;
    logic busy_q, done_q;

    // Combinational reductions. Each is consumed by exactly one register
    // stage, so no path carries two multiplies.
    logic signed [PRODUCT_BITS-1:0] feedback_next;
    logic signed [WIDE_BITS-1:0] recurrence_wide;
    logic signed [STATE_BITS-1:0] recurrence_sat;
    logic recurrence_overflow;
    logic signed [PRODUCT_BITS-1:0] scale_next_1;
    logic signed [PRODUCT_BITS-1:0] scale_next_2;
    logic signed [WIDE_BITS-1:0] scaled_wide_1;
    logic signed [WIDE_BITS-1:0] scaled_wide_2;
    logic signed [STATE_BITS-1:0] scaled_sat_1;
    logic signed [STATE_BITS-1:0] scaled_sat_2;
    logic scale_overflow_1;
    logic scale_overflow_2;

    // Sign extension relies on ordinary Verilog signed-context widening
    // (assigning/comparing a narrower signed value against a wider signed
    // one) rather than an explicit {{N{x[msb]}}, x} replication: this
    // project's pinned Icarus Verilog release (oss-cad-suite 2025-02-13,
    // "sorry: constant selects in always_* processes are not currently
    // supported") silently substitutes the whole parent vector for such a
    // replicated bit-select inside always_comb/always_ff when it is mixed
    // with a plain (non-select) operand, corrupting the arithmetic result
    // even though it only warns. Plain signed widening needs no bit-select
    // at all, so it never hits that fallback.
    function automatic logic signed [STATE_BITS-1:0] saturate(
        input logic signed [WIDE_BITS-1:0] value
    );
        logic signed [WIDE_BITS-1:0] maximum;
        logic signed [WIDE_BITS-1:0] minimum;
        begin
            maximum = WIDE_BITS'(STATE_MAX);
            minimum = WIDE_BITS'(STATE_MIN);
            if (value > maximum)
                saturate = STATE_MAX;
            else if (value < minimum)
                saturate = STATE_MIN;
            else
                saturate = value[STATE_BITS-1:0];
        end
    endfunction

    always_comb begin
        feedback_next = state_1 * RESONATOR_COEFF;

        recurrence_wide = WIDE_BITS'(sample_lat)
                        + (WIDE_BITS'(feedback_product) >>> COEFF_FRAC)
                        - WIDE_BITS'(state_2);
        recurrence_sat = saturate(recurrence_wide);
        recurrence_overflow = (recurrence_wide != WIDE_BITS'(recurrence_sat));

        scale_next_1 = recurrence_reg * SCALE_COEFF;
        scale_next_2 = state_1 * SCALE_COEFF;
        scaled_wide_1 = WIDE_BITS'(scale_product_1) >>> COEFF_FRAC;
        scaled_wide_2 = WIDE_BITS'(scale_product_2) >>> COEFF_FRAC;
        scaled_sat_1 = saturate(scaled_wide_1);
        scaled_sat_2 = saturate(scaled_wide_2);
        scale_overflow_1 = (scaled_wide_1 != WIDE_BITS'(scaled_sat_1));
        scale_overflow_2 = (scaled_wide_2 != WIDE_BITS'(scaled_sat_2));
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state                   <= S_IDLE;
            state_1                 <= '0;
            state_2                 <= '0;
            cycle_count             <= '0;
            cycle_valid             <= 1'b0;
            overflow                <= 1'b0;
            busy_q                  <= 1'b0;
            done_q                  <= 1'b0;
            sample_lat              <= '0;
            feedback_product        <= '0;
            recurrence_reg          <= '0;
            recurrence_overflow_reg <= 1'b0;
            scale_product_1         <= '0;
            scale_product_2         <= '0;
        end else begin
            cycle_valid <= 1'b0;
            done_q      <= 1'b0;
            case (state)
                S_IDLE: begin
                    busy_q <= 1'b0;
                    if (sample_ce) begin
                        sample_lat       <= sample;
                        feedback_product <= feedback_next;
                        busy_q           <= 1'b1;
                        state            <= S_REC;
                    end
                end
                S_REC: begin
                    if (cycle_count == CYCLE_COUNT_W'(CYCLE_SAMPLES - 1)) begin
                        // Carrier-cycle boundary: keep the recurrence result
                        // and run the periodic scale over the next cycles.
                        recurrence_reg          <= recurrence_sat;
                        recurrence_overflow_reg <= recurrence_overflow;
                        state                   <= S_SCALE;
                    end else begin
                        state_1     <= recurrence_sat;
                        state_2     <= state_1;
                        cycle_count <= cycle_count + 1'b1;
                        overflow    <= overflow | recurrence_overflow;
                        busy_q      <= 1'b0;
                        done_q      <= 1'b1;
                        state       <= S_IDLE;
                    end
                end
                S_SCALE: begin
                    scale_product_1 <= scale_next_1;
                    scale_product_2 <= scale_next_2;
                    state           <= S_COMMIT;
                end
                S_COMMIT: begin
                    state_1     <= scaled_sat_1;
                    state_2     <= scaled_sat_2;
                    cycle_count <= '0;
                    cycle_valid <= 1'b1;
                    overflow    <= overflow | recurrence_overflow_reg |
                                   scale_overflow_1 | scale_overflow_2;
                    busy_q      <= 1'b0;
                    done_q      <= 1'b1;
                    state       <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

    assign busy = busy_q;
    assign done = done_q;

    initial begin
        if (SAMPLE_BITS < 2 || STATE_BITS < SAMPLE_BITS)
            $error("goertzel_resonator: invalid sample/state width");
        if (COEFF_BITS <= COEFF_FRAC)
            $error("goertzel_resonator: coefficient needs integer/sign bits");
        if (CYCLE_SAMPLES < 1)
            $error("goertzel_resonator: CYCLE_SAMPLES must be positive");
        if (SCALE_COEFF < 0 || SCALE_COEFF > (1 <<< COEFF_FRAC))
            $error("goertzel_resonator: SCALE_COEFF must represent 0..1");
        if (GOERTZEL_MAX_CYCLES < 2)
            $error("goertzel_resonator: initiation interval too small");
    end

endmodule
