# Pipeline IA FaultDiag

Ce dossier contient le pipeline PyTorch utilisé pour la preuve de faisabilité du diagnostic automatique des défauts d'isolement sur la boucle D.

## Contenu

- `configs/` : configuration d'entraînement du modèle tabulaire.
- `faultdiag/data/` : construction du dataset canonique à partir des sorties FaultSim.
- `faultdiag/models/` : modèle `TabularHierMLP`.
- `faultdiag/training/` : boucle d'entraînement, pertes, métriques et checkpoints.
- `faultdiag/evaluation/` : génération des figures d'évaluation.
- `scripts/` : scripts de test et de lancement rapide.
- `notebooks/` : notebook Colab de validation du pipeline.
- `results/` : métriques et journaux du run exploité dans le mémoire.

## Commandes principales

```bash
python -m faultdiag.data.build_dataset \
  --faultsim_dir /content/faultsim_raw/outputs/FaultSim \
  --out_dir /content/faultdiag_dataset \
  --exclude_classes HEALTHY \
  --min_class_count 5 \
  --loop_length_m 9007

python -m faultdiag.training.train \
  --config configs/baseline_tabular.yaml \
  --dataset_dir /content/faultdiag_dataset \
  --output_dir /content/runs \
  --epochs 120
```

## Résultat de référence

Run : `20260616_193519_tabular_hier_mlp_faultsim`

- Scénarios utilisés : 2212
- Features utilisées : 73
- Paramètres du modèle : 45586
- Meilleure époque : 28
- Accuracy test hold-out : 75,17 %
- Macro-F1 test hold-out : 76,29 %
- MAE localisation : 437,8 m
- Prédictions à ±120 m : 19,0 %

Les résultats doivent être interprétés comme une preuve de faisabilité. Le modèle classe bien les défauts francs et les ouvertures de circuit. La localisation reste une estimation de zone probable et ne valide pas encore l'objectif du tronçon inter-regards de 60 m.

## Données lourdes

Les fichiers bruts `.mat`, les caches Simulink et les sorties complètes de simulation ne sont pas versionnés. Ils doivent rester dans les exports locaux FaultSim.
