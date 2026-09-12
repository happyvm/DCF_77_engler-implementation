// SPDX-License-Identifier: MIT
// Engeler Goertzel bank with carrier-relative AM and PM observables.
//
// The dot and cross products rotate the AM/PM bins into the carrier frame
// without first calculating an angle:
//   AM raw = AM . carrier
//   PM raw = PM x carrier
// Both are intentionally unnormalised soft metrics. Normalisation and output
// saturation belong after SNR/range measurements with reference vectors.
//
// Throughput / resource trade-off (BEA-36): the four 33x33 products are far too
// deep to close at 125 MHz in one cycle -- yosys' mul2dsp has to split a 33x33
// signed multiply into several 18x18 MULT18X18D partial products and sum them
// with a ~30-deep carry chain, and putting that behind the state-driven operand
// mux measured 19.1 ns (52 MHz) on the routed ECP5 top.
//
// Instead each 33x33 product is decomposed *exactly* into four 18x18 signed
// sub-products (a signed limb split at bit LIMB_LO):
//
//   a = a_lo + (a_hi << LIMB_LO)         a_lo unsigned, a_hi signed
//   b = b_lo + (b_hi << LIMB_LO)
//   a*b = a_lo*b_lo                              (shift 0)
//       + (a_lo*b_hi + a_hi*b_lo) << LIMB_LO     (both stored, summed later)
//       + (a_hi*b_hi)             << 2*LIMB_LO
//
// Every sub-product fits one MULT18X18D with no carry chain, and the limb
// split is an exact re-association of the two's-complement product, so the
// result is bit-identical to `a * b` truncated to PRODUCT_BITS. The low limb is
// at most 17 bits so it is representable as a positive 18-bit signed value in
// the (signed-only) ECP5 DSP.
//
// The products are time-shared through two physical multipliers, one arithmetic
// reduction per clock: a four-state micro-sequence per product (S_LOAD limbs,
// S_MA a_lo*b_lo + a_hi*b_hi, S_MB a_lo*b_hi + a_hi*b_lo, S_ACC combine into
// the destination register) walked over the four products. This keeps exactly
// one multiplier pair -- the same single-multiplier spirit that keeps the
// detector inside the XC3S1400AN's 32-hard-multiplier envelope -- while no
// cycle carries more than one 18x18 multiply plus a short reduction.
//
// Latency: observable_valid trails the bank's cycle_valid by 18 clk
// (1 snapshot + 4 products x 4 states + 1 dot/cross sum). The observables are
// only meaningful at observable_valid, produced once per carrier cycle, so the
// extra latency is immaterial: in hardware a carrier cycle is ~134*12 clk and
// the accelerated system test spaces samples 4 clk apart (48 clk/cycle).
// cycle_valid presented while the sequencer is not in S_IDLE cannot be latched
// and is ignored -- the cadence contract is checked in sim/sample_cadence_tb.sv
// and sim/goertzel_sample_contract.sv.

module engeler_observables #(
    parameter int SAMPLE_BITS = 14,
    parameter int STATE_BITS = 32,
    // Carrier-cycle length; exposed so a formal harness can shrink the period.
    // Production keeps the resonator default of 12.
    parameter int CYCLE_SAMPLES = 12,
    // Bank scaling constants, exposed so a time-compressed simulation can
    // widen the bins in proportion to a shortened second; hardware keeps
    // the bank's own defaults.
    parameter logic signed [18:0] CARRIER_SCALE = 19'sd131059,
    parameter logic signed [18:0] AM_SCALE      = 19'sd130993,
    parameter logic signed [18:0] PM_SCALE      = 19'sd126157
) (
    input  logic clk,
    input  logic rst,
    input  logic sample_ce,
    input  logic signed [SAMPLE_BITS-1:0] sample,
    output logic signed [STATE_BITS:0] carrier_real,
    output logic signed [STATE_BITS:0] carrier_imag,
    output logic signed [(2*STATE_BITS)+2:0] am_inphase_raw,
    output logic signed [(2*STATE_BITS)+2:0] pm_quadrature_raw,
    output logic observable_valid,
    output logic overflow
);

    localparam int COMPLEX_BITS = STATE_BITS + 1;
    localparam int PRODUCT_BITS = 2 * COMPLEX_BITS;

    // Signed-limb decomposition geometry. LIMB_LO splits each operand into an
    // unsigned low limb (<= 17 bits, positive in an 18-bit signed DSP operand)
    // and a signed high limb (<= 18 bits). LIMB_BITS is the DSP operand width.
    localparam int LIMB_BITS = 18;
    localparam int LIMB_LO = (COMPLEX_BITS + 1) / 2;
    localparam int LIMB_HI = COMPLEX_BITS - LIMB_LO;
    localparam int SUB_BITS = 2 * LIMB_BITS;
    // The re-association is evaluated modulo the product width, exactly like
    // the single-cycle `a * b` truncated to PRODUCT_BITS: truncating each
    // sub-product before its constant shift preserves the low bits that the
    // shift can still reach, so the sum is bit-identical.
    localparam int FULL_BITS = PRODUCT_BITS;

    initial begin
        if (LIMB_LO < 1 || LIMB_HI < 1)
            $error("engeler_observables: operand too narrow for a limb split");
        if (LIMB_LO > LIMB_BITS - 1 || LIMB_HI > LIMB_BITS)
            $error("engeler_observables: limbs do not fit the DSP operand width");
    end

    logic signed [STATE_BITS-1:0] carrier_s1, carrier_s2;
    logic signed [STATE_BITS-1:0] am_s1, am_s2;
    logic signed [STATE_BITS-1:0] pm_s1, pm_s2;
    // Combinational bin rotations (state -> complex).
    logic signed [STATE_BITS:0] am_real, am_imag;
    logic signed [STATE_BITS:0] pm_real, pm_imag;
    logic signed [STATE_BITS:0] carrier_real_c, carrier_imag_c;
    logic cycle_valid;
    // Bank sequencer handshake. The observables block does not consume it --
    // the cadence contract is checked in sim/sample_cadence_tb.sv -- but it is
    // explicitly wired (not left dangling) so the connection is visible.
    logic bank_busy, bank_done;

    engeler_goertzel_bank #(
        .SAMPLE_BITS(SAMPLE_BITS), .STATE_BITS(STATE_BITS),
        .CYCLE_SAMPLES(CYCLE_SAMPLES),
        .CARRIER_SCALE(CARRIER_SCALE), .AM_SCALE(AM_SCALE), .PM_SCALE(PM_SCALE)
    ) detector_i (
        .clk(clk), .rst(rst), .sample_ce(sample_ce), .sample(sample),
        .carrier_s1(carrier_s1), .carrier_s2(carrier_s2),
        .am_s1(am_s1), .am_s2(am_s2), .pm_s1(pm_s1), .pm_s2(pm_s2),
        .cycle_valid(cycle_valid), .overflow(overflow),
        .busy(bank_busy), .done(bank_done)
    );

    // Observables has no use for the handshake; fold it away so the wires are
    // not flagged as unused (the value is deliberately not observable here).
    wire unused_bank_handshake = bank_busy ^ bank_done;

    goertzel_complex_12 #(.STATE_BITS(STATE_BITS)) carrier_complex_i (
        .state_1(carrier_s1), .state_2(carrier_s2),
        .bin_real(carrier_real_c), .bin_imag(carrier_imag_c)
    );

    goertzel_complex_12 #(.STATE_BITS(STATE_BITS)) am_complex_i (
        .state_1(am_s1), .state_2(am_s2),
        .bin_real(am_real), .bin_imag(am_imag)
    );

    goertzel_complex_12 #(.STATE_BITS(STATE_BITS)) pm_complex_i (
        .state_1(pm_s1), .state_2(pm_s2),
        .bin_real(pm_real), .bin_imag(pm_imag)
    );

    // The operand snapshot freezes one carrier cycle's bins so the serialised
    // products all use the same inputs. carrier_real/carrier_imag expose the
    // same snapshot as diagnostics.
    logic signed [STATE_BITS:0] snap_am_real, snap_am_imag;
    logic signed [STATE_BITS:0] snap_pm_real, snap_pm_imag;
    logic signed [STATE_BITS:0] snap_carrier_real, snap_carrier_imag;

    // Operand pair for the product currently being formed, selected from the
    // frozen snapshot by the 2-bit product index.
    logic signed [COMPLEX_BITS-1:0] mul_a, mul_b;

    logic [1:0] prod;   // 0 -> AM dot real, 1 -> AM dot imag,
                        // 2 -> PM cross (ir), 3 -> PM cross (ri)

    always_comb begin
        case (prod)
            2'd0: begin mul_a = snap_am_real;  mul_b = snap_carrier_real; end
            2'd1: begin mul_a = snap_am_imag;  mul_b = snap_carrier_imag; end
            2'd2: begin mul_a = snap_pm_imag;  mul_b = snap_carrier_real; end
            default: begin mul_a = snap_pm_real; mul_b = snap_carrier_imag; end
        endcase
    end

    // Registered, DSP-aligned signed limbs of the current product's operands.
    logic signed [LIMB_BITS-1:0] a_lo_q, a_hi_q, b_lo_q, b_hi_q;

    // Sub-products, each one 18x18 (at most) MULT18X18D with no carry chain.
    logic signed [SUB_BITS-1:0] p00_q, p01_q, p10_q, p11_q;

    // Exact re-association of the full product, evaluated modulo PRODUCT_BITS
    // (the same truncation the single-cycle `a * b` performed before its result
    // was registered).
    logic signed [FULL_BITS-1:0] product_wide;
    always_comb begin
        product_wide =
              FULL_BITS'($signed(p00_q))
            + (FULL_BITS'($signed(p01_q)) <<< LIMB_LO)
            + (FULL_BITS'($signed(p10_q)) <<< LIMB_LO)
            + (FULL_BITS'($signed(p11_q)) <<< (2*LIMB_LO));
    end

    logic signed [PRODUCT_BITS-1:0] am_rr, am_ii, pm_ir, pm_ri;

    typedef enum logic [2:0] {
        ST_IDLE, ST_LOAD, ST_MA, ST_MB, ST_ACC, ST_SUM
    } state_t;
    state_t state;

    // One product per four states: S_LOAD registers the limbs, S_MA and S_MB
    // issue the two 18x18 multiplier pairs, S_ACC combines them into the
    // destination register. Ample budget: a carrier cycle is 48 clk even in
    // the accelerated test, versus 4*4 = 16 clk of product work.
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= ST_IDLE;
            prod <= 2'd0;
            snap_am_real <= '0; snap_am_imag <= '0;
            snap_pm_real <= '0; snap_pm_imag <= '0;
            snap_carrier_real <= '0; snap_carrier_imag <= '0;
            carrier_real <= '0; carrier_imag <= '0;
            a_lo_q <= '0; a_hi_q <= '0; b_lo_q <= '0; b_hi_q <= '0;
            p00_q <= '0; p01_q <= '0; p10_q <= '0; p11_q <= '0;
            am_rr <= '0; am_ii <= '0; pm_ir <= '0; pm_ri <= '0;
            am_inphase_raw <= '0; pm_quadrature_raw <= '0;
            observable_valid <= 1'b0;
        end else begin
            observable_valid <= 1'b0;
            case (state)
                ST_IDLE: begin
                    if (cycle_valid) begin
                        snap_am_real <= am_real; snap_am_imag <= am_imag;
                        snap_pm_real <= pm_real; snap_pm_imag <= pm_imag;
                        snap_carrier_real <= carrier_real_c;
                        snap_carrier_imag <= carrier_imag_c;
                        carrier_real <= carrier_real_c;
                        carrier_imag <= carrier_imag_c;
                        prod <= 2'd0;
                        state <= ST_LOAD;
                    end
                end
                ST_LOAD: begin
                    a_lo_q <= {1'b0, mul_a[LIMB_LO-1:0]};
                    a_hi_q <= {{(LIMB_BITS-LIMB_HI){mul_a[COMPLEX_BITS-1]}},
                               mul_a[COMPLEX_BITS-1:LIMB_LO]};
                    b_lo_q <= {1'b0, mul_b[LIMB_LO-1:0]};
                    b_hi_q <= {{(LIMB_BITS-LIMB_HI){mul_b[COMPLEX_BITS-1]}},
                               mul_b[COMPLEX_BITS-1:LIMB_LO]};
                    state <= ST_MA;
                end
                ST_MA: begin
                    p00_q <= a_lo_q * b_lo_q;
                    p11_q <= a_hi_q * b_hi_q;
                    state <= ST_MB;
                end
                ST_MB: begin
                    p01_q <= a_lo_q * b_hi_q;
                    p10_q <= a_hi_q * b_lo_q;
                    state <= ST_ACC;
                end
                ST_ACC: begin
                    case (prod)
                        2'd0: am_rr <= product_wide[PRODUCT_BITS-1:0];
                        2'd1: am_ii <= product_wide[PRODUCT_BITS-1:0];
                        2'd2: pm_ir <= product_wide[PRODUCT_BITS-1:0];
                        default: pm_ri <= product_wide[PRODUCT_BITS-1:0];
                    endcase
                    if (prod == 2'd3) begin
                        state <= ST_SUM;
                    end else begin
                        prod <= prod + 2'd1;
                        state <= ST_LOAD;
                    end
                end
                ST_SUM: begin
                    am_inphase_raw <=
                        {am_rr[PRODUCT_BITS-1], am_rr}
                      + {am_ii[PRODUCT_BITS-1], am_ii};
                    pm_quadrature_raw <=
                        {pm_ir[PRODUCT_BITS-1], pm_ir}
                      - {pm_ri[PRODUCT_BITS-1], pm_ri};
                    observable_valid <= 1'b1;
                    state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
