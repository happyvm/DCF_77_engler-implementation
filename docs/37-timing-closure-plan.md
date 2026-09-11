# Plan de fermeture du timing `release_reference` à 125 MHz

Ce document suit le ticket **BEA-36**. Il consigne le baseline mesuré, les
optimisations effectuées, les résultats obtenus et l'architecture restant à
mettre en place pour atteindre l'objectif.

Toutes les mesures de ce document proviennent d'un **placement/routage réel**
`nextpnr-ecp5` (pas d'une estimation Yosys), sur `LFE5U-45F-7BG256I`,
`--45k --package CABGA256 --freq 125`, avec la contrainte de clock de
`synth/dcf77_hat_top.lpf`. La graine du placeur est fixée (`--seed 1` dans la
cible `make timing`) : sans cela la Fmax rapportée varie de plusieurs MHz entre
deux exécutions du même netlist et toute comparaison avant/après n'a pas de sens.

Chaîne d'outils : OSS CAD Suite 2025-02-13 (Yosys 0.50, nextpnr-ecp5 0.7,
Icarus 13, Verilator 5.032), comme la CI `.github/workflows/rtl.yml`. Les
mesures de cette section ont été reproduites sur le HEAD local (Yosys 0.52,
nextpnr-ecp5 0.9-3).

## 1. Baseline (commit `e25f05b`, avant modification)

| Mesure | Valeur |
|---|---|
| Fmax `clk_sys` (post-route) | **21,54 MHz** |
| Pire chemin registre→registre | **46,43 ns** |
| Fmax cible | 125 MHz (période 8 ns) |
| Slack pire chemin | ≈ −38,4 ns |
| LUT4 (logic) | 8 474 / 22 528 |
| FF | 5 359 / 22 528 |
| EBR18 | 8 / 32 |
| MULT18X18D | 30 / 32 |
| PLL | 1 |

**Le chemin critique réel n'était PAS `frequency_discipline`.** C'était
`core_i.field_seq_i.calendar_i` (`rtl/ml_decoder/calendar_candidate_search.sv`) :
`candidate` → `best_q` sur 46,43 ns. La cause : le score de chaque candidat était
accumulé dans une boucle **série** de neuf additions/soustractions signées
(pile de neuvième niveau), et le découpage décimal utilisait `candidate % 10` /
`candidate / 10`, ce qui a fait inférer un **réseau diviseur par constante** posé
directement sur le chemin.

Le routage domine le délai (≈ 29 ns de routage pour 17 ns de logique) : la chaîne
de retenue d'un additionneur se retrouve dispersée sur plusieurs colonnes. Le
design n'a par ailleurs **aucun plan de broches ni floorplan**
(`docs/27-ecp5-pin-plan-hat.md`), donc les I/O sont placées automatiquement.

## 2. Optimisations effectuées (commit `28ae137`)

### 2.1 Recherche ML (minute / heure / calendrier)

`minute_candidate_search`, `hour_candidate_search` et `calendar_candidate_search`
calculent tous `score = Σ_i ±evidence[i]`. L'ordre d'accumulation était une
chaîne de dépendance série de N additions de `SCORE_BITS` (19–20 bits).

L'addition en complément à deux étant **associative modulo 2^N**, sommer les
termes via un **arbre équilibré** est *bit-identique* au résultat série, mais
réduit la profondeur de N à ⌈log₂(N+1)⌉ niveaux d'additionneurs :

| module | termes | niveaux avant | niveaux après |
|---|---:|---:|---:|
| `minute_candidate_search` | 8 | 8 | 3 |
| `hour_candidate_search`   | 7 | 7 | 3 |
| `calendar_candidate_search` | 9 | 9 | 4 |

`calendar_candidate_search` remplace en outre `candidate % 10` / `/ 10` par une
cascade de comparaisons explicites (même structure que
`minute_candidate_search`), supprimant le diviseur constant.

Aucun changement de sémantique : c'est une réassociation d'addition, prouvée
bit-exacte par les preuves formelles existantes (`formal/*_candidate_search.sby`)
et les bancs unitaires, qui passent tous inchangés.

### 2.2 `frequency_discipline`

Le sélecteur `kp = locked ? TRACK_KP : ACQ_KP` (idem `ki`, `estimator_shift`)
placé **avant** les produits faisait inférer à Yosys un **multiplicateur général
18×18** et un **barrel shifter** variables sur le chemin critique. En testant
`frequency_locked` **autour** des produits, chaque branche utilise des
constantes de compilation (les gains sont des paramètres) : les produits par des
constantes se réduisent en décalages/ajouts, et le décalage devient du câblage.
L'arithmétique est inchangée (même constante sélectionnée par état), la preuve
formelle `formal/frequency_discipline.sby` passe.

Effet secondaire : 2 `MULT18X18D` libérés (30 → 28).

## 3. Actuateur PI multi-cycle de `frequency_discipline` (commit `2955a86`, vérifié)

Après §2, le pire chemin était devenu le **calcul PI 64 bits mono-cycle** de
`frequency_discipline` (≈ 41 ns, `second_phase_detector.phase_error_cycles` →
`frequency_discipline.trim_inc`) : une chaîne de ≈ 7 opérations 64 bits en série.

La boucle de discipline est cadencée à **une observation par seconde** alors que
`clk_sys` tourne à 125 MHz : un échantillon accepté dispose de ~10⁸ cycles oisifs.
Le calcul PI a donc été réécrit en **machine à états séquentielle** exécutant
**une réduction 64 bits par cycle** (`S_RAW` → `S_COMMIT`), la mise à jour de
`estimated_offset`, `trim_inc`, `integrator`, du compteur de verrouillage et de
l'horodatage étant **atomique** dans l'état terminal.

- **Sémantique et précision DSP strictement préservées** : chaque expression,
  largeur d'opérande, constante, convention de signe, saturation, anti-windup et
  limite de slew est identique à la version mono-cycle ; seules les frontières de
  registres entre réductions indépendantes ont bougé.
- **Latence : 10 cycles** après `measurement_ce`. Un `busy` explicite gèle le
  calcul : `measurement_ce` présenté pendant `busy` est **ignoré**, il ne peut pas
  écraser un calcul en vol (assertions dans `formal/frequency_discipline_formal.sv`,
  banc `sim/frequency_discipline_tb.sv`).
- Le chemin holdover/rejet reste mono-cycle dans `S_IDLE`.

Vérification sur le HEAD local :

| Contrôle | Résultat |
|---|---|
| `make test-frequency-discipline` | PASS (contrat multi-cycle inclus) |
| `make test` (suite complète, `dcf77_system_tb` 10 scénarios) | PASS |
| `make lint` | PASS |
| `sby -f formal/frequency_discipline.sby` | PASS (PASS, rc=0) |
| `make resource-check` | PASS (LUT4 9 336, FF 6 218, EBR 8, MULT 28, PLL 1) |

### Résultat post-route (`make timing`, seed 1)

| Mesure | Baseline | §2 | §3 (HEAD) |
|---|---:|---:|---:|
| Fmax `clk_sys` | 21,54 MHz | 25,57 MHz | **27,53 MHz** |
| Pire chem. reg→reg | 46,43 ns | 39,11 ns | 36,32 ns |
| Bloc du pire chemin | `calendar_candidate_search` | `frequency_discipline` | **`goertzel` (`observables_i.detector_i.pm_i`)** |
| LUT4 (logic) | 8 474 | 9 660 | 9 336 |
| FF | 5 359 | 5 359 | 6 218 |
| EBR18 | 8 | 8 | 8 |
| MULT18X18D | 30 | 28 | 28 |
| PLL | 1 | 1 | 1 |

Toutes les limites du profil `release_reference` restent respectées. Gain cumulé
depuis le baseline : **+27,8 %** (21,54 → 27,53 MHz). L'objectif **125 MHz n'est
pas atteint**.

### Rapport de timing versionné (HEAD, `make timing`, seed 1)

| Champ | Valeur |
|---|---|
| Commit testé | `2955a86` (RTL) — ce document |
| Cible | `LFE5U-45F-7BG256I`, `release_reference`, 125 MHz |
| Fmax obtenu | **27,53 MHz** |
| Slack pire chemin | **−28,32 ns** (8,00 ns − 36,32 ns) |
| Chemin critique final | `observables_i.detector_i.pm_i.state_1` → `overflow` (résonateur PM) |
| LUT4 | 9 336 |
| FF | 6 218 |
| EBR18 | 8 |
| MULT18X18D | 28 |
| PLL | 1 |

## 4. Chemin critique restant : le banc Goertzel (analyse BEA-36)

Le pire chemin est maintenant, à 36,32 ns (logic ≈ 15 ns + routage ≈ 21 ns) :

```
core_i.detector_i.observables_i.detector_i.pm_i.state_1  (FF)
  → feedback_product  (MULT18X18D, state_1 × RESONATOR_COEFF)
  → recurrence_wide   (add/sub 51 bits + saturation)
  → scale_product_1   (MULT18X18D, recurrence_sat × SCALE_COEFF)
  → scaled_wide/scaled_sat → overflow FF
```

Deux **multiplications de constantes 32×19 mises en série** plus l'additionneur
de récurrence ne peuvent pas descendre sous 8 ns dans un seul cycle : la
profondeur logique seule est d'environ 15 ns, et le routage (le FF de `state_1`
est placé à ~10 colonnes du DSP) ajoute ~21 ns.

### 4.1 Tentative : résonateur pipeliné multi-cycle (prototype, reverté)

Comme pour `frequency_discipline`, la récurrence a été réécrite en pipeline
explicite (une réduction par cycle, `S_MUL → S_REC → S_COMMIT/S_SCALE_*`). Le
prototype était **bit-exact** :

- `formal/goertzel_resonator_formal.sv` étendu au contrat `busy` : PASS ;
- banc d'équivalence 240 échantillons aléatoires contre un modèle golden
  mono-cycle verbatim (y compris saturation/overflow collant) : PASS ;
- banc `engeler_goertzel_bank_tb` (valeurs exactes 47 995 / 41 565 …) : PASS.

**Mais il a dû être reverté** : `sim/dcf77_system_tb.sv` présente **un
échantillon par cycle** au cœur (`sample_ce <= 1'b1` à chaque `posedge clk`,
le scheduler et l'ADC étant hors de ce chemin de test ; voir l'en-tête du banc,
« the core sees one sample per clock »). Un résonateur multi-cycle y **perd des
échantillons**, casse la fréquence du banc de Goertzel et le récepteur ne
s'acquiert plus (`dcf77_system_tb: FAIL (8 scénarios)`).

Autrement dit : la boucle de récurrence d'un filtre de Goertzel est **séquentielle
par construction** (s[n] dépend de s[n−1]) ; son débit est limité par sa latence.
On ne peut pas la pipeliner *et* la faire tourner à un échantillon par cycle. Le
contrat de simulation actuel exige ce débit.

### 4.2 Architecture minimale nécessaire

Le résonateur **doit** être multi-cycle par échantillon en matériel : à
`Fs = 930 kS/s` et `clk_sys = 125 MHz` il y a **~134 cycles `clk_sys` par
échantillon**. La solution correcte est le pipeline multi-cycle (prototype
ci-dessus, bit-exact et prouvé). Pour l'adopter sans casser la simulation, il
faut **une** des deux voies :

1. **Modéliser la cadence réelle dans le banc système.** Faire piloter
   `sample_ce` du cœur à la cadence réelle (p. ex. via `sample_scheduler`, ou un
   strobe espacé) au lieu d'un échantillon par cycle. Coût : le banc
   `dcf77_system_tb` ralentit proportionnellement à l'espacement des échantillons
   (aujourd'hui ~210 s ; ×6 à ×8 inacceptable en CI). C'est la voie *propre* si
   l'on accepte de repenser la compression temporelle du banc.
2. **Optimisation mono-cycle du résonateur** (préserve le débit 1 échantillon/cycle) :
   - **Décomposer les multiplications par constante en décalages/soustractions.**
     `SCALE_COEFF = 2^17 − δ` avec δ petit (13 / 79 / 4915 selon le bin), donc
     `scale(x) = x − x·δ/2^17` = `x` moins quelques `x >>> k` : plus de DSP sur
     le chemin de scaling. Ne s'applique pas à `RESONATOR_COEFF = 227023`
     (≈ √3·2^17, non décomposable).
   - **Floorplan / plan de broches** (`docs/27-ecp5-pin-plan-hat.md`) : ~21 des
     36 ns sont du routage, et rien n'est contraint physiquement aujourd'hui.
     Placer les DSP et les FF de récurrence dans une même colonne peut réduire
     fortement ce terme sans toucher au RTL.

Ces deux voies mono-cycle restent **limitées** : l'additionneur de récurrence
51 bits + la saturation + la multiplication de récurrence restent sur le chemin,
donc la cible 125 MHz pour ce bloc est incertaine sans la voie 1.

### 4.3 Autres blocs profonds identifiés

- `sample_scheduler` : deux additions 40 bits en cascade sur un cycle.
- `second_phase_detector` : portion amont (phase → `phase_error`).
- `pm_chip_integrator`, `pm_correlator`, `observables` : à confirmer après
  correction du résonateur (ces blocs tournent eux aussi à 1 échantillon/cycle).
- `ml_field_sequencer` / `dcf77_receiver_core` : composition à ré-évaluer.

## 5. Statut

Objectif **125 MHz non atteint**, mais le verrou identifié en §4 est levé.

Le **résonateur Goertzel est passé en séquenceur multi-cycle** conformément à la
décision architecturale de BEA-36 (JC, commentaire du 2026-09-11) : chaque
échantillon accepté est étalé sur ≤ 4 `clk_sys` (`S_IDLE` → `S_REC` →
`S_SCALE` → `S_COMMIT`), une réduction arithmétique par cycle, avec poignée de
main `busy`/`done`. L'arithmétique reste **bit-identique** (mêmes largeurs,
décalages, saturations, overflow) ; seules les frontières de registres entre
réductions indépendantes ont bougé. Le contrat de cadence (« jamais de
`sample_ce` pendant `busy` ») est prouvé (`formal/goertzel_resonator_formal.sv`,
`formal/engeler_goertzel_bank_formal.sv`), exercé contre le vrai ordonnanceur
930 kS/s (`sim/sample_cadence_tb.sv`) et **imposé en simulation**
(`sim/goertzel_sample_contract.sv`). Le banc fonctionnel reste accéléré
(`sample_ce` espacé de la latence du pipeline, 4 `clk`).

Le chemin critique **a sauté hors du Goertzel** — c'est maintenant
`lcd_i2c_driver` (§5.2), exactement le principe « traiter un bloc à la fois »
demandé par JC.

| Contrôle | Résultat |
|---|---|
| `make test-goertzel` / `test-observables` | PASS (vecteurs de référence inchangés) |
| `make test-sample-cadence` (930 kS/s vs `busy`) | PASS (min_gap 134 clk, busy_max 3) |
| `make test-system` (10 scénarios) | PASS |
| suite rapide complète (30 cibles) | PASS |
| `make lint` | PASS (0 avertissement) |
| `sby -f formal/goertzel_resonator.sby` | PASS |
| `sby -f formal/engeler_goertzel_bank.sby` | PASS |
| `sby -f formal/engeler_observables.sby` | PASS |
| `make resource-check` | PASS (LUT4 9 421, FF 6 671, EBR 8, MULT 28, PLL 1) |

### 5.1 Rapport de timing versionné (`make timing`, seed 1)

| Champ | Valeur |
|---|---|
| Commit testé | commit BEA-36 « Goertzel multi-cycle » (voir §5) |
| Cible | `LFE5U-45F-7BG256I`, `release_reference`, 125 MHz |
| Fmax obtenu | **28,24 MHz** (27,53 MHz au baseline §1/§3) |
| Slack pire chemin | **−27,42 ns** (8,00 − 35,42 ns) |
| Chemin critique final | `lcd_i2c_driver` (`lcd_i.pos` → `lcd_i.shadow_valid`) |
| LUT4 | 9 421 |
| FF | 6 671 |
| EBR18 | 8 |
| MULT18X18D | 28 |
| PLL | 1 |

Gain depuis le baseline : 21,54 → **28,24 MHz (+31,1 %)** sur la chaîne, toutes
les limites du profil `release_reference` respectées, `MULT18X18D` inchangé
(28/32), précision DSP préservée.

### 5.2 Chemin critique restant : `lcd_i2c_driver`

Un seul chemin reg→reg domine désormais à **35,42 ns** (logic ≈ 13 ns + routage
≈ 22 ns) et il est **entièrement hors du chemin d'échantillonnage** :

```
lcd_i.pos (FF) → mux frame[pos] / shadow[pos] → comparaison pos_dirty
  → logique de prochain-état → lcd_i.shadow_valid (FF)
```

`pos_dirty = !shadow_valid[pos] || (shadow[pos] != frame[pos])` place deux
multiplexeurs 40×8 indexés par `pos` **et** la comparaison sur le chemin
combinatoire du prochain état `SCAN`. Le chemin va du compteur `pos` au registre
qui en dépend ; le routage domine parce que les 40 entrées de `frame`/`shadow`
sont dispersées (pas de floorplan). C'est exactement le bloc signalé en
`docs/39` §7 (P1, 29,3 MHz), hors du chemin critique des échantillons : une
optimisation y est **sans risque fonctionnel** (un test `lcd_i2c_driver_tb`
purement protocole le couvre).

Pistes (par ordre de gain attendu, à mener sous le même principe) :

1. **Pipeliner la lecture `frame[pos]`/`shadow[pos]`** : registrer la valeur lue
   un cycle avant la décision `pos_dirty`, sortant les deux mux du chemin
   `pos → prochain état`. Le scan coûte un cycle de plus par position, sans
   conséquence (le scan n'est pas sur le chemin des échantillons).
2. **Remplacer la comparaison 8 bits par un bit « sale » par position,**
   recalculé une fois par seconde (ou à l'écriture), réduisant le chemin à une
   lecture d'un bit.
3. **Floorplan / plan de broches** (`docs/27`) pour ramener le terme de routage
   (≈ 22 des 35 ns) en regroupant `pos`, le tableau `frame` et la logique de
   prochain état.

Après ce bloc, l'itération continue sur `second_phase_detector`,
`pm_minute_sync`, `sample_scheduler` (déjà à 141 MHz, non bloquant), les
corrélateurs PM, puis les compositions top — selon le principe de JC : budget de
cycles explicite, assertion de contrat, test de cadence séparé lorsque la
cadence le permet.

### 5.3 Note CI

`make test-system` (Verilator) passe mais coûte ~18 min de mur à `SAMPLE_PERIOD=4`
(×4 vs la cadence accélérée historique) : le timeout mur a été porté de 900 à
2400 s. La correction fonctionnelle n'est pas affectée ; une alternative plus
rapide consisterait à piloter `sample_ce` par `ready` (espacement ~2,2 cycles en
moyenne), à considérer si le temps CI devient un problème.
