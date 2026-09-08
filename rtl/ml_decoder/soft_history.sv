// SPDX-License-Identifier: MIT
// Circular, synchronous soft-decision history.  Keeping the complete record in
// one unpacked array lets Yosys infer ECP5 EBRs (no vendor primitive is used).
module soft_history #(
    parameter int DEPTH = 3600,
    parameter int EVIDENCE_BITS = 16,
    parameter int QUALITY_BITS = 8,
    parameter int ADDR_BITS = $clog2(DEPTH),
    parameter int WORD_BITS = 2*EVIDENCE_BITS + QUALITY_BITS + 7
) (
    input logic clk, input logic rst,
    input logic write_valid,
    input logic signed [EVIDENCE_BITS-1:0] am_evidence,
    input logic signed [EVIDENCE_BITS-1:0] pm_evidence,
    input logic sample_valid,
    input logic [QUALITY_BITS-1:0] quality,
    input logic [5:0] second_position,
    output logic [ADDR_BITS-1:0] write_pointer,
    output logic history_full,
    input logic read_enable,
    input logic [ADDR_BITS-1:0] read_address,
    output logic read_valid,
    output logic signed [EVIDENCE_BITS-1:0] read_am_evidence,
    output logic signed [EVIDENCE_BITS-1:0] read_pm_evidence,
    output logic read_sample_valid,
    output logic [QUALITY_BITS-1:0] read_quality,
    output logic [5:0] read_second_position
);
    localparam int USED_BITS = 2*EVIDENCE_BITS + QUALITY_BITS + 7;
    logic [WORD_BITS-1:0] memory [0:DEPTH-1];
    logic [WORD_BITS-1:0] read_word;

    always_ff @(posedge clk) begin
        if (rst) begin
            write_pointer <= '0;
            history_full <= 1'b0;
            read_valid <= 1'b0;
        end else begin
            read_valid <= read_enable;
            if (read_enable)
                read_word <= memory[read_address];
            if (write_valid) begin
                memory[write_pointer] <= {am_evidence, pm_evidence,
                                          sample_valid, quality, second_position};
                if (write_pointer == DEPTH-1) begin
                    write_pointer <= '0;
                    history_full <= 1'b1;
                end else
                    write_pointer <= write_pointer + 1'b1;
            end
        end
    end
    always_comb begin
        {read_am_evidence, read_pm_evidence, read_sample_valid, read_quality,
         read_second_position} = read_word[USED_BITS-1:0];
    end
    initial begin
        if (DEPTH < 1 || WORD_BITS != USED_BITS)
            $error("soft_history: invalid parameters");
    end
endmodule
