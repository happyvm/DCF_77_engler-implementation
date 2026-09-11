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
Icarus 13, Verilator 5.032), comme la CI `.github/workflows/rtl.yml`.

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

## 2. Optimisations effectuées (arbres d'addition équilibrés + constantes)

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

## 3. Résultats après optimisation (seed 1, mêmes contraintes)

| Mesure | Baseline | Après | Δ |
|---|---:|---:|---:|
| Fmax `clk_sys` | 21,54 MHz | **25,57 MHz** | +18,7 % |
| Pire chem. reg→reg | 46,43 ns | 39,11 ns | −7,3 ns |
| Bloc du pire chemin | `calendar_candidate_search` | `frequency_discipline` (via `second_phase_detector`) | — |
| LUT4 (logic) | 8 474 | 9 660 | +1 186 |
| FF | 5 359 | 5 359 | 0 |
| EBR18 | 8 | 8 | 0 |
| MULT18X18D | 30 | **28** | −2 |
| PLL | 1 | 1 | 0 |

Toutes les limites du profil `release_reference` restent respectées
(`make resource-check` PASS).

Validation : `make test` (suite complète, dont `dcf77_system_tb` 10 scénarios),
`make test-calendar-ml` / `test-minute-ml` / `test-hour-ml` /
`test-frequency-discipline`, et les preuves formelles
`calendar_candidate_search.sby`, `minute_candidate_search.sby`,
`hour_candidate_search.sby`, `frequency_discipline.sby` passent sur la révision
modifiée.

## 4. Chemins restants et architecture minimale nécessaire

À 24 MHz, il reste ≈ 46 points de terminaison en slack négatif à 8 ns. Le pire
chemin restant est le **calcul PI de `frequency_discipline`** (≈ 41 ns,
`second_phase_detector.phase_error_cycles` → `frequency_discipline.trim_inc`).

### 4.1 `frequency_discipline` — calcul PI multi-cycle (priorité 1)

Le chemin est une chaîne de ≈ 7 opérations **64 bits** en série
(Soustraction+shift+addition pour `estimate_next`, puis `integrator + i_delta`,
puis deux additions pour `requested`, puis les bornages et le slew). Chaque
additionneur 64 bits se mappe sur une longue chaîne de retenue ; la profondeur
ne peut pas descendre sous 8 ns en un cycle.

**Architecture minimale proposée** — machine à états séquentielle :

1. `busy`/`done` explicites ; pendant `busy`, accepter une nouvelle mesure ne
   peut pas écraser les opérandes en cours (registre d'entrée séparé + assertion
   SVA, ou mise en file et traitement après `done`).
2. Étaler le calcul sur ≈ 5 cycles, un opérande 64 bits par cycle :
   `raw_frequency` → `estimate_next` → `proportional`/`i_delta` →
   `integrator_candidate`/`requested` (anti-windup) → bornage + slew + mise à
   jour de `trim_inc`.
3. Profondeur par cycle = un additionneur 64 bits ≈ 3–5 ns < 8 ns.
4. **Latence documentée** : ≈ 5 cycles après `measurement_ce`. La boucle est
   cadencée à 1 Hz : c'est négligeable.

Conséquence : le contrat du bloc change (il faut attendre `done` plutôt que
supposer une mise à jour en un cycle). Le banc `sim/frequency_discipline_tb.sv`
doit être adapté pour **attendre la fin de calcul** (pas affaibli : les valeurs
attendues restent identiques). La cadence réelle (1 mesure/s) rend la propriété
« pas d'écrasement » triviale à tenir, mais elle doit être **assertée**.

### 4.2 Autres blocs profonds identifiés

- `sample_scheduler` : deux additions 40 bits en cascade sur un cycle
  (`increment_ext` puis `phase_sum`). Pipeline possible sur 2 cycles avec
  `sample_ce` en sortie, ou réduction de largeur démontrée.
- `second_phase_detector` : la portion amont du chemin restant (phase →
  `phase_error`).
- `pm_chip_integrator`, `goertzel/*` : à confirmer par mesure (les MULT ont déjà
  été time-sharés dans le commit `77487ec`).
- `ml_field_sequencer` / `dcf77_receiver_core` : chemins de composition à
  ré-évaluer après chaque correction de bloc.

### 4.3 Améliorations sans coût logique

- **Plan de broches / floorplan** (`docs/27-ecp5-pin-plan-hat.md`) : le routage
  représente ~60–65 % du délai des pires chemins, et aucun placement physique
  n'est contraint aujourd'hui. Contraindre les I/O et un floorplan grossier
  (colonnes des chaînes de retenue, DSP, EBR) peut améliorer la Fmax sans
  toucher au RTL.
- Poursuivre la campagne **chemin critique par chemin critique** : chaque
  correction révèle le suivant (mesure `make timing`, graine fixée).

## 5. Statut

L'objectif **125 MHz n'est pas encore atteint**. Le design est passé de 21,5 à
25,6 MHz (+18,7 %) avec une sémantique et une précision DSP préservées, et sans
sortir de l'enveloppe historique. La fermeture complète nécessite la campagne de
pipelining décrite en §4 (au premier chef le calcul PI multi-cycle de
`frequency_discipline`), que le présent travail a instrumentée et priorisée.
