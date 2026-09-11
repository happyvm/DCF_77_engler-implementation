# Block timing characterisation (BEA-37)

Target: LFE5U-45F-7BG256I speed grade -7, nextpnr-ecp5 --45k, clk target 125 MHz.

Post-route measurements from `nextpnr-ecp5 --report`. Raw records in `raw/`.

| module | kind | fmax_mhz | worst_slack_ns | lut4 | ff | ebr18 | mult18x18d | pll |
|---|---|---|---|---|---|---|---|---|
| sample_scheduler | low-rate-control | 141.323 | 0.924 | 161 | 138 | 0 | 0 | 0 |
| adc_if | io-interface | 211.372 | 3.269 | 93 | 137 | 0 | 0 | 0 |
| pga_spi_master | io-interface | 214.5 | 3.338 | 117 | 75 | 0 | 0 | 0 |
| goertzel_resonator | single-cycle | 34.661 | -20.851 | 544 | 183 | 0 | 6 | 0 |
| goertzel_complex_12 | single-cycle | 90.769 | -3.017 | 218 | 160 | 0 | 2 | 0 |
| engeler_goertzel_bank | single-cycle | 27.29 | -28.644 | 1595 | 451 | 0 | 18 | 0 |
| engeler_observables | composition | 28.062 | -27.636 | 2163 | 1051 | 0 | 28 | 0 |
| am_bit_extractor | multicycle | 70.338 | -6.217 | 891 | 447 | 0 | 0 | 0 |
| dcf77_prn_generator | low-rate-control | 346.26 | 5.112 | 70 | 65 | 0 | 0 | 0 |
| pm_prn_correlator | single-cycle | 112.385 | -0.898 | 248 | 172 | 0 | 0 | 0 |
| engeler_pm_correlator | single-cycle | 119.904 | -0.34 | 256 | 189 | 0 | 0 | 0 |
| pm_chip_integrator | multicycle | 96.909 | -2.319 | 444 | 297 | 0 | 0 | 0 |
| engeler_pm_pipeline | composition | 95.621 | -2.458 | 659 | 392 | 0 | 0 | 0 |
| pm_phase_discriminator | composition | 69.793 | -6.328 | 2185 | 1005 | 0 | 0 | 0 |
| second_phase_detector | low-rate-control | 59.748 | -8.737 | 1756 | 603 | 0 | 0 | 0 |
| pm_minute_sync | low-rate-control | 39.811 | -17.119 | 2097 | 810 | 0 | 0 | 0 |
| second_evidence_aggregator | single-cycle | 230.203 | 3.656 | 134 | 211 | 0 | 0 | 0 |
| soft_history | multicycle | 140.548 | 0.885 | 229 | 262 | 12 | 0 | 0 |
| ml_field_sequencer | composition | 41.693 | -15.985 | 3937 | 1348 | 0 | 0 | 0 |
| minute_candidate_search | multicycle | 39.673 | -17.206 | 1739 | 449 | 0 | 0 | 0 |
| hour_candidate_search | multicycle | 45.971 | -13.753 | 1694 | 415 | 0 | 0 | 0 |
| calendar_candidate_search | multicycle | 38.824 | -17.757 | 1893 | 397 | 0 | 0 | 0 |
| ml_decoder_controller | low-rate-control | 92.61 | -2.798 | 896 | 315 | 0 | 0 | 0 |
| receiver_lock_controller | low-rate-control | 165.865 | 1.971 | 106 | 55 | 0 | 0 | 0 |
| frequency_discipline | multicycle | 68.185 | -6.666 | 2167 | 1094 | 0 | 0 | 0 |
| pps_generator | low-rate-control | 219.829 | 3.451 | 101 | 60 | 0 | 0 | 0 |
| pps_uart | composition | 138.351 | 0.772 | 564 | 251 | 0 | 0 | 0 |
| time_telemetry | low-rate-control | 151.194 | 1.386 | 581 | 233 | 0 | 0 | 0 |
| uart_tx | io-interface | 229.2 | 3.637 | 102 | 68 | 0 | 0 | 0 |
| hat_spi_slave | io-interface | 111.148 | -0.997 | 515 | 253 | 0 | 0 | 0 |
| lcd_i2c_driver | io-interface | 29.347 | -26.075 | 1016 | 172 | 0 | 0 | 0 |
| i2c_master_byte | io-interface | 216.216 | 3.375 | 117 | 78 | 0 | 0 | 0 |
| engeler_detector | composition | 28.461 | -27.136 | 9967 | 3752 | 0 | 28 | 0 |
| dcf77_receiver_core | composition | 26.914 | -29.156 | 15564 | 5796 | 8 | 28 | 0 |
| dcf77_hat_top | composition | 28.914 | -26.585 | 17253 | 6178 | 8 | 28 | 1 |

## Timing health (indicative, clk_sys = 125 MHz)

Bands: >=200 excellent, 175-200 very-good, 150-175 acceptable, 125-150 weak, <125 failing.  Multicycle / low-rate-control blocks are annotated, not failed, on an isolated slow path.

- `dcf77_receiver_core`: 26.9 MHz — failing (single-cycle)
- `engeler_goertzel_bank`: 27.3 MHz — failing (single-cycle)
- `engeler_observables`: 28.1 MHz — failing (single-cycle)
- `engeler_detector`: 28.5 MHz — failing (single-cycle)
- `dcf77_hat_top`: 28.9 MHz — failing (single-cycle)
- `lcd_i2c_driver`: 29.3 MHz — failing (single-cycle)
- `goertzel_resonator`: 34.7 MHz — failing (single-cycle)
- `calendar_candidate_search`: 38.8 MHz — failing (architectural-multicycle)
- `minute_candidate_search`: 39.7 MHz — failing (architectural-multicycle)
- `pm_minute_sync`: 39.8 MHz — failing (architectural-multicycle)
- `ml_field_sequencer`: 41.7 MHz — failing (single-cycle)
- `hour_candidate_search`: 46.0 MHz — failing (architectural-multicycle)
- `second_phase_detector`: 59.7 MHz — failing (architectural-multicycle)
- `frequency_discipline`: 68.2 MHz — failing (architectural-multicycle)
- `pm_phase_discriminator`: 69.8 MHz — failing (single-cycle)
- `am_bit_extractor`: 70.3 MHz — failing (architectural-multicycle)
- `goertzel_complex_12`: 90.8 MHz — failing (single-cycle)
- `ml_decoder_controller`: 92.6 MHz — failing (architectural-multicycle)
- `engeler_pm_pipeline`: 95.6 MHz — failing (single-cycle)
- `pm_chip_integrator`: 96.9 MHz — failing (architectural-multicycle)
- `hat_spi_slave`: 111.1 MHz — failing (single-cycle)
- `pm_prn_correlator`: 112.4 MHz — failing (single-cycle)
- `engeler_pm_correlator`: 119.9 MHz — failing (single-cycle)
- `pps_uart`: 138.4 MHz — weak (single-cycle)
- `soft_history`: 140.5 MHz — weak (architectural-multicycle)
- `sample_scheduler`: 141.3 MHz — weak (architectural-multicycle)
- `time_telemetry`: 151.2 MHz — acceptable (architectural-multicycle)
- `receiver_lock_controller`: 165.9 MHz — acceptable (architectural-multicycle)
- `adc_if`: 211.4 MHz — excellent (single-cycle)
- `pga_spi_master`: 214.5 MHz — excellent (single-cycle)
- `i2c_master_byte`: 216.2 MHz — excellent (single-cycle)
- `pps_generator`: 219.8 MHz — excellent (architectural-multicycle)
- `uart_tx`: 229.2 MHz — excellent (single-cycle)
- `second_evidence_aggregator`: 230.2 MHz — excellent (single-cycle)
- `dcf77_prn_generator`: 346.3 MHz — excellent (architectural-multicycle)

## Critical paths (post-route, per block)

### dcf77_receiver_core — 26.9 MHz (composition)

1. `dut.detector_i.observables_i.detector_i.am_i.state_1_TRELLIS_FF_Q_10` -> `dut.detector_i.observables_i.detector_i.am_i.state_1_TRELLIS_FF_Q_17` : 36.63 ns (logic 14.78 + route 21.85, 153 segs)
2. `sig_q_TRELLIS_FF_Q_1` -> `sig_o[14]$tr_io` : 5.54 ns (logic 0.24 + route 5.30, 4 segs)

### engeler_goertzel_bank — 27.3 MHz (single-cycle)

1. `dut.pm_i.state_1_TRELLIS_FF_Q_15` -> `dut.pm_i.state_1_TRELLIS_FF_Q_5` : 36.12 ns (logic 15.67 + route 20.45, 153 segs)
2. `sig_q_TRELLIS_FF_Q_3` -> `sig_o[12]$tr_io` : 6.11 ns (logic 0.24 + route 5.88, 4 segs)

### engeler_observables — 28.1 MHz (composition)

1. `dut.detector_i.carrier_i.state_1_TRELLIS_FF_Q_19` -> `dut.detector_i.carrier_i.overflow_TRELLIS_FF_Q` : 35.11 ns (logic 15.08 + route 20.04, 155 segs)
2. `sig_ctr_TRELLIS_FF_Q_8` -> `sig_o[7]$tr_io` : 5.08 ns (logic 0.24 + route 4.84, 4 segs)

### engeler_detector — 28.5 MHz (composition)

1. `dut.observables_i.detector_i.pm_i.state_1_TRELLIS_FF_Q_15` -> `dut.observables_i.detector_i.pm_i.overflow_TRELLIS_FF_Q` : 34.61 ns (logic 14.93 + route 19.68, 149 segs)
2. `sig_ctr_TRELLIS_FF_Q_1` -> `sig_o[14]$tr_io` : 7.14 ns (logic 0.24 + route 6.91, 4 segs)

### dcf77_hat_top — 28.9 MHz (composition)

1. `core_i.detector_i.observables_i.detector_i.carrier_i.state_1_TRELLIS_FF_Q_29` -> `core_i.detector_i.observables_i.detector_i.carrier_i.overflow_TRELLIS_FF_Q` : 34.06 ns (logic 14.67 + route 19.39, 131 segs)
2. `reset_n$tr_io` -> `reset_n_LUT4_D_Z_TRELLIS_FF_LSR_2` : 6.54 ns (logic 0.24 + route 6.30, 5 segs)
3. `adc_i.sample_valid_TRELLIS_FF_Q` -> `diag_sample_valid$tr_io` : 6.19 ns (logic 0.00 + route 6.19, 2 segs)

### lcd_i2c_driver — 29.3 MHz (io-interface)

1. `dut.pos_TRELLIS_FF_Q_3` -> `dut.state_TRELLIS_FF_Q_2` : 33.55 ns (logic 13.23 + route 20.32, 117 segs)
2. `sig_ctr_TRELLIS_FF_Q_7` -> `sig_o[8]$tr_io` : 6.37 ns (logic 0.24 + route 6.13, 4 segs)

### goertzel_resonator — 34.7 MHz (single-cycle)

1. `dut.state_1_TRELLIS_FF_Q_6` -> `dut.state_1_TRELLIS_FF_Q_14` : 28.33 ns (logic 14.40 + route 13.93, 139 segs)
2. `sig_q_TRELLIS_FF_Q_7` -> `sig_o[8]$tr_io` : 5.64 ns (logic 0.24 + route 5.40, 4 segs)

### calendar_candidate_search — 38.8 MHz (multicycle)

1. `dut.candidate_TRELLIS_FF_Q_5` -> `dut.quality_gap_TRELLIS_FF_Q_1` : 25.23 ns (logic 9.72 + route 15.51, 119 segs)
2. `sig_q_TRELLIS_FF_Q_10` -> `sig_o[5]$tr_io` : 5.07 ns (logic 0.24 + route 4.83, 4 segs)

### minute_candidate_search — 39.7 MHz (multicycle)

1. `dut.candidate_TRELLIS_FF_Q_4` -> `dut.quality_gap_TRELLIS_FF_Q_1` : 24.68 ns (logic 9.14 + route 15.54, 139 segs)
2. `sig_ctr_TRELLIS_FF_Q_5` -> `sig_o[10]$tr_io` : 5.06 ns (logic 0.24 + route 4.83, 4 segs)

### pm_minute_sync — 39.8 MHz (low-rate-control)

1. `dut.history[10]_TRELLIS_FF_Q_7` -> `dut.quality_gap_TRELLIS_FF_Q` : 24.59 ns (logic 8.54 + route 16.06, 131 segs)
2. `sig_q_TRELLIS_FF_Q_14` -> `sig_o[1]$tr_io` : 5.65 ns (logic 0.24 + route 5.42, 4 segs)

### ml_field_sequencer — 41.7 MHz (composition)

1. `dut.minute_i.candidate_TRELLIS_FF_Q_4` -> `dut.minute_i.quality_gap_TRELLIS_FF_Q_1` : 23.46 ns (logic 8.71 + route 14.75, 107 segs)
2. `sig_ctr_TRELLIS_FF_Q_6` -> `sig_o[9]$tr_io` : 5.30 ns (logic 0.24 + route 5.07, 4 segs)

### hour_candidate_search — 46.0 MHz (multicycle)

1. `dut.evidence[1]_TRELLIS_FF_Q_23` -> `dut.quality_gap_TRELLIS_FF_Q` : 21.23 ns (logic 8.35 + route 12.88, 127 segs)
2. `sig_ctr_TRELLIS_FF_Q_8` -> `sig_o[7]$tr_io` : 6.40 ns (logic 0.24 + route 6.17, 4 segs)

### second_phase_detector — 59.7 MHz (low-rate-control)

1. `dut.magnitude_q_TRELLIS_FF_Q_65` -> `dut.missed_seconds_TRELLIS_FF_Q_1` : 15.79 ns (logic 5.47 + route 10.32, 153 segs)
2. `sig_ctr_TRELLIS_FF_Q` -> `sig_o[15]$tr_io` : 5.33 ns (logic 0.24 + route 5.09, 4 segs)

### frequency_discipline — 68.2 MHz (multicycle)

1. `sig_phase_error_TRELLIS_FF_Q_22` -> `dut.accepted_count_TRELLIS_FF_Q_3` : 13.72 ns (logic 5.71 + route 8.00, 141 segs)
2. `sig_ctr_TRELLIS_FF_Q_4` -> `sig_o[11]$tr_io` : 5.13 ns (logic 0.24 + route 4.90, 4 segs)

### pm_phase_discriminator — 69.8 MHz (composition)

1. `dut.early_i.correlator_i.correlator_i.correlation_TRELLIS_FF_Q_39` -> `dut.div_dividend_TRELLIS_FF_Q_14` : 13.80 ns (logic 5.23 + route 8.57, 81 segs)
2. `sig_ctr_TRELLIS_FF_Q_2` -> `sig_o[13]$tr_io` : 5.74 ns (logic 0.24 + route 5.51, 4 segs)

### am_bit_extractor — 70.3 MHz (multicycle)

1. `sig_am_observable_TRELLIS_FF_Q_66` -> `dut.am_soft_bit_TRELLIS_FF_Q_25` : 13.69 ns (logic 6.69 + route 7.00, 177 segs)
2. `sig_q_TRELLIS_FF_Q_8` -> `sig_o[7]$tr_io` : 5.47 ns (logic 0.24 + route 5.23, 4 segs)

### goertzel_complex_12 — 90.8 MHz (single-cycle)

1. `sig_state_2_TRELLIS_FF_Q_10` -> `sig_bin_real_q_TRELLIS_FF_Q` : 10.49 ns (logic 6.59 + route 3.90, 65 segs)
2. `sig_q_TRELLIS_FF_Q_5` -> `sig_o[10]$tr_io` : 6.43 ns (logic 0.24 + route 6.19, 4 segs)

### ml_decoder_controller — 92.6 MHz (low-rate-control)

1. `dut.minute_TRELLIS_FF_Q_5` -> `dut.alt_month_TRELLIS_FF_Q_2` : 10.27 ns (logic 2.75 + route 7.52, 25 segs)
2. `sig_ctr_TRELLIS_FF_Q_13` -> `sig_o[2]$tr_io` : 5.32 ns (logic 0.24 + route 5.08, 4 segs)

### engeler_pm_pipeline — 95.6 MHz (composition)

1. `dut.integrator_i.chip_accumulator_TRELLIS_FF_Q_73` -> `dut.integrator_i.chip_soft_TRELLIS_FF_Q_31` : 9.93 ns (logic 5.39 + route 4.54, 159 segs)
2. `sig_ctr_TRELLIS_FF_Q_8` -> `sig_o[7]$tr_io` : 5.46 ns (logic 0.24 + route 5.22, 4 segs)

### pm_chip_integrator — 96.9 MHz (multicycle)

1. `sig_pm_observable_TRELLIS_FF_Q_66` -> `dut.chip_soft_TRELLIS_FF_Q_20` : 9.79 ns (logic 5.39 + route 4.40, 159 segs)
2. `sig_q_TRELLIS_FF_Q_5` -> `sig_o[10]$tr_io` : 5.26 ns (logic 0.24 + route 5.03, 4 segs)

### hat_spi_slave — 111.1 MHz (io-interface)

1. `dut.rx_shift_TRELLIS_FF_Q_1` -> `dut.tx_shift_TRELLIS_FF_Q_3` : 8.47 ns (logic 1.67 + route 6.80, 17 segs)
2. `sig_q_TRELLIS_FF_Q_14` -> `sig_o[1]$tr_io` : 5.52 ns (logic 0.24 + route 5.28, 4 segs)

### pm_prn_correlator — 112.4 MHz (single-cycle)

1. `sig_pm_soft_TRELLIS_FF_Q_14` -> `dut.accumulator_TRELLIS_FF_Q` : 8.37 ns (logic 3.19 + route 5.18, 59 segs)
2. `sig_q_TRELLIS_FF_Q_12` -> `sig_o[3]$tr_io` : 5.42 ns (logic 0.24 + route 5.19, 4 segs)

### engeler_pm_correlator — 119.9 MHz (single-cycle)

1. `sig_pm_soft_TRELLIS_FF_Q_12` -> `dut.correlator_i.accumulator_TRELLIS_FF_Q_3` : 7.82 ns (logic 3.09 + route 4.73, 51 segs)
2. `sig_ctr_TRELLIS_FF_Q_10` -> `sig_o[5]$tr_io` : 5.27 ns (logic 0.24 + route 5.04, 4 segs)

### pps_uart — 138.4 MHz (composition)

1. `dut.formatter_i.byte_index_TRELLIS_FF_Q_1` -> `dut.uart_i.shift_reg_TRELLIS_FF_Q_8` : 6.70 ns (logic 1.46 + route 5.24, 15 segs)
2. `sig_ctr_TRELLIS_FF_Q_15` -> `sig_o[0]$tr_io` : 5.11 ns (logic 0.24 + route 4.87, 4 segs)

### soft_history — 140.5 MHz (multicycle)

1. `dut.memory.0.1` -> `sig_read_second_position_q_TRELLIS_FF_Q` : 1.28 ns (logic 0.24 + route 1.05, 5 segs)
2. `sig_ctr_TRELLIS_FF_Q_15` -> `sig_o[0]$tr_io` : 5.33 ns (logic 0.24 + route 5.10, 4 segs)

### sample_scheduler — 141.3 MHz (low-rate-control)

1. `sig_trim_inc_TRELLIS_FF_Q_23` -> `dut.sample_ce_TRELLIS_FF_Q` : 6.55 ns (logic 3.22 + route 3.33, 83 segs)
2. `sig_ctr_TRELLIS_FF_Q_3` -> `sig_o[12]$tr_io` : 5.01 ns (logic 0.24 + route 4.78, 4 segs)

### time_telemetry — 151.2 MHz (low-rate-control)

1. `dut.byte_index_TRELLIS_FF_Q_2` -> `dut.checksum_TRELLIS_FF_Q_5` : 6.09 ns (logic 1.63 + route 4.46, 17 segs)
2. `sig_ctr_TRELLIS_FF_Q_12` -> `sig_o[3]$tr_io` : 5.20 ns (logic 0.24 + route 4.96, 4 segs)

### receiver_lock_controller — 165.9 MHz (low-rate-control)

1. `dut.holdover_count_TRELLIS_FF_Q_5` -> `dut.holdover_count_TRELLIS_FF_Q_4` : 5.08 ns (logic 1.91 + route 3.17, 23 segs)
2. `sig_ctr_TRELLIS_FF_Q_14` -> `sig_o[1]$tr_io` : 4.91 ns (logic 0.24 + route 4.67, 4 segs)

### adc_if — 211.4 MHz (io-interface)

1. `dut.bit_count_TRELLIS_FF_Q_3` -> `dut.ch0_sample_TRELLIS_FF_Q_3` : 4.21 ns (logic 0.71 + route 3.50, 9 segs)
2. `sig_ctr_TRELLIS_FF_Q_6` -> `sig_o[9]$tr_io` : 5.15 ns (logic 0.24 + route 4.91, 4 segs)

### pga_spi_master — 214.5 MHz (io-interface)

1. `dut.bit_index_TRELLIS_FF_Q` -> `dut.shift_word_TRELLIS_FF_Q` : 3.71 ns (logic 1.11 + route 2.60, 13 segs)
2. `sig_ctr_TRELLIS_FF_Q_14` -> `sig_o[1]$tr_io` : 4.93 ns (logic 0.24 + route 4.70, 4 segs)

### i2c_master_byte — 216.2 MHz (io-interface)

1. `dut.q_TRELLIS_FF_Q_5` -> `dut.done_TRELLIS_FF_Q` : 3.68 ns (logic 0.73 + route 2.95, 9 segs)
2. `sig_q_TRELLIS_FF_Q_14` -> `sig_o[1]$tr_io` : 5.16 ns (logic 0.24 + route 4.92, 4 segs)

### pps_generator — 219.8 MHz (low-rate-control)

1. `dut.pulse_count_TRELLIS_FF_Q_23` -> `dut.pulse_count_TRELLIS_FF_Q_9` : 4.02 ns (logic 1.80 + route 2.23, 49 segs)
2. `sig_ctr_TRELLIS_FF_Q` -> `sig_o[15]$tr_io` : 4.86 ns (logic 0.24 + route 4.63, 4 segs)

### uart_tx — 229.2 MHz (io-interface)

1. `dut.baud_count_TRELLIS_FF_Q` -> `dut.shift_reg_TRELLIS_FF_Q_1` : 3.41 ns (logic 0.71 + route 2.71, 9 segs)
2. `sig_ctr_TRELLIS_FF_Q_13` -> `sig_o[2]$tr_io` : 5.77 ns (logic 0.24 + route 5.53, 4 segs)

### second_evidence_aggregator — 230.2 MHz (single-cycle)

1. `sig_pm_evidence_q_TRELLIS_FF_Q_12` -> `sig_q_TRELLIS_FF_Q_15` : 3.82 ns (logic 0.73 + route 3.09, 9 segs)
2. `sig_ctr_TRELLIS_FF_Q_14` -> `sig_o[1]$tr_io` : 5.10 ns (logic 0.24 + route 4.87, 4 segs)

### dcf77_prn_generator — 346.3 MHz (low-rate-control)

1. `sig_chip_index_q_TRELLIS_FF_Q` -> `sig_q_TRELLIS_FF_Q_15` : 2.36 ns (logic 0.64 + route 1.73, 7 segs)
2. `sig_q_TRELLIS_FF_Q_4` -> `sig_o[11]$tr_io` : 5.03 ns (logic 0.24 + route 4.79, 4 segs)


## Summary

### 10 slowest blocks

- `dcf77_receiver_core`: 26.9 MHz (composition)
- `engeler_goertzel_bank`: 27.3 MHz (single-cycle)
- `engeler_observables`: 28.1 MHz (composition)
- `engeler_detector`: 28.5 MHz (composition)
- `dcf77_hat_top`: 28.9 MHz (composition)
- `lcd_i2c_driver`: 29.3 MHz (io-interface)
- `goertzel_resonator`: 34.7 MHz (single-cycle)
- `calendar_candidate_search`: 38.8 MHz (multicycle)
- `minute_candidate_search`: 39.7 MHz (multicycle)
- `pm_minute_sync`: 39.8 MHz (low-rate-control)

### Largest LUT consumers

- `dcf77_hat_top`: 17253 LUT4
- `dcf77_receiver_core`: 15564 LUT4
- `engeler_detector`: 9967 LUT4
- `ml_field_sequencer`: 3937 LUT4
- `pm_phase_discriminator`: 2185 LUT4
- `frequency_discipline`: 2167 LUT4
- `engeler_observables`: 2163 LUT4
- `pm_minute_sync`: 2097 LUT4
- `calendar_candidate_search`: 1893 LUT4
- `second_phase_detector`: 1756 LUT4

### Largest DSP consumers

- `engeler_observables`: 28 MULT18X18D
- `engeler_detector`: 28 MULT18X18D
- `dcf77_receiver_core`: 28 MULT18X18D
- `dcf77_hat_top`: 28 MULT18X18D
- `engeler_goertzel_bank`: 18 MULT18X18D
- `goertzel_resonator`: 6 MULT18X18D
- `goertzel_complex_12`: 2 MULT18X18D
- `sample_scheduler`: 0 MULT18X18D
- `adc_if`: 0 MULT18X18D
- `pga_spi_master`: 0 MULT18X18D

### Largest RAM consumers

- `soft_history`: 12 EBR18
- `dcf77_receiver_core`: 8 EBR18
- `dcf77_hat_top`: 8 EBR18
- `sample_scheduler`: 0 EBR18
- `adc_if`: 0 EBR18
- `pga_spi_master`: 0 EBR18
- `goertzel_resonator`: 0 EBR18
- `goertzel_complex_12`: 0 EBR18
- `engeler_goertzel_bank`: 0 EBR18
- `engeler_observables`: 0 EBR18
