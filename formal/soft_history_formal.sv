// Circular history: the write pointer never leaves [0, DEPTH), advances
// by exactly one per write and wraps at DEPTH-1, history_full is sticky,
// and read_valid is exactly the registered read_enable.
module soft_history_formal;
    localparam int DEPTH = 5;
    localparam int ADDR_BITS = 3;

    (* gclk *) logic clk;
    (* anyseq *) logic write_valid, sample_valid, read_enable;
    (* anyseq *) logic signed [3:0] am_evidence, pm_evidence;
    (* anyseq *) logic [7:0] quality;
    (* anyseq *) logic [5:0] second_position;
    (* anyseq *) logic [ADDR_BITS-1:0] read_address;
    logic rst = 1'b1;
    logic past_valid = 1'b0;

    logic [ADDR_BITS-1:0] write_pointer;
    logic history_full, read_valid, read_sample_valid;
    logic signed [3:0] read_am_evidence, read_pm_evidence;
    logic [7:0] read_quality;
    logic [5:0] read_second_position;

    soft_history #(.DEPTH(DEPTH), .EVIDENCE_BITS(4), .ADDR_BITS(ADDR_BITS)) dut (.*);

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;
        // Only in-range addresses are ever read (the readers derive their
        // address from write_pointer); keep the memory access in range.
        assume(read_address < DEPTH);

        if (past_valid) assert(write_pointer < DEPTH);
        if (past_valid && !$past(rst)) begin
            assert(read_valid == $past(read_enable));
            if ($past(write_valid)) begin
                if ($past(write_pointer) == DEPTH - 1) begin
                    assert(write_pointer == 0);
                    assert(history_full);
                end else
                    assert(write_pointer == $past(write_pointer) + 1);
            end else
                assert(write_pointer == $past(write_pointer));
            if ($past(history_full))
                assert(history_full);
        end
    end
endmodule
