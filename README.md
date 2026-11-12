# Growtin'

Application iOS native (SwiftUI, iOS 26, Liquid Glass) d'accompagnement quotidien pour les personnes préoccupées par la chute ou l'affinement de leurs cheveux. C'est une application de bien-être : elle ne pose aucun diagnostic et ne remplace pas un professionnel de santé.

Décisions, audit et avancement : [docs/PLAN.md](docs/PLAN.md).

## Compiler sans Xcode (dans le cloud)

Le fichier `.github/workflows/ios.yml` fait tout le travail sur un Mac de GitHub, à chaque envoi de code :

1. il lance les tests du cœur métier ;
2. il compile l'app avec Xcode 26 ;
3. il démarre l'app dans un simulateur iPhone et capture les écrans principaux, en mode clair et en mode sombre, avec des données de démonstration fictives.

Les captures et les journaux de compilation se téléchargent depuis l'onglet **Actions** du dépôt GitHub, dans la section **Artifacts** de chaque exécution. Pour un dépôt public, les Mac de GitHub sont gratuits. Pour un dépôt privé, ils consomment le quota gratuit de minutes du compte.

Pour installer l'app sur un vrai iPhone sans Xcode, il faudra passer par **TestFlight**, ce qui nécessite un compte Apple Developer (99 € par an, également indispensable pour publier sur l'App Store).

## Ouvrir et lancer l'app (Mac avec Xcode)

Il te faut un Mac avec **Xcode 26** (gratuit sur le Mac App Store).

1. Ouvre `Growtin.xcodeproj` dans Xcode.
2. Dans le navigateur de gauche, clique sur le projet **Growtin**, puis sur la cible **Growtin** et l'onglet **Signing & Capabilities**. Choisis ton équipe dans **Team** (ton identifiant Apple suffit pour tester sur simulateur ou sur ton iPhone).
3. En haut de la fenêtre, choisis un simulateur (par exemple iPhone 17), puis appuie sur **⌘R**.

Si Xcode signale que le paquet `GrowtinCore` est introuvable : menu **File › Packages › Reset Package Caches**.

## Lancer les tests

Les tests du cœur métier (routine, régularité, prévisions, signaux d'alerte, sources) :

```bash
cd Packages/GrowtinCore
```

```bash
swift test
```

Ils tournent sur Mac comme sur Linux.

## Organisation

```
Growtin.xcodeproj         Projet Xcode (dossiers synchronisés : tout fichier ajouté dans Growtin/ est inclus)
Growtin/
  App/                    Point d'entrée, navigation, modèle central (AppModel)
  DesignSystem/           Couleurs, espacements, composants réutilisables
  Persistence/            Enregistrements SwiftData
  Services/               Rappels locaux
  Features/               Onboarding, Aujourd'hui, Progrès, Séances, Explorer, Réglages
  Resources/              Icône, couleurs, manifeste de confidentialité
Packages/GrowtinCore/     Logique métier en Swift pur, testable sans iPhone
  Sources/…/Resources/sources.json   Base de références scientifiques vérifiées
backend/ai/system-prompt.md          Prompt système du futur Coach IA
research/                 Données brutes de vérification des sources
Config/                   Entitlements (chiffrement des données)
```

## Personnage 3D des exercices

Les séances de l'onglet Explorer sont montrées par un personnage 3D animé (femme ou homme selon le profil, modifiable),
en tenue de sport, dans un studio lumineux rendu avec SceneKit (sol, ombres douces, rotation au doigt) : 50 mouvements,
calculés séparément pour chaque corps, accessoires (chaise, table, mur, encadrement de porte, tapis de yoga, lit).
Le corps provient des ressources de [MakeHuman](https://github.com/makehumancommunity/makehuman), publiées dans le
domaine public (CC0 1.0). La marche et la boxe dans le vide sont des captures du
[CMU Graphics Lab Motion Capture Database](http://mocap.cs.cmu.edu) (financement NSF EIA-0196217) ; les autres
mouvements sont écrits par poses clés et cinématique inverse. Tout le pipeline est dans `scripts/mannequin` (voir son README).

## État honnête

- **Testé** : le package `GrowtinCore` (79 tests, Swift 6.2, sans avertissement), la logique du serveur (Node) et le
  Coach déployé (test de bout en bout à chaque déploiement).
- **Compilé dans le cloud** : l'app complète (Xcode 26, simulateur), avec captures d'écran automatiques à chaque envoi.
- **Pas encore développé** : Apple Santé, l'export des données, la sauvegarde et la synchronisation.
