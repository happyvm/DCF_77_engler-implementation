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
// The four 33x33 products share one physical multiplier: they are issued one
// per clock through `mul_p` and accumulated in a four-state sequencer. This
// replaces four parallel multipliers with a single one, which is what keeps
// the detector inside the XC3S1400AN's 32-hard-multiplier envelope. The extra
// latency is harmless: observables only have meaning at observable_valid,
// which is produced once per carrier cycle.

module engeler_observables #(
    parameter int SAMPLE_BITS = 14,
    parameter int STATE_BITS = 32,
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

    logic signed [STATE_BITS-1:0] carrier_s1, carrier_s2;
    logic signed [STATE_BITS-1:0] am_s1, am_s2;
    logic signed [STATE_BITS-1:0] pm_s1, pm_s2;
    // Combinational bin rotations (state -> complex).
    logic signed [STATE_BITS:0] am_real, am_imag;
    logic signed [STATE_BITS:0] pm_real, pm_imag;
    logic signed [STATE_BITS:0] carrier_real_c, carrier_imag_c;
    logic cycle_valid;

    engeler_goertzel_bank #(
        .SAMPLE_BITS(SAMPLE_BITS), .STATE_BITS(STATE_BITS),
        .CARRIER_SCALE(CARRIER_SCALE), .AM_SCALE(AM_SCALE), .PM_SCALE(PM_SCALE)
    ) detector_i (
        .clk(clk), .rst(rst), .sample_ce(sample_ce), .sample(sample),
        .carrier_s1(carrier_s1), .carrier_s2(carrier_s2),
        .am_s1(am_s1), .am_s2(am_s2), .pm_s1(pm_s1), .pm_s2(pm_s2),
        .cycle_valid(cycle_valid), .overflow(overflow)
    );

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

    logic signed [STATE_BITS:0] mul_a, mul_b;
    logic signed [PRODUCT_BITS-1:0] mul_p;
    assign mul_p = mul_a * mul_b;

    logic signed [PRODUCT_BITS-1:0] am_rr, am_ii, pm_ir, pm_ri;

    typedef enum logic [2:0] {
        ST_IDLE, ST_P0, ST_P1, ST_P2, ST_P3, ST_SUM
    } state_t;
    state_t state;

    // Product operand select. Only the four product states drive the shared
    // multiplier; every other state feeds zeros so the datapath is defined.
    always_comb begin
        case (state)
            ST_P0: begin mul_a = snap_am_real; mul_b = snap_carrier_real; end
            ST_P1: begin mul_a = snap_am_imag; mul_b = snap_carrier_imag; end
            ST_P2: begin mul_a = snap_pm_imag; mul_b = snap_carrier_real; end
            ST_P3: begin mul_a = snap_pm_real; mul_b = snap_carrier_imag; end
            default: begin mul_a = '0; mul_b = '0; end
        endcase
    end

    // One clock to latch the cycle's bins, four to issue the products, one to
    // form the dot/cross sums: observable_valid trails cycle_valid by six.
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= ST_IDLE;
            snap_am_real <= '0; snap_am_imag <= '0;
            snap_pm_real <= '0; snap_pm_imag <= '0;
            snap_carrier_real <= '0; snap_carrier_imag <= '0;
            carrier_real <= '0; carrier_imag <= '0;
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
                        state <= ST_P0;
                    end
                end
                ST_P0: begin am_rr <= mul_p; state <= ST_P1; end
                ST_P1: begin am_ii <= mul_p; state <= ST_P2; end
                ST_P2: begin pm_ir <= mul_p; state <= ST_P3; end
                ST_P3: begin pm_ri <= mul_p; state <= ST_SUM; end
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
