// UART transmitter (8N1, LSB first): the line idles high, ready is the
// complement of a frame in flight, a byte accepted on valid&&ready is
// followed by a start bit, its eight data bits and a stop bit each held
// for exactly CLKS_PER_BIT clocks, and the line is high again with ready
// reasserted right after the stop bit. The frame is reconstructed from
// the tx pin alone and compared with the accepted byte.
module uart_tx_formal;
    (* gclk *) logic clk;
    (* anyseq *) logic valid;
    (* anyseq *) logic [7:0] data;
    logic rst_n = 1'b0;
    logic past_valid = 1'b0;
    logic ready, tx;

    // CLKS_PER_BIT = 2 keeps a whole 10-bit frame (20 clocks) inside the
    // bounded depth.
    localparam int unsigned CPB = 2;
    uart_tx #(.CLK_HZ(2 * 115_200), .BAUD(115_200)) dut (.*);

    logic [7:0] captured = '0;
    logic [9:0] seen = '0;
    logic [5:0] since_accept = '0;
    logic in_frame = 1'b0;

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst_n <= 1'b1;

        if (past_valid && $past(rst_n)) begin
            if (ready) assert(tx);

            // Timeline: the accept is seen here one cycle late, when the
            // start bit is already on the line; since_accept counts the
            // following cycles from 0, so bit k (0 = start, 9 = stop)
            // spans since_accept in [k*CPB-1, k*CPB+CPB-2] and the whole
            // frame ends at 10*CPB-2, ready returning on the next cycle.
            if ($past(valid) && $past(ready)) begin
                in_frame <= 1'b1; since_accept <= '0; captured <= $past(data);
                assert(!ready);
                assert(!tx);               // start bit begins immediately
            end else if (in_frame) begin
                since_accept <= since_accept + 1'b1;
                // Sample every bit on its last clock.
                if ((since_accept + 2) % CPB == 0)
                    seen <= {tx, seen[9:1]};
                // Level must not change inside a bit period.
                if ((since_accept + 1) % CPB != 0) assert(tx == $past(tx));
                assert(!ready);
                if (since_accept == 10 * CPB - 2) begin
                    in_frame <= 1'b0;
                    assert(tx);            // stop bit
                    assert({tx, seen[9:1]} == {1'b1, captured, 1'b0});
                end
            end
            if (!in_frame && !($past(valid) && $past(ready))) assert(ready);
            // After the stop bit ready returns without gap.
            if ($past(in_frame) && !in_frame) assert(ready);
        end
    end
endmodule
