`timescale 1ns/1ps
// Behavioral LTC6912 (data sheet 6912fa serial interface: DIN sampled MSB
// first on rising CLK while CS/LD is low, latch loaded on rising CS/LD)
// driven by pga_spi_master. Checks the word the PGA latches after reset
// and after an explicit send, the bit count and clock rate on the bus,
// that nothing toggles while idle, and that done/busy frame the transfer.
module pga_spi_master_tb;
    localparam int unsigned CLK_HZ = 125_000_000;
    localparam int unsigned SCK_HZ = 100_000;
    localparam int HALF = CLK_HZ / (2 * SCK_HZ);

    logic clk = 0, rst = 1, send = 0;
    logic [3:0] gain_a = 4'b0111, gain_b = 4'b1000;
    logic pga_sck, pga_mosi, pga_cs_n, busy, done;

    pga_spi_master #(.CLK_HZ(CLK_HZ), .SCK_HZ(SCK_HZ)) dut (.*);
    always #4 clk = ~clk;

    // --- LTC6912 model -----------------------------------------------------
    logic [7:0] shift = '0, latched = '0;
    integer clocks_in_frame = 0, latch_count = 0;
    integer last_rise = -1, min_period = 1 << 30, max_period = 0;
    integer now = 0;
    always @(posedge clk) now = now + 1;
    always @(posedge pga_sck) begin
        if (pga_cs_n) $fatal(1, "CLK edge while CS/LD high");
        shift = {shift[6:0], pga_mosi};
        clocks_in_frame = clocks_in_frame + 1;
        if (last_rise >= 0) begin
            if (now - last_rise < min_period) min_period = now - last_rise;
            if (now - last_rise > max_period) max_period = now - last_rise;
        end
        last_rise = now;
    end
    always @(posedge pga_cs_n) begin
        if (!rst) begin
            latched = shift;
            latch_count = latch_count + 1;
            if (clocks_in_frame != 8)
                $fatal(1, "frame had %0d clocks, expected 8", clocks_in_frame);
        end
        clocks_in_frame = 0;
        last_rise = -1;
    end
    always @(negedge pga_cs_n) begin
        clocks_in_frame = 0;
        last_rise = -1;
    end

    integer done_count = 0;
    always @(posedge clk) if (done) done_count = done_count + 1;

    task automatic wait_done(input integer max_cycles);
        integer c;
        begin
            c = 0;
            while (!done && c < max_cycles) begin @(posedge clk); c = c + 1; end
            if (!done) $fatal(1, "transfer did not complete");
            @(posedge clk); #1;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk); rst <= 0; @(posedge clk); #1;
        // Power-up word goes out on its own.
        if (!busy) $fatal(1, "no automatic transfer after reset");
        wait_done(40 * HALF);
        if (latched !== 8'b1000_0111)
            $fatal(1, "power-up word latched as %b", latched);
        if (busy || !pga_cs_n || pga_sck)
            $fatal(1, "bus not idle after transfer");
        if (min_period != 2 * HALF || max_period != 2 * HALF)
            $fatal(1, "SCK period %0d..%0d cycles, expected %0d", min_period, max_period, 2 * HALF);

        // Idle: nothing moves.
        repeat (4 * HALF) begin
            @(posedge clk);
            if (busy || pga_sck || !pga_cs_n) $fatal(1, "bus active while idle");
        end

        // Explicit reprogramming with a different pair of codes.
        gain_a = 4'b0100; gain_b = 4'b0001;
        send <= 1; @(posedge clk); send <= 0;
        wait_done(40 * HALF);
        if (latched !== 8'b0001_0100)
            $fatal(1, "resent word latched as %b", latched);
        if (latch_count != 2 || done_count != 2)
            $fatal(1, "latch/done counts %0d/%0d, expected 2/2", latch_count, done_count);

        // A send during a transfer is queued, not lost.
        send <= 1; @(posedge clk); send <= 0;
        repeat (3) @(posedge clk);
        send <= 1; @(posedge clk); send <= 0;
        wait_done(40 * HALF);
        wait_done(40 * HALF);
        if (latch_count != 4) $fatal(1, "queued send lost (%0d latches)", latch_count);

        $display("pga_spi_master_tb: PASS");
        $finish;
    end

    initial begin #20_000_000; $fatal(1, "timeout"); end
endmodule
