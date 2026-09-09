# État de qualification RTL

Cette matrice est factuelle : **✓** renvoie vers un artefact versionné qui
justifie la case. Une case **—** signifie qu'aucun artefact ou rapport conservé
ne permet encore de revendiquer ce niveau, même si un essai ponctuel a pu être
effectué. Les rapports produits en CI (versions, Yosys, budget, nextpnr et
formal) sont conservés comme artefacts du workflow [`rtl.yml`](../.github/workflows/rtl.yml).

| Bloc | Prévu | RTL présent | Test unitaire | Test d’intégration | Preuve formelle | Synthèse | Timing | Test FPGA | Test RF réel |
|---|---|---|---|---|---|---|---|---|---|
| Interface ADC | [✓](30-rtl-development-guide.md#étape-b--acquisition-adc-brute) | [✓](../rtl/platform/adc_if.sv) | [✓](../sim/adc_if_tb.sv) | [✓](../sim/dcf77_hat_top_tb.sv) | [✓](../formal/adc_if.sby) | — | — | — | — |
| Ordonnanceur d’échantillons | [✓](30-rtl-development-guide.md#étape-b--acquisition-adc-brute) | [✓](../rtl/core/sample_scheduler.sv) | — | [✓](../sim/dcf77_hat_top_tb.sv) | [✓](../formal/sample_scheduler.sby) | — | — | — | — |
| Programmation PGA LTC6912 | [✓](22-ltc6912-pga.md) | [✓](../rtl/platform/pga_spi_master.sv) | [✓](../sim/pga_spi_master_tb.sv) | [✓](../sim/dcf77_hat_top_tb.sv) | [✓](../formal/pga_spi_master.sby) (borné) | — | — | — | — |
| Banque Goertzel | [✓](30-rtl-development-guide.md#étape-d--détection-porteuse-et-am) | [✓](../rtl/goertzel/engeler_goertzel_bank.sv) | [✓](../sim/engeler_goertzel_bank_tb.sv) | [✓](../sim/engeler_observables_tb.sv) | — | — | — | — | — |
| Extraction AM | [✓](30-rtl-development-guide.md#étape-d--détection-porteuse-et-am) | [✓](../rtl/am/am_bit_extractor.sv) | [✓](../sim/am_bit_extractor_tb.sv) | [✓](../sim/dcf77_system_tb.sv) | — | — | — | — | — |
| Synchronisation seconde (AM + PZF) | [✓](30-rtl-development-guide.md#étape-e--détection-pm-et-synchronisation) | [✓](../rtl/sync/second_phase_detector.sv) | [✓](../sim/second_phase_detector_tb.sv), [✓](../sim/second_phase_ramp_tb.sv) | [✓](../sim/dcf77_system_tb.sv) | [✓](../formal/second_phase_detector.sby) (borné + couverture) | — | — | — | — |
| Générateur PRN DCF77 | [✓](30-rtl-development-guide.md#étape-e--détection-pm-et-synchronisation) | [✓](../rtl/pm/dcf77_prn_generator.sv) | [✓](../sim/dcf77_prn_generator_tb.sv) | [✓](../sim/engeler_pm_pipeline_tb.sv) | — | — | — | — | — |
| Corrélateur et pipeline PM | [✓](30-rtl-development-guide.md#étape-e--détection-pm-et-synchronisation) | [✓](../rtl/pm/engeler_pm_pipeline.sv) | [✓](../sim/engeler_pm_correlator_tb.sv) | [✓](../sim/engeler_pm_pipeline_tb.sv) | — | — | — | — | — |
| Discriminateur de phase PZF (early/late) | [✓](10-dcf77-pm-prn.md) | [✓](../rtl/pm/pm_phase_discriminator.sv) | [✓](../sim/pm_phase_discriminator_tb.sv) | [✓](../sim/dcf77_system_tb.sv) | — | — | — | — | — |
| Synchronisation minute | [✓](30-rtl-development-guide.md#étape-e--détection-pm-et-synchronisation) | [✓](../rtl/sync/pm_minute_sync.sv) | [✓](../sim/pm_minute_sync_tb.sv) | [✓](../sim/dcf77_system_tb.sv) | [✓](../formal/pm_minute_sync.sby) (borné) | — | — | — | — |
| Agrégation AM/PM par seconde | [✓](04-time-decoder.md) | [✓](../rtl/ml_decoder/second_evidence_aggregator.sv) | [✓](../sim/second_evidence_aggregator_tb.sv) | [✓](../sim/dcf77_system_tb.sv) | [✓](../formal/second_evidence_aggregator.sby) (borné) | — | — | — | — |
| Historique soft | [✓](04-time-decoder.md) | [✓](../rtl/ml_decoder/soft_history.sv) | [✓](../sim/soft_history_tb.sv) | [✓](../sim/dcf77_system_tb.sv) | [✓](../formal/soft_history.sby) | — | — | — | — |
| Séquenceur de champs / recherche ML | [✓](36-ml-minute-search-rtl.md) | [✓](../rtl/ml_decoder/ml_field_sequencer.sv) | [✓](../sim/ml_field_sequencer_tb.sv) | [✓](../sim/dcf77_system_tb.sv) | — | — | — | — | — |
| Recherche ML minute/heure/calendrier | [✓](30-rtl-development-guide.md#étape-f--décodeur-temporel-ml) | [✓](../rtl/ml_decoder/minute_candidate_search.sv) | [✓](../sim/minute_candidate_search_tb.sv), [✓](../sim/hour_candidate_search_tb.sv), [✓](../sim/calendar_candidate_search_tb.sv) | [✓](../sim/dcf77_system_tb.sv) | [✓](../formal/minute_candidate_search.sby) (borné) | — | — | — | — |
| Contrôleur de continuité ML | [✓](04-time-decoder.md) | [✓](../rtl/ml_decoder/ml_decoder_controller.sv) | [✓](../sim/ml_decoder_controller_tb.sv) | [✓](../sim/dcf77_system_tb.sv) | — | — | — | — | — |
| Politique de verrouillage | [✓](30-rtl-development-guide.md#étape-g--discipline-dhorloge-et-produit-final) | [✓](../rtl/control/receiver_lock_controller.sv) | [✓](../sim/receiver_lock_controller_tb.sv) | [✓](../sim/dcf77_system_tb.sv) | [✓](../formal/receiver_lock_controller.sby) | — | — | — | — |
| Discipline de fréquence | [✓](13-ecp5-clock-discipline.md) | [✓](../rtl/clock_discipline/frequency_discipline.sv) | [✓](../sim/frequency_discipline_tb.sv) | [✓](../sim/dcf77_system_tb.sv) | [✓](../formal/frequency_discipline.sby) (borné) | — | — | — | — |
| PPS | [✓](30-rtl-development-guide.md#étape-g--discipline-dhorloge-et-produit-final) | [✓](../rtl/core/pps_generator.sv) | [✓](../sim/pps_generator_tb.sv) | [✓](../sim/dcf77_system_tb.sv) | [✓](../formal/pps_generator.sby) | — | — | — | — |
| Télémétrie UART | [✓](29-hat-uart-time.md) | [✓](../rtl/core/time_telemetry.sv) | [✓](../sim/time_telemetry_tb.sv) | [✓](../sim/uart_tx_tb.sv) | [✓](../formal/time_telemetry.sby), [✓](../formal/uart_tx.sby) (bornés) | — | — | — | — |
| Esclave SPI HAT (carte de registres) | [✓](27-ecp5-pin-plan-hat.md) | [✓](../rtl/platform/hat_spi_slave.sv) | [✓](../sim/hat_spi_slave_tb.sv) | [✓](../sim/dcf77_hat_top_tb.sv) | [✓](../formal/hat_spi_slave.sby) | — | — | — | — |
| Afficheur LCD I2C (ST7036) | [✓](24-lcd-display.md) | [✓](../rtl/platform/lcd_i2c_driver.sv) | [✓](../sim/lcd_i2c_driver_tb.sv) | [✓](../sim/dcf77_hat_top_tb.sv) | [✓](../formal/i2c_master_byte.sby) (moteur octet, borné) | — | — | — | — |
| Cœur récepteur (ADC → PPS/UART) | [✓](30-rtl-development-guide.md#étape-g--discipline-dhorloge-et-produit-final) | [✓](../rtl/core/dcf77_receiver_core.sv) | — | [✓](../sim/dcf77_system_tb.sv) (signal DCF77 synthétique, 10 scénarios) | — | — | — | — | — |
| Top HAT | [✓](27-ecp5-pin-plan-hat.md) | [✓](../rtl/top/dcf77_hat_top.sv) | — | [✓](../sim/dcf77_hat_top_tb.sv) | — | — | — | — | — |

Les colonnes synthèse, timing et preuve ne seront cochées qu'après ajout au
dépôt d'un rapport de référence identifié (révision, cible et versions), et non
sur la seule existence d'une commande CI. De même, un test FPGA ou RF exige une
trace de banc versionnée et ses conditions de mesure.
