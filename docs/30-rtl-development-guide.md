# Guide de développement RTL

Ce document est la feuille de route à suivre pour écrire, vérifier et intégrer le
RTL du récepteur DCF77. Il complète le plan global de reconstruction et transforme
les blocs fonctionnels en livrables vérifiables.

## 1. Cible et règles non négociables

- La cible matérielle est le **Lattice ECP5 LFE5U-45F-7BG256I**.
- `rtl/core/` reste portable et ne contient aucune primitive constructeur.
- `rtl/platform/` contient les interfaces physiques et les adaptations de carte.
- `rtl/ecp5/` contient uniquement les PLL, mémoires et primitives propres à ECP5.
- Le profil `release_reference` doit respecter `rtl/resource_budget.json` :
  22 528 LUT4, 22 528 bascules, 32 EBR et 32 multiplicateurs 18 x 18 au maximum.
- Le profil `lab_debug` peut ajouter des FIFO et de l'instrumentation, mais aucun
  de ces éléments ne doit être nécessaire au fonctionnement du récepteur final.
- Une hypothèse issue d'une documentation composant doit être citée dans le code
  ou dans un document de conception. Une chronologie d'interface ne doit pas être
  déduite uniquement du nom des signaux.

## 2. Ordre de réalisation

Chaque étape doit être simulée et synthétisée avant de commencer la suivante.

### Étape A — socle de simulation et d'intégration

1. Figer une version reproductible de la chaîne d'outils.
2. Ajouter les cibles `make lint`, `make test`, `make formal`, `make synth` et
   `make timing`.
3. Créer un paquet RTL pour les largeurs, constantes et types communs.
4. Définir une convention unique de reset et de handshake.
5. Mettre les tests rapides dans la CI et conserver leurs graines aléatoires.

**Critère de sortie :** un clone propre peut lancer lint, tests et synthèse avec
une seule commande documentée.

### Étape B — acquisition ADC brute

1. Vérifier dans la fiche technique LTC1407A la polarité de `CONV`, le délai de
   conversion, le front de changement de `SDO`, le front d'échantillonnage, la
   position exacte de CH0/CH1 et tous les minima/maxima temporels.
2. Transformer ces valeurs en paramètres ou assertions dans
   `rtl/platform/adc_if.sv`; ne pas valider le brochage de trame sur une simple
   hypothèse `{CH0, padding, CH1, padding}`.
3. Connecter `sample_scheduler` à `adc_if` dans un banc de test d'intégration.
4. Tester les mots `0`, `-1`, minimum et maximum, les deux canaux, le reset au
   milieu d'une trame et une demande lorsque l'interface est occupée.
5. Ajouter une petite FIFO asynchrone/synchrone selon le domaine d'horloge retenu,
   puis diffuser les échantillons bruts vers le Raspberry Pi par SPI.

**Critère de sortie :** capture continue à 930 kéch/s sans perte, vérifiée par
compteur de séquence et par analyse logique sur la carte.

### Étape C — référence numérique bit-exacte

1. Générer en Python des vecteurs ADC signés contenant porteuse, AM, PM, bruit,
   brouilleur étroit et erreur d'horloge.
2. Définir pour chaque bloc RTL le format fixe sous la forme
   `Q<entier>.<fraction>`, les règles d'arrondi et la saturation.
3. Produire les résultats attendus dans le même format entier que le RTL.
4. Versionner de petits vecteurs déterministes; générer les longues campagnes en
   CI afin de ne pas alourdir le dépôt.

**Critère de sortie :** tous les calculs fixes futurs ont un oracle logiciel
bit-exact, et pas seulement une comparaison en virgule flottante avec tolérance.

### Étape D — détection porteuse et AM

1. Implémenter un Goertzel élémentaire avec largeur, coefficient et politique de
   saturation paramétrables.
2. Vérifier impulsion, sinus au bin, décalage fréquentiel, saturation et reset.
3. Instancier les états porteuse et AM, puis produire une enveloppe signée.
4. Ajouter le détecteur AM simple avant la corrélation de gabarit AM.
5. Mesurer LUT, bascules, EBR, DSP, latence et fréquence maximale.

**Critère de sortie :** bit AM stable à 1 bit/s et position de seconde retrouvée
sur les vecteurs de référence aux SNR définis dans les tests.

### Étape E — détection PM et synchronisation

1. Implémenter la rotation complexe/CORDIC et vérifier chaque quadrant.
2. Ajouter le Goertzel PM et la décimation vers 3,875 kéch/s.
3. Générer la séquence officielle de 512 chips depuis une source unique partagée
   avec le modèle Python.
4. Corréler PM0/PM1 et rechercher le motif de début de minute.
5. Conserver une sortie douce signée; ne pas seuiller avant le décodeur.

**Critère de sortie :** pic PM aligné avec la seconde AM, polarité correcte et
absence de faux verrouillage au niveau de bruit de qualification.

### Étape F — décodeur temporel ML

1. Stocker jusqu'à 3600 valeurs douces avec validité et qualité.
2. Implémenter successivement les recherches seconde, minute puis heure.
3. Gérer les changements de minute, d'heure, de date, CET/CEST et les secondes
   intercalaires sans lire une mémoire hors limites.
4. Ajouter les écarts meilleur/deuxième candidat et un verrouillage à hystérésis.
5. Ne publier l'heure que lorsque tous les seuils de confiance sont satisfaits.

**Critère de sortie :** acquisition en 60 s ou moins sur signal propre et refus de
publier une heure sur bruit seul pendant la campagne statistique prévue.

### Étape G — discipline d'horloge et produit final

1. Fermer la boucle de correction sur `trim_inc` sans modifier la PLL système.
2. Ajouter rejet des impulsions, bornage, anti-windup et mode holdover.
3. Générer PPS et télémétrie UART uniquement à partir de l'état validé.
4. Contraindre toutes les horloges et interfaces, puis fermer le timing.
5. Tester séparément `release_reference` et `lab_debug` sur carte.

**Critère de sortie :** erreur d'horloge verrouillée inférieure ou égale à
0,1 ppm, contraintes temporelles satisfaites et budget historique respecté.

## 3. Contrats RTL

### Horloge et reset

- Préférer un seul domaine `clk_sys` et des `clock enable` (`sample_ce`,
  `carrier_ce`, `second_ce`) aux horloges fabriquées dans la logique.
- Utiliser `rst` actif à 1 dans le cœur portable. Synchroniser toute entrée de
  reset asynchrone avant de la distribuer au cœur.
- Toute traversée de domaine doit employer un synchroniseur, un handshake ou une
  FIFO CDC reconnue et être signalée dans les contraintes.

### Flux de données

- Un événement ponctuel (`sample_valid`) dure exactement un cycle.
- Un flux susceptible de subir une contre-pression utilise `valid`/`ready`; les
  données restent stables tant que `valid && !ready`.
- Les pertes interdites déclenchent un drapeau persistant remis à zéro par reset
  ou par une commande explicite.
- Les unités et le point binaire apparaissent dans le nom ou le commentaire du
  port. Les ports DSP sont explicitement `signed`.

### Arithmétique fixe

- Dimensionner chaque addition, multiplication et accumulation sur papier avant
  de tronquer.
- La troncature implicite et les mélanges signé/non signé sont interdits.
- Saturer les états récursifs; un débordement modulaire n'est accepté que s'il est
  démontré intentionnel et testé.
- Tester systématiquement les deux valeurs extrêmes et les valeurs autour de zéro.

### Style et structure

- Un module principal par fichier, même nom pour le module et le fichier.
- Paramètres en majuscules; signaux et ports en `snake_case`.
- Employer SystemVerilog synthétisable (`logic`, `always_ff`, `always_comb`) pour
  le nouveau code et donner une valeur à toute sortie dans chaque chemin combinatoire.
- Aucun `#delay`, `force`, accès fichier ou construction réservée au testbench ne
  doit apparaître sous `rtl/`.
- Chaque module comporte son rôle, les formats numériques, la latence, le débit,
  le comportement au reset et les hypothèses temporelles.

## 4. Stratégie de vérification

Pour chaque module, fournir au minimum :

1. un test déterministe des cas nominaux;
2. les valeurs limites et resets à chaque état important;
3. un test aléatoire comparé au modèle Python;
4. des assertions de protocole et d'absence de débordement;
5. une couverture des états et transitions;
6. une synthèse ECP5 avec contrôle des avertissements;
7. pour une interface physique, une mesure sur carte et une trace analysée.

Un test ne doit jamais dépendre d'une temporisation arbitraire quand il peut
attendre un événement de protocole. Toute graine qui révèle une erreur devient un
test de régression permanent.

### Definition of Done d'un bloc

Un bloc est terminé uniquement si :

- son contrat et ses formats fixes sont documentés;
- lint, simulation et assertions passent sans avertissement inexpliqué;
- la comparaison au modèle de référence passe;
- sa latence et son débit sont testés;
- la synthèse ECP5 passe et les ressources sont enregistrées;
- toutes les contraintes temporelles associées existent;
- les erreurs/faults sont observables;
- le code et les tests sont relus ensemble.

## 5. Outils nécessaires

### Outils obligatoires pour contribuer

| Outil | Usage dans ce projet |
|---|---|
| Git | versions, branches, revue et traçabilité des changements |
| GNU Make | point d'entrée stable pour toutes les commandes locales et CI |
| Python 3 | modèle de référence, génération de vecteurs et scripts de rapports |
| `venv` + `pip` | environnement Python isolé et dépendances verrouillées |
| Verilator | lint SystemVerilog, simulation rapide et mesure de couverture |
| Icarus Verilog (`iverilog`, `vvp`) | simulations RTL légères et tests rapides |
| cocotb | testbenches Python et comparaison RTL/modèle bit-exact |
| NumPy/SciPy | génération de signal et référence DSP |
| Yosys | synthèse du RTL portable et synthèse ECP5 |
| nextpnr-ecp5 | placement, routage et analyse temporelle ECP5 |
| Project Trellis (`ecppack`, `ecpunpack`) | production et inspection du bitstream ECP5 |
| base de données `prjtrellis-db` | données du composant utilisées par nextpnr |

Les tests CI ne doivent pas choisir silencieusement un simulateur différent : la
commande et la version sont imprimées au début du journal.

### Outils obligatoires pour la mise au point matérielle

| Outil | Usage dans ce projet |
|---|---|
| OpenOCD ou `ecpdap`/outil équivalent validé | chargement SRAM et accès JTAG |
| programmateur JTAG compatible 3,3 V | récupération d'une carte non amorçable |
| `flashrom` ou utilitaire ECP5 validé | programmation et vérification de la SPI NOR |
| analyseur logique >= 100 Méch/s | validation de `CONV`, `SCK`, `SDO`, SPI, UART et PPS |
| oscilloscope | rampes d'alimentation, horloge, PPS et intégrité des signaux |
| générateur de signaux RF | injection contrôlée autour de 77,5 kHz |
| fréquencemètre ou référence GPS/PPS | calibration de fréquence et latence absolue |

### Outils fortement recommandés

| Outil | Usage |
|---|---|
| SymbiYosys + moteur SMT (`sby`, Boolector ou Yices) | preuve des FIFO, compteurs, handshakes et invariants |
| GTKWave | inspection locale des traces VCD/FST |
| `cocotb-test` ou runner cocotb | intégration uniforme avec Make/pytest |
| pytest | tests du modèle, scripts et campagnes paramétrées |
| Ruff | formatage et lint Python |
| Mypy | vérification des types des outils Python |
| Lattice Diamond | comparaison constructeur, programmation de secours et validation ciblée |
| Sigrok/PulseView | capture et décodage des interfaces numériques sur banc |

### Outils de CI et de qualité du dépôt

- Une image de conteneur doit figer les versions de Verilator, Yosys, nextpnr et
  Project Trellis.
- La CI exécute au minimum `make lint`, `make test`, `make synth` et
  `git diff --check`.
- Une tâche plus longue exécute les preuves formelles, campagnes bruit/SNR et la
  vérification de `rtl/resource_budget.json`.
- Les rapports de timing et d'utilisation sont conservés comme artefacts; les
  bitstreams ne sont publiés que depuis une révision étiquetée.

## 6. Commandes cibles du dépôt

L'interface attendue du futur système de build est :

```sh
make setup          # crée l'environnement Python et vérifie les exécutables
make lint           # lint SystemVerilog et Python
make test           # toutes les simulations RTL rapides
make test TEST=adc_if
make formal         # propriétés formelles
make synth PROFILE=release_reference
make synth PROFILE=lab_debug
make timing PROFILE=release_reference
make bitstream PROFILE=lab_debug
make clean
```

Une cible absente doit être ajoutée au moment où le premier livrable concerné est
introduit. Une cible ne doit pas réussir si elle a ignoré un outil ou un test requis.

## 7. Revue avant fusion

- Le comportement correspond-il au modèle et à la fiche technique primaire ?
- Tous les paramètres ont-ils une plage valide vérifiée ?
- Les signedness, largeurs intermédiaires et troncatures sont-elles explicites ?
- Reset, backpressure, surcharge et perte d'entrée ont-ils été testés ?
- Les CDC et contraintes temporelles sont-elles complètes ?
- Les avertissements ont-ils été corrigés plutôt que masqués ?
- Le profil de référence respecte-t-il le budget historique ?
- Le changement augmente-t-il l'activité numérique près de 77,5 kHz ?
- La documentation, le test et le RTL sont-ils modifiés dans le même commit ?

Cette liste est bloquante pour les interfaces ADC, horloge, PPS et pour tous les
états récursifs du détecteur.

Les commandes et fichiers désormais disponibles pour Verilator, SymbiYosys,
Yosys et le contrôle du budget ECP5 sont détaillés dans
[`35-rtl-toolchain.md`](35-rtl-toolchain.md).
