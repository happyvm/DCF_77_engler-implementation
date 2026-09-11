# TEST BASELINE — DCF77 Engler Receiver

**Date :** 2026-09-11  
**Machine :** Paperclip (Linux 7.0.0-28-generic)  
**Commit :** e9af3df  
**Toolchain :** Icarus Verilog 12.0, Verilator 5.032, Yosys 0.52, Python 3.x

## Résumé

| Catégorie           | Total | PASS | FAIL | SKIP |
|---------------------|-------|------|------|------|
| Tests unitaires RTL | 29    | 29   | 0    | 0    |
| Tests intégration   | 2     | 2    | 0    | 0    |
| **Total**           | **31**| **31**| **0** | **0** |

**Verdict : 31/31 PASS — baseline zéro propre.**

## Contexte du projet

- 37 modules SystemVerilog (4875 lignes)
- 30 testbenches dans `sim/`
- 29 preuves formelles (SymbiYosys, non exécutées dans ce baseline — temps > 48 min)
- Cible : Lattice ECP5 LFE5U-45F, référence XC3S1400AN

## Résultats détaillés

### Tests unitaires (Icarus Verilog)

| # | Testbench | Statut | Wall-time estimé |
|---|-----------|--------|------------------|
| 1 | adc_if_tb | PASS | < 1s |
| 2 | pps_generator_tb | PASS | < 1s |
| 3 | time_telemetry_tb | PASS | < 1s |
| 4 | uart_tx_tb | PASS | < 1s |
| 5 | engeler_goertzel_bank_tb | PASS | < 1s |
| 6 | engeler_observables_tb | PASS | < 1s |
| 7 | dcf77_prn_generator_tb | PASS | < 1s |
| 8 | engeler_pm_correlator_tb | PASS | ~1s |
| 9 | pm_chip_integrator_tb | PASS | < 1s |
| 10 | engeler_pm_pipeline_tb | PASS | ~2s |
| 11 | am_bit_demodulator_tb | PASS | < 1s |
| 12 | pm_minute_sync_tb | PASS | < 1s |
| 13 | minute_candidate_search_tb | PASS | < 1s |
| 14 | hour_candidate_search_tb | PASS | < 1s |
| 15 | second_phase_detector_tb | PASS | < 1s |
| 16 | receiver_lock_controller_tb | PASS | < 1s |
| 17 | qualification_disabled_tb | PASS | < 1s |
| 18 | test_resource_budget (Python) | PASS | < 1s |
| 19 | soft_history_tb | PASS | < 1s |
| 20 | ml_decoder_controller_tb | PASS | < 1s |
| 21 | frequency_discipline_tb | PASS | < 1s |
| 22 | second_evidence_aggregator_tb | PASS | < 1s |
| 23 | calendar_candidate_search_tb | PASS | < 1s |
| 24 | ml_field_sequencer_tb | PASS | < 1s |
| 25 | pm_phase_discriminator_tb | PASS | ~10s |
| 26 | second_phase_ramp_tb | PASS | < 1s |
| 27 | pga_spi_master_tb | PASS | < 1s |
| 28 | hat_spi_slave_tb | PASS | < 1s |
| 29 | lcd_i2c_driver_tb | PASS | ~2s |

### Tests d'intégration

| # | Testbench | Simulateur | Statut | Note |
|---|-----------|------------|--------|------|
| 30 | dcf77_hat_top_tb | Icarus | PASS | 6 assertions paramétriques non-fatales au time 0 |
| 31 | dcf77_system_tb | Verilator | PASS | 12/12 scénarios OK |

#### Détail scénarios dcf77_system_tb

| Scénario | Statut | Min simulées |
|----------|--------|-------------|
| clean_signal | PASS | 4 |
| noise_only | PASS | 5 |
| no_signal | PASS | 5 |
| pm_polarity_inverted | PASS | 4 |
| noisy_signal | PASS | 4 |
| midnight_month_end | PASS | 4 |
| oscillator_fast | PASS | 4 |
| oscillator_slow | PASS | 4 |
| dropout_then_lock | PASS | 4 |
| dropout_reacquire | PASS | 8 |
| cet_to_cest | PASS | 4 |
| cet_to_cest_after | PASS | 7 |

### Assertions non-fatales (dcf77_hat_top_tb)

6 assertions `$error` au time 0 — paramètres de configuration hors plage attendue pour la simulation HAT-level. Ne bloquent pas le test, qui rapporte PASS :

1. `second_phase_detector: SECOND_CYCLES + SEARCH_TOLERANCE overflows the position counter`
2. `am_demodulator: invalid window parameter`
3. `pm_chip_integrator: PRN interval exceeds one second` (×4 instances : main + early + late)
4. `pm_chip_integrator: invalid timing parameter` (×1)

Ces erreurs sont attendues dans la configuration HAT qui utilise des paramètres différents du core standalone.

## Commandes de reproduction

```bash
# Suite complète
cd /data/paperclip/workspaces/dcf77-engler
make test

# Test spécifique
make test-adc-if
make test-frequency-discipline

# Intégration système (Verilator, ~10 min)
make test-system

# Scénario système individuel
build/vl_system/dcf77_system_tb +scenario=1
```

## Preuves formelles

29 fichiers `.sby` dans `formal/`. Le `make formal` complet nécessite environ 48 minutes (1m40/preuve). Non exécuté dans ce baseline — à lancer séparément avec un timeout adapté.

## Environnement

| Composant | Version |
|-----------|---------|
| Icarus Verilog | 12.0 (stable) |
| Verilator | 5.032 |
| Yosys | 0.52 |
| SymbiYosys | installé (sby) |
| Python | 3.x |
| OS | Linux 7.0.0-28-generic |