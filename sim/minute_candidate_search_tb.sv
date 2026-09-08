`timescale 1ns/1ps
module minute_candidate_search_tb;
    logic clk = 0, rst = 1, load_valid = 0, start = 0;
    logic [2:0] load_index = 0;
    logic signed [15:0] soft_bit = 0;
    logic busy, result_valid, confident;
    logic [5:0] minute;
    logic signed [19:0] best_score;
    logic [19:0] quality_gap;
    logic [7:0] encoded = 8'b10110111; // minute 37 plus even-parity bit
    integer index;

    minute_candidate_search #(
        .SOFT_BITS(16), .QUALIFICATION_ENABLED(1'b1),
        .MIN_SCORE(20'sd700), .MIN_GAP(20'd100)
    ) dut (.*);
    always #5 clk = ~clk;

    initial begin
        repeat (2) @(posedge clk); rst <= 0;
        for (index = 0; index < 8; index = index + 1) begin
            load_index <= index[2:0];
            soft_bit <= encoded[index] ? 16'sd100 : -16'sd100;
            load_valid <= 1; @(posedge clk);
            load_valid <= 0; @(posedge clk);
        end
        start <= 1; @(posedge clk); start <= 0;
        wait (result_valid); #1;
        if (!confident || minute != 6'd37)
            $fatal(1, "minute search mismatch: %0d", minute);
        if (best_score != 20'sd800 || quality_gap < 20'd100)
            $fatal(1, "minute confidence mismatch: score=%0d gap=%0d",
                   best_score, quality_gap);
        if (busy)
            $fatal(1, "search remained busy after result");
        $display("minute_candidate_search_tb: PASS");
        $finish;
    end

    initial begin
        #2000; $fatal(1, "timeout");
    end
endmodule
