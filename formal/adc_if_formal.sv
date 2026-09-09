// LTC1407A serial interface: sample_valid is a single-cycle pulse that
// returns the interface to idle, busy mirrors the state machine, SCK
// idles low and CONV is only ever high while converting, adc_fault is
// sticky, and a conversion request while busy is exactly what raises it.
module adc_if_formal;
    (* gclk *) logic clk;
    (* anyseq *) logic sample_ce, adc_sdo;
    logic rst = 1'b1;
    logic past_valid = 1'b0;

    logic adc_conv, adc_sck, sample_valid, busy, adc_fault;
    logic signed [13:0] ch0_sample, ch1_sample;

    adc_if #(.CONV_CYCLES(2), .SCK_HALF_CYCLES(1)) dut (.*);

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;

        if (past_valid) begin
            assert(!(adc_conv && adc_sck));
            if (!busy) begin
                assert(!adc_conv);
                assert(!adc_sck);
            end
        end
        if (past_valid && !$past(rst)) begin
            assert(!(sample_valid && $past(sample_valid)));
            if (sample_valid) begin
                assert(!busy);
                assert($past(busy));
            end
            if ($past(adc_fault))
                assert(adc_fault);
            if (adc_fault && !$past(adc_fault))
                assert($past(sample_ce && busy));
            if ($past(sample_ce) && !$past(busy))
                assert(busy && adc_conv);
        end
    end
endmodule
