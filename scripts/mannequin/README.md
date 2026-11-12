# Personnage 3D des exercices

Le personnage animé de l'onglet Explorer (femme ou homme selon le profil) est produit entièrement par ces scripts.

## Origine du corps et des mouvements

- **Corps** : maillage, cibles de morphologie, squelette et poids proviennent de
  [MakeHuman](https://github.com/makehumancommunity/makehuman) (dossier `makehuman/data`), dont les ressources sont
  publiées dans le domaine public (**CC0 1.0**). Seule la morphologie (silhouette athlétique) est reprise ; tête de
  mannequin lisse, tenue de sport modélisée ici (short, brassière, liseré vert).
- **Marche, marche rapide et boxe dans le vide** : captures de mouvement du
  [CMU Graphics Lab Motion Capture Database](http://mocap.cs.cmu.edu) (conversion BVH de B. Hahne), base créée avec le
  financement de la NSF (EIA-0196217). Conditions : utilisation libre, y compris dans un produit commercial ;
  revente des données interdite, même converties.
- **Tous les autres mouvements** : poses clés écrites dans `motions.py`.

## Pipeline

1. `export.py <makehuman/data> [--preview dossier]` : morphologie (athlétique, proportions idéales), tête de mannequin
   lisse (sans visage), pose debout bras le long du corps, mains détendues ; tenue en coques séparées découpées
   selon des champs scalaires lisses (bords nets) ; export de `Growtin/Resources/Mannequin/mannequin-{female,male}.bin`
   et `mannequin.json`.
2. `motions.py` : bibliothèque des mouvements, écrite dans
   `Packages/GrowtinCore/Sources/GrowtinCore/Resources/motions.json` après contrôle des os et des régions.
   - poses clés en angles par articulation, ou par objectifs résolus par cinématique inverse (`ik.py`) : pieds qui
     restent posés (pas chassés, fentes, squats, cercles de hanches), mains posées sur les genoux, les cuisses,
     un mur, le crâne, mains jointes (arbre, salutation) ;
   - captures CMU reciblées (`mocap.py`) : rotations « monde » de chaque articulation depuis la pose en T,
     boucle choisie automatiquement puis fondue. Dossier des fichiers BVH : variable `CMU_BVH`.
3. `motion_eval.py <motions.json> <corps.npz> <planche.png> [ids]` : planche d'aperçu (même calcul que l'app :
   cinématique directe, skinning linéaire, mise au sol, décalages mis à l'échelle du corps). `MAXK=n` limite le
   nombre d'images par mouvement.
4. `solve_poses.py <corps.npz>` : outil d'auteur des poses au sol (à quatre pattes, tailleur, papillon, enfant).
5. `mocap_preview.py` : aperçu d'un extrait de capture avant de l'ajouter.

Les décalages de la racine sont calculés sur le squelette masculin ; `motions.json` porte sa hauteur de bassin
(`referenceHeight`) et l'app les met à l'échelle de chaque corps.

Format binaire `GTM4` : en-tête (`GTM4`, nombre de maillages), puis pour chaque maillage (corps, puis vêtements) :
matière (uint32 : 0 peau, 1 tissu, 2 liseré), nombre de sommets, nombre d'indices (uint32), positions et normales
(float32 ×3), indices d'os (uint16 ×4), poids (float32 ×4), indices de triangles (uint32).
