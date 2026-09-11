# Subsystem timing characterisation (BEA-37)

Subsystems map onto the existing RTL integration ladder (composition modules), so each row is a real post-route measurement of the composed netlist.

| subsystem | module | kind | fmax_mhz | worst_slack_ns | lut4 | ff | ebr18 | mult18x18d |
|---|---|---|---|---|---|---|---|---|
| receiver_dsp_core | engeler_detector | composition | 30.671 | -24.604 | 9932 | 3752 | 0 | 28 |

## Critical paths

### receiver_dsp_core (engeler_detector) — 30.7 MHz

1. `dut.observables_i.detector_i.pm_i.state_1_TRELLIS_FF_Q_28` -> `dut.observables_i.detector_i.pm_i.overflow_TRELLIS_FF_Q` : 32.08 ns (logic 14.97 + route 17.11)
2. `sig_ctr_TRELLIS_FF_Q` -> `sig_o[15]$tr_io` : 6.25 ns (logic 0.24 + route 6.01)

