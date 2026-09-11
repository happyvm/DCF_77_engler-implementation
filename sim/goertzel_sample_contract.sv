`timescale 1ns/1ps
// BEA-36 sample-cadence contract monitor.
//
// The Goertzel resonator is a multi-cycle sequencer: after a sample is
// accepted it needs GOERTZEL_MAX_CYCLES clk_sys (currently 4) before it can
// accept the next one. Presenting sample_ce while `busy` is a caller error;
// the design must never silently drop it. This monitor turns that into a hard
// simulation failure. It is not instantiated in production RTL (it is a
// simulation-only observer) -- the same contract is proven in
// formal/goertzel_resonator_formal.sv and checked against the real 930 kS/s
// scheduler in sim/sample_cadence_tb.sv.
module goertzel_sample_contract (
    input logic clk,
    input logic rst,
    input logic sample_ce,
    input logic busy
);
    always_ff @(posedge clk)
        if (!rst && busy && sample_ce)
            $fatal(1, "goertzel_sample_contract: sample_ce presented while busy (BEA-36 contract)");
endmodule
