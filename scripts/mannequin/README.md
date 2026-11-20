# Personnage 3D des exercices

Le personnage animé de l'onglet Explorer (femme ou homme selon le profil) est produit entièrement par ces scripts.

## Origine du corps et des mouvements

- **Corps** : maillage, cibles de morphologie, squelette et poids proviennent de
  [MakeHuman](https://github.com/makehumancommunity/makehuman) (dossier `makehuman/data`), dont les ressources sont
  publiées dans le domaine public (**CC0 1.0**). Seule la morphologie (silhouette athlétique) est reprise ; tête de
  mannequin lisse, tenue de sport modélisée ici (short, brassière, liseré vert).
- **Tous les mouvements** (marche et boxe dans le vide comprises) : poses clés écrites dans `motions.py`. Plus aucun ne
  vient d'une capture : les deux captures de marche du [CMU Graphics Lab Motion Capture Database](http://mocap.cs.cmu.edu)
  utilisées jusque-là avaient le genou d'appui plié de 20 à 30° (marche « accroupie »). L'outil de reciblage (`mocap.py`,
  `mocap_preview.py`) reste disponible ; conditions de la base : utilisation libre, y compris dans un produit commercial,
  revente des données interdite, même converties (financement NSF EIA-0196217).

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
     un mur, le crâne, mains jointes (arbre, salutation : doigts tendus dans le plan de la paume, pouces le long
     des index). Mains posées sur les cuisses (assis) et sur le genou (étirement « 4 ») : orientées dans le
     prolongement de l'avant-bras (coudes vers l'arrière, doigts un peu vers l'intérieur), le poignet reste incliné
     de moins de 25° sur le côté ; au-delà, le skinning le casse en arête. Étirement de l'arrière des cuisses : une
     main sur la cuisse tendue, l'autre sur le genou plié (un bras tendu vers l'autre jambe traverserait ce genou) ;
   - contacts : le script lit les corps de l'app (`Growtin/Resources/Mannequin`, même skinning). Une main placée
     par objectif, puis chaque main de chaque image clé, qui s'enfonce dans le corps est ramenée à sa surface le
     long de la normale de la peau (2 mm de jeu), avec la même orientation et le coude du même côté. Les objectifs
     des mains posées sont donc pris un peu sous la peau : la mise en contact les pose exactement dessus, quelle que
     soit la morphologie. Quand le buste, les épaules ou le bassin bougent (respiration, haussements d'épaules,
     abdos, extension du dos, cercles de hanches), `keep_hands` garde les mains au même endroit de la partie du corps
     qui les porte. Une transition où une main traverserait le corps reçoit trois points de passage, mains écartées
     de 3 cm de la peau, sur la même courbe de vitesse. Environ vingt minutes pour les deux corps ;
   - appuis fixes (pompes inclinées, pont fessier, chat-vache, posture de l'enfant, rowing) : l'app interpole des angles,
     un appui dériverait entre deux clés éloignées. `planted` découpe la transition en clés rapprochées où mains,
     pieds et genoux sont résolus à chaque fois ; les hauteurs sont réglées sur la peau (paumes, genoux, front, dos
     touchent le sol ensemble). `flat_hands` écarte le pouce dans le plan de la paume d'une main posée à plat ;
   - serviette (`"kind": "towel"`) : une bande qui passe à plat sous la voûte du pied avant, puis monte de chaque
     côté jusqu'à un poing. Champs : `vertices` (trois indices de sommets de la peau : paume gauche, dessous de la
     voûte du pied, paume droite, calculés pour chaque corps), `backs` et `depth` (sommet du dos de chaque main, en
     face de celui de la paume, et distance dont le bout du brin s'écarte de la paume à l'opposé du dos de la main :
     il est tenu dans le creux du poing, pas sur la peau ; `TowelPath.grip`), `under` (les deux points au sol où la
     bande sort de sous le pied, en décalages horizontaux `[x, z]` depuis le sommet du pied : d'abord celui du brin de
     la main gauche, puis celui de la main droite ; ils sont à 12 mm du contour du pied), `width` et `thickness`
     (section de la bande à plat, en mètres ; elle se resserre à 22 × 12 mm dans le poing). L'app (`TowelPath`,
     GrowtinCore) et les planches (`towel_segments`, `motion_eval.py`) tracent les mêmes trois tronçons, sans vrille :
     la largeur de la bande reste dans l'axe du pied. Une serviette ne s'allonge pas : chaque poing se déplace sur une
     sphère centrée sur le point où son brin sort de sous le pied (longueur totale constante à quelques millimètres
     près, grâce à des clés rapprochées), des bras tendus vers l'avant jusqu'aux côtes basses. Le brin entre dans
     le poing du côté de l'auriculaire, en travers de la paume (le poignet s'incline de 20° au plus pour rester dans
     cet axe) ; sa profondeur dans le poing et la fermeture de chaque doigt sont réglées sur la peau : la bande
     passe à 1,5 mm de la paume et des doigts qui l'entourent, sans les traverser ; le pied avant est surélevé de
     l'épaisseur de la bande ;
     les poings sont placés de part et d'autre du pied avant, et leur écart est élargi jusqu'à ce que les brins
     passent à 6 mm au moins de la peau sur toute la course (`towel_clearance`, 11 positions : pied avant, tibias,
     genoux, cuisses, bras ; le script s'arrête en erreur s'il n'y parvient pas) ;
   - scan corporel au lit (`bed-scan-*`) : le corps repose vraiment sur le matelas. La hanche s'étend jusqu'à ce que
     mollets et talons touchent, le dos des mains est posé (hauteur du poignet réglée à chaque clé). L'oreiller
     (`pillow_under`) est réglé sur la peau de chaque corps : son dessus au point le plus bas du crâne (la tête s'y
     enfonce de 1 mm), son bord côté pieds juste avant la nuque (plus loin, le cou et les épaules y entreraient), sa
     taille à la mesure d'une tête (`depth` 26 cm le long du lit, `width` 48 cm en travers ; 34 × 56 cm par défaut),
     taie bleu-gris qui se détache du drap. Réglé auparavant sur le bas du cou et par un décalage fixe depuis
     l'articulation de la tête, il laissait la tête 6 à 17 mm au-dessus (48 mm menton levé) et posée sur son bord. Le
     cou se règle pour que le crâne reste posé quand la tête tourne (`scan_solve`).
     La respiration soulève le milieu du buste par des rotations qui se compensent : bassin, épaules et tête ne bougent
     pas. Toutes les étapes partent de la même pose, dans le même lit (sans plaid, `"bare": true`, puisque les jambes
     y sont posées) : seuls le geste et le cadrage changent. Gestes lents mais francs, lisibles sur un téléphone :
     les pointes des pieds se redressent puis retombent, le ventre se soulève d'environ 3 cm, les mains se
     referment puis se déplient pendant que les épaules se décollent puis se déposent, la tête roule sur l'oreiller
     sans hochement ;
   - torsion allongée, genoux vers la poitrine (`laid`, `bed_pillow`) : même principe, mais chaque clé est placée
     exactement sur le matelas d'après toute la peau, sans la mise au sol automatique de l'app (qui échantillonne la
     peau, à quelques millimètres près) ; oreiller sous le crâne de chaque corps (`pillow_under` pour les genoux vers la
     poitrine) ;
   - genoux vers la poitrine (`knees_chest`) : cuisses ramenées sur le ventre (125° depuis la direction des pieds),
     genoux pliés, tibias parallèles à peu près horizontaux (talons vers les fesses), genoux écartés de la largeur du
     bassin ; jambes résolues par cinématique inverse (posées par des angles, les tibias s'écartaient en V et, vus d'en
     haut, semblaient dressés vers le plafond). Bassin en rétroversion réglé pour que sacrum et haut du dos touchent le
     matelas ensemble (la colonne rend la bascule, la tête reste sur l'oreiller) ; chaque main posée sur le devant de son
     genou, à la hauteur de la peau (main et avant-bras sans enfoncement), bras qui ne se croisent pas ; les mains
     ramènent les genoux de 15° vers la poitrine à l'expiration ; cadré sur le corps, presque de profil (10°), un peu
     d'en haut (20°) : la silhouette jambes repliées se lit (de trois quarts d'en haut, bras et tibias s'emmêlaient) ;
   - méditation assise : jambes croisées, la gauche devant, résolues par cinématique inverse ; la hauteur de chaque
     cheville est réglée pour que le pied touche le sol au niveau des fesses et des cuisses ; les deux tibias restent
     distincts (`leg_overlap` : aucun sommet d'une jambe sous la peau de l'autre, 4 mm de jeu au moins ; la cheville
     gauche avance s'il le faut). Dos des mains posé sur la cuisse juste en retrait du genou, paumes vers le ciel
     (hauteur du poignet réglée sur la peau), coudes souples près du corps, épaules basses (clavicules abaissées de 5°) ;
     vu un peu d'en haut (22°) pour que les paumes posées se voient. Bassin basculé de 9° vers l'avant (dos droit),
     tapis centré sous le corps ;
   - étapes « Visage » (`bed-scan-face`, `chair-face`) : le mannequin n'a pas de visage ; contraction et relâchement se
     lisent sur les épaules et la tête, cadrées de près, sans hochement (relaxation : épaules hautes et tête rentrée
     sans basculer, tenues 5 s, puis relâchement net et 10 s de respiration calme ; scan : épaules qui se déposent et
     tête qui roule sur l'oreiller) ;
   - respirations assises (`chair-breathe`, `abs-contract`) : poitrine qui se soulève et épaules qui montent un peu,
     tête droite ; ventre contracté : bas du dos arrondi, côtes basses vers le bassin, cadré sur le buste, de profil ;
   - torsion allongée (`twist_pose`) : sur le dos, genoux pliés, pieds à plat sur le matelas (lit sans plaid), bras
     ouverts en V. Les genoux tombent ensemble d'un côté : le bassin roule de 45°, les hanches font le reste ; la jambe
     du dessous s'arrête quand son côté touche le matelas, celle du dessus quand elle touche l'autre (les jambes sont
     prises comme des volumes autour de leurs os, mesure qui reste juste même si elles se traversaient ; du milieu
     des cuisses aux pieds, pas plus serrées qu'au repos à 6 mm près). Les pieds roulent sur leur tranche presque sur
     place (centre déplacé de 9 mm au plus : ni le pied ni la peau posée ne glissent de plus de 15 mm). Le bassin qui roule sur une fesse soulève le sacrum : il bascule
     jusqu'à ce que le bassin (haut des cuisses compris) et le haut du dos touchent le matelas ensemble, et la colonne
     répartit entre ses étages la rotation qui le sépare du thorax, resté à plat : épaules et mains ne bougent pas.
     La tête tourne à l'opposé des genoux, le cou réglé pour que le crâne reste à la hauteur de l'oreiller. Clés
     rapprochées (12 par descente), cadrage resserré sur le corps, vu de haut depuis le pied du lit ;
   - assises (chaise, bord du lit) : la peau touche le dessus de l'assise sans s'y enfoncer. Sa hauteur est lue sur
     la peau de chaque corps dans la pose assise (`SEAT_TOP`, `SEAT_DROP` : fesses et cuisses plus ou moins épaisses ;
     0,5 mm de jeu) ; chaise et lit sont posés à cette hauteur sous le bassin. Au bord du lit, le matelas s'arrête
     12 cm devant le bassin (`BED_EDGE`) : la cuisse d'une jambe tendue talon au sol passe devant lui. Quand la pose
     change ce qui est posé (jambe qui se tend, buste qui se penche et fait pivoter le bassin), `on_seat` remonte le
     bassin à chaque clé jusqu'à ce que la peau touche de nouveau le matelas, pieds et mains résolus ensuite
     (étirement de l'arrière des cuisses : le buste bascule d'un bloc depuis les hanches, de 10° à 46°, dos long ;
     jambe tendue à 99,8 % de sa longueur, le bassin avance de 1 à 3 cm sur le matelas pour que le talon ne bouge
     pas ; la jambe se tend en glissant, pied à 12 mm du sol) ;
   - tempos des consignes de la relaxation : poings serrés 5 s puis 10 s de relâchement, épaules tenues 5 s, ventre
     contracté 5 s buste droit (bas de la colonne à peine fléchi, haut redressé d'autant) puis relâché lentement ;
   - squat sur chaise (`chair_squat`) : debout devant la chaise, les hanches reculent, le buste se penche, les bras
     montent devant ; les fesses descendent jusqu'à effleurer l'assise (descente du bassin réglée sur la peau, 1 mm de
     jeu), bassin au-dessus du milieu de l'assise, cuisses au-dessus d'elle, tibias presque verticaux, pieds résolus
     à chaque clé. La chaise (assise à 46 cm) est placée d'après chaque corps (45 cm pour la femme), en coordonnées du sol (sans ancre) :
     son milieu sous les hanches en bas du squat, son bord avant au moins 1 cm derrière les mollets du personnage
     debout. Une ancre sur une image clé numérotée ne convient pas ici : des clés intermédiaires sont ajoutées
     après coup, et la chaise s'était retrouvée réglée sur une pose presque debout (assise à 77 cm) ;
   - porte (`"kind": "door"`) : bras en chandelier, coudes à hauteur d'épaule, avant-bras verticaux et paumes à plat
     sur la face des montants (réglés sur la peau, 1 mm de jeu). `width` donne la distance entre les axes des
     montants, à la mesure de chaque corps ; les avant-bras ne bougent plus pendant que le corps avance d'un bloc
     depuis les chevilles (penché d'une dizaine de degrés en fin de course, regard horizontal). Vue de trois quarts
     arrière (110°) : les deux avant-bras et les deux mains se voient sur leur montant (de face, le montant proche
     cachait le sien). Même cadrage pour les deux corps : de la tête et du bout des doigts aux orteils, avec la plus
     petite marge (calcul de CameraFraming) qui montre le linteau (2,12 m) : 0,05 m pour l'homme, 0,2 m pour la femme ;
   - marches sur place (`march_foot`) : le pied se déroule (talon levé, pointe posée), monte à la verticale de son
     appui, n'avance qu'une fois en l'air, redescend de même ; les deux pieds sont résolus à chaque clé (32 clés par
     cycle), ils ne glissent pas au sol ;
   - marche et marche soutenue (`walk_foot`, `walk_pose`, `walking`) : écrites par objectifs, sur place, le sol défilant
     sous le corps à vitesse constante. Chaque pied suit le cycle réel (attaque du talon pointe relevée, pied à plat,
     talon qui se lève en roulant sur l'avant-pied, poussée, passage du pas) ; le pied d'appui est posé sur le sol
     d'après sa peau. Le bassin est porté par la jambe d'appui presque tendue (genou à 170–172° au milieu de l'appui, 158–162° juste après la pose du talon, quand elle amortit),
     monte au passage à la verticale, redescend au double appui (le talon se pose à l'instant où la jambe arrière a
     amené le bassin à la même hauteur : `front` est résolu pour cela), se décale vers la jambe d'appui et tourne avec
     la jambe qui avance ; les épaules tournent à l'opposé, la tête reste de face. Promenade : un cycle en 1,2 s, bras
     souples à l'opposé des jambes ; marche soutenue : un cycle en 0,92 s, coudes à 90°, poings qui montent à hauteur
     de poitrine. 40 et 36 clés par cycle ;
   - captures reciblées (`mocap.py`, liste `MOCAP`, vide aujourd'hui) : rotations « monde » de chaque articulation
     depuis la pose en T, boucle choisie automatiquement puis fondue. Dossier des fichiers BVH : variable `CMU_BVH` ;
   - bras levés (`reach_arm`, `overhead_y`, `joined_up`) : la main est visée depuis l'épaule une fois montée avec le
     bras (rythme scapulo-huméral). Visée depuis l'épaule au repos, elle arrivait trop près et le coude pliait à angle
     droit (bras « en losange » de la salutation et de l'arbre). Grands cercles de bras de l'échauffement
     (`warm_arm`) : montée par l'avant, descente par le côté, 22° en arrière du plan des épaules, jamais tendu droit
     derrière le dos ;
   - verre tenu (`"kind": "glass"`, pause) : cylindre posé contre la paume droite. Champs : `vertices` (trois sommets
     de la peau de la main : creux de la paume, bord de la paume côté index, dos de la main en face du premier),
     `depth` (distance de la paume à l'axe du verre), `width` (diamètre), `height`. L'app (`HeldGlass`, GrowtinCore) et
     les planches (`glass_pose`, `glass_mesh`, `motion_eval.py`) le placent de la même façon à chaque image. Dans
     `motions.py`, on donne le centre et l'axe du verre : la main s'en déduit (`glass_hand`), sa distance à la paume
     et la fermeture de chaque doigt et du pouce sont réglées sur la peau ; pendant les pas, le bras droit garde le
     verre devant le ventre (`glass_steps`) ;
   - cercles dans les deux sens (`both_ways` : épaules de la mobilité du matin, hanches) : deux tours dans un sens,
     arrêt progressif, deux tours dans l'autre. Cercles de hanches : le bassin tourne au-dessus des pieds posés et la
     colonne se courbe à l'opposé, résolue pour que la tête ne bouge pas ; flexion avant : le dos s'enroule étage par
     étage (tête, haut du dos, bas du dos, bassin) et se déroule dans l'ordre inverse (`fold`) ; mollets : les talons
     tournent autour de la base des orteils, qui ne glissent pas (`calf_raise`) ;
   - salutation des bras : entre l'horizontale et le haut, une clé bras à 135° devant soi (interpolés directement, les
     bras s'ouvraient en V sur les côtés) ; coudes à 165–169° mains jointes au-dessus de la tête (`overhead_y`,
     allonge 0,997). Posture de l'arbre : le poids passe sur la jambe d'appui pieds posés, puis le pied se soulève à
     la verticale de son appui avant de partir vers le mollet (`tree_shift`) ; il glissait de 15 cm au sol ;
   - pas chassés : chaque pas est résolu en six clés (pied qui monte à la verticale, se déplace en l'air, se pose à la
     verticale ; pied d'appui replacé à chaque clé) : moins de 4 mm de glissement. Genoux fléchis à 140° environ pieds
     posés (la consigne : « genoux légèrement fléchis »), bras détendus près du corps, coudes pliés, écartés de 23° au
     plus (ils s'ouvraient à 40°, comme des jumping jacks que la consigne ne demande pas) ; vus de trois quarts (28°) ;
   - rowing serviette : bassin penché de 17°, buste (bassin → cou) à 23–24°, genoux à 134–151° ; pied avant presque
     sous le milieu du corps, pied arrière en retrait et sur le côté : les brins montent de part et d'autre du genou
     avant, la cuisse arrière reste derrière eux (8 mm au moins de la peau à chaque image). Bande de 10 cm × 5 mm
     (une serviette pliée en long) ; chaque brin mesure 0,80 m (femme) ou 0,91 m (homme), constant à 2 mm près ;
   - boxe dans le vide : garde, poings devant le menton (7 à 10 cm du visage au plus près), placée dans le repère du
     regard (dans celui du buste tourné, les deux poings partaient vers la joue droite) ; coups droits vers l'avant,
     coude à peine plié au bout du coup (allonge 0,94). En garde, les coudes s'écartent un peu (`BOX_FLARE`) : serrés,
     les avant-bras entraient dans la poitrine quand le buste tourne ; ils se rentrent pendant le coup ;
   - squats partiels : bras placés par leur direction, en miroir, à chaque clé (`hs_dir`) : tendus en V au-dessus de
     la tête le long des oreilles, en bas à l'horizontale devant soi, en passant un peu en diagonale ;
   - grand étirement : inclinaison sur le côté répartie sur toute la colonne (`SIDE_SPLIT`), bassin et pieds
     immobiles : le buste (hanches → base du cou) s'incline de 18 à 19° de chaque côté ;
   - pas sur place lents (`slow_step`, `slow_steps`) : le pied monte et redescend à la verticale de son appui par
     cinématique inverse, sans glisser ; repris par la récupération, le retour au calme et la pause (gorgée d'eau).
     Retour au calme (`march-breathe`) : douze pas sans arrêt, une respiration profonde toutes les deux enjambées
     (5,2 s) portée par le pas lui-même (poitrine qui s'ouvre, tête un peu relevée, bras à peine écartés) ;
   - posture de l'enfant : la respiration soulève le milieu du dos d'environ 2,5 cm ; bas et haut du dos, cou et tête
     rendent la courbure pour que le point du front posé au sol ne bouge pas, mains posées fixes (bras à 96 % de leur
     longueur au repos, de quoi suivre le dos). Cadrée sur le corps, de trois quarts avant (−40°), un peu d'en haut ;
   - appuis réglés sur la peau : gainage sur les genoux (genoux, avant-bras et paumes touchent le sol ensemble), talon
     posé pointe en l'air au bord du lit, paume sur le sommet du crâne, mur au ras de la paume. Un pied qui quitte
     le sol ou s'y pose passe par des clés intermédiaires (talon levé pointe posée, pied décollé) : il ne traîne pas.
     Étirement de la cuisse (retour au calme) : le talon se lève de 24°, orteils posés au même endroit, puis le pied
     monte de 2 cm à la verticale avant de partir vers l'arrière ; il se repose de même (`quad_foot`). Entre le pied
     décollé et le talon haut, la cheville suit une droite, résolue en quatre clés, genou droit devant (`quad_lift`) :
     interpolés directement, les angles faisaient passer le pied devant la jambe d'appui (jambes en ciseaux). Ouverture
     de la poitrine : mains jointes paume contre paume derrière le dos, bras tendus 25° derrière la verticale,
     omoplates serrées, haut du dos en extension et tête droite (`chest_clasp` ; écart des poignets réglé pour que les
     paumes se touchent à 1–2 mm près sans se traverser). Vu presque de profil, un peu de l'arrière (105°) :
     la main sur le cou-de-pied se voit des deux côtés, et la poitrine qui s'ouvre.
   - contrôle final : après l'écriture du fichier, `motions.py` lance `prop_scan.py` et affiche un avertissement
     encadré pour tout mouvement dont la peau entre de plus de 5 mm dans un accessoire.
3. `prop_scan.py` : peau dans les accessoires. Chaque mouvement à accessoires est rejoué pour les deux corps comme
   dans l'app (`FPS` images par seconde, 15 par défaut, clés interpolées comprises) ; pour chaque pavé de l'accessoire
   (mêmes dimensions que l'app : `boxes_for`, `motion_eval.py`), profondeur maximale de peau à l'intérieur, instant,
   os et nombre de sommets. Au-delà de 5 mm (`LIMIT_MM`) le mouvement est signalé et le script sort en erreur. La
   profondeur plafonne à la demi-épaisseur du pavé (20 mm pour une assise). Il ne mesure que l'enfoncement : un corps
   qui flotte au-dessus de son assise se voit sur les planches de `review.py`.
4. `review.py <dossier> [N] [exercices…]` : planches de contrôle de chaque étape d'exercice pour les deux corps, N
   images réparties sur la boucle, interpolées comme dans l'app, avec le sol, les accessoires (serviette comprise),
   la consigne et le cadrage resserré des mouvements qui en ont un. `SIZE` : taille d'une image ; `MOTIONS_JSON` :
   autre fichier de mouvements.
5. `motion_eval.py <motions.json> <corps.npz> <planche.png> [ids]` : planche d'aperçu (même calcul que l'app :
   cinématique directe, skinning linéaire, mise au sol, décalages mis à l'échelle du corps). `MAXK=n` limite le
   nombre d'images par mouvement.
6. `solve_poses.py <corps.npz>` : outil d'auteur des poses au sol (à quatre pattes, tailleur, papillon, enfant).
7. `mocap_preview.py` : aperçu d'un extrait de capture avant de l'ajouter.

`motions.json` (format 3) contient une version de chaque mouvement par corps (`bodies.male`, `bodies.female`) :
le script est rejoué pour chaque squelette, si bien que les mains jointes se touchent et que les pieds restent posés
pour l'homme comme pour la femme. Bras levés : la clavicule et l'omoplate participent au mouvement (rythme
scapulo-huméral), ce qui évite l'épaule écrasée du skinning linéaire. Mouvements au lit : `support` donne la hauteur
du matelas sur lequel le corps repose.

Cadrage : `camera` donne l'angle de vue (`yaw`, `pitch`). Sans autre champ, l'app cadre le corps entier, sol compris,
sur toutes les images clés. `camera.frame` (liste d'articulations) demande un cadrage resserré : la caméra vise le
centre de la boîte de ces articulations sur toutes les images clés, élargie de `camera.margin` mètres (20 cm par
défaut), et s'en approche sans descendre sous 1 m ; elle garde la même élévation, donc reste au-dessus de la zone
(et du matelas). Menton rentré (tête, cou et
épaules de profil), cercles d'épaules (tête, épaules, coudes), mollets (des genoux au sol) et ouverture de poitrine
dans la porte (des orteils au bout des doigts, linteau compris, de trois quarts arrière) sont cadrés ainsi (`close_up`), comme la posture de l'enfant et les genoux vers la poitrine (corps entier, sans le lit). Cercles de chevilles : corps entier, de trois quarts du côté du mur (35°), la main posée à plat sur le mur dans l'image. Le passage d'un cadrage à l'autre dure 1,2 s (0,6 s entre deux vues d'ensemble). Calcul dans
`CameraFraming` (GrowtinCore), refait à l'identique par `camera_shot` (`motion_eval.py`) pour les planches de
`review.py` : même point visé, même champ à la distance de la caméra (aperçu sans perspective, carte supposée de
proportions 1,03). Quand deux mouvements successifs ont le même décor au même endroit (étapes du scan corporel),
l'app le garde en place au lieu de le reconstruire.

Articulations d'appoint (`upperarm01-half.L`, `lowerarm01-half.L`, `upperleg01-half.L`, `lowerleg01-half.L` et leurs
pendants à droite) : placées au même point que l'os qu'elles doublent (champ `half` dans `mannequin.json`), elles
prennent la moitié de sa rotation. Dans une pliure (épaule, coude, hanche, genou), la peau partagée entre deux os est
répartie entre le parent, l'appoint et l'os, si bien qu'aucun mélange ne dépasse la moitié de l'angle : la pliure
reste arrondie au lieu de se pincer en angle vif. Elles ne figurent pas dans les poses : l'app et les aperçus les
recalculent à chaque image.

Huit influences d'os par sommet (`INFLUENCES` dans `export.py`) : autour des épaules, jusqu'à 7 os comptent ; avec 4,
certains sommets perdaient jusqu'à 28 % de leur poids et la peau se froissait entre la bretelle et le cou, bras levés.
À moins de 3 cm des lignes de la tenue, là où le bras compte (emmanchure, bretelles), les poids sont remplacés par une
solution harmonique (`harmonize_weights`) : les poids d'origine, linéaires par grand triangle, pliaient la surface à
chaque arête bras levé et le bord de la brassière se dessinait en escalier sous l'aisselle.

Corps masculin : l'épaule n'est pas subdivisée (pas de bretelle) et ses triangles font 2 cm. Après les articulations
d'appoint, les poids du bras ont une cassure de pente sur la ligne où l'appoint culmine ; le skinning y pliait la
surface en arête vive (liseré blanc à la clavicule épaules haussées, plaque blanche sur le deltoïde bras en avant,
anneau sur l'avant-bras, visibles dans l'app). `smooth_arm_weights` lisse ces poids (20 passes laplaciennes) autour
des appoints de l'épaule et du coude et dans la torsion de l'avant-bras, à deux couronnes près ; mains, tête et dos le
long de la colonne gardent leurs poids (contacts des mains et appui allongé inchangés). Arêtes pliées de plus de 25°
par la pose : 29 → 9 (haussement d'épaules), 27 → 13 (rowing), 10 → 3 (coude, étirement « 4 »), 7 → 2 (poignet,
assis). Le corps féminin n'est pas touché.

Dans l'app, la surface est déformée sur le processeur (`SurfaceDeformer`, GrowtinCore) : skinning linéaire, puis
normales recalculées sur les triangles déformés (sommets dédoublés le long de la tenue soudés). Le skinning du GPU
se contentait de tourner les normales avec les os ; dans une pliure très ouverte (épaule bras levés), elles déviaient
jusqu'à 90° de la surface réelle et l'éclairage dessinait une tache blanche.

Format binaire `GTM5` (lu par `MannequinFile`, GrowtinCore) : en-tête (`GTM5`, nombre de maillages, influences par
sommet), puis pour chaque maillage (peau, tissu, liseré, découpés dans la même surface) : matière (uint32 : 0 peau,
1 tissu, 2 liseré), nombre de sommets, nombre d'indices (uint32), positions et normales (float32 ×3), indices d'os
(uint16 × influences, de la plus forte à la plus faible), poids (float32 × influences), indices de triangles (uint32).
