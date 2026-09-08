# État de qualification RTL

Cette matrice est factuelle : **✓** renvoie vers un artefact versionné qui
justifie la case. Une case **—** signifie qu'aucun artefact ou rapport conservé
ne permet encore de revendiquer ce niveau, même si un essai ponctuel a pu être
effectué. Les rapports produits en CI (versions, Yosys, budget, nextpnr et
formal) sont conservés comme artefacts du workflow [`rtl.yml`](../.github/workflows/rtl.yml).

| Bloc | Prévu | RTL présent | Test unitaire | Test d’intégration | Preuve formelle | Synthèse | Timing | Test FPGA | Test RF réel |
|---|---|---|---|---|---|---|---|---|---|
| Interface ADC | [✓](30-rtl-development-guide.md#étape-b--acquisition-adc-brute) | [✓](../rtl/platform/adc_if.sv) | [✓](../sim/adc_if_tb.sv) | — | — | — | — | — | — |
| Ordonnanceur d’échantillons | [✓](30-rtl-development-guide.md#étape-b--acquisition-adc-brute) | [✓](../rtl/core/sample_scheduler.sv) | — | — | — | — | — | — | — |
| Banque Goertzel | [✓](30-rtl-development-guide.md#étape-d--détection-porteuse-et-am) | [✓](../rtl/goertzel/engeler_goertzel_bank.sv) | [✓](../sim/engeler_goertzel_bank_tb.sv) | [✓](../sim/engeler_observables_tb.sv) | — | — | — | — | — |
| Extraction AM | [✓](30-rtl-development-guide.md#étape-d--détection-porteuse-et-am) | [✓](../rtl/am/am_bit_extractor.sv) | [✓](../sim/am_bit_extractor_tb.sv) | — | — | — | — | — | — |
| Générateur PRN DCF77 | [✓](30-rtl-development-guide.md#étape-e--détection-pm-et-synchronisation) | [✓](../rtl/pm/dcf77_prn_generator.sv) | [✓](../sim/dcf77_prn_generator_tb.sv) | [✓](../sim/engeler_pm_pipeline_tb.sv) | — | — | — | — | — |
| Corrélateur et pipeline PM | [✓](30-rtl-development-guide.md#étape-e--détection-pm-et-synchronisation) | [✓](../rtl/pm/engeler_pm_pipeline.sv) | [✓](../sim/engeler_pm_correlator_tb.sv) | [✓](../sim/engeler_pm_pipeline_tb.sv) | — | — | — | — | — |
| Synchronisation minute | [✓](30-rtl-development-guide.md#étape-e--détection-pm-et-synchronisation) | [✓](../rtl/sync/pm_minute_sync.sv) | [✓](../sim/pm_minute_sync_tb.sv) | — | — | — | — | — | — |
| Recherche ML minute/heure | [✓](30-rtl-development-guide.md#étape-f--décodeur-temporel-ml) | [✓](../rtl/ml_decoder/minute_candidate_search.sv) | [✓](../sim/minute_candidate_search_tb.sv) | — | — | — | — | — | — |
| PPS | [✓](30-rtl-development-guide.md#étape-g--discipline-dhorloge-et-produit-final) | [✓](../rtl/core/pps_generator.sv) | [✓](../sim/pps_generator_tb.sv) | [✓](../sim/time_telemetry_tb.sv) | — | — | — | — | — |
| Télémétrie UART | [✓](30-rtl-development-guide.md#étape-g--discipline-dhorloge-et-produit-final) | [✓](../rtl/core/time_telemetry.sv) | [✓](../sim/time_telemetry_tb.sv) | [✓](../sim/uart_tx_tb.sv) | — | — | — | — | — |
| Cœur intégré | [✓](30-rtl-development-guide.md#étape-g--discipline-dhorloge-et-produit-final) | [✓](../rtl/core/engeler_detector.sv) | — | [✓](../sim/engeler_pm_pipeline_tb.sv) | — | — | — | — | — |

Les colonnes synthèse, timing et preuve ne seront cochées qu'après ajout au
dépôt d'un rapport de référence identifié (révision, cible et versions), et non
sur la seule existence d'une commande CI. De même, un test FPGA ou RF exige une
trace de banc versionnée et ses conditions de mesure.
