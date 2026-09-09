// Receiver lock policy: time/PPS are published only in LOCKED or
// HOLDOVER, every state transition needs the event that justifies it,
// and a build with qualification disabled never publishes at all.
module receiver_lock_controller_formal;
    localparam logic [2:0] UNSYNC = 3'd0, ACQUIRING = 3'd1, LOCKED = 3'd2, HOLDOVER = 3'd3;

    (* gclk *) logic clk;
    (* anyseq *) logic qualification_valid, result_consistent, ml_qualified;
    (* anyseq *) logic minute_qualified, frequency_qualified, holdover_tick;
    logic rst = 1'b1;
    logic past_valid = 1'b0;

    logic time_valid, pps_valid, ml_locked, minute_locked, frequency_locked;
    logic [2:0] state_code;
    logic time_valid_off, pps_valid_off, ml_locked_off, minute_locked_off, frequency_locked_off;
    logic [2:0] state_code_off;

    receiver_lock_controller #(
        .QUALIFICATION_ENABLED(1'b1), .ACQUIRE_RESULTS(2), .EXIT_FAILURES(2),
        .HOLDOVER_ENABLED(1'b1), .HOLDOVER_TICKS(3)
    ) dut (
        .clk(clk), .rst(rst), .qualification_valid(qualification_valid),
        .result_consistent(result_consistent), .ml_qualified(ml_qualified),
        .minute_qualified(minute_qualified), .frequency_qualified(frequency_qualified),
        .holdover_tick(holdover_tick), .time_valid(time_valid), .pps_valid(pps_valid),
        .ml_locked(ml_locked), .minute_locked(minute_locked),
        .frequency_locked(frequency_locked), .state_code(state_code)
    );

    receiver_lock_controller #(.QUALIFICATION_ENABLED(1'b0)) dut_off (
        .clk(clk), .rst(rst), .qualification_valid(qualification_valid),
        .result_consistent(result_consistent), .ml_qualified(ml_qualified),
        .minute_qualified(minute_qualified), .frequency_qualified(frequency_qualified),
        .holdover_tick(holdover_tick), .time_valid(time_valid_off), .pps_valid(pps_valid_off),
        .ml_locked(ml_locked_off), .minute_locked(minute_locked_off),
        .frequency_locked(frequency_locked_off), .state_code(state_code_off)
    );

    wire all_qualified = result_consistent && ml_qualified && minute_qualified &&
                         frequency_qualified;

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;

        if (past_valid) begin
            // Outputs are pure functions of the state.
            assert(time_valid == (state_code == LOCKED || state_code == HOLDOVER));
            assert(pps_valid == time_valid);
            assert(!ml_locked || time_valid);
            assert(!minute_locked || time_valid);
            assert(!frequency_locked || time_valid);
            // Qualification disabled: nothing is ever published.
            assert(!time_valid_off && !pps_valid_off && state_code_off == UNSYNC);
        end

        if (past_valid && !$past(rst)) begin
            case ($past(state_code))
                UNSYNC: begin
                    // Leaves UNSYNC only on a fully qualified evaluation, and
                    // with ACQUIRE_RESULTS = 2 never straight into LOCKED.
                    assert(state_code == UNSYNC || state_code == ACQUIRING);
                    if (state_code == ACQUIRING)
                        assert($past(qualification_valid && all_qualified));
                end
                ACQUIRING: begin
                    assert(state_code != HOLDOVER);
                    if (state_code != ACQUIRING)
                        assert($past(qualification_valid));
                    if (state_code == LOCKED)
                        assert($past(all_qualified));
                    if (state_code == UNSYNC)
                        assert($past(!all_qualified));
                end
                LOCKED: begin
                    assert(state_code != ACQUIRING);
                    // Only a failed evaluation can end LOCKED.
                    if (state_code != LOCKED)
                        assert($past(qualification_valid && !all_qualified));
                end
                HOLDOVER: begin
                    assert(state_code != ACQUIRING);
                    if (state_code == LOCKED)
                        assert($past(qualification_valid && all_qualified));
                    if (state_code == UNSYNC)
                        assert($past(holdover_tick));
                end
                default: assert(0);
            endcase
        end
    end
endmodule
