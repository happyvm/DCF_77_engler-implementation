`timescale 1ns/1ps
// BEA-36 pm_minute_sync cadence contract monitor.
//
// pm_minute_sync is a four-stage multi-cycle sequencer: after a sample is
// accepted it needs PM_MINUTE_SYNC_MAX_CYCLES clk_sys (currently 4) before it
// can accept the next one. Presenting pm_second_valid while `busy` is a caller
// error; the design must never silently drop it. This monitor turns that into
// a hard simulation failure. It is not instantiated in production RTL (it is a
// simulation-only observer) -- the same contract is proven in
// formal/pm_minute_sync_formal.sv.
//
// In the real receiver pm_second_valid pulses once per DCF77 second
// (pm_correlation_valid from engeler_pm_pipeline), i.e. ~10^8 clk_sys apart at
// 125 MHz, so the contract is trivially met; it only constrains the
// time-compressed unit benches, which must space their strobes.
module pm_minute_sync_contract (
    input logic clk,
    input logic rst,
    input logic pm_second_valid,
    input logic busy
);
    always_ff @(posedge clk)
        if (!rst && busy && pm_second_valid)
            $fatal(1, "pm_minute_sync_contract: pm_second_valid presented while busy (BEA-36 contract)");
endmodule