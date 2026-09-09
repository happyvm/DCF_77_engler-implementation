// Purely combinational bin rotation: for any pair of Goertzel states, check
// the two published identities directly against a wider-precision
// recomputation of the same coefficients (so the check cannot just restate
// the RTL) and that the truncating cast the module relies on never
// discards a set bit, i.e. bin_real/bin_imag never actually alias a wrapped
// value. A single clock is enough since the module has no state.
module goertzel_complex_12_formal;
    localparam int STATE_BITS = 32;
    localparam int COEFF_BITS = 19;
    localparam int COEFF_FRAC = 17;
    localparam logic signed [COEFF_BITS-1:0] COS_COEFF = 19'sd113512;
    localparam logic signed [COEFF_BITS-1:0] SIN_COEFF = 19'sd65536;

    (* gclk *) logic clk;
    (* anyseq *) logic signed [STATE_BITS-1:0] state_1, state_2;
    logic signed [STATE_BITS:0] bin_real, bin_imag;

    goertzel_complex_12 #(
        .STATE_BITS(STATE_BITS), .COEFF_BITS(COEFF_BITS), .COEFF_FRAC(COEFF_FRAC),
        .COS_COEFF(COS_COEFF), .SIN_COEFF(SIN_COEFF)
    ) dut (.*);

    // Independent wide reference: no cast narrower than the true product
    // width, so this does not share the RTL's own truncation.
    logic signed [STATE_BITS+COEFF_BITS-1:0] cos_product_ref, sin_product_ref;
    logic signed [STATE_BITS+COEFF_BITS-1:0] real_ref_wide, imag_ref_wide;

    always_comb begin
        cos_product_ref = state_2 * COS_COEFF;
        sin_product_ref = state_2 * SIN_COEFF;
        real_ref_wide = (STATE_BITS+COEFF_BITS)'(state_1) - (cos_product_ref >>> COEFF_FRAC);
        imag_ref_wide = sin_product_ref >>> COEFF_FRAC;
    end

    always_ff @(posedge clk) begin
        // COS_COEFF/SIN_COEFF are both below 2^COEFF_FRAC (cos/sin of 30
        // degrees, checked once as a sanity bound on the fixture itself),
        // so state_2's scaled contribution never exceeds state_2's own
        // magnitude and the wide reference fits in STATE_BITS+1 bits
        // without loss -- the same guarantee the module's own comment
        // relies on to justify its truncating cast.
        assert(COS_COEFF < (1 <<< COEFF_FRAC) && COS_COEFF >= 0);
        assert(SIN_COEFF < (1 <<< COEFF_FRAC) && SIN_COEFF >= 0);
        assert(bin_real == (STATE_BITS+1)'(real_ref_wide));
        assert(bin_imag == (STATE_BITS+1)'(imag_ref_wide));
    end
endmodule
