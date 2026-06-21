# Résultats du run TabularHierMLP

Run : `20260616_193519_tabular_hier_mlp_faultsim`

Ce dossier conserve les résultats textuels du run utilisé dans le chapitre IV du mémoire. Les checkpoints binaires, les images lourdes, les sorties `.mat` et les caches Simulink ne sont pas versionnés ici.

## Synthèse

| Métrique | Valeur |
|---|---:|
| Best epoch | 28 |
| Accuracy test hold-out | 75,17 % |
| Balanced accuracy test | 76,46 % |
| Macro-F1 test | 76,29 % |
| MAE localisation | 437,8 m |
| Médiane erreur localisation | 354,7 m |
| P90 erreur localisation | 918,2 m |
| Prédictions à ±60 m | 7,9 % |
| Prédictions à ±120 m | 19,0 % |

## Interprétation

Le modèle distingue très bien `EARTH_SHORT` et `OPEN_CIRCUIT` sur le jeu de test considéré. Les classes `HUMIDITY_PROGRESSIVE` et `REACTIVE_INCIPIENT` restent partiellement confondues. Cette confusion est cohérente avec la proximité physique des défauts progressifs résistifs et réactifs lorsqu'ils sont observés uniquement depuis la tête de boucle.

La localisation n'atteint pas encore l'objectif du tronçon inter-regards. La distance prédite doit être utilisée comme une indication de zone probable.

## Note sur le split spatial

Les fichiers `test_spatial` du run original étaient identiques au test aléatoire. Ils ne sont donc pas utilisés comme preuve de validation spatiale stricte. Un vrai split spatial doit être généré dans une étape ultérieure.
