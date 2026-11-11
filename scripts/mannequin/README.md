# Personnage 3D des exercices

Le personnage animé de l'onglet Explorer (femme ou homme selon le profil) est produit entièrement par ces scripts.

## Origine du corps

Maillage, cibles de morphologie, squelette et poids proviennent de
[MakeHuman](https://github.com/makehumancommunity/makehuman) (dossier `makehuman/data`), dont les ressources sont
publiées dans le domaine public (**CC0 1.0**). Aucun autre modèle tiers n'est utilisé.

## Pipeline

1. `export.py <makehuman/data> [--preview dossier]` : morphologie (athlétique, proportions idéales), tête de mannequin
   lisse (sans visage), pose debout bras le long du corps, régions musculaires et tenue (short, brassière),
   export de `Growtin/Resources/Mannequin/mannequin-{female,male}.bin` et `mannequin.json`.
2. `motions.py` : bibliothèque des mouvements (poses clés en angles par articulation, accessoires, cadrage),
   écrite dans `Packages/GrowtinCore/Sources/GrowtinCore/Resources/motions.json` après contrôle des os et des régions.
3. `motion_eval.py <motions.json> <corps.npz> <planche.png> [ids]` : aperçu des poses clés (même calcul que l'app :
   cinématique directe, skinning linéaire, mise au sol).
4. `solve_poses.py <corps.npz>` : outil d'auteur qui calcule les angles des poses au sol à partir de contraintes
   (mains sous les épaules, genoux sous les hanches…).

Format binaire `GTM3` : en-tête (`GTM3`, nombre de sommets, nombre d'indices), positions et normales (float32 ×3),
indices d'os (uint16 ×4), poids (float32 ×4), attributs (uint8 ×4 : région A, région B, mélange, part de tissu),
indices de triangles (uint32).
