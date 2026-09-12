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

Le chemin critique **a sauté hors du Goertzel** : il est `lcd_i2c_driver` puis,
après la correction de celui-ci (§5.3), `pm_minute_sync` (§5.4) — exactement le
principe « traiter un bloc à la fois » demandé par JC.

| Contrôle | Résultat |
|---|---|
| `make test-goertzel` / `test-observables` | PASS (vecteurs de référence inchangés) |
| `make test-sample-cadence` (930 kS/s vs `busy`) | PASS (min_gap 134 clk, busy_max 3) |
| `make test-system` (10 scénarios) | PASS |
| `make test-lcd` / `test-integration` | PASS |
| suite rapide complète (30 cibles) | PASS |
| `make lint` | PASS (0 avertissement) |
| `sby -f formal/goertzel_resonator.sby` | PASS |
| `sby -f formal/engeler_goertzel_bank.sby` | PASS |
| `sby -f formal/engeler_observables.sby` | PASS |
| `make resource-check` | PASS (LUT4 9 458, FF 6 682, EBR 8, MULT 28, PLL 1) |

### 5.1 Rapport de timing versionné (`make timing`, seed 1)

| Champ | Valeur |
|---|---|
| Commit testé | `747d565` (Goertzel) puis `4af7364` (LCD) |
| Cible | `LFE5U-45F-7BG256I`, `release_reference`, 125 MHz |
| Fmax obtenu | **29,21 MHz** (baseline §1 : 21,54 ; §3 : 27,53) |
| Slack pire chemin | **−26,23 ns** (8,00 − 34,23 ns) |
| Chemin critique final | `core_i.detector_i.minute_sync_i.locked` (`pm_minute_sync`) |
| LUT4 | 9 458 |
| FF | 6 682 |
| EBR18 | 8 |
| MULT18X18D | 28 |
| PLL | 1 |

Gain depuis le baseline : 21,54 → **29,21 MHz (+35,6 %)**, toutes les limites du
profil `release_reference` respectées, `MULT18X18D` inchangé (28/32), précision
DSP préservée.

### 5.2 Chemin critique n°1 : `lcd_i2c_driver` (corrigé, §5.3)

Un chemin reg→reg dominait à **35,42 ns** (logic ≈ 13 ns + routage ≈ 22 ns),
entièrement **hors du chemin d'échantillonnage** :

```
lcd_i.pos (FF) → mux frame[pos] / shadow[pos] → comparaison pos_dirty
  → logique de prochain-état → lcd_i.state (FF)
```

Isolé (`make timing-block BLOCK=lcd_i2c_driver`) : 30,14 MHz,
`pos → state` 32,66 ns (131 segments). `pos_dirty = !shadow_valid[pos] ||
(shadow[pos] != frame[pos])` plaçait le multiplexeur 40×8 indexé par `pos` **et**
la comparaison sur le chemin combinatoire du prochain état `SCAN` ; le routage
domine parce que les 40 entrées de `frame`/`shadow` sont dispersées (pas de
floorplan). C'est le bloc signalé en `docs/39` §7 (P1, 29,3 MHz).

### 5.3 Correction `lcd_i2c_driver` (commit `4af7364`)

**Lu puis décidé sur deux cycles** : `SCAN` registre la cellule
(`frame_q`/`shadow_q`/`valid_q <= frame[pos]/shadow[pos]/shadow_valid[pos]`) et
`SCAN_DECIDE` prend la décision sur des valeurs **registrées**. Le multiplexeur
40×8 sort du chemin `pos → prochain état`. Le scan est hors chemin
d'échantillonnage : le cycle supplémentaire par position est gratuit.

Résultat isolé : **30,14 → 31,02 MHz** (`pos → state` → `pos → shadow DPRAM`),
et surtout le chemin **quitte le top** :

| Niveau | Avant | Après |
|---|---:|---:|
| `lcd_i2c_driver` isolé | 30,14 MHz | 31,02 MHz |
| `dcf77_hat_top` (post-route, seed 1) | 28,24 MHz | **29,21 MHz** |

Le gain top est plus grand que le gain isolé parce que le bloc cesse d'être le
chemin limitant ; ce qui reste dans `lcd_i2c_driver` est désormais dominé par le
**routage du tableau `shadow` (LUTRAM) indexé par `pos`** (≈ 19 des 31 ns) : la
suite (bit « sale » par position, ou floorplan `docs/27`) est consignée ici mais
non implémentée à ce stade.

`lcd_i2c_driver_tb` (protocole octet-par-octet, DDRAM, rafraîchissements
partiels) et `dcf77_hat_top_tb` restent PASS.

### 5.4 Chemin critique n°2 (nouveau) : `pm_minute_sync`

Après §5.3, le pire chemin top est **34,23 ns** et se situe dans
`core_i.detector_i.minute_sync_i` (`pm_minute_sync`), signalé en `docs/39` §7
(P1, 39,8 MHz isolé). C'est un **filtre apparié 1 résultat/seconde** : comme
`frequency_discipline`, il dispose de ~10⁸ cycles oisifs par mise à jour et le
même traitement s'applique — **budget de cycles explicite, calcul séquentiel
multi-cycle, assertion de contrat**. C'est le prochain bloc, non commencé à ce
stade.

Après lui, l'itération continue (par ordre de Fmax isolé décroissant, `docs/39`
§7) sur `second_phase_detector` (59,7), `pm_minute_sync`/`calendar`/`minute`/
`hour` (≈ 38–40), `pm_phase_discriminator` (69,8) et les **corrélateurs PM /
`engeler_pm_pipeline` (95–120 MHz — sous la cible de peu)**, puis les
compositions top, selon le principe de JC : budget de cycles explicite,
assertion de contrat, test de cadence séparé lorsque la cadence le permet.

> Note de périmètre : même les blocs les plus rapides hors Goertzel restent
> sous 125 MHz (`engeler_pm_correlator` 119,9, `pm_prn_correlator` 112,4) — la
> fermeture complète est une campagne multi-bloc, pas un correctif unique.

### 5.5 Note CI

`make test-system` (Verilator) passe mais coûte ~18 min de mur à `SAMPLE_PERIOD=4`
(×4 vs la cadence accélérée historique) : le timeout mur a été porté de 900 à
2400 s. La correction fonctionnelle n'est pas affectée ; une alternative plus
rapide consisterait à piloter `sample_ce` par `ready` (espacement ~2,2 cycles en
moyenne), à considérer si le temps CI devient un problème.

## 6. `pm_minute_sync` : séquenceur multi-cycle (commit `122cca5`)

Après §5, le pire chemin **routé du top** était dans `pm_minute_sync`
(34,23 ns, `docs/39` §3 : `history[10][7] → quality_gap`) : une chaîne
combinatoire unique exécutée en un cycle faisant la somme série de **15 termes**
du filtre apparié, la sélection des deux meilleurs candidats, puis la
qualification (`MIN_GAP`, dominance du marqueur `60*best >= 11*Σ|corr|`).

Comme `frequency_discipline` (§3), ce bloc produit **un résultat par seconde
DCF77** (~10⁸ cycles `clk_sys` oisifs à 125 MHz). Il est réécrit en
**séquenceur à quatre états** — `S_IDLE → S_SCORE → S_SELECT → S_MARK →
S_COMMIT` — une réduction arithmétique par état :

- `S_SCORE` : somme du filtre apparié (arbre d'additionneurs) + accumulateur
  `Σ|corr|` ;
- `S_SELECT` : `|score|` et sélection top-2 ;
- `S_MARK` : dominance du marqueur + `locked` + `quality_gap` ;
- `S_COMMIT` : décalage de `history`, mise à jour des accumulateurs ou
  commit terminal (`result_valid`, sorties, reset des accumulateurs).

**Latence : 4 cycles** après acceptation d'un échantillon, `busy` explicite.
`pm_second_valid` présenté pendant `busy` est **ignoré** (contrat appelant).

**Précision DSP strictement préservée (bit-à-bit)** : mêmes expressions,
largeurs, constantes, saturations et conventions de signe ; seules les
frontières de registres entre réductions *indépendantes* ont bougé. La somme des
15 termes est un **arbre d'additionneurs équilibré**, bit-identique à la somme
série (associativité de l'addition en complément à deux modulo 2^N), profondeur
4 au lieu de 15. La cadence réelle (1 valid/s) rend la latence transparente.

Vérification :

| Contrôle | Résultat |
|---|---|
| `make test-minute-sync` (vecteurs exacts + latence busy=4) | PASS |
| `make test-qualification-disabled` | PASS |
| `make test-system` (10 scénarios, Verilator) | PASS |
| `make lint` | PASS (0 avertissement) |
| `sby -f formal/pm_minute_sync.sby` (k-induction, contrat inclus) | PASS |
| `make resource-check` | PASS (LUT4 9 289, FF 6 929, EBR 8, MULT 28, PLL 1) |

Le contrat de cadence est **prouvé** (`formal/pm_minute_sync_formal.sv` :
légalité de transition, `busy ≤ 4` cycles consécutifs, `result_valid` arrive
exactement 4 cycles après un `pm_second_valid` accepté, `locked` ne change
qu'avec `result_valid`) et **imposé en simulation**
(`sim/pm_minute_sync_contract.sv`, instancié dans les deux bancs qui pilotent
`pm_second_valid`). Le cœur réel pilote `pm_correlation_valid` à la vraie
cadence (1/s), très au-dessus de la latence de 4 cycles : aucun échantillon
n'est perdu in situ.

### Rapport de timing versionné (`make timing`, seed 1)

| Champ | Valeur |
|---|---|
| Commit testé | `122cca5` |
| Cible | `LFE5U-45F-7BG256I`, `release_reference`, 125 MHz |
| Fmax obtenu | **31,73 MHz** (baseline : 21,54 ; §3 : 27,53 ; §5.1 : 29,21) |
| Slack pire chemin | **−23,52 ns** (8,00 − 31,52 ns) |
| Chemin critique final | `lcd_i.pos[2]` → `lcd_i.shadow.0.3` (DPRAM) — 121 segments |
| LUT4 | 9 289 |
| FF | 6 929 |
| EBR18 | 8 |
| MULT18X18D | 28 |
| PLL | 1 |

Le chemin critique **quitte `pm_minute_sync`** : il est maintenant
`lcd_i2c_driver` (§5.2/§5.3), dominé par le **routage du tableau `shadow`
(LUTRAM) indexé par `pos`** (logic 13,3 ns + routage 18,2 ns). C'est le point
déjà signalé en §5.3 comme nécessitant soit un bit « sale » par position, soit
un **floorplan** (`docs/27-ecp5-pin-plan-hat.md`).

Gain depuis le baseline : 21,54 → **31,73 MHz (+47,3 %)**, toutes les limites du
profil `release_reference` respectées, `MULT18X18D` inchangé (28/32), précision
DSP préservée.

## 7. `lcd_i2c_driver` : découplage du rendu et du scan (commit `HEAD`)

Après §6, le pire chemin **routé du top** était `lcd_i.pos[2]` →
`lcd_i.shadow.0.3` (DPRAM), 31,52 ns (logic 12,8 + routage 18,2). L'analyse du
netlist post-route montre que ce n'est **pas** le seul accès au tableau `shadow` :
le chemin démarre à `pos` et se termine à `frame_q`, en traversant **116 cellules
de retenue `CCU2`** — c'est-à-dire la chaîne des **divisions décimales par
constante** du rendu (`tens`/`units`, `year % 100`, `quality / 10`, `/ 100`),
qui se retrouvait dans le même cône combinatoire que la lecture/écriture
indexée par `pos`.

Trois changements, tous **hors du chemin d'échantillonnage** (le bloc affiche à
~1 Hz ; chaque `tick` dispose de ~10⁸ cycles oisifs) :

1. **`DATA_V` écrit `frame_q` au lieu de `frame[pos]`.** `frame_q` a été chargé
   pour cette position en `SCAN` et `pos` ne bouge pas avant `FLUSH` : la valeur
   est identique, mais le multiplexeur 40:1 indexé par `pos` sort du chemin
   d'écriture (`send` + `shadow[pos]`).
2. **Adresse DDRAM enregistrée.** `addr_q <= ddram_address` en `SCAN_DECIDE`
   (arithmétique `pos < 20` / `pos − 20`), présentée en `ADDR_V` : la
   soustraction/comparaison ne partage plus de cône avec l'écriture de cellule.
3. **Décomposition décimale pipelinée.** Les divisions imbriquées sur deux
   niveaux (`(year % 100) % 10`, `(quality / 10) % 10`, `quality / 100`) sont
   coupées par un registre `year_lo_q` / `qual_10_q` / `qual_100_q`. Latence
   **+1 cycle**, immatérielle à la cadence de 1 tick/s ; valeurs identiques.

Aucun changement de sémantique : mêmes expressions, largeurs, constantes et
résultats ; seules des frontières de registre ont bougé (décalage de 1 cycle sur
des sous-expressions internes du rendu).

> **Variante écartée.** Une capture complète du `frame` rendu dans un tableau
> `frame_r[0:39]` à chaque début de scan a été prototypée : elle amenait le bloc
> **isolé** à 49,93 MHz, mais le routage du **top** ne convergait plus (coût
> routeur encore croissant à 52 min ; le banc de 40 octets crée un point chaud de
> congestion). Elle a été **revertée** au profit de la version ci-dessus.

Vérification :

| Contrôle | Résultat |
|---|---|
| `make test-lcd` (protocole octet-par-octet, lignes exactes) | PASS |
| `make test` (suite complète + `dcf77_system_tb` + cadence) | PASS |
| `make lint` | PASS (0 avertissement) |
| `sby -f formal/lcd_i2c_driver.sby` (bmc + cover) | PASS |
| `make resource-check` | PASS (LUT4 9 815, FF 6 955, EBR 8, MULT 28, PLL 1) |

Bloc isolé (`make timing-block`, flow BEA-37) : **30,72 → 50,81 MHz**, chemin
résiduel `pos → frame_q` (19,68 ns, multiplexeur 40:1) ; +25 FF seulement.

### Rapport de timing versionné (`make timing`, seed 1)

| Champ | Valeur |
|---|---|
| Commit testé | `8f8c226` (RTL) puis ce commit |
| Cible | `LFE5U-45F-7BG256I`, `release_reference`, 125 MHz |
| Fmax obtenu | **37,40 MHz** (baseline : 21,54 ; §3 : 27,53 ; §5.1 : 29,21 ; §6 : 31,73) |
| Slack pire chemin | **−19,74 ns** (8,00 − 27,74 ns) |
| Chemin critique final | `core_i.field_seq_i.minute_i.candidate` → `...minute_i.confident` (`minute_candidate_search`) |
| LUT4 | 9 815 |
| FF | 6 955 |
| EBR18 | 8 |
| MULT18X18D | 28 |
| PLL | 1 |

Le chemin critique **quitte `lcd_i2c_driver`** : il est maintenant
`minute_candidate_search` (`candidate` → `confident`, 26,74 ns), le bloc P1 de
`docs/39` §7 (≈ 39,7 MHz isolé, 1 recherche/minute). C'est le prochain bloc de
l'itération « un bloc à la fois ».

Gain depuis le baseline : 21,54 → **37,40 MHz (+73,7 %)**, toutes les limites du
profil `release_reference` respectées, `MULT18X18D` inchangé (28/32), précision
DSP préservée. **Objectif 125 MHz non atteint** — campagne multi-bloc en cours.

## 8. Corrélateurs de champs ML : séquenceur multi-cycle (BEA-36, cycle courant)

Les trois moteurs de recherche ML `minute_candidate_search`,
`hour_candidate_search` et `calendar_candidate_search` partageaient la même
structure : un **seul cycle combinatoire** allant du curseur `candidate` au
résultat (`candidate → découpage décimal → arbre ±évidence → comparaison →
confident/quality_gap`). Chacun était déjà « multicycle » (une recherche par
minute, lancée par `ml_field_sequencer` via `start`/`result_valid`), mais la
recherche elle-même déroulait un candidat par cycle sur **un** long chemin.

Comme `frequency_discipline` (§3), `pm_minute_sync` (§6) et le résonateur
Goertzel (§5), ces blocs disposent d'un budget de cycles énorme (une recherche
par minute ⇒ ~10⁸ `clk_sys` oisifs à 125 MHz). Chacun est réécrit en
**séquenceur à quatre états** — `S_IDLE → S_SCORE → S_SELECT → S_EMIT` — avec
**une réduction arithmétique par état** :

- `S_SCORE` : découpage décimal du curseur + arbre d'additionneurs équilibré des
  huit/sept/neuf termes ±évidence → `score_q` (registre) ;
- `S_SELECT` : `score_q` contre `best_q`/`second_q`, capture de la meilleure
  valeur ; le curseur n'avance qu'en quittant `S_SELECT` ;
- `S_EMIT` : seuils de qualification (`MIN_SCORE`/`MIN_GAP`) → `confident`,
  `quality_gap`, `result_valid` ; `busy` retombe.

**Précision DSP strictement préservée (bit-à-bit)** : mêmes expressions,
largeurs, constantes, sentinelles, ordre de départage et conventions de signe ;
seules les frontières de registre entre réductions *indépendantes* ont bougé.
Latences (documentées) : `2*60 + 1 = 121` cycles (minute), `2*24 + 1 = 49`
(hour), `2*(last−first+1) + 1` (calendrier, jusqu'à 201 pour l'année 0..99).
`ml_field_sequencer` attend `result_valid` — la latence supplémentaire est
transparente à la cadence réelle (une recherche/minute).

### Vérification

| Contrôle | Résultat |
|---|---|
| `make test-minute-ml` / `test-hour-ml` / `test-calendar-ml` | PASS (vecteurs exacts inchangés) |
| `make test-ml-controller` / `test-field-sequencer` / `test-qualification-disabled` | PASS |
| `make test` (suite complète, `dcf77_system_tb` incluse) | PASS |
| `make lint` | PASS (0 avertissement) |
| `sby -f formal/{minute,hour,calendar}_candidate_search.sby` | PASS (k-induction) |
| `make resource-check` | PASS (LUT4 9 351, FF 7 026, EBR 8, MULT 28, PLL 1) |

Les trois preuves `candidate_search` passent désormais en **k-induction**
(invariants de phase mutuellement inductifs), ce qui a permis de **réintégrer
`calendar_candidate_search` champ `year` (0..99)** dans la preuve — le BMC 40 pas
précédent devait l'exclure faute d'un déroulé tractable.

### Rapport de timing versionné (`make timing`, seed 1)

| Champ | Valeur |
|---|---|
| Cible | `LFE5U-45F-7BG256I`, `release_reference`, 125 MHz |
| Fmax obtenu | **52,27 MHz** (37,40 → 41,76 → 48,71 → 52,27) |
| Slack pire chemin | −11,13 ns (8,00 − 19,13 ns) |
| Chemin critique final | `core_i.detector_i.observables_i.state` → `observables_i.mul_a` (`engeler_observables`) |
| LUT4 | 9 351 |
| FF | 7 026 |
| EBR18 | 8 |
| MULT18X18D | 28 |
| PLL | 1 |

Le chemin critique **quitte le décodeur ML** : il est maintenant dans
`engeler_observables` (entrée d'un multiplicateur du banc). Gain depuis le
baseline : 21,54 → **52,27 MHz (+142,6 %)**, toutes les limites du profil
`release_reference` respectées, `MULT18X18D` inchangé (28/32), précision DSP
préservée. **Objectif 125 MHz non atteint** — campagne multi-bloc en cours ; le
prochain bloc est `engeler_observables`.



## 9. `engeler_observables` + `lcd_i2c_driver` (BEA-36, cycle courant)

Après §8 le pire chemin routé du top était `observables_i.state` →
`observables_i.mul_a` (**19,13 ns**), c'est-à-dire le multiplexeur d'opérandes
câblé directement sur l'entrée d'un produit **33×33 signé** en un seul cycle.
`mul2dsp` doit découper un tel produit en plusieurs `MULT18X18D` et en sommer les
produits partiels avec une chaîne de retenue d'environ 30 cellules : aucun
pipeline d'opérandes ne peut fermer 8 ns tant que le produit reste entier.

### 9.1 `engeler_observables` : produit signé décomposé en membres 18×18

Chaque produit 33×33 est décomposé **exactement** en quatre sous-produits 18×18
signés (découpe en membres au bit `LIMB_LO`, entiers bas non signés de 17 bits,
entiers hauts signés de 16 bits) :

```
a·b = a_lo·b_lo + (a_lo·b_hi + a_hi·b_lo)·2^17 + a_hi·b_hi·2^34
```

Chaque sous-produit tient dans **un seul `MULT18X18D` sans chaîne de retenue**,
et la réassociation est exacte en complément à deux, donc bit-identique au
produit mono-cycle tronqué à `PRODUCT_BITS`. Les produits sont sérialisés sur
deux multiplicateurs physiques, une réduction arithmétique par cycle, via un
micro-séquenceur à quatre états par produit (`S_LOAD` membres, `S_MA`
`a_lo·b_lo` + `a_hi·b_hi`, `S_MB` `a_lo·b_hi` + `a_hi·b_lo`, `S_ACC` recombinaison
et écriture de la destination), parcouru pour les quatre produits.

- **Sémantique et précision DSP strictement préservées (bit-à-bit)** : mêmes
  produits, mêmes sommes/soustractions `+`/`−` finales, même troncature
  `PRODUCT_BITS`. Seules les frontières de registres internes ont bougé.
- **Latence : 18 cycles** après le `cycle_valid` du banc (1 instantané +
  4 produits × 4 états + 1 somme), contre 6 auparavant. Un `cycle_valid`
  présenté hors de `S_IDLE` est ignoré (contrat de cadence inchangé).
- Le budget est large : 18 clk contre 48 clk par cycle de porteuse dans le banc
  système accéléré (`SAMPLE_PERIOD = 4`), et ~1600 clk en matériel.

Vérification :

| Contrôle | Résultat |
|---|---|
| `make test-observables` (vecteurs exacts 575 140 769 / 71 729) | PASS |
| `make test-observables-equiv` (**599 observables**, opérandes aléatoires 33 bits vs modèle mono-cycle full-width) | PASS (bit-exact) |
| `make test-goertzel` / `test-sample-cadence` | PASS |
| `sby -f formal/engeler_observables.sby` (latence exacte = 18) | PASS |
| `sby -f formal/goertzel_resonator.sby` / `engeler_goertzel_bank.sby` | PASS |

### 9.2 `lcd_i2c_driver` : lecture de `frame` en deux étages + chiffres enregistrés

Le chemin `observables` corrigé, le pire chemin du top est devenu
`lcd_i.pos` → `frame_q` (**19,08 ns**) : yosys mappe la lecture combinatoire
`frame[pos]` (40 entrées) sur un **multiplexeur à chaîne de retenue d'environ
90 cellules `CCU2`** (`cmp2lcu`), dont le délai croît linéairement avec le
nombre d'entrées.

Deux changements, tous hors chemin d'échantillonnage (affichage à ~1 Hz) :

1. **Lecture `frame` en deux étages enregistrés.** Le tableau `frame` est
   réorganisé en cinq groupes de huit (`frame[0:4][0:7]`) ; l'état `SCAN_GRP`
   charge les cinq octets de groupe par cinq multiplexeurs **8:1**
   (`frame[g][pos[2:0]]`, indice de groupe constant), puis `SCAN` sélectionne le
   groupe par un multiplexeur **5:1** (`grp_q[pos[5:3]]`). Trois petits
   multiplexeurs séparés par un registre au lieu d'une chaîne de retenue de 40
   entrées. Un cycle de plus par position, gratuit à 1 Hz.
2. **Octets de chiffres enregistrés.** Les divisions décimales par constante
   (`/10`, `%10`, `/100`) sont calculées **une fois** dans un étage de registres
   (`hh10_q` … `q1_q`), la construction de `frame` ne faisant plus que
   sélectionner des octets enregistrés. Sans cet étage, le pire chemin du top
   était devenu `quality → %10 → digit → mux frame` (18,05 ns) : la chaîne de
   retenue de la division partageait un cône avec la lecture de scan.

Aucun changement de sémantique : mêmes caractères, mêmes positions, mêmes
horodatages ; seules des frontières de registre internes ont bougé (latence du
rendu +1 cycle, immatérielle à 1 Hz).

Vérification :

| Contrôle | Résultat |
|---|---|
| `make test-lcd` (protocole octet-par-octet, lignes exactes) | PASS |
| `make test-integration` (top HAT, init LCD, interfaces) | PASS |
| `make lint` | PASS (0 avertissement) |
| `sby -f formal/lcd_i2c_driver.sby` (bmc + cover, protocole I2C aux broches) | PASS |

### 9.3 Rapport de timing versionné (`make timing`, seed 1)

| Champ | Valeur |
|---|---|
| Cible | `LFE5U-45F-7BG256I`, `release_reference`, 125 MHz |
| Fmax obtenu | **57,77 MHz** (baseline : 21,54 ; §3 : 27,53 ; §5.1 : 29,21 ; §6 : 31,73 ; §7 : 37,40 ; §8 : 52,27) |
| Slack pire chemin | **−9,31 ns** (8,00 − 17,31 ns) |
| Chemin critique final | `core_i.detector_i.second_sync_i.magnitude_q` → `edge_armed` → `slew` (`second_phase_detector`) |
| LUT4 | 9 484 |
| FF | 7 321 |
| EBR18 | 8 |
| MULT18X18D | 28 |
| PLL | 1 |

Le chemin critique **quitte le banc Goertzel puis l'afficheur** : il est
maintenant dans `second_phase_detector` (§9.4), le bloc P0 de `docs/39` §7
(59,7 MHz isolé, mesure par seconde). Gain depuis le baseline :
21,54 → **57,77 MHz (+168 %)**, toutes les limites du profil `release_reference`
respectées, `MULT18X18D` inchangé (28/32), précision DSP préservée.
**Objectif 125 MHz non atteint** — campagne multi-bloc en cours.

### 9.4 Prochain bloc : `second_phase_detector`

Pire chemin **17,31 ns** (`second_sync_i.magnitude_q[58]` → `edge_armed` →
`slew`), sur la portion amont « magnitude → erreur de phase ». C'est un
détecteur de front **une mesure par seconde** : comme `frequency_discipline`
(§3), `pm_minute_sync` (§6) et les recherches ML (§8), il dispose de ~10⁸ cycles
oisifs par mise à jour et le même traitement s'applique — budget de cycles
explicite, calcul séquentiel multi-cycle, assertion de contrat.

Après lui, l'itération continue « un bloc à la fois » sur `pm_phase_discriminator`
(69,8), `second_phase_detector`/`pm_minute_sync`/recherches ML, et les
corrélateurs PM / `engeler_pm_pipeline` (95–120 MHz) mentionnés en §5.4.
