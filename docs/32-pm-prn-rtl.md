# Corrélateur PM/PRN RTL

## Blocs implémentés

Le premier chemin de corrélation PM Engeler est séparé en trois modules :

```text
dcf77_prn_generator
  -> prn_chip + chip_index
  -> pm_prn_correlator
  -> corrélation douce sur 512 chips

engeler_pm_correlator
  -> assemblage d'une hypothèse complète

pm_chip_integrator
  -> intégration de 120 cycles de porteuse par chip

engeler_pm_pipeline
  -> minutage + intégration + corrélation
```

Le générateur RTL est le pendant bit-exact de `tools/dcf77_prn.py`. Il utilise le
registre de neuf bits, le masque de Galois `0x110` et le mécanisme de sortie de
l'état nul documentés par les sources PTB.

## Contrat temporel

- `reset_cycle` replace le générateur sur le premier chip et vide l'accumulateur.
- `prn_chip` désigne le chip courant avant le front actif de `chip_ce`.
- Sur `chip_ce`, le corrélateur consomme simultanément `pm_soft` et `prn_chip`,
  puis le générateur avance au chip suivant.
- Au chip d'indice 511, `correlation_valid` est produit pendant un cycle et
  `correlation` contient la somme des 512 contributions.
- L'accumulateur est remis à zéro après chaque séquence afin d'autoriser la
  corrélation de la seconde suivante sans reset global.

Le score utilise la convention :

```text
chip 0 -> contribution = -pm_soft
chip 1 -> contribution = +pm_soft
```

Une séquence inversée produit donc le score opposé. Le signe absolu ne doit pas
encore être interprété comme une valeur DCF77 0 ou 1, car l'antenne et la chaîne
analogique peuvent inverser la polarité observée.

## Largeurs fixes

La largeur par défaut de `pm_soft` est 24 bits. L'accumulateur ajoute dix bits,
ce qui couvre sans débordement la somme de 512 valeurs signées, y compris la
valeur négative extrême. Aucun seuillage n'est effectué : le score reste une
information douce pour la synchronisation et le futur décodeur ML.

## Vérification

Les tests RTL vérifient :

- les 35 premiers chips connus;
- une longueur de 512 chips;
- exactement 256 chips à 1;
- l'inversion bit à bit;
- le retour de l'index à zéro et l'impulsion de fin;
- un score de `+51200` pour 512 chips d'amplitude 100 alignés;
- un score de `-51200` pour leur séquence inversée.

## Étapes suivantes

`pm_chip_integrator.sv` réalise désormais le minutage nominal complet : début au
cycle porteuse 15 500, 120 cycles intégrés par chip, 512 chips et fin au cycle
76 940. L'addition du dernier échantillon est incluse avant saturation et
présentation au corrélateur. `engeler_pm_pipeline.sv` raccorde cet intégrateur au
corrélateur sans horloge dérivée.

Ce pipeline représente encore une seule hypothèse d'alignement. Pour obtenir le
synchroniseur haute immunité décrit par Engeler, il reste à :

1. rechercher plusieurs décalages autour de l'estimation AM;
2. accumuler le motif minute PM connu des secondes 0 à 14;
3. mesurer l'écart entre le meilleur et le deuxième pic avant tout verrouillage;
4. figer `OUTPUT_SHIFT` à partir des captures et campagnes de dynamique;
5. vérifier le comportement en présence d'une seconde intercalaire.
