# Modele complet de boucle AGL - DIAM4100

Ce dossier contient la version modulaire de la boucle complete alimentee par
le DIAM4100.

## Fichiers principaux

- `AGL_FullLoop_DIAM4100.slx` : modele Simulink de la boucle complete.
- `AGL_FullLoop_DIAM4100.before_regard_topology_fix.slx` : sauvegarde du
  modele avant la correction de topologie des regards equipes.
- `FullLoop_simParams.m` : parametres centralises de la boucle complete.
- `FullLoop_TI_database.m` : table finale des parametres TI OCEM.
- `FullLoop_prepareDIAM4100.m` : initialise le DIAM4100 detaille avec la
  brillance active et le Ki interpole depuis le sweep.
- `FullLoop_lookupKiFromSweep.m` : interpolation de Ki depuis
  `model/DIAM4100/figures/DIAM4100_Ki_best_schedule.csv`.
- `FullLoop_patchTopologyOpenXML.py` : corrige le `.slx` courant sans ecraser
  le sous-systeme DIAM4100 modifie manuellement.
- `outputs/FullLoop_load_topology.csv` : placement des charges et TI.
- `outputs/FullLoop_cable_segments.csv` : segmentation du cable.
- `outputs/FullLoop_surge_topology.csv` : placement des parafoudres.

## Architecture retenue

Le DIAM4100 est conserve comme sous-systeme Simulink avec deux ports
electriques externes. La boucle aval est construite avec :

- 50 sections de cable `Pi Section Line`;
- 51 transformateurs d'isolement saturables;
- 51 charges secondaires resistives;
- 15 placeholders de parafoudres;
- 7 points de mesure courant exportes vers le workspace;
- 2 exports de tete RCC : `u_RCC(t)` et `i_RCC(t)`.

Le primaire de chaque transformateur d'isolement est insere en serie dans la
boucle par les ports `lconn:1` et `lconn:2`. La charge secondaire est fermee
uniquement sur l'enroulement secondaire, entre `rconn:1` et `rconn:2`.

## Exports de simulation

Le modele exporte les signaux suivants au format `Timeseries` :

- `u_RCC` : tension instantanee entre les ports externes `+` et `-` du
  sous-systeme `Diam4100_CCR`.
- `i_RCC` : courant instantane en tete de boucle, mesure par le capteur de
  courant de sortie du DIAM4100.
- `DIAM4100_Irms` : courant RMS utilise par la regulation interne du DIAM4100.
- `FullLoop_I_MEAS_001`, `FullLoop_I_MEAS_010`, `FullLoop_I_MEAS_020`,
  `FullLoop_I_MEAS_030`, `FullLoop_I_MEAS_040`, `FullLoop_I_MEAS_050` et
  `FullLoop_I_MEAS_051` : courants instantanes aux points de mesure internes
  de la boucle.

## Geometrie de boucle

- Longueur totale de boucle : 9007 m.
- Regards equipes : 49.
- Distance entre deux regards equipes consecutifs : 60 m.
- Feux : 47 regards avec un TI chacun.
- Manches a vent : 2 regards, chacun avec deux TI de 45 W au meme endroit.
- Distance du RCC au premier regard : 3063,5 m.
- Distance du dernier regard au RCC : 3063,5 m.
- Segmentation cable : 3063,5 m + 48 x 60 m + 3063,5 m.

Cette structure explique pourquoi il ne doit pas y avoir plusieurs sections
PI de 60 m entre deux transformateurs consecutifs. Les longues sections de
cable n'apparaissent qu'entre le RCC et les extremites de la zone equipee.

## Charges modelisees

| Groupe | Nombre de regards | Modules TI/charge | Charge secondaire | TI |
| --- | ---: | ---: | ---: | ---: |
| Feux 65 VA | 3 | 3 | 65 VA | 150 W |
| Feux 39 VA | 23 | 23 | 39 VA | 65 W |
| Feux 8 VA | 13 | 13 | 8 VA | 25 W |
| Feux 23 VA | 6 | 6 | 23 VA | 65 W |
| Feux 22 VA | 2 | 2 | 22 VA | 65 W |
| Manches a vent | 2 | 4 | 45 VA provisoire | 45 W |

Pour les manches a vent, la charge secondaire exacte reste a confirmer par
datasheet locale. La valeur provisoire est egale a la puissance nominale du TI
de 45 W.

## Parametrage TI

Les transformateurs d'isolement utilisent le bloc Simulink generique
`Saturable Transformer`. Les valeurs ne sont pas codees en dur dans les blocs :
elles sont centralisees dans `FullLoop_TI_database.m` a partir du tableau final
valide pour les puissances 25 W, 45 W, 65 W, 150 W, 200 W et 300 W.

La fuite `Ldp = Lds` est calculee par interpolation lineaire a partir des
points experimentaux `P_ref = [45, 150] W` et
`Ld_ref = [0.370, 1.19] mH`.

## Ouverture dans MATLAB

Depuis la session MATLAB ou Simulink est deja disponible :

```matlab
cd('C:\Users\KSSS\Documents\Claude\Projects\Projet Fin d''Etude (PFE)\model\FullLoop_DIAM4100')
FullLoop_openModel(6)   % B5 ; utiliser 1..6 pour B0..B5
```

Le script charge `FullLoop`, prepare la structure `DIAM4100`, interpole `Ki`
depuis le sweep et ouvre `AGL_FullLoop_DIAM4100.slx`.

## Points a raffiner

1. Remplacer les placeholders de parafoudres par un modele MOV non lineaire
   des que la fiche technique est fixee.
2. Remplacer l'hypothese de charge des manches a vent par la valeur issue de
   la documentation constructeur.
3. Lancer une simulation courte, puis verifier le conditionnement numerique
   avec les 51 transformateurs saturables.
