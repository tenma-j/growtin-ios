# Growtin' — plan de refonte iOS et décisions

Dernière mise à jour : 2026-11-06.

## 1. Décisions prises (carte blanche)

| Sujet | Décision | Raison |
|---|---|---|
| Ordre de l'onboarding | « Parlons de toi » passe en 2e position, « Depuis quand ? » en 3e | Demande explicite |
| Growtin Score | Remplacé par **Régularité** : la part des habitudes choisies qui ont été réalisées | Un score de santé capillaire calculé sans mesure validée est trompeur (App Review 1.4.1) |
| Projection « 59 → 75 », « +12 % » | **Supprimée**. Remplacée par une feuille de route et des scénarios sur les **habitudes** (régularité, sommeil), avec intervalle à 95 % et « Données insuffisantes » sous 14 jours | Aucune prédiction biologique sans modèle validé |
| Stade de Norwood | Conservé, **choisi par l'utilisateur**. Ajout de l'échelle de Ludwig pour les femmes | L'auto-évaluation n'est pas une classification automatique |
| Analyse IA des photos | Aucune interprétation de l'état des cheveux au lancement. Contrôles de qualité et de comparabilité sur l'appareil, comparaison visuelle par l'utilisateur | Une IA qui décrit un recul ou une densité fait une évaluation clinique : c'est le point qui exposerait le plus à la réglementation des dispositifs médicaux et au refus App Store |
| Photos | Stockées **sur l'iPhone uniquement**, chiffrées par iOS. Sauvegarde cloud chiffrée plus tard, uniquement avec consentement explicite | Données très sensibles : le moins de transferts possible |
| Backend (phase E) | **Supabase, région Europe (Francfort)** : authentification (Sign in with Apple), Postgres avec règles d'accès par utilisateur, stockage, fonctions serveur pour l'IA et RevenueCat | CloudKit ne permet ni code serveur, ni proxy IA, ni réception des événements RevenueCat |
| IA | API Claude d'Anthropic, appelée **uniquement depuis le serveur**. Citations limitées à la base de sources vérifiées, contrôlées par le serveur | Aucune clé dans l'app, aucune référence inventée |
| Tutoiement | Partout | Ton « compagnon » ; uniformise la web app |
| Appareils | iPhone, portrait, **iOS 26 minimum** | Liquid Glass natif sans code de compatibilité |
| Identifiant d'app | `app.growtin.ios` (à remplacer par le tien si tu possèdes un domaine) | — |
| Photos des recettes | Pas d'images Google : elles sont protégées par le droit d'auteur (risque de retrait, App Review 5.2.1). Options : banques d'images à licence commerciale (Pexels, Unsplash), images générées par IA **signalées comme telles**, ou shooting | Je ne peux pas générer de photos dans cet environnement |

Sur la réglementation : tu as raison, laisser l'utilisateur choisir son stade et donner des conseils d'hygiène de vie relève du **bien-être**. Pour le rester, l'application ne doit pas : déterminer un stade ou un type d'alopécie, mesurer une densité ou une évolution à partir des photos, ni conseiller, doser ou arrêter un traitement. Le code applique ces règles (moteur de routine, détecteur de signaux d'alerte, prompt système et contrôles serveur).

## 2. Audit de la web app (résumé)

**Conservé** : identité sobre noir et blanc, accroche, avertissement à cocher, micro-actions quotidiennes, séances guidées (respiration, massage en 4 zones), sources affichées, repères nutritionnels.

**Corrigé** :
- promesses de résultat (« repousse possible », « réduction visible de la chute », « cheveux plus épais ») ;
- sous-score « microcirculation », qui n'est pas mesurable ;
- « Confiance : élevée » d'une analyse IA non validée ;
- protéines à 1,2 g/kg (référence EFSA : 0,83 g/kg) ;
- allégations non autorisées (oméga-3 et cuir chevelu, hydratation et casse) ;
- noix du Brésil sans mise en garde sur l'excès de sélénium ;
- massage présenté comme agissant sur la microcirculation (l'étude ne porte que sur 9 hommes sans groupe témoin) ;
- série de jours culpabilisante (remplacée par le nombre de jours actifs) ;
- mélange tutoiement/vouvoiement.

**Ajouté** : navigation par onglets, routine personnalisée et modifiable, bilan du jour, régularité, tableau prévisionnel, fiches de preuve, sources vérifiées, détection des signaux d'alerte, rappels, suppression des données.

## 3. Avancement

| Phase | Contenu | État |
|---|---|---|
| A. Fondations | Package `GrowtinCore`, modèles, base de sources, design system, projet Xcode | **Fait**. 35 tests unitaires passent sous Linux ; l'interface n'a pas encore été compilée |
| B. Onboarding, navigation, Aujourd'hui | 12 écrans, routine générée, régularité, bilan du jour, éditeur de routine, rappels, séances guidées, réglages, suppression des données | **Écrit**, à compiler dans Xcode |
| D (partiel). Tableau prévisionnel | Graphiques 7 j à 12 mois, scénarios d'habitudes, feuille de route, calendrier des photos | **Écrit**, à compiler dans Xcode |
| C. Photos | Capture guidée (AVFoundation, repères, photo précédente en transparence, lumière et angle en direct), contrôle de netteté et de luminosité, détection du visage (Vision) pour le cadrage, conditions déclarées, comparabilité, frise par zone, comparaison curseur / superposition / côte à côte, suppression | **Fait**. Logique testée (46 tests), interface compilée dans le cloud |
| E. Backend et IA | Supabase, proxy IA, quotas, cache, suivi des coûts, Coach | Prompt système rédigé, reste à faire |
| F. Nutrition | 37 recettes avec de vraies photos (rawpixel, domaine public), valeurs calculées depuis la table Ciqual 2020 (ANSES), apports par portion et part des valeurs de référence, filtres selon régime et allergies, recherche, favoris, recette du jour, planning de la semaine, liste de courses partageable | **Fait** (premier lot de 37 recettes, à étendre) |
| F bis. Explorer | Exercices, bibliothèque éducative | À faire |
| G. Abonnement, Santé, notifications avancées | RevenueCat (entitlement `premium`), paywall SwiftUI, HealthKit (sommeil, pas) | À faire |
| H. Fiabilisation et App Store | Tests d'interface, accessibilité, fiche App Store, étiquettes de confidentialité, TestFlight | À faire |

## 4. Conformité App Store (points déjà pris en compte)

- **1.4.1** (applications de santé) : pas de diagnostic, pas de mesure non validée, sources affichées, orientation médicale gratuite.
- **5.1.1 / 5.1.3** (données de santé) : données locales, aucune revente, pas de publicité, consentement avant toute personnalisation IA.
- **5.1.1(v)** (suppression de compte) : la suppression complète des données locales existe déjà. La suppression du compte serveur viendra avec le backend.
- **Manifeste de confidentialité** (`PrivacyInfo.xcprivacy`) : aucun suivi publicitaire, aucune donnée collectée à ce stade.
- **3.1.2** (abonnements) : sera traité avec RevenueCat. Le paywall affichera le prix localisé, la période, le renouvellement, la restauration des achats et les liens légaux.
- **Accessibilité** : Dynamic Type, VoiceOver (libellés et valeurs), Réduire les animations, cibles d'au moins 44 points.
