# Extraction de bit AM en RTL

## Principe

`rtl/am/am_bit_extractor.sv` constitue le premier décodeur AM simple prévu par
la phase D du guide RTL. Il suppose que `second_ce` est déjà aligné et compare
trois fenêtres de même durée :

```text
0 ... 100 ms   : référence à amplitude réduite pour les deux valeurs
100 ... 200 ms : fenêtre porteuse réduite seulement pour un bit 1
200 ... 300 ms : référence à amplitude normale pour les deux valeurs
```

À 77 500 cycles de porteuse par seconde, chaque fenêtre contient exactement
7 750 résultats Goertzel. La sortie douce est :

```text
am_soft_bit = somme_normale + somme_réduite - 2 * somme_données
```

Une valeur positive favorise donc le bit 1 et une valeur négative le bit 0. Le
seuil nul provient des deux niveaux mesurés dans la seconde courante; le bloc ne
prend aucune décision dure et n'introduit pas de seuil d'amplitude arbitraire.

## Arithmétique et interface

- Les sommes disposent de `$clog2(WINDOW_CYCLES)+2` bits de garde afin de
  couvrir les trois termes du discriminateur sans rebouclage.
- `OUTPUT_SHIFT` adapte le produit AM/porteuse de grande largeur à la mémoire du
  futur décodeur.
- La réduction de largeur sature explicitement au lieu de reboucler.
- Le dernier échantillon de la fenêtre de référence est inclus dans le résultat.
- `bit_valid` dure un cycle et apparaît à 300 ms au point nominal.
- `carrier_position` rend l'alignement observable en simulation et sur analyseur.

Ce détecteur est une étape de bring-up et une source de bit doux. La
synchronisation AM haute immunité d'Engeler devra ensuite corréler l'enveloppe
avec les gabarits AM moyens sur plusieurs secondes, plutôt que supposer
`second_ce` connu.

`rtl/core/engeler_detector.sv` raccorde maintenant la banque Goertzel et ses
observables à cet extracteur AM et au pipeline PM/PRN. Il constitue la première
chaîne intégrée allant des échantillons ADC signés aux deux évidences douces.

## Vérification

Le test réduit utilise deux fenêtres de deux cycles. Il vérifie deux secondes
successives, l'impulsion de validité et des évidences exactes de -60 pour le cas
AM0 et +60 pour le cas AM1.
