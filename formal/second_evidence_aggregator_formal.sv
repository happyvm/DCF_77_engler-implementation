// Per-second evidence record: exactly one write per second boundary
// (the cycle after second_ce), never otherwise; the record carries the
// boundary's second position and quality, and its sample_valid is true
// exactly when both AM and PM evidence arrived during the second that
// just ended (a pulse on the boundary cycle counts for the next second).
module second_evidence_aggregator_formal;
    localparam int EVIDENCE_BITS = 4;

    (* gclk *) logic clk;
    (* anyseq *) logic second_ce, am_valid, pm_valid;
    (* anyseq *) logic signed [EVIDENCE_BITS-1:0] am_evidence_in, pm_evidence_in;
    (* anyseq *) logic [7:0] quality_in;
    (* anyseq *) logic [5:0] second_position;
    logic rst = 1'b1;
    logic past_valid = 1'b0;

    logic write_valid, sample_valid;
    logic signed [EVIDENCE_BITS-1:0] am_evidence, pm_evidence;
    logic [7:0] quality;
    logic [5:0] second_position_out;

    second_evidence_aggregator #(.EVIDENCE_BITS(EVIDENCE_BITS)) dut (.*);

    // Reference model of "seen during the current second".
    logic model_am = 1'b0, model_pm = 1'b0;
    logic signed [EVIDENCE_BITS-1:0] model_am_val = '0, model_pm_val = '0;

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;

        if (rst) begin
            model_am <= 1'b0; model_pm <= 1'b0;
        end else begin
            if (second_ce) begin
                model_am <= am_valid; model_pm <= pm_valid;
            end else begin
                if (am_valid) model_am <= 1'b1;
                if (pm_valid) model_pm <= 1'b1;
            end
            if (am_valid) model_am_val <= am_evidence_in;
            if (pm_valid) model_pm_val <= pm_evidence_in;
        end

        if (past_valid && !$past(rst)) begin
            assert(write_valid == $past(second_ce));
            if (write_valid) begin
                assert(sample_valid == ($past(model_am) && $past(model_pm)));
                assert(second_position_out == $past(second_position));
                assert(quality == $past(quality_in));
                if ($past(model_am)) assert(am_evidence == $past(model_am_val));
                if ($past(model_pm)) assert(pm_evidence == $past(model_pm_val));
            end
        end
    end
endmodule
