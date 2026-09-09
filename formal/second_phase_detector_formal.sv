// Second-phase detector, checked from the ports for an arbitrary envelope
// and arbitrary PM measurements: second_ce is a one-clock pulse, it never
// fires while still searching, the detector never falls back to SEARCH,
// the published phase error always lies inside the tracking aperture, and
// -- the header's central claim -- once acquired, consecutive second
// ticks are SECOND_CYCLES carrier cycles apart give or take the one-cycle
// slew, whatever the RF does. A short second (10 cycles: the position
// counter must also hold SECOND_CYCLES + SEARCH_TOLERANCE, so not a power
// of two) keeps several seconds after acquisition inside the bounded depth.
module second_phase_detector_formal;
    localparam int SC = 10;
    localparam int TW = 2;
    localparam int IB = 8;

    (* gclk *) logic clk;
    (* anyseq *) logic carrier_ce, pm_measurement_valid;
    (* anyseq *) logic signed [IB-1:0] am_envelope;
    (* anyseq *) logic signed [$clog2(SC):0] pm_phase_error_cycles;
    (* anyseq *) logic [7:0] pm_quality;
    logic rst = 1'b1;
    logic past_valid = 1'b0;
    logic second_ce, measurement_outlier;
    logic signed [$clog2(SC):0] phase_error_cycles;
    logic [7:0] quality;
    logic [7:0] measurement_age;
    logic [1:0] state;

    second_phase_detector #(
        .INPUT_BITS(IB), .SECOND_CYCLES(SC), .AM_EDGE_THRESHOLD(4),
        .SEARCH_TOLERANCE(1), .TRACK_WINDOW(TW), .ACQUIRE_HITS(2),
        .HOLDOVER_AFTER(2), .AGE_BITS(8)
    ) dut (.*);

    // The detector registers carrier_ce once at its input; counting the
    // same delayed copy makes the tick spacing exact rather than +-1.
    logic ce_d = 1'b0;
    logic [4:0] ce_count = '0;
    logic ticked = 1'b0;

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        rst <= 1'b0;
        ce_d <= carrier_ce;

        if (past_valid && !$past(rst)) begin
            assert(!(second_ce && $past(second_ce)));
            if (second_ce) assert(state != 2'd0);
            if ($past(state) != 2'd0) assert(state != 2'd0);
            assert(phase_error_cycles <= TW && phase_error_cycles >= -TW);

            if (second_ce) begin
                if (ticked)
                    assert(ce_count >= SC - 1 && ce_count <= SC + 1);
                // Reachability: a full second after acquisition, one
                // shortened and one lengthened by the slew, and a tick
                // issued from HOLDOVER.
                cover(ticked);
                cover(ticked && ce_count == SC - 1);
                cover(ticked && ce_count == SC + 1);
                cover(ticked && state == 2'd2);
                ticked <= 1'b1;
                ce_count <= {4'd0, ce_d};
            end else if (ce_count != 5'h1F) begin
                ce_count <= ce_count + {4'd0, ce_d};
            end
        end
    end
endmodule
