`timescale 1ns/1ps
module hour_candidate_search_tb;
    logic clk = 0, rst = 1, load_valid = 0, start = 0;
    logic [2:0] load_index = 0;
    logic signed [15:0] soft_bit = 0;
    logic busy, result_valid, confident;
    logic [4:0] hour;
    logic signed [18:0] best_score;
    logic [18:0] quality_gap;
    logic [6:0] encoded = 7'b0011000; // hour 18 plus even parity
    integer index;

    hour_candidate_search #(
        .SOFT_BITS(16), .QUALIFICATION_ENABLED(1'b1),
        .MIN_SCORE(19'sd600), .MIN_GAP(19'd100)
    ) dut (.*);
    always #5 clk = ~clk;

    initial begin
        repeat (2) @(posedge clk); rst <= 0;
        for (index = 0; index < 7; index = index + 1) begin
            load_index <= index[2:0];
            soft_bit <= encoded[index] ? 16'sd100 : -16'sd100;
            load_valid <= 1; @(posedge clk);
            load_valid <= 0; @(posedge clk);
        end
        start <= 1; @(posedge clk); start <= 0;
        wait (result_valid); #1;
        if (!confident || hour != 5'd18)
            $fatal(1, "hour search mismatch: %0d", hour);
        if (best_score != 19'sd700 || quality_gap < 19'd100)
            $fatal(1, "hour confidence mismatch: score=%0d gap=%0d",
                   best_score, quality_gap);
        if (busy)
            $fatal(1, "search remained busy after result");
        $display("hour_candidate_search_tb: PASS");
        $finish;
    end

    initial begin
        #1000; $fatal(1, "timeout");
    end
endmodule
