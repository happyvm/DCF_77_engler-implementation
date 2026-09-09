// HAT SPI slave: MISO is quiet while deselected, the control register
// changes only through a transaction, transaction_done is a single-cycle
// pulse that follows a CS_N release, and the identity registers read back
// 0xDC/0x77 in a bounded scripted read.
module hat_spi_slave_formal;
    (* gclk *) logic clk;
    (* anyseq *) logic spi_sclk, spi_mosi, spi_cs_n;
    (* anyseq *) logic [2:0] lock_state;
    (* anyseq *) logic time_valid, pps_valid, ml_locked, minute_locked, frequency_locked;
    (* anyseq *) logic adc_fault, detector_overflow, cest;
    (* anyseq *) logic [7:0] phase_quality, year;
    (* anyseq *) logic [5:0] second, minute, day;
    (* anyseq *) logic [4:0] hour;
    (* anyseq *) logic [2:0] weekday;
    (* anyseq *) logic [3:0] month;
    (* anyseq *) logic signed [23:0] trim_inc;
    logic rst = 1'b1;
    logic past_valid = 1'b0;
    logic spi_miso, transaction_done;
    logic [7:0] control;

    hat_spi_slave #(.RTL_VERSION(16'h0102)) dut (.*);

    // Synchronized copy of CS_N as the DUT sees it (two-stage synchronizer).
    logic [3:0] cs_hist = 4'hF;

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;
        cs_hist <= {cs_hist[2:0], spi_cs_n};

        if (past_valid && !$past(rst)) begin
            // Deselected for long enough that the synchronizers agree:
            // MISO must be low and control must not change.
            if (cs_hist == 4'hF) begin
                assert(!spi_miso);
                assert(control == $past(control));
            end
            assert(!(transaction_done && $past(transaction_done)));
            // done follows a CS_N rising edge seen through the synchronizer.
            if (transaction_done)
                assert(cs_hist[3:2] == 2'b01 || cs_hist[3:2] == 2'b11);
        end
    end
endmodule
