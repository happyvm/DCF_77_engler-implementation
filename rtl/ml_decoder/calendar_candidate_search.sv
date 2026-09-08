// SPDX-License-Identifier: MIT
// One shared correlator for the remaining DCF77 fields.  Select FIELD when
// loading/starting: 0=day, 1=weekday, 2=month, 3=year, 4=Z1/Z2/A1/A2 flags.
module calendar_candidate_search #(
    parameter int SOFT_BITS=16, parameter int SCORE_BITS=SOFT_BITS+4
) (
    input logic clk, input logic rst,
    input logic load_valid, input logic [3:0] load_index,
    input logic signed [SOFT_BITS-1:0] soft_bit,
    input logic [2:0] field, input logic start,
    output logic busy, output logic result_valid,
    output logic [7:0] best_value,
    output logic signed [SCORE_BITS-1:0] best_score,
    output logic signed [SCORE_BITS-1:0] second_score,
    output logic [SCORE_BITS-1:0] quality_gap
);
    logic signed [SOFT_BITS-1:0] evidence[0:8];
    logic [7:0] candidate, last, first, best_value_q;
    logic [8:0] bits; logic [3:0] units, tens;
    logic signed [SCORE_BITS-1:0] score, best_q, second_q, nb, ns;
    always_comb begin
        case(field)
          0: begin first=1; last=31; end
          1: begin first=1; last=7; end
          2: begin first=1; last=12; end
          3: begin first=0; last=99; end
          default: begin first=0; last=7; end // zone: CET, CEST and two announcements
        endcase
        units = 4'(candidate % 8'd10); tens = 4'(candidate / 8'd10);
        bits='0;
        if (field == 1) bits[2:0]=candidate[2:0];
        else if (field == 4) begin
            // Three legal mutually exclusive zone/announcement combinations.
            bits[0] = candidate[0]; bits[1] = ~candidate[0];
            bits[2] = candidate[1]; bits[3] = candidate[2];
        end else begin
            bits[0]=units[0]; bits[1]=units[1]; bits[2]=units[2]; bits[3]=units[3];
            bits[4]=tens[0]; bits[5]=tens[1]; bits[6]=tens[2]; bits[7]=tens[3];
            bits[8]=^bits[7:0]; // local parity contribution
        end
        score='0;
        for(int i=0;i<9;i=i+1)
            score = bits[i] ? score+SCORE_BITS'(evidence[i]) : score-SCORE_BITS'(evidence[i]);
        nb=best_q; ns=second_q;
        if(score>best_q) begin nb=score; ns=best_q; end
        else if(score>second_q) ns=score;
    end
    always_ff @(posedge clk) begin
        if(rst) begin
            for(int i=0;i<9;i=i+1) evidence[i]<='0;
            candidate<=0; busy<=0; result_valid<=0; best_value<=0;
            best_value_q<=0; best_q<={1'b1,{(SCORE_BITS-1){1'b0}}};
            second_q<={1'b1,{(SCORE_BITS-1){1'b0}}}; best_score<=0; second_score<=0; quality_gap<=0;
        end else begin
            result_valid<=0;
            if(load_valid&&!busy) evidence[load_index]<=soft_bit;
            if(start&&!busy) begin candidate<=first; best_value_q<=first; best_q<={1'b1,{(SCORE_BITS-1){1'b0}}};
                second_q<={1'b1,{(SCORE_BITS-1){1'b0}}}; busy<=1; end
            else if(busy) begin
                if(score>best_q) best_value_q<=candidate;
                if(candidate==last) begin best_value <= score>best_q ? candidate:best_value_q;
                    best_score<=nb; second_score<=ns; quality_gap<=nb-ns;
                    busy<=0; result_valid<=1; end
                else begin candidate<=candidate+1'b1; best_q<=nb; second_q<=ns; end
            end
        end
    end
endmodule
