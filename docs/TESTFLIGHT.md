# Installer Growtin' sur ton iPhone avec TestFlight (sans Xcode)

Tout se fait depuis un navigateur. Compte environ 20 minutes la première fois.
**Ne colle jamais ta clé privée (.p8) dans une conversation** : elle va uniquement dans les secrets GitHub.

## 1. Déclarer l'identifiant de l'app

1. Va sur <https://developer.apple.com/account/resources/identifiers/list>.
2. Clique sur **+**, choisis **App IDs**, puis **App**.
3. Description : `Growtin`. Bundle ID : **Explicit**, valeur `app.growtin.ios`.
4. Ne coche aucune capacité particulière, puis clique sur **Continue** et **Register**.

## 2. Créer la fiche de l'app dans App Store Connect

1. Va sur <https://appstoreconnect.apple.com/apps>, clique sur **+**, puis **Nouvelle app**.
2. Plateforme : **iOS**. Nom : `Growtin'` (si le nom est déjà pris, essaie `Growtin' – Suivi capillaire`).
3. Langue principale : **Français**. Identifiant de lot : `app.growtin.ios`. SKU : `growtin-ios`. Accès : **Accès complet**.

## 3. Créer une clé API App Store Connect

1. Dans App Store Connect : **Utilisateurs et accès**, onglet **Intégrations**, section **App Store Connect API**.
2. La première fois, clique sur **Demander l'accès** et accepte les conditions.
3. Clique sur **Générer une clé API** (ou **+**). Nom : `GitHub Actions`. Accès : **Admin**.
4. **Télécharge le fichier .p8** : il n'est téléchargeable qu'une seule fois. Garde-le en lieu sûr.
5. Note l'**ID de la clé** (Key ID) et l'**ID de l'émetteur** (Issuer ID), affiché en haut de la page.

## 4. Trouver ton Team ID

Sur <https://developer.apple.com/account>, rubrique **Membership details** : copie le **Team ID** (10 caractères).

## 5. Ajouter les quatre secrets sur GitHub

Va sur <https://github.com/tenma-j/growtin-ios/settings/secrets/actions> et clique sur **New repository secret** pour chacun :

| Nom du secret | Valeur |
|---|---|
| `APP_STORE_CONNECT_KEY_ID` | l'ID de la clé |
| `APP_STORE_CONNECT_ISSUER_ID` | l'ID de l'émetteur |
| `APPLE_TEAM_ID` | ton Team ID |
| `APP_STORE_CONNECT_PRIVATE_KEY` | tout le contenu du fichier .p8, ouvert avec TextEdit, y compris les lignes `-----BEGIN PRIVATE KEY-----` et `-----END PRIVATE KEY-----` |

## 6. Lancer l'envoi

Dis-moi que c'est fait : je lance la chaîne **TestFlight** et je surveille l'envoi.
Tu peux aussi la lancer toi-même : onglet **Actions** du dépôt, **TestFlight**, **Run workflow**.

## 7. Installer l'app

1. Après l'envoi, Apple traite la version (de quelques minutes à une heure).
2. Dans App Store Connect : ton app, onglet **TestFlight**, section **Tests internes** : crée un groupe et ajoute-toi comme testeur.
3. Installe l'app **TestFlight** sur ton iPhone depuis l'App Store, puis accepte l'invitation reçue par e-mail.
