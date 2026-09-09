// pps_uart is pure wiring around three already independently proven blocks
// (pps_generator, time_telemetry, uart_tx): the only logic it adds is
// fanning pps_internal out to both pps_ref and hat_pps. That identity is
// the one thing worth checking here rather than re-deriving the children's
// own already-proven contracts.
module pps_uart_formal;
    (* gclk *) logic clk;
    (* anyseq *) logic second_ce, time_valid, telemetry_request;
    (* anyseq *) logic [15:0] year_bcd, utc_offset_bcd;
    (* anyseq *) logic [7:0] month_bcd, day_bcd, hour_bcd, minute_bcd, second_bcd;
    (* anyseq *) logic utc_offset_negative;
    (* anyseq *) logic [1:0] receiver_state;
    (* anyseq *) logic [11:0] quality_bcd;
    logic rst = 1'b1;
    logic past_valid = 1'b0;
    logic pps_ref, hat_pps, hat_uart_tx, telemetry_busy, telemetry_done;

    pps_uart dut (.*);

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;
        if (past_valid) assert(pps_ref == hat_pps);
    end
endmodule
