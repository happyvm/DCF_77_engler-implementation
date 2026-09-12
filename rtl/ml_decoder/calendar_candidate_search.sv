// SPDX-License-Identifier: MIT
// One shared correlator for the remaining DCF77 fields.  Select FIELD when
// loading/starting: 0=day, 1=weekday, 2=month, 3=year, 4=Z1/Z2/A1/A2 flags.
//
// Same multi-cycle sequencer as minute_candidate_search.sv /
// hour_candidate_search.sv (see docs/37-timing-closure-plan.md §8): the shared
// correlator runs a handful of times per minute, so each candidate is spread
// over two cycles -- S_SCORE (decimal split + +-evidence balanced tree ->
// score_q) then S_SELECT (score_q vs best_q/second_q, best-value capture) --
// plus a final S_EMIT phase publishing best/score/gap.  The previous
// single-cycle form put the whole decode+tree+compare cone on one ~20 ns path
// at the top.  Bit-identical arithmetic and tie-break order; latency is
// 2*(last-first+1) + 1 cycles (up to 201 for the year field, 0..99).
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
`ifdef FORMAL
    // Formal-only observability (see formal/calendar_candidate_search_formal.sv).
    , output logic [7:0] candidate_o
    , output logic [1:0] state_o
    , output logic signed [SCORE_BITS-1:0] best_q_o
    , output logic signed [SCORE_BITS-1:0] second_q_o
    , output logic [7:0] best_value_q_o
`endif
);

    localparam logic [1:0] S_IDLE   = 2'd0;
    localparam logic [1:0] S_SCORE  = 2'd1;
    localparam logic [1:0] S_SELECT = 2'd2;
    localparam logic [1:0] S_EMIT   = 2'd3;

    logic [1:0] state;
    logic signed [SOFT_BITS-1:0] evidence[0:8];
    logic [7:0] candidate, last, first, best_value_q;
`ifdef FORMAL
    assign candidate_o = candidate;
    assign state_o = state;
`endif
    logic [8:0] bits; logic [3:0] units, tens;
    logic signed [SCORE_BITS-1:0] score, score_q, best_q, second_q, nb, ns;
`ifdef FORMAL
    assign best_q_o = best_q;
    assign second_q_o = second_q;
    assign best_value_q_o = best_value_q;
`endif
    // Balanced-tree score accumulation.  The naive serial loop
    //   score = score +/- evidence[i]
    // built a nine-deep carry chain that dominated the ECP5 critical path
    // (see docs/37-timing-closure-plan.md).  Two's-complement addition is
    // associative under modular wraparound, so summing the nine signed
    // +/-evidence terms through a balanced tree is bit-identical to the
    // serial accumulation while cutting the combinational depth from nine
    // adders to four.  Each term is sign-extended by the assignment itself,
    // avoiding explicit width casts.
    logic signed [SCORE_BITS-1:0] t0, t1, t2, t3, t4, t5, t6, t7, t8;
    logic signed [SCORE_BITS-1:0] p0, p1, p2, p3;

    // Pure per-candidate decode + balanced tree: no register boundary inside.
    always_comb begin
        case(field)
          0: begin first=1; last=31; end
          1: begin first=1; last=7; end
          2: begin first=1; last=12; end
          3: begin first=0; last=99; end
          default: begin first=0; last=7; end // zone: CET, CEST and two announcements
        endcase
        // Explicit decimal split (same structure as minute_candidate_search)
        // instead of candidate%10 / candidate/10, which inferred a deep
        // constant-divider network directly on the critical path.
        if (candidate >= 8'd90) begin tens = 4'd9; units = 4'(candidate - 8'd90); end
        else if (candidate >= 8'd80) begin tens = 4'd8; units = 4'(candidate - 8'd80); end
        else if (candidate >= 8'd70) begin tens = 4'd7; units = 4'(candidate - 8'd70); end
        else if (candidate >= 8'd60) begin tens = 4'd6; units = 4'(candidate - 8'd60); end
        else if (candidate >= 8'd50) begin tens = 4'd5; units = 4'(candidate - 8'd50); end
        else if (candidate >= 8'd40) begin tens = 4'd4; units = 4'(candidate - 8'd40); end
        else if (candidate >= 8'd30) begin tens = 4'd3; units = 4'(candidate - 8'd30); end
        else if (candidate >= 8'd20) begin tens = 4'd2; units = 4'(candidate - 8'd20); end
        else if (candidate >= 8'd10) begin tens = 4'd1; units = 4'(candidate - 8'd10); end
        else begin tens = 4'd0; units = candidate[3:0]; end
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
        t0 = bits[0] ? SCORE_BITS'(evidence[0]) : SCORE_BITS'(-evidence[0]);
        t1 = bits[1] ? SCORE_BITS'(evidence[1]) : SCORE_BITS'(-evidence[1]);
        t2 = bits[2] ? SCORE_BITS'(evidence[2]) : SCORE_BITS'(-evidence[2]);
        t3 = bits[3] ? SCORE_BITS'(evidence[3]) : SCORE_BITS'(-evidence[3]);
        t4 = bits[4] ? SCORE_BITS'(evidence[4]) : SCORE_BITS'(-evidence[4]);
        t5 = bits[5] ? SCORE_BITS'(evidence[5]) : SCORE_BITS'(-evidence[5]);
        t6 = bits[6] ? SCORE_BITS'(evidence[6]) : SCORE_BITS'(-evidence[6]);
        t7 = bits[7] ? SCORE_BITS'(evidence[7]) : SCORE_BITS'(-evidence[7]);
        t8 = bits[8] ? SCORE_BITS'(evidence[8]) : SCORE_BITS'(-evidence[8]);
        p0 = t0 + t1;
        p1 = t2 + t3;
        p2 = t4 + t5;
        p3 = t6 + t7;
        score = (p0 + p1) + (p2 + (p3 + t8));
    end

    // Top-2 selection on the registered score of the current candidate.
    always_comb begin
        nb=best_q; ns=second_q;
        if(score_q>best_q) begin nb=score_q; ns=best_q; end
        else if(score_q>second_q) ns=score_q;
    end

    always_ff @(posedge clk) begin
        if(rst) begin
            for(int i=0;i<9;i=i+1) evidence[i]<='0;
            candidate<=0; score_q<=0; busy<=0; result_valid<=0; best_value<=0;
            best_value_q<=0; best_q<={1'b1,{(SCORE_BITS-1){1'b0}}};
            second_q<={1'b1,{(SCORE_BITS-1){1'b0}}}; best_score<=0; second_score<=0; quality_gap<=0;
            state<=S_IDLE;
        end else begin
            result_valid<=0;
            if(load_valid&&!busy) evidence[load_index]<=soft_bit;

            case(state)
                S_IDLE: begin
                    busy<=1'b0;
                    if(start) begin candidate<=first; best_value_q<=first;
                        best_q<={1'b1,{(SCORE_BITS-1){1'b0}}};
                        second_q<={1'b1,{(SCORE_BITS-1){1'b0}}}; busy<=1'b1;
                        state<=S_SCORE; end
                end

                S_SCORE: begin
                    score_q<=score;
                    state<=S_SELECT;
                end

                S_SELECT: begin
                    best_q<=nb; second_q<=ns;
                    if(score_q>best_q) best_value_q<=candidate;
                    if(candidate==last) state<=S_EMIT;
                    else begin candidate<=candidate+1'b1; state<=S_SCORE; end
                end

                S_EMIT: begin
                    best_value<=best_value_q;
                    best_score<=best_q; second_score<=second_q;
                    quality_gap<=best_q-second_q;
                    result_valid<=1'b1; busy<=1'b0; state<=S_IDLE;
                end

                default: state<=S_IDLE;
            endcase
        end
    end
endmodule
