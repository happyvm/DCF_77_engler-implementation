`timescale 1ns/1ps

module adc_if_tb;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg sample_ce = 1'b0;
    reg adc_sdo = 1'b0;
    wire adc_conv;
    wire adc_sck;
    wire signed [13:0] ch0_sample;
    wire signed [13:0] ch1_sample;
    wire sample_valid;
    wire busy;
    wire adc_fault;

    reg [31:0] stimulus;
    integer stimulus_bit;
    integer valid_count = 0;

    adc_if #(.CONV_CYCLES(2), .SCK_HALF_CYCLES(1)) dut (
        .clk(clk), .rst(rst), .sample_ce(sample_ce),
        .adc_conv(adc_conv), .adc_sck(adc_sck), .adc_sdo(adc_sdo),
        .ch0_sample(ch0_sample), .ch1_sample(ch1_sample),
        .sample_valid(sample_valid), .busy(busy), .adc_fault(adc_fault)
    );

    always #4 clk = ~clk;

    // Present each bit before the DUT's rising serial-clock edge.
    always @(negedge adc_sck) begin
        if (stimulus_bit < 31) begin
            stimulus_bit = stimulus_bit + 1;
            adc_sdo = stimulus[stimulus_bit];
        end
    end

    always @(posedge clk)
        if (sample_valid)
            valid_count = valid_count + 1;

    initial begin
        stimulus = {14'h3ffb, 2'b00, 14'h0123, 2'b00};
        stimulus_bit = 31;
        adc_sdo = stimulus[31];

        repeat (3) @(posedge clk);
        rst <= 1'b0;
        @(posedge clk);
        sample_ce <= 1'b1;
        @(posedge clk);
        sample_ce <= 1'b0;

        // Deliberately request another sample while shifting to exercise the
        // sticky overrun/fault indicator.
        wait (adc_sck == 1'b1);
        @(posedge clk);
        sample_ce <= 1'b1;
        @(posedge clk);
        sample_ce <= 1'b0;

        wait (sample_valid);
        #1;
        if (ch0_sample !== -14'sd5)
            $fatal(1, "channel 0 mismatch: %0d", ch0_sample);
        if (ch1_sample !== 14'sh0123)
            $fatal(1, "channel 1 mismatch: %0d", ch1_sample);
        if (!adc_fault)
            $fatal(1, "busy conversion request did not set adc_fault");
        if (valid_count != 1)
            $fatal(1, "sample_valid pulse count mismatch: %0d", valid_count);

        @(posedge clk);
        if (sample_valid)
            $fatal(1, "sample_valid was wider than one clock");

        $display("adc_if_tb: PASS");
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "timeout");
    end
endmodule
