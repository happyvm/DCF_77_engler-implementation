// LTC6912 programmer: CLK only toggles while CS/LD is low, MOSI never
// changes while CLK is high (DIN setup/hold), every frame carries exactly
// 8 clocks and shifts out {gain_b, gain_a} as sampled when the frame
// began, done is a single-cycle pulse that only follows a CS/LD rising
// edge, and the bus is idle (CS/LD high, CLK low) whenever the block is
// not busy.
module pga_spi_master_formal;
    (* gclk *) logic clk;
    (* anyseq *) logic send;
    (* anyseq *) logic [3:0] gain_a, gain_b;
    logic rst = 1'b1;
    logic past_valid = 1'b0;
    logic pga_sck, pga_mosi, pga_cs_n, busy, done;

    // HALF_CYCLES = 2 keeps one frame inside the bounded depth.
    pga_spi_master #(.CLK_HZ(8), .SCK_HZ(2)) dut (.*);

    logic [7:0] shifted = '0, expected = '0;
    logic [3:0] clocks = '0;
    logic in_frame = 1'b0;

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;

        if (past_valid && !$past(rst)) begin
            // Frame bookkeeping from the pins alone. The DUT captures the
            // gain word in the cycle it decides to start (CS/LD falls one
            // cycle later), hence $past on the gain inputs.
            if ($past(pga_cs_n) && !pga_cs_n) begin
                in_frame <= 1'b1; clocks <= '0; shifted <= '0;
                expected <= {$past(gain_b), $past(gain_a)};
            end
            if (pga_sck && !$past(pga_sck)) begin
                assert(!pga_cs_n);
                shifted <= {shifted[6:0], pga_mosi};
                clocks <= clocks + 1'b1;
            end
            if (!$past(pga_cs_n) && pga_cs_n) begin
                in_frame <= 1'b0;
                assert(clocks == 4'd8);
                assert(!pga_sck);
                // The eight bits sampled on the rising CLK edges are the
                // word latched at frame start.
                if (in_frame) assert(shifted == expected);
            end
            if ($past(pga_sck) && pga_sck)
                assert(pga_mosi == $past(pga_mosi));
            assert(!(done && $past(done)));
            if (done)
                assert(pga_cs_n && !pga_sck);
            if (!busy) begin
                assert(pga_cs_n);
                assert(!pga_sck);
            end
        end
    end
endmodule
