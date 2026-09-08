# Goertzel RTL — premier étage Engeler

## Périmètre implémenté

`rtl/goertzel/goertzel_resonator.sv` implémente la récurrence :

```text
s[n] = x[n] + 2 cos(w) s[n-1] - s[n-2]
```

Les deux états sont multipliés par `k` toutes les 12 acquisitions. Cette mise à
l'échelle périodique est le mécanisme décrit par Engeler pour obtenir un détecteur
à mémoire exponentielle sans fenêtre glissante.

À 930 kéch/s et 77,5 kHz :

```text
échantillons par porteuse = 12
2 cos(2 pi / 12)          = sqrt(3)
coefficient Q2.17         = 227023
```

Le bloc sature explicitement les états et fournit un drapeau `overflow`
persistant. `cycle_valid` marque le résultat mis à l'échelle de chaque cycle de
porteuse. Le point binaire des états est celui des échantillons d'entrée; les
coefficients sont en Q2.17.

## Banque des trois détecteurs

`rtl/goertzel/engeler_goertzel_bank.sv` instancie les chemins :

| Chemin | Bande visée | Coefficient `k` Q2.17 |
|---|---:|---:|
| porteuse | valeur initiale étroite | 131059 |
| AM | environ 15 Hz | 130993 |
| PM | environ 930 Hz | 126157 |

Les valeurs AM et PM proviennent de l'approximation documentée
`B_3dB ~= 0.32 (1-k) Fc`, arrondie au format fixe. La valeur porteuse est seulement
une valeur initiale : la future boucle de discipline devra pouvoir la resserrer.

## Contrat et limites

- Un échantillon n'est accepté que lorsque `sample_ce` vaut 1.
- Les trois chemins reçoivent exactement le même flux et leurs `cycle_valid`
  doivent rester alignés.
- `overflow` est persistant jusqu'au reset afin qu'une largeur insuffisante ne
  passe pas inaperçue.
- `goertzel_complex_12.sv` convertit les deux états en composantes réelle et
  imaginaire avec `cos(pi/6)` et `sin(pi/6)` en Q1.17.
- `engeler_observables.sv` calcule directement le produit scalaire AM/porteuse et
  le produit vectoriel PM/porteuse. Cette rotation implicite évite un calcul
  d'angle dans le chemin principal.
- Les métriques AM et PM restent volontairement non normalisées et conservent
  toute la précision des produits. Leur normalisation sera figée après les
  campagnes de dynamique et de bruit.
- Les largeurs et coefficients définitifs ne sont pas encore gelés. Ils devront
  être qualifiés avec le générateur de signal bit-exact et les captures ADC.

## Vérification actuelle

Le banc `sim/engeler_goertzel_bank_tb.sv` injecte quatre cycles d'une porteuse à
12 phases, avec des pauses entre acquisitions. Il compare les six états à des
vecteurs entiers de référence, vérifie les quatre impulsions `cycle_valid` et
refuse toute saturation inattendue.

Avant de déclarer cet étage terminé, il reste à ajouter :

1. les tests formels de saturation et de maintien sans `sample_ce`;
2. des balayages fréquence/amplitude/bruit issus du modèle Python;
3. la synthèse ECP5 et le relevé LUT/DSP/fréquence maximale;
4. la normalisation des observables et la corrélation AM;
5. le CORDIC nécessaire aux sorties explicites de phase;
6. la validation sur une capture LTC1407A réelle.
