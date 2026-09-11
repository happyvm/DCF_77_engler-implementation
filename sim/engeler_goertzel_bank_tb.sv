`timescale 1ns/1ps
// Three Goertzel resonators fed a 12-phase carrier.  The resonator is now a
// multi-cycle sequencer (BEA-36): successive sample_ce pulses must be spaced
// at least GOERTZEL_MAX_CYCLES apart (the initiation interval), so this bench
// paces them at SAMPLE_PERIOD = 4 instead of one per clock.  The arithmetic is
// bit-exact versus the former single-cycle datapath, so the reference state
// vectors below are unchanged.  The bench also enforces the busy contract:
// sample_ce must never be presented while busy, and busy must drop within the
// documented budget.
module engeler_goertzel_bank_tb;
    localparam int SAMPLE_PERIOD = 4;   // == goertzel_resonator GOERTZEL_MAX_CYCLES

    logic clk = 0;
    logic rst = 1;
    logic sample_ce = 0;
    logic signed [13:0] sample = 0;
    logic signed [31:0] carrier_s1, carrier_s2;
    logic signed [31:0] am_s1, am_s2;
    logic signed [31:0] pm_s1, pm_s2;
    logic cycle_valid;
    logic overflow;
    logic busy, done;
    integer sample_index;
    integer valid_count = 0;

    engeler_goertzel_bank dut (.*);
    always #5 clk = ~clk;

    function automatic logic signed [13:0] carrier_sample(input integer phase);
        case (phase)
            0: carrier_sample = 0;
            1: carrier_sample = 500;
            2: carrier_sample = 866;
            3: carrier_sample = 1000;
            4: carrier_sample = 866;
            5: carrier_sample = 500;
            6: carrier_sample = 0;
            7: carrier_sample = -500;
            8: carrier_sample = -866;
            9: carrier_sample = -1000;
            10: carrier_sample = -866;
            default: carrier_sample = -500;
        endcase
    endfunction

    always @(posedge clk)
        if (cycle_valid)
            valid_count = valid_count + 1;

    // Busy-contract monitor: how long busy may stay high, and a hard error if
    // a sample is ever presented while the bank is still busy.
    integer busy_run = 0, busy_max = 0;
    always @(posedge clk) begin
        if (rst) begin
            busy_run = 0;
        end else begin
            if (busy) busy_run = busy_run + 1;
            else busy_run = 0;
            if (busy_run > busy_max) busy_max = busy_run;
            if (busy && sample_ce)
                $fatal(1, "sample_ce presented while busy (BEA-36 contract)");
        end
    end

    initial begin
        repeat (2) @(posedge clk);
        rst <= 0;

        for (sample_index = 0; sample_index < 48; sample_index = sample_index + 1) begin
            sample <= carrier_sample(sample_index % 12);
            sample_ce <= 1;
            @(posedge clk);
            sample_ce <= 0;
            repeat (SAMPLE_PERIOD - 1) @(posedge clk);
        end
        // Let the last accepted sample finish its boundary commit and be
        // counted before checking (the commit trails the accept by up to
        // SAMPLE_PERIOD-1 cycles now that the resonator is multi-cycle).
        repeat (SAMPLE_PERIOD + 1) @(posedge clk);
        #1;

        if (valid_count != 4)
            $fatal(1, "cycle_valid count mismatch: %0d", valid_count);
        if (carrier_s1 !== -32'sd47995 || carrier_s2 !== -32'sd41565)
            $fatal(1, "carrier state mismatch: %0d %0d", carrier_s1, carrier_s2);
        if (am_s1 !== -32'sd47934 || am_s2 !== -32'sd41514)
            $fatal(1, "AM state mismatch: %0d %0d", am_s1, am_s2);
        if (pm_s1 !== -32'sd43673 || pm_s2 !== -32'sd37825)
            $fatal(1, "PM state mismatch: %0d %0d", pm_s1, pm_s2);
        if (overflow)
            $fatal(1, "unexpected resonator saturation");
        if (busy_max > SAMPLE_PERIOD - 1)
            $fatal(1, "busy exceeded the initiation interval: %0d", busy_max);

        $display("engeler_goertzel_bank_tb: PASS");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "timeout");
    end
endmodule