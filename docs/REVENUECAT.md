# Abonnements Premium avec RevenueCat

Le code est prêt : paywall, restauration des achats, gestion de l'abonnement, droit `premium`, webhook serveur.
Il reste la configuration des comptes, à faire une fois.

## 1. Apple : contrat et abonnements

1. **App Store Connect › Accords, taxes et activités bancaires** : signe le contrat **Applications payantes** et renseigne tes coordonnées bancaires et fiscales. Sans ce contrat, aucun abonnement ne peut être testé ni vendu.
2. **App Store Connect › ton app › Abonnements** : crée un **groupe d'abonnements** nommé `Growtin' Premium`, puis deux abonnements :
   - `growtin_premium_monthly` : durée 1 mois ;
   - `growtin_premium_annual` : durée 1 an, avec éventuellement une **offre de lancement** « essai gratuit » (7 jours par exemple).
   Pour chacun : un prix, un nom affiché et une description en français, et la capture d'écran du paywall demandée pour la vérification (je peux te la fournir depuis les captures automatiques).
3. **Utilisateurs et accès › Intégrations › Achats intégrés** : génère une **clé d'achats intégrés** (fichier .p8) pour RevenueCat.

## 2. RevenueCat

1. Crée un compte sur <https://app.revenuecat.com>, puis un projet `Growtin'`.
2. **Apps › + New › App Store** : identifiant de lot `app.growtin.ios`, puis importe la clé d'achats intégrés de l'étape 1.3 (avec son Key ID et ton Issuer ID).
3. **Products** : importe `growtin_premium_monthly` et `growtin_premium_annual`.
4. **Entitlements › + New** : identifiant **`premium`** (exactement), et attache-lui les deux produits.
5. **Offerings** : l'offre `default` (courante) avec deux packages : **Monthly** → produit mensuel, **Annual** → produit annuel.
6. **Project settings › API keys** : copie la clé publique **Apple App Store** (elle commence par `appl_`) et donne-la-moi : elle est publique par conception.

## 3. Relier RevenueCat au serveur (droit Premium pour le Coach)

1. Choisis un secret long et aléatoire (par exemple 40 caractères).
2. **Supabase › Edge Functions › Secrets** : ajoute `REVENUECAT_WEBHOOK_AUTH` avec la valeur `Bearer <ton secret>`.
3. **RevenueCat › Integrations › Webhooks › + New** :
   - URL : `https://hxaioqwdqtuxlodfhfxg.supabase.co/functions/v1/revenuecat-webhook`
   - Authorization header : `Bearer <ton secret>` (exactement la même valeur).
4. Lance **Actions › Backend › Run workflow** sur GitHub pour déployer le webhook, puis clique sur **Send test event** dans RevenueCat.

## 4. Tester sans payer

Les achats faits depuis une version **TestFlight** passent par l'environnement de test d'Apple (Sandbox) : rien n'est prélevé, et les abonnements se renouvellent en accéléré (un mois dure quelques minutes). Tu peux vérifier dans RevenueCat que l'achat apparaît, puis dans Supabase (table `entitlements`) que le droit Premium est bien accordé.

## Ce qu'Apple vérifie sur le paywall (règle 3.1.2)

Le paywall de Growtin' affiche déjà : le nom et la durée de chaque formule, le prix localisé et la période, les conditions de l'essai gratuit, le renouvellement automatique et la façon de résilier, le bouton « Restaurer mes achats », et les liens vers les conditions d'utilisation et la politique de confidentialité. Il n'annonce que des avantages réellement disponibles.
