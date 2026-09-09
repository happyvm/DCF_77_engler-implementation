// Fractional sample scheduler: the accumulator must follow exact modular
// arithmetic with the trimmed increment, sample_ce must be exactly the
// carry of that addition (registered), and with an increment below half
// the accumulator range two conversions can never be requested on
// consecutive clocks (the ADC frame would collide).
module sample_scheduler_formal;
    localparam int PHASE_BITS = 8;
    localparam [PHASE_BITS-1:0] NOMINAL_INC = 8'd100;
    localparam int TRIM_BITS = 4;

    (* gclk *) logic clk;
    (* anyseq *) logic signed [TRIM_BITS-1:0] trim_inc;
    logic rst = 1'b1;
    logic sample_ce;
    logic [PHASE_BITS-1:0] sample_phase;
    logic past_valid = 1'b0;

    logic [PHASE_BITS-1:0] model_phase = '0;
    logic model_ce = 1'b0;
    logic [PHASE_BITS:0] model_sum;
    logic [PHASE_BITS:0] trim_ext;

    sample_scheduler #(
        .PHASE_BITS(PHASE_BITS), .NOMINAL_INC(NOMINAL_INC), .TRIM_BITS(TRIM_BITS)
    ) dut (.*);

    always_comb begin
        trim_ext = {{(PHASE_BITS + 1 - TRIM_BITS){trim_inc[TRIM_BITS-1]}}, trim_inc};
        model_sum = {1'b0, model_phase} + {1'b0, NOMINAL_INC} + trim_ext;
    end

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;
        if (rst) begin
            model_phase <= '0;
            model_ce <= 1'b0;
        end else begin
            model_phase <= model_sum[PHASE_BITS-1:0];
            model_ce <= model_sum[PHASE_BITS];
        end

        if (past_valid) begin
            assert(sample_phase == model_phase);
            assert(sample_ce == model_ce);
            // 100 - 8 .. 100 + 7 < 128: never two events back to back.
            assert(!(sample_ce && $past(sample_ce)));
        end
    end
endmodule
