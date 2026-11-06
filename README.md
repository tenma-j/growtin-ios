# Growtin'

Application iOS native (SwiftUI, iOS 26, Liquid Glass) d'accompagnement quotidien pour les personnes préoccupées par la chute ou l'affinement de leurs cheveux. C'est une application de bien-être : elle ne pose aucun diagnostic et ne remplace pas un professionnel de santé.

Décisions, audit et avancement : [docs/PLAN.md](docs/PLAN.md).

## Ouvrir et lancer l'app (Mac)

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

## État honnête

- **Testé** : le package `GrowtinCore` (35 tests). Il compile sans avertissement avec Swift 6.2.
- **Écrit mais pas encore compilé** : toute l'interface SwiftUI. Elle a été développée sans Xcode, dans un environnement Linux. Elle a été relue, mais la première compilation dans Xcode peut faire apparaître quelques erreurs à corriger.
- **Pas encore développé** : les onglets Coach et Nutrition, qui affichent clairement « En cours de développement » ; la capture photo ; le backend ; l'abonnement ; Apple Santé.
