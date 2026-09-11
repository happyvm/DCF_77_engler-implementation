# Subsystem timing characterisation (BEA-37)

Subsystems map onto the existing RTL integration ladder (composition modules), so each row is a real post-route measurement of the composed netlist.

| subsystem | module | kind | fmax_mhz | worst_slack_ns | lut4 | ff | ebr18 | mult18x18d |
|---|---|---|---|---|---|---|---|---|
| goertzel_observables | engeler_observables | composition | 28.062 | -27.636 | 2163 | 1051 | 0 | 28 |
| receiver_dsp_core | engeler_detector | composition | 28.461 | -27.136 | 9967 | 3752 | 0 | 28 |
| ml_decode_subsystem | ml_field_sequencer | composition | 41.693 | -15.985 | 3937 | 1348 | 0 | 0 |
| frequency_discipline_subsystem | frequency_discipline | multicycle | 68.185 | -6.666 | 2167 | 1094 | 0 | 0 |
| full_receiver_core | dcf77_receiver_core | composition | 26.914 | -29.156 | 15564 | 5796 | 8 | 28 |
| full_hat_top | dcf77_hat_top | composition | 28.914 | -26.585 | 17253 | 6178 | 8 | 28 |

## Critical paths

### full_receiver_core (dcf77_receiver_core) — 26.9 MHz

1. `dut.detector_i.observables_i.detector_i.am_i.state_1_TRELLIS_FF_Q_10` -> `dut.detector_i.observables_i.detector_i.am_i.state_1_TRELLIS_FF_Q_17` : 36.63 ns (logic 14.78 + route 21.85)
2. `sig_q_TRELLIS_FF_Q_1` -> `sig_o[14]$tr_io` : 5.54 ns (logic 0.24 + route 5.30)

### goertzel_observables (engeler_observables) — 28.1 MHz

1. `dut.detector_i.carrier_i.state_1_TRELLIS_FF_Q_19` -> `dut.detector_i.carrier_i.overflow_TRELLIS_FF_Q` : 35.11 ns (logic 15.08 + route 20.04)
2. `sig_ctr_TRELLIS_FF_Q_8` -> `sig_o[7]$tr_io` : 5.08 ns (logic 0.24 + route 4.84)

### receiver_dsp_core (engeler_detector) — 28.5 MHz

1. `dut.observables_i.detector_i.pm_i.state_1_TRELLIS_FF_Q_15` -> `dut.observables_i.detector_i.pm_i.overflow_TRELLIS_FF_Q` : 34.61 ns (logic 14.93 + route 19.68)
2. `sig_ctr_TRELLIS_FF_Q_1` -> `sig_o[14]$tr_io` : 7.14 ns (logic 0.24 + route 6.91)

### full_hat_top (dcf77_hat_top) — 28.9 MHz

1. `core_i.detector_i.observables_i.detector_i.carrier_i.state_1_TRELLIS_FF_Q_29` -> `core_i.detector_i.observables_i.detector_i.carrier_i.overflow_TRELLIS_FF_Q` : 34.06 ns (logic 14.67 + route 19.39)
2. `reset_n$tr_io` -> `reset_n_LUT4_D_Z_TRELLIS_FF_LSR_2` : 6.54 ns (logic 0.24 + route 6.30)
3. `adc_i.sample_valid_TRELLIS_FF_Q` -> `diag_sample_valid$tr_io` : 6.19 ns (logic 0.00 + route 6.19)

### ml_decode_subsystem (ml_field_sequencer) — 41.7 MHz

1. `dut.minute_i.candidate_TRELLIS_FF_Q_4` -> `dut.minute_i.quality_gap_TRELLIS_FF_Q_1` : 23.46 ns (logic 8.71 + route 14.75)
2. `sig_ctr_TRELLIS_FF_Q_6` -> `sig_o[9]$tr_io` : 5.30 ns (logic 0.24 + route 5.07)

### frequency_discipline_subsystem (frequency_discipline) — 68.2 MHz

1. `sig_phase_error_TRELLIS_FF_Q_22` -> `dut.accepted_count_TRELLIS_FF_Q_3` : 13.72 ns (logic 5.71 + route 8.00)
2. `sig_ctr_TRELLIS_FF_Q_4` -> `sig_o[11]$tr_io` : 5.13 ns (logic 0.24 + route 4.90)

