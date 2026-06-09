# Jumeau numerique d'une boucle de balisage aeronautique

Depot prive de conception et de modelisation d'une boucle AGL alimentee par
un regulateur DIAM4100. Le depot est volontairement limite aux documents,
modeles, scripts et resultats necessaires pour comprendre et reproduire le
travail de conception.

## Structure

```text
docs/
  Chapitre_I_Architecture_Balisage_ASECNA.docx
  Chapitre_II_Etat_de_l_art.docx
  Proposition_de_recherche_PFE.docx
  Jumeau_Numerique.docx

references/
  articles/
  cables/
  lighting/
  rcc/
  standards/
  transformers/

model/
  Cable.slx
  DIAM4100/
  OCEM_TI/
  FullLoop_DIAM4100/
```

## Contenu justifie

- `docs/` contient uniquement les quatre documents academiques du projet.
- `references/` contient les sources techniques strictement utilisees pour
  justifier les choix de modelisation : DIAM4100, TI, cable, feu, norme et
  article scientifique.
- `model/DIAM4100/` contient le modele SCR du regulateur, le parametrage, le
  gain scheduling, le sweep de Ki et les sorties de validation.
- `model/OCEM_TI/` contient le modele generique de transformateur
  d'isolement et les scripts de validation associes.
- `model/FullLoop_DIAM4100/` contient l'assemblage complet de la boucle :
  DIAM4100, cables, TI, charges, parafoudres placeholders et topologie.

## Ouverture rapide

Dans MATLAB, depuis la racine du depot :

```matlab
cd('model/FullLoop_DIAM4100')
FullLoop_openModel(6)
```

`FullLoop_openModel(6)` charge la brillance B5, initialise les parametres de
boucle et prepare le gain `Ki` depuis le sweep DIAM4100.

## Politique de versionnement

Les caches Simulink, artefacts d'acceleration, sauvegardes automatiques,
fichiers temporaires, logs et brouillons ne sont pas versionnes. Le depot doit
rester une archive de conception, pas une copie brute du poste de travail.
