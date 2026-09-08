// SPDX-License-Identifier: MIT
// Receiver-wide lock policy.  qualification_valid marks an independent
// decoder/frequency result; result_consistent says it agrees with the previous
// time solution.  holdover_tick is normally the local one-second tick.

module receiver_lock_controller #(
    parameter bit QUALIFICATION_ENABLED = 1'b0,
    parameter int unsigned ACQUIRE_RESULTS = 3,
    parameter int unsigned EXIT_FAILURES = 2,
    parameter bit HOLDOVER_ENABLED = 1'b1,
    parameter int unsigned HOLDOVER_TICKS = 60
) (
    input  logic clk,
    input  logic rst,
    input  logic qualification_valid,
    input  logic result_consistent,
    input  logic ml_qualified,
    input  logic minute_qualified,
    input  logic frequency_qualified,
    input  logic holdover_tick,
    output logic time_valid,
    output logic pps_valid,
    output logic ml_locked,
    output logic minute_locked,
    output logic frequency_locked,
    output logic [2:0] state_code
);

    localparam logic [2:0] UNSYNC    = 3'd0;
    localparam logic [2:0] ACQUIRING = 3'd1;
    localparam logic [2:0] LOCKED    = 3'd2;
    localparam logic [2:0] HOLDOVER  = 3'd3;
    localparam int ACQUIRE_WIDTH = (ACQUIRE_RESULTS <= 1) ? 1 : $clog2(ACQUIRE_RESULTS + 1);
    localparam int FAILURE_WIDTH = (EXIT_FAILURES <= 1) ? 1 : $clog2(EXIT_FAILURES + 1);
    localparam int HOLDOVER_WIDTH = (HOLDOVER_TICKS <= 1) ? 1 : $clog2(HOLDOVER_TICKS + 1);

    logic [2:0] state_q;
    logic [ACQUIRE_WIDTH-1:0] acquire_count;
    logic [FAILURE_WIDTH-1:0] failure_count;
    logic [HOLDOVER_WIDTH-1:0] holdover_count;
    logic all_qualified;

    assign all_qualified = QUALIFICATION_ENABLED && result_consistent &&
                           ml_qualified && minute_qualified && frequency_qualified;
    assign state_code = state_q;
    assign time_valid = (state_q == LOCKED) || (state_q == HOLDOVER);
    assign pps_valid = time_valid;
    assign ml_locked = time_valid && ml_qualified;
    assign minute_locked = time_valid && minute_qualified;
    assign frequency_locked = time_valid && frequency_qualified;

    always_ff @(posedge clk) begin
        if (rst || !QUALIFICATION_ENABLED) begin
            state_q <= UNSYNC;
            acquire_count <= '0;
            failure_count <= '0;
            holdover_count <= '0;
        end else begin
            case (state_q)
                UNSYNC: begin
                    acquire_count <= '0;
                    failure_count <= '0;
                    holdover_count <= '0;
                    if (qualification_valid && all_qualified) begin
                        if (ACQUIRE_RESULTS == 1)
                            state_q <= LOCKED;
                        else begin
                            state_q <= ACQUIRING;
                            acquire_count <= 1;
                        end
                    end
                end
                ACQUIRING: if (qualification_valid) begin
                    if (!all_qualified) begin
                        state_q <= UNSYNC;
                        acquire_count <= '0;
                    end else if (acquire_count >= ACQUIRE_RESULTS - 1) begin
                        state_q <= LOCKED;
                        acquire_count <= '0;
                        failure_count <= '0;
                    end else begin
                        acquire_count <= acquire_count + 1'b1;
                    end
                end
                LOCKED: if (qualification_valid) begin
                    if (all_qualified) begin
                        failure_count <= '0;
                    end else if (failure_count >= EXIT_FAILURES - 1) begin
                        failure_count <= '0;
                        holdover_count <= '0;
                        if (HOLDOVER_ENABLED && (HOLDOVER_TICKS != 0))
                            state_q <= HOLDOVER;
                        else
                            state_q <= UNSYNC;
                    end else begin
                        failure_count <= failure_count + 1'b1;
                    end
                end
                HOLDOVER: begin
                    if (qualification_valid && all_qualified) begin
                        state_q <= LOCKED;
                        failure_count <= '0;
                        holdover_count <= '0;
                    end else if (holdover_tick) begin
                        if (holdover_count >= HOLDOVER_TICKS - 1) begin
                            state_q <= UNSYNC;
                            holdover_count <= '0;
                        end else begin
                            holdover_count <= holdover_count + 1'b1;
                        end
                    end
                end
                default: state_q <= UNSYNC;
            endcase
        end
    end

    initial begin
        if (ACQUIRE_RESULTS == 0 || EXIT_FAILURES == 0)
            $error("receiver_lock_controller: count parameters must be nonzero");
    end

endmodule
