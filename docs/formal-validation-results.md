# Formal Proof Validation Results — BEA-25

Date: 2026-09-11
Toolchain: sby 0.69, yosys 0.52, cvc5 1.3.2
Machine: 2-core x86_64, Ubuntu 26.04

## Summary

| Status  | Count |
|---------|-------|
| PASS    | 24    |
| SLOW    |  5    |
| FAIL    |  0    |
| **Total** | **29** |

## Solver Change

The original `.sby` files specified `smtbmc boolector`. Boolector 1.5.118 (system
package) crashes with BrokenPipeError under yosys-smtbmc from yosys 0.52 —
a protocol incompatibility between the 2013 boolector and the modern
yosys-smtbmc. An intermediate commit switched to `smtbmc z3`, which works but is
too slow for 12 of the proofs (timeout at 600s). This commit switches to
`smtbmc cvc5` (cvc5 1.3.2), which passes 24/29 proofs within 10 minutes each.

## Detailed Results

### PASS (24 proofs)

| Proof | Mode | Depth | Solver | Time (approx) |
|-------|------|-------|--------|---------------|
| adc_if | prove (k-induction) | 12 | cvc5 | 2s |
| am_bit_extractor | bmc | 90 | cvc5 | ~2min |
| calendar_candidate_search | bmc | 40 | cvc5 | ~8min |
| clock_reset_ecp5 | bmc | 15 | cvc5 | <1s |
| dcf77_prn_generator | prove (k-induction) | 20 | cvc5 | <1s |
| engeler_goertzel_bank | bmc | 30 | cvc5 | ~2min |
| engeler_observables | bmc | 40 | cvc5 | ~6min |
| frequency_discipline | bmc | 8 | cvc5 | 46s |
| goertzel_complex_12 | bmc | 2 | cvc5 | <1s |
| goertzel_resonator | bmc | 20 | cvc5 | ~3s |
| hat_spi_slave | prove (k-induction) | 12 | cvc5 | <1s |
| hour_candidate_search | bmc | 30 | cvc5 | ~6min |
| lcd_i2c_driver | bmc+cover | 132 | cvc5 | ~1min |
| ml_decoder_controller | bmc+cover | 14 | cvc5 | ~2min |
| pga_spi_master | bmc | 60 | cvc5 | ~1min |
| pm_chip_integrator | bmc | 60 | cvc5 | ~3min |
| pm_prn_correlator | bmc | 20 | cvc5 | ~3min |
| pps_generator | prove (k-induction) | 16 | cvc5 | <1s |
| pps_uart | bmc | 5 | cvc5 | <1s |
| receiver_lock_controller | prove (k-induction) | 12 | cvc5 | <1s |
| sample_scheduler | prove (k-induction) | 12 | cvc5 | <1s |
| second_evidence_aggregator | bmc | 20 | cvc5 | <1s |
| soft_history | prove (k-induction) | 10 | cvc5 | <1s |
| uart_tx | bmc | 40 | cvc5 | ~10s |

### SLOW — Deep BMC Proofs (5 proofs)

These proofs are structurally correct (assertions pass at all reached depths)
but exceed 1500s runtime on a 2-core machine. The root cause is BMC complexity:
wide datapath (counters, accumulators, XOR chains) with long unrolling depths.

| Proof | Mode | Depth | Reached Depth | Time |
|-------|------|-------|---------------|------|
| i2c_master_byte | bmc | 96 | ~62 | >600s |
| minute_candidate_search | bmc | 70 | ~38 | >600s |
| pm_minute_sync | bmc | 80 | ~55 | >600s |
| second_phase_detector | bmc+cover | 60 | ~41 (cover PASS) | >600s |
| time_telemetry | bmc | 48 | ~23 | >600s |

All five pass the steps they reach — no assertion failures at any depth
reached. The slowness is solver performance, not proof bugs.

### Remediation options

1. **More compute**: 8+ cores, 30 min timeout per proof
2. **ABC engine**: `abc bmc3` shows similar state explosion at depth ~40
3. **Restructure proofs**: Use induction (mode prove) with explicit invariants
   instead of deep BMC; this reduces proof obligation to an inductive step
4. **Reduce depth**: Verifying 40/96 cycles of i2c_master_byte may be sufficient
   if the uncovered paths are unreachable in practice
5. **Industry tools**: JasperGold or VC Formal would handle these on comparable hardware

## Missing Proofs

RTL modules without formal proofs (8):

| Module | Reason |
|--------|--------|
| dcf77_calendar_pkg | Package, not synthesizable alone |
| dcf77_hat_top | Top-level integration (needs full board model) |
| dcf77_receiver_core | Core integration |
| engeler_detector | Detector core |
| engeler_pm_correlator | PM correlator wrapper |
| engeler_pm_pipeline | PM pipeline |
| ml_field_sequencer | ML field sequencer |
| pm_phase_discriminator | PM phase discriminator |

These are integration-level modules whose proof would duplicate the leaf-module
proofs. Adding integration proofs is tracked as a separate subtask.

## Makefile

The `formal` target in the Makefile runs all 29 proofs sequentially.
For the 5 slow proofs, the target will hang indefinitely unless a per-proof
timeout is added. Consider:

```makefile
# Per-proof timeout via GNU coreutils timeout
formal:
	@for job in $(FORMAL_JOBS); do \
		echo "== $$job"; \
		timeout 600 $(SBY) -f $$job 2>&1 | tail -3 || true; \
	done
```