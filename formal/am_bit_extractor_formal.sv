// Carrier-synchronous AM window accumulator, checked against an
// independent reference model of the same three sliding windows (reduced,
// data, reference) built from the spec in the module's own header comment
// rather than copied from its RTL: soft evidence = reference + reduced -
// 2*data, latched and saturated exactly on the last cycle of the reference
// window, one cycle after second_ce clears every accumulator. A short
// second (20 cycles, three 3-cycle windows) keeps several seconds inside
// the bounded depth while keeping the windows non-overlapping as the RTL's
// own elaboration-time checks require.
module am_bit_extractor_formal;
    localparam int SC = 20;
    localparam int WC = 3;
    localparam int RS = 0;
    localparam int DS = 5;
    localparam int RFS = 10;
    localparam int IB = 6;
    localparam int OB = 8;
    localparam int OSFT = 1;
    localparam int SUM_BITS = IB + $clog2(WC) + 2;
    localparam int POS_BITS = $clog2(SC);
    localparam logic signed [OB-1:0] OUTPUT_MAX = {1'b0, {(OB-1){1'b1}}};
    localparam logic signed [OB-1:0] OUTPUT_MIN = {1'b1, {(OB-1){1'b0}}};

    (* gclk *) logic clk;
    (* anyseq *) logic second_ce, carrier_ce;
    (* anyseq *) logic signed [IB-1:0] am_observable;
    logic rst = 1'b1;
    logic past_valid = 1'b0;
    logic signed [OB-1:0] am_soft_bit;
    logic bit_valid;
    logic [POS_BITS-1:0] carrier_position;

    am_bit_extractor #(
        .INPUT_BITS(IB), .OUTPUT_BITS(OB), .OUTPUT_SHIFT(OSFT),
        .SECOND_CYCLES(SC), .REDUCED_START_CYCLE(RS), .DATA_START_CYCLE(DS),
        .REFERENCE_START_CYCLE(RFS), .WINDOW_CYCLES(WC)
    ) dut (.*);

    function automatic logic signed [OB-1:0] ref_saturate(
        input logic signed [SUM_BITS-1:0] value
    );
        logic signed [SUM_BITS-1:0] maximum, minimum;
        begin
            maximum = {{(SUM_BITS-OB){1'b0}}, OUTPUT_MAX};
            minimum = {{(SUM_BITS-OB){1'b1}}, OUTPUT_MIN};
            if (value > maximum) ref_saturate = OUTPUT_MAX;
            else if (value < minimum) ref_saturate = OUTPUT_MIN;
            else ref_saturate = value[OB-1:0];
        end
    endfunction

    logic [POS_BITS-1:0] ref_position = '0;
    logic signed [SUM_BITS-1:0] ref_data = '0, ref_reduced = '0, ref_reference = '0;
    logic ref_bit_valid = 1'b0;
    logic signed [OB-1:0] ref_soft_bit = '0;

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;

        if (rst) begin
            ref_position <= '0; ref_data <= '0; ref_reduced <= '0; ref_reference <= '0;
            ref_bit_valid <= 1'b0; ref_soft_bit <= '0;
        end else begin
            ref_bit_valid <= 1'b0;
            if (second_ce) begin
                ref_position <= '0; ref_data <= '0; ref_reduced <= '0; ref_reference <= '0;
            end else if (carrier_ce) begin
                logic signed [SUM_BITS-1:0] ext;
                ext = {{(SUM_BITS-IB){am_observable[IB-1]}}, am_observable};

                if (ref_position == POS_BITS'(SC - 1))
                    ref_position <= '0;
                else
                    ref_position <= ref_position + 1'b1;

                if (ref_position < POS_BITS'(RS + WC))
                    ref_reduced <= ref_reduced + ext;
                if ((ref_position >= POS_BITS'(DS)) && (ref_position < POS_BITS'(DS + WC)))
                    ref_data <= ref_data + ext;
                if ((ref_position >= POS_BITS'(RFS)) && (ref_position < POS_BITS'(RFS + WC))) begin
                    ref_reference <= ref_reference + ext;
                    if (ref_position == POS_BITS'(RFS + WC - 1)) begin
                        ref_soft_bit <= ref_saturate(
                            ((ref_reference + ext) + ref_reduced - (ref_data <<< 1)) >>> OSFT);
                        ref_bit_valid <= 1'b1;
                    end
                end
            end
        end

        if (past_valid && !$past(rst)) begin
            assert(carrier_position == ref_position);
            assert(bit_valid == ref_bit_valid);
            if (bit_valid) assert(am_soft_bit == ref_soft_bit);
        end
    end
endmodule
