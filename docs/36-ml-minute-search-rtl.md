# Recherche ML minute et heure

`rtl/ml_decoder/minute_candidate_search.sv` commence l'étape de décodage
hiérarchique d'Engeler après acquisition de la position de seconde.

Le bloc mémorise les huit évidences douces correspondant aux bits DCF77 21 à 28,
génère les 60 mots BCD minute légaux et calcule leur corrélation. Le bit 28 est
recalculé comme parité paire des sept bits d'information : une erreur de parité
contribue donc au score au lieu de provoquer immédiatement le rejet de la trame.

## Architecture

Un seul candidat est évalué par cycle système. La recherche complète prend 60
cycles et évite de construire 60 corrélateurs parallèles. Pour chaque bit attendu :

```text
attendu 1 -> score += évidence
attendu 0 -> score -= évidence
```

Le meilleur et le deuxième score sont suivis pendant la recherche. `confident`
requiert à la fois `MIN_SCORE` et un écart `MIN_GAP`; le résultat et les métriques
restent visibles même si la confiance échoue.

## Historique et calendrier

`soft_history` conserve 3 600 observations dans un tableau synchrone compact
(AM, PM, validité, qualité et position de seconde). Cette écriture RTL portable
est destinée à l'inférence EBR ECP5 et ne contient aucune primitive constructeur.
Le contrôleur parcourt le tampon du plus récent au plus ancien et cadence les
moteurs partagés, au lieu de dupliquer les corrélateurs.

`calendar_candidate_search` généralise cette recherche séquentielle au jour du
mois, jour de semaine, mois, année et aux indicateurs CET/CEST, A1 et A2. Les
parités font partie des mots candidats et les trois métriques (meilleur,
deuxième, écart) sont conservées. La publication n'intervient qu'après trois
trames civiles consécutives cohérentes.

Les fonctions calendaires couvrent les années 2000--2099, les longueurs de mois,
le 29 février et le changement de date à minuit. Les sauts CET/CEST ne sont
acceptés que lorsqu'ils sont annoncés le dernier dimanche de mars/octobre. Une
seconde 60 est acceptée sous A2; elle allonge la minute mais ne duplique ni ne
saute l'horodatage de la minute suivante.

## Recherche de l'heure

`rtl/ml_decoder/hour_candidate_search.sv` applique la même architecture partagée
aux bits 29 à 35. Il évalue uniquement les 24 heures légales, recalcule la parité
paire des six bits BCD et termine en 24 cycles. Le moteur publie lui aussi le
meilleur score, l'écart au deuxième candidat et une confiance à deux seuils.

Le test de référence charge l'heure 18 et attend un score de 700. La gestion du
passage 23 -> 00 dans un historique multi-minute appartiendra au contrôleur ML,
pas au générateur d'un candidat isolé.
