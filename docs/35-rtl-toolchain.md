# Chaîne de vérification, preuve et synthèse RTL

Le dépôt fournit maintenant des points d'entrée concrets pour les outils listés
dans le guide RTL. Les versions doivent être figées dans la future image CI;
`make tool-versions` les affiche avant tout rapport de qualification.

## Installation reproductible

`tools/install-rtl-toolchain.sh` installe la publication OSS CAD Suite
`2025-02-13` dans un répertoire dédié. Cette publication fournit ensemble
Icarus, Verilator, Yosys, nextpnr-ecp5, Project Trellis, SymbiYosys et
Boolector. La CI met ce répertoire en cache, mais la date figée dans le script
reste la source de vérité; changer de chaîne nécessite donc une modification
relue et versionnée du script.

```sh
tools/install-rtl-toolchain.sh
source "$HOME/.local/oss-cad-suite-2025-02-13/environment"
make tool-versions
```

## Vérification statique

```sh
make lint
```

Verilator charge tous les blocs du détecteur, élabore `engeler_detector` et
signale les largeurs incohérentes, signaux inutilisés, latches et constructions
non supportées. Les petits `lint-*` Icarus restent utiles pour isoler rapidement
un sous-ensemble.

## Preuve formelle

```sh
make formal
```

SymbiYosys exécute actuellement une preuve bornée/inductive du générateur PPS
avec Boolector. Le harnais maintient un modèle indépendant de la durée
d'impulsion et démontre, pour toutes les séquences d'entrée dans la profondeur
choisie :

- que PPS reste bas quand la base de temps est invalide;
- qu'un `second_ce` valide déclenche PPS;
- que la sortie correspond exactement au compteur de largeur attendu, y compris
  en cas de nouveau déclenchement pendant une impulsion.

Les prochains candidats à la preuve sont les bornes des accumulateurs, les 512
avances du LFSR, l'unicité de `correlation_valid` et la stabilité
`valid && !ready` de la télémétrie.

## Synthèse ECP5

```sh
make synth        # cœur détecteur (historique)
make synth-ecp5   # top complet dcf77_hat_top pour LFE5U-45F
make synth-core   # diagnostic détecteur isolé
```

Yosys lit le RTL portable, contrôle la hiérarchie, lance `synth_ecp5` et produit
selon la cible :

```text
build/release_reference.json      (make synth)
build/release_reference-stat.txt
build/synth_ecp5.json             (make synth-ecp5)
build/synth_ecp5-stat.txt
```

Le placement-routage avec nextpnr-ecp5 ne deviendra bloquant qu'après ajout du
fichier LPF complet et des contraintes d'horloge validées contre le PCB.
La cible `make timing` réalise néanmoins périodiquement un placement-routage
sans brochage à 125 MHz pour détecter les régressions du cœur. Son rapport ne
constitue pas une clôture de timing de carte.

### Rapport de ressources ECP5 (dcf77_hat_top, LFE5U-45F-7BG256I)

```
Ressource         Utilisé   Limite ECP5    %     Limite ref. (XC3S1400AN)
─────────────────────────────────────────────────────────────────────────
LUT4              8,417     43,776         19%   22,528
TRELLIS_FF        5,345     43,776         12%   22,528
DP16KD (EBR18)        8        108          7%       32
MULT18X18D            42         96         44%       32 ⚠ (dépasse)
EHXPLLL (PLL)          1          4         25%        8
CCU2C              3,601       —            —         —
PFUMX                707       —            —         —
L6MUX21               48       —            —         —
TRELLIS_DPR16X4        6       —            —         —
```

⚠ Le design utilise 42 MULT18X18D, ce qui dépasse l'enveloppe historique
XC3S1400AN de 32 multiplieurs. Le budget ECP5 est respecté (96 disponibles).
Une optimisation des multiplieurs est nécessaire pour la conformité
`release_reference` ; voir `docs/09-gaps-and-open-questions.md` § FPGA resource
ceiling et `docs/16-fpga-resource-budget.md`.

## Contrôle automatique du budget

```sh
make resource-check       # enveloppe XC3S1400AN (release_reference)
make resource-check-ecp5  # enveloppe LFE5U-45F (ecp5_limits)
make timing
```

`tools/check_resource_budget.py` compte dans le netlist ECP5 les cellules
`LUT4`, `TRELLIS_FF`, `DP16KD`, `MULT18X18D` et `EHXPLLL`, puis applique les
limites de `rtl/resource_budget.json`. Le profil `release_reference` échoue si
l'enveloppe XC3S1400AN est dépassée ; `ecp5_limits` vérifie la cible physique
LFE5U-45F.

La RAM distribuée ne peut pas être déduite de manière fiable par un simple
comptage final des types de cellules. Le script l'annonce explicitement au lieu
de prétendre la vérifier; un parseur du rapport mémoire Yosys sera ajouté avec
les premières mémoires du décodeur ML.

## Placement, routage et bitstream

Les outils prévus sont :

```text
Yosys -> nextpnr-ecp5 -> ecppack (Project Trellis)
```

Ils fourniront respectivement le netlist technologique, le rapport de timing et
le bitstream. Aucun objectif de timing ne sera déclaré satisfait sur la seule
base d'une synthèse Yosys : il faut un placement-routage complet et toutes les
contraintes d'horloge/I/O.

## Commandes disponibles

```sh
make tool-versions
make lint
make test-tools
make formal
make synth
make synth-ecp5
make resource-check
make resource-check-ecp5
```

`make test-tools` vérifie le parseur de ressources sans nécessiter de FPGA ni de
simulateur HDL. Les autres commandes échouent volontairement si leur exécutable
requis est absent; elles ne doivent jamais transformer une vérification ignorée
en succès CI.

Le workflow `.github/workflows/rtl.yml` exécute versions, tests Python, tests
RTL et lint sur chaque pull request. La synthèse et le budget sont dans une
tâche séparée. Le placement-routage et les preuves, plus longs, s'exécutent le
lundi, sur demande et pour les tags de version. Tous les rapports restent
téléchargeables comme artefacts GitHub Actions, y compris lors d'un échec.
