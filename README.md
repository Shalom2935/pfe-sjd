# Jumeau numerique d'une boucle de balisage aeronautique

Depot prive de conception et de reproduction pour une boucle AGL alimentee
par un regulateur DIAM4100. Le depot versionne le modele source, les scripts
de parametrage, les documents de conception et les resultats compacts
necessaires pour verifier la demarche. Les modeles et sorties generes
localement ne sont pas versionnes.

## Prerequis

- MATLAB R2023a ou compatible.
- Simulink.
- Simscape Electrical / Specialized Power Systems.
- Git.

Le modele FaultSim complet est genere localement a partir du modele source.
Ne pas versionner `AGL_FullLoop_DIAM4100_faultsim.slx`, les caches Simulink
ou les sorties lourdes de campagne.

## Installation

Cloner le depot prive puis ouvrir MATLAB :

```bash
git clone https://github.com/Shalom2935/pfe-sjd.git
cd pfe-sjd
```

Dans MATLAB :

```matlab
repo = '<chemin-vers-le-depot>';
cd(fullfile(repo, 'model', 'FullLoop_DIAM4100'))
addpath(pwd)
addpath(fullfile(pwd, 'FaultSim'))
```

## Structure utile

```text
docs/
  Chapitre_I_Architecture_Balisage_ASECNA.docx
  Chapitre_II_Etat_de_l_art.docx
  Proposition_de_recherche_PFE.docx
  Jumeau_Numerique.docx

references/
  Sources techniques utilisees pour DIAM4100, TI, cables, feux, normes et
  articles.

model/
  DIAM4100/              Modele et validation du regulateur.
  OCEM_TI/               Modele generique des transformateurs d'isolement.
  FullLoop_DIAM4100/     Boucle complete et campagne FaultSim.
```

## Ouvrir le modele source

Le modele source versionne est :

```text
model/FullLoop_DIAM4100/AGL_FullLoop_DIAM4100.slx
```

Pour l'ouvrir avec les parametres DIAM4100 et le gain `Ki` issus du sweep :

```matlab
cd(fullfile(repo, 'model', 'FullLoop_DIAM4100'))
FullLoop_openModel(6)   % B5 ; utiliser 1..6 pour B0..B5
```

Le modele exporte notamment `u_RCC`, `i_RCC`, `DIAM4100_Irms` et sept mesures
internes de courant.

## Regenerer le modele FaultSim

Le modele de defauts n'est pas pousse sur GitHub. Le regenerer localement :

```matlab
cd(fullfile(repo, 'model', 'FullLoop_DIAM4100', 'FaultSim'))

FaultSim_prepareModel( ...
    'ForceRebuild', true, ...
    'Mode', 'smoke')
```

Cette commande cree localement :

```text
model/FullLoop_DIAM4100/AGL_FullLoop_DIAM4100_faultsim.slx
```

Le modele source `AGL_FullLoop_DIAM4100.slx` n'est pas modifie.

## Reproduire le smoke test

Le smoke test valide la topologie de defaut, les exports RCC et l'extraction
des features sur les 8 classes de defaut.

```matlab
cd(fullfile(repo, 'model', 'FullLoop_DIAM4100', 'FaultSim'))

FaultSim_runBatch( ...
    'Mode', 'smoke', ...
    'RebuildModel', false, ...
    'OverwriteExisting', true)
```

Les fichiers raw sont generes dans :

```text
model/FullLoop_DIAM4100/outputs/FaultSim/raw/smoke/
```

Les features et logs sont generes avec un tag de plage, par exemple :

```text
outputs/FaultSim/features/FaultSim_features_smoke_000001_000008.csv
outputs/FaultSim/logs/FaultSim_runlog_smoke_000001_000008.csv
```

Le depot conserve seulement la synthese compacte de reference :

```text
model/FullLoop_DIAM4100/outputs/FaultSim/metadata/FaultSim_smoke_summary.csv
```

## Reproduire la campagne complete

La configuration actuelle genere 19 836 scenarios. Le temps de simulation est
de `1.10 s`; seules les dernieres `0.10 s` stables sont sauvegardees et
utilisees pour les features. A 50 Hz, cette fenetre correspond a 5 periodes
et 1000 echantillons a 10 kHz.

Generer d'abord le modele FaultSim :

```matlab
FaultSim_prepareModel( ...
    'ForceRebuild', true, ...
    'Mode', 'full', ...
    'AcceptUnvalidatedRanges', true)
```

Verifier la taille de la table sans lancer la campagne :

```matlab
sc = FaultSim_buildScenarioTable( ...
    'Mode', 'full', ...
    'AcceptUnvalidatedRanges', true);
height(sc)
```

Faire un pre-run court :

```matlab
FaultSim_runBatch( ...
    'Mode', 'full', ...
    'AcceptUnvalidatedRanges', true, ...
    'RebuildModel', false, ...
    'StartAt', 1, ...
    'EndAt', 200, ...
    'RunTag', 'prerun')
```

La campagne peut etre executee par plages avec `StartAt`, `EndAt` et
`RunTag`. Ces parametres servent seulement a identifier et isoler une plage de
scenarios dans les fichiers produits :

```matlab
FaultSim_runBatch('Mode','full','AcceptUnvalidatedRanges',true, ...
    'RebuildModel',false,'StartAt',1,'EndAt',5000,'RunTag','plage_1')
```

`MaxScenarios` reste disponible et s'applique apres `StartAt` :

```matlab
FaultSim_runBatch('Mode','full','AcceptUnvalidatedRanges',true, ...
    'StartAt',5001,'MaxScenarios',5000,'RunTag','plage_2')
```
