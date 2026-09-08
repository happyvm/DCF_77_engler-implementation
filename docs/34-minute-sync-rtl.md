# Synchronisation minute PM en RTL

`rtl/sync/pm_minute_sync.sv` ajoute la première recherche hiérarchique de
synchronisation temporelle au pipeline Engeler. Le bloc reçoit une corrélation
PRN douce par seconde et recherche le motif PM connu :

```text
secondes 0 ... 9  : 1111111111, PRN inversé
secondes 10 ... 14: 00000,      PRN normal
```

## Recherche et confiance

Une fenêtre glissante de 15 secondes calcule un score signé à chaque nouvelle
seconde. Pendant 60 positions successives, le bloc conserve :

- la magnitude du meilleur score;
- la magnitude du deuxième score;
- la position de fin de la meilleure fenêtre;
- la polarité RF observée.

Après la soixantième hypothèse, `result_valid` publie les résultats. `locked`
n'est affirmé que si le meilleur score dépasse `MIN_SCORE` et si son écart au
deuxième dépasse `MIN_GAP`. Ces seuils sont des paramètres de qualification et
ne doivent pas être figés avant les campagnes de bruit.

La recherche utilise la valeur absolue du score pour tolérer une inversion de
polarité dans l'antenne ou la chaîne analogique. La sortie
`pm_polarity_inverted` mémorise le signe du candidat gagnant afin que les futurs
bits PM puissent être remis dans la convention logique choisie.

## Interprétation de la position

`best_window_end` est un index relatif à la campagne de 60 hypothèses qui vient
de se terminer. Il désigne la position où la fenêtre `111111111100000` s'est
achevée, donc la seconde DCF77 14 lorsque la réception est alignée. Le futur
contrôleur de temps convertira cet index relatif en impulsion de début de minute.

Le bloc est raccordé à la sortie PM dans `rtl/core/engeler_detector.sv`. Les
seuils, le verrouillage, la polarité, la meilleure magnitude et l'écart de
qualité sont exposés au futur contrôleur temporel plutôt que masqués dans le
détecteur.

## Limites actuelles

- Le bloc cherche une seule suite ordinaire; le décalage du marqueur pendant une
  seconde intercalaire reste à intégrer.
- Les seuils par défaut sont nuls pour permettre la simulation. Un profil de
  production doit fournir des seuils issus des statistiques AWGN et RF réelles.
- La stabilité du gagnant sur plusieurs campagnes de 60 secondes n'est pas
  encore imposée.
- L'estimation AM grossière doit ensuite réduire la zone de recherche et le coût
  de mémorisation dans l'intégration finale.
