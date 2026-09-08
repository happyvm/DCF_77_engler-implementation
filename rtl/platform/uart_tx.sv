module uart_tx #(
    parameter int unsigned CLK_HZ = 125_000_000,
    parameter int unsigned BAUD   = 115_200
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] data,
    input  logic       valid,
    output logic       ready,
    output logic       tx
);

    localparam int unsigned CLKS_PER_BIT = (CLK_HZ + (BAUD / 2)) / BAUD;
    localparam int unsigned COUNT_W = (CLKS_PER_BIT <= 1) ? 1 : $clog2(CLKS_PER_BIT);

    logic [COUNT_W-1:0] baud_count;
    logic [9:0]         shift_reg;
    logic [3:0]         bit_count;
    logic               busy;

    assign ready = !busy;
    assign tx    = busy ? shift_reg[0] : 1'b1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_count <= '0;
            shift_reg  <= 10'h3ff;
            bit_count  <= '0;
            busy       <= 1'b0;
        end else begin
            if (!busy) begin
                baud_count <= '0;
                bit_count  <= '0;

                if (valid) begin
                    // UART 8N1, LSB first:
                    // start(0), data[7:0], stop(1)
                    shift_reg <= {1'b1, data, 1'b0};
                    busy      <= 1'b1;
                end
            end else if (baud_count == CLKS_PER_BIT - 1) begin
                baud_count <= '0;

                if (bit_count == 4'd9) begin
                    busy      <= 1'b0;
                    bit_count <= '0;
                    shift_reg <= 10'h3ff;
                end else begin
                    shift_reg <= {1'b1, shift_reg[9:1]};
                    bit_count <= bit_count + 1'b1;
                end
            end else begin
                baud_count <= baud_count + 1'b1;
            end
        end
    end

    initial begin
        if (CLK_HZ == 0) begin
            $error("uart_tx: CLK_HZ must be non-zero");
        end
        if (BAUD == 0) begin
            $error("uart_tx: BAUD must be non-zero");
        end
        if (CLKS_PER_BIT < 2) begin
            $error("uart_tx: CLK_HZ/BAUD ratio is too small");
        end
    end

endmodule
