`timescale 1ns/1ps
//
// Behavioral model of the LTC1407-1/LTC1407A-1 serial protocol (see the
// header of rtl/platform/adc_if.sv for the data sheet timing this
// mirrors) driving adc_if, checking that the DUT recovers the correct
// 28 data bits -- including the chip's one-conversion pipeline delay --
// under: 0, -1, the extreme codes, two distinct channel values in one
// frame, several back-to-back conversions, a reset mid-transaction, and
// a conversion request while busy.
module adc_if_tb;
    localparam integer LEAD_BITS = 2;
    localparam integer DATA_BITS = 14;
    localparam integer GAP_BITS  = 2;

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

    integer valid_count = 0;
    integer i;

    adc_if #(.CONV_CYCLES(2), .SCK_HALF_CYCLES(1)) dut (
        .clk(clk), .rst(rst), .sample_ce(sample_ce),
        .adc_conv(adc_conv), .adc_sck(adc_sck), .adc_sdo(adc_sdo),
        .ch0_sample(ch0_sample), .ch1_sample(ch1_sample),
        .sample_valid(sample_valid), .busy(busy), .adc_fault(adc_fault)
    );

    always #5 clk = ~clk;

    always @(posedge clk)
        if (sample_valid)
            valid_count = valid_count + 1;

    // --- ADC behavioral model -------------------------------------------
    //
    // input_ch0/ch1 are the analog values "present" for the upcoming
    // conversion; the data sheet's pipeline means the frame clocked out
    // after a given CONV edge reports the values latched at the
    // *previous* edge, not this one. shift_out_ch0/ch1 hold that
    // previous, now-being-shifted-out pair.
    reg signed [13:0] input_ch0 = 14'sd0;
    reg signed [13:0] input_ch1 = 14'sd0;
    reg signed [13:0] captured_ch0 = 14'sd0;
    reg signed [13:0] captured_ch1 = 14'sd0;
    reg signed [13:0] shift_out_ch0;
    reg signed [13:0] shift_out_ch1;
    integer sck_edge = 0;

    always @(posedge adc_conv) begin
        shift_out_ch0 <= captured_ch0;
        shift_out_ch1 <= captured_ch1;
        captured_ch0  <= input_ch0;
        captured_ch1  <= input_ch1;
        sck_edge = 0;
    end

    // SCK is host-generated; the model only reacts to it. Per the data
    // sheet, SDO changes shortly after each rising edge: the first two
    // and the two separator edges are undefined/hi-Z, driven here as X
    // so that a framing bug pulling from the wrong bit position is
    // caught by a !== mismatch instead of silently reusing a real bit.
    always @(posedge adc_sck) begin
        sck_edge = sck_edge + 1;
        if (sck_edge >= 1 && sck_edge <= LEAD_BITS)
            adc_sdo <= 1'bx;
        else if (sck_edge >= LEAD_BITS + 1 && sck_edge <= LEAD_BITS + DATA_BITS)
            adc_sdo <= shift_out_ch0[LEAD_BITS + DATA_BITS - sck_edge];
        else if (sck_edge >= LEAD_BITS + DATA_BITS + 1 &&
                 sck_edge <= LEAD_BITS + DATA_BITS + GAP_BITS)
            adc_sdo <= 1'bx;
        else
            adc_sdo <= shift_out_ch1[LEAD_BITS + DATA_BITS + GAP_BITS + DATA_BITS - sck_edge];
    end

    // --- Test driver -------------------------------------------------
    reg signed [13:0] got_ch0, got_ch1;

    task automatic request_conversion;
        begin
            @(posedge clk);
            sample_ce <= 1'b1;
            @(posedge clk);
            sample_ce <= 1'b0;
        end
    endtask

    // Sets the analog inputs for the *next* conversion, requests one
    // conversion now, and reports what this frame actually produced
    // (the previous conversion's inputs, per the pipeline).
    task automatic do_conversion(
        input logic signed [13:0] next_ch0,
        input logic signed [13:0] next_ch1
    );
        begin
            input_ch0 = next_ch0;
            input_ch1 = next_ch1;
            request_conversion();
            wait (sample_valid);
            got_ch0 = ch0_sample;
            got_ch1 = ch1_sample;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        rst <= 1'b0;

        // Warm-up conversion: its own output reflects the undefined
        // pre-power-up state, which this model defines as (0, 0). Its
        // argument (0, -1) is what the *next* frame will report.
        do_conversion(14'sd0, -14'sd1);
        if (got_ch0 !== 14'sd0 || got_ch1 !== 14'sd0)
            $fatal(1, "warm-up frame mismatch: %0d %0d", got_ch0, got_ch1);

        // This frame reports the warm-up inputs: exercises 0 and -1.
        do_conversion(-14'sd8192, 14'sd8191);
        if (got_ch0 !== 14'sd0 || got_ch1 !== -14'sd1)
            $fatal(1, "0/-1 frame mismatch: %0d %0d", got_ch0, got_ch1);
        // sample_valid must already be a single-cycle pulse before the
        // next request; verified again explicitly at the end.

        // Reports the previous frame's inputs: minimum and maximum
        // codes, one per channel, in the same frame.
        do_conversion(14'sd4321, -14'sd4321);
        if (got_ch0 !== -14'sd8192 || got_ch1 !== 14'sd8191)
            $fatal(1, "min/max frame mismatch: %0d %0d", got_ch0, got_ch1);

        // Reports the previous frame's distinct, non-extreme values.
        do_conversion(14'sd0, 14'sd0);
        if (got_ch0 !== 14'sd4321 || got_ch1 !== -14'sd4321)
            $fatal(1, "distinct-channel frame mismatch: %0d %0d", got_ch0, got_ch1);

        // Flush: confirms the previous (0, 0) request lands cleanly
        // after several back-to-back conversions.
        do_conversion(14'sd0, 14'sd0);
        if (got_ch0 !== 14'sd0 || got_ch1 !== 14'sd0)
            $fatal(1, "back-to-back flush mismatch: %0d %0d", got_ch0, got_ch1);

        // sample_valid must be exactly one clk cycle wide. Let the
        // DUT's own nonblocking clear settle before sampling, or this
        // would race the same edge that clears it.
        @(posedge clk);
        #1;
        if (sample_valid)
            $fatal(1, "sample_valid was wider than one clock");

        // Conversion request while busy: sets the sticky fault, and
        // must not corrupt the frame already in flight.
        input_ch0 = 14'sd777; input_ch1 = -14'sd777;
        request_conversion();
        wait (adc_sck === 1'b1);
        @(posedge clk);
        sample_ce <= 1'b1;
        @(posedge clk);
        sample_ce <= 1'b0;
        wait (sample_valid);
        #1;
        if (!adc_fault)
            $fatal(1, "busy conversion request did not set adc_fault");
        got_ch0 = ch0_sample;
        got_ch1 = ch1_sample;
        if (got_ch0 !== 14'sd0 || got_ch1 !== 14'sd0)
            $fatal(1, "in-flight frame corrupted by request-while-busy: %0d %0d",
                   got_ch0, got_ch1);

        // Reset mid-transaction: start a frame, let a few SCK edges
        // pass, then reset the *interface* and confirm a clean, idle
        // recovery. rst only reinitializes adc_if's own state machine;
        // the physical ADC keeps its own conversion pipeline, so the
        // model below is deliberately left running.
        do_conversion(14'sd555, -14'sd555);
        input_ch0 = 14'sd9999; input_ch1 = -14'sd9999;
        request_conversion();
        repeat (5) @(posedge adc_sck);
        rst <= 1'b1;
        @(posedge clk);
        rst <= 1'b0;
        #1;
        if (busy || sample_valid || adc_conv || adc_sck)
            $fatal(1, "reset mid-transaction did not return to a clean idle state");

        // The next conversion after reset legitimately reports the
        // stale pair pipelined by the interrupted frame (9999, -9999):
        // that is correct, datasheet-accurate behavior, not a bug, and
        // confirms the reset left no residual bit-shift misalignment.
        do_conversion(14'sd321, -14'sd321);
        if (got_ch0 !== 14'sd9999 || got_ch1 !== -14'sd9999)
            $fatal(1, "post-reset frame mismatch: %0d %0d", got_ch0, got_ch1);

        // A further, fresh conversion proves clean ongoing recovery.
        do_conversion(14'sd0, 14'sd0);
        if (got_ch0 !== 14'sd321 || got_ch1 !== -14'sd321)
            $fatal(1, "post-reset recovery frame mismatch: %0d %0d", got_ch0, got_ch1);

        $display("adc_if_tb: PASS");
        $finish;
    end

    initial begin
        #30000;
        $fatal(1, "timeout");
    end
endmodule
