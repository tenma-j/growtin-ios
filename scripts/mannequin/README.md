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
   lisse (sans visage), pose debout bras le long du corps, mains détendues, poids lissés aux pliures (épaules,
   hanches, coudes, genoux). La tenue fait partie de la surface du corps : la peau est découpée le long de courbes
   nettes (champs scalaires lisses), la zone de tissu est légèrement gonflée et lissée ; rien ne peut passer à travers.
   Près des lignes de la tenue, les triangles sont subdivisés (milieux replacés sur la surface lisse) et les champs
   sont recalculés exactement sur chaque nouveau sommet : bords droits et bretelles nettes, même pour une bande plus
   étroite qu'un triangle du corps.
   Export de `Growtin/Resources/Mannequin/mannequin-{female,male}.bin` (un maillage par matière) et `mannequin.json`.
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

`motions.json` (format 3) contient une version de chaque mouvement par corps (`bodies.male`, `bodies.female`) :
le script est rejoué pour chaque squelette, si bien que les mains jointes se touchent et que les pieds restent posés
pour l'homme comme pour la femme. Bras levés : la clavicule et l'omoplate participent au mouvement (rythme
scapulo-huméral), ce qui évite l'épaule écrasée du skinning linéaire. Mouvements au lit : `support` donne la hauteur
du matelas sur lequel le corps repose.

Articulations d'appoint (`upperarm01-half.L`, `lowerarm01-half.L`, `upperleg01-half.L`, `lowerleg01-half.L` et leurs
pendants à droite) : placées au même point que l'os qu'elles doublent (champ `half` dans `mannequin.json`), elles
prennent la moitié de sa rotation. Dans une pliure (épaule, coude, hanche, genou), la peau partagée entre deux os est
répartie entre le parent, l'appoint et l'os, si bien qu'aucun mélange ne dépasse la moitié de l'angle : la pliure
reste arrondie au lieu de se pincer en angle vif. Elles ne figurent pas dans les poses : l'app et les aperçus les
recalculent à chaque image.

Huit influences d'os par sommet (`INFLUENCES` dans `export.py`) : autour des épaules, jusqu'à 7 os comptent ; avec 4,
certains sommets perdaient jusqu'à 28 % de leur poids et la peau se froissait entre la bretelle et le cou, bras levés.

Dans l'app, la surface est déformée sur le processeur (`SurfaceDeformer`, GrowtinCore) : skinning linéaire, puis
normales recalculées sur les triangles déformés (sommets dédoublés le long de la tenue soudés). Le skinning du GPU
se contentait de tourner les normales avec les os ; dans une pliure très ouverte (épaule bras levés), elles déviaient
jusqu'à 90° de la surface réelle et l'éclairage dessinait une tache blanche.

Format binaire `GTM5` (lu par `MannequinFile`, GrowtinCore) : en-tête (`GTM5`, nombre de maillages, influences par
sommet), puis pour chaque maillage (peau, tissu, liseré, découpés dans la même surface) : matière (uint32 : 0 peau,
1 tissu, 2 liseré), nombre de sommets, nombre d'indices (uint32), positions et normales (float32 ×3), indices d'os
(uint16 × influences, de la plus forte à la plus faible), poids (float32 × influences), indices de triangles (uint32).
