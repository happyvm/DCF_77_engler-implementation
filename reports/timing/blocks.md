# Block timing characterisation (BEA-37)

Target: LFE5U-45F-7BG256I speed grade -7, nextpnr-ecp5 --45k, clk target 125 MHz.

Post-route measurements from `nextpnr-ecp5 --report`. Raw records in `raw/`.

| module | kind | fmax_mhz | worst_slack_ns | lut4 | ff | ebr18 | mult18x18d | pll |
|---|---|---|---|---|---|---|---|---|
| engeler_detector | composition | 30.671 | -24.604 | 9932 | 3752 | 0 | 28 | 0 |

## Timing health (indicative, clk_sys = 125 MHz)

Bands: >=200 excellent, 175-200 very-good, 150-175 acceptable, 125-150 weak, <125 failing.  Multicycle / low-rate-control blocks are annotated, not failed, on an isolated slow path.

- `engeler_detector`: 30.7 MHz — failing (single-cycle)

## Critical paths (post-route, per block)

### engeler_detector — 30.7 MHz (composition)

1. `dut.observables_i.detector_i.pm_i.state_1_TRELLIS_FF_Q_28` -> `dut.observables_i.detector_i.pm_i.overflow_TRELLIS_FF_Q` : 32.08 ns (logic 14.97 + route 17.11, 147 segs)
2. `sig_ctr_TRELLIS_FF_Q` -> `sig_o[15]$tr_io` : 6.25 ns (logic 0.24 + route 6.01, 4 segs)


## Summary

### 10 slowest blocks

- `engeler_detector`: 30.7 MHz (composition)

### Largest LUT consumers

- `engeler_detector`: 9932 LUT4

### Largest DSP consumers

- `engeler_detector`: 28 MULT18X18D

### Largest RAM consumers

- `engeler_detector`: 0 EBR18
