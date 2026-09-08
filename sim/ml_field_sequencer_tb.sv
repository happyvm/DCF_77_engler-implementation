`timescale 1ns/1ps
// Drives ml_field_sequencer against a small behavioral model of
// soft_history's read port, preloaded with the AM evidence a real DCF77
// minute would produce for a known target time, and checks every decoded
// field plus the three zone/announcement flags.
module ml_field_sequencer_tb;
    localparam int HISTORY_DEPTH = 64;
    localparam int HISTORY_ADDR_BITS = $clog2(HISTORY_DEPTH);

    logic clk = 0, rst = 1;
    logic start, busy;
    logic [HISTORY_ADDR_BITS-1:0] history_write_pointer;
    logic history_read_enable;
    logic [HISTORY_ADDR_BITS-1:0] history_read_address;
    logic history_read_valid;
    logic signed [15:0] history_am_evidence;
    logic history_sample_valid;
    logic [5:0] history_second_position;
    logic result_valid;
    logic [5:0] out_minute;
    logic out_minute_confident;
    logic signed [19:0] out_minute_best_score;
    logic [19:0] out_minute_quality_gap;
    logic [4:0] out_hour;
    logic out_hour_confident;
    logic [5:0] out_day;
    logic [2:0] out_weekday;
    logic [3:0] out_month;
    logic [7:0] out_year;
    logic out_cest, out_dst_announcement, out_leap_announcement;

    ml_field_sequencer #(
        .HISTORY_DEPTH(HISTORY_DEPTH), .QUALIFICATION_ENABLED(1'b1),
        .MINUTE_MIN_SCORE(20'sd200), .MINUTE_MIN_GAP(20'd100),
        .HOUR_MIN_SCORE(19'sd140), .HOUR_MIN_GAP(19'd100)
    ) dut (.*);
    always #5 clk = ~clk;

    // --- Behavioral soft_history read-port model ------------------------
    logic signed [15:0] mem_am [0:HISTORY_DEPTH-1];
    logic mem_valid [0:HISTORY_DEPTH-1];
    logic [5:0] mem_pos [0:HISTORY_DEPTH-1];

    logic read_valid_r;
    logic signed [15:0] read_am_r;
    logic read_sample_valid_r;
    logic [5:0] read_pos_r;

    always @(posedge clk) begin
        read_valid_r <= history_read_enable;
        if (history_read_enable) begin
            read_am_r <= mem_am[history_read_address];
            read_sample_valid_r <= mem_valid[history_read_address];
            read_pos_r <= mem_pos[history_read_address];
        end
    end
    assign history_read_valid = read_valid_r;
    assign history_am_evidence = read_am_r;
    assign history_sample_valid = read_sample_valid_r;
    assign history_second_position = read_pos_r;

    integer i;
    localparam signed [15:0] HI = 16'sd100;
    localparam signed [15:0] LO = -16'sd100;

    initial begin
        for (i = 0; i < HISTORY_DEPTH; i = i + 1) begin
            mem_am[i] = 16'sd0; mem_valid[i] = 1'b0; mem_pos[i] = 6'd59;
        end
        // Positions 0-58 hold one full minute's worth of AM evidence for
        // the target time minute=34, hour=17, day=15, weekday=3 (Wed),
        // month=11, CEST active (Z1=1), no A1/A2 announcement. Bit
        // values below were hand-derived from the same BCD + even-parity
        // convention minute_candidate_search/hour_candidate_search/
        // calendar_candidate_search score against.
        for (i = 0; i <= 58; i = i + 1) begin
            mem_pos[i] = i[5:0]; mem_valid[i] = 1'b1; mem_am[i] = 16'sd0;
        end
        // Zone/announcement bits.
        mem_am[16] = LO; // A1 = 0 (no DST announcement)
        mem_am[17] = HI; // Z1 = 1 (CEST)
        mem_am[19] = LO; // A2 = 0 (no leap-second announcement)
        // Minute 34: bits 21-28.
        mem_am[21] = LO; mem_am[22] = LO; mem_am[23] = HI; mem_am[24] = LO;
        mem_am[25] = HI; mem_am[26] = HI; mem_am[27] = LO; mem_am[28] = HI;
        // Hour 17: bits 29-35.
        mem_am[29] = HI; mem_am[30] = HI; mem_am[31] = HI; mem_am[32] = LO;
        mem_am[33] = HI; mem_am[34] = LO; mem_am[35] = LO;
        // Day 15: bits 36-41.
        mem_am[36] = HI; mem_am[37] = LO; mem_am[38] = HI; mem_am[39] = LO;
        mem_am[40] = HI; mem_am[41] = LO;
        // Weekday 3 (Wed): bits 42-44.
        mem_am[42] = HI; mem_am[43] = HI; mem_am[44] = LO;
        // Month 11: bits 45-49.
        mem_am[45] = HI; mem_am[46] = LO; mem_am[47] = LO; mem_am[48] = LO;
        mem_am[49] = HI;
        // Year 24: bits 50-57.
        mem_am[50] = LO; mem_am[51] = LO; mem_am[52] = HI; mem_am[53] = LO;
        mem_am[54] = LO; mem_am[55] = HI; mem_am[56] = LO; mem_am[57] = LO;

        start <= 0;
        history_write_pointer <= HISTORY_ADDR_BITS'(59);
        repeat (2) @(posedge clk); rst <= 0; @(posedge clk);

        start <= 1; @(posedge clk); start <= 0;
        wait (result_valid);
        #1;

        if (out_minute !== 6'd34 || !out_minute_confident)
            $fatal(1, "minute mismatch: got %0d confident=%0b", out_minute, out_minute_confident);
        if (out_minute_best_score !== 20'sd800)
            $fatal(1, "minute best_score mismatch: got %0d", out_minute_best_score);
        if (out_hour !== 5'd17 || !out_hour_confident)
            $fatal(1, "hour mismatch: got %0d confident=%0b", out_hour, out_hour_confident);
        if (out_day !== 6'd15)
            $fatal(1, "day mismatch: got %0d", out_day);
        if (out_weekday !== 3'd3)
            $fatal(1, "weekday mismatch: got %0d", out_weekday);
        if (out_month !== 4'd11)
            $fatal(1, "month mismatch: got %0d", out_month);
        if (out_year !== 8'd24)
            $fatal(1, "year mismatch: got %0d", out_year);
        if (!out_cest)
            $fatal(1, "cest mismatch: expected 1");
        if (out_dst_announcement)
            $fatal(1, "dst_announcement mismatch: expected 0");
        if (out_leap_announcement)
            $fatal(1, "leap_announcement mismatch: expected 0");
        // busy clears one cycle after result_valid (S_DONE -> S_IDLE).
        @(posedge clk);
        #1;
        if (busy)
            $fatal(1, "busy did not clear after result_valid");

        $display("ml_field_sequencer_tb: PASS");
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "timeout");
    end
endmodule
