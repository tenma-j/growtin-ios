# Serveur de Growtin' (Supabase)

Le serveur sert uniquement au **Coach IA** pour l'instant :

- `functions/coach` : reçoit une question, applique les signaux d'alerte, vérifie le quota du jour, appelle Claude (Anthropic) avec la base de sources vérifiées, retire toute citation inconnue, bloque les formulations interdites (dosages, promesses, arrêt de traitement) et enregistre le coût.
- `functions/delete-account` : supprime le compte anonyme et ses compteurs (exigence App Store 5.1.1(v)).
- `migrations/` : tables de quotas et de droits Premium, avec sécurité au niveau des lignes.

**Aucune conversation ni donnée de santé n'est stockée côté serveur.** La clé Anthropic n'existe que dans les secrets des fonctions.

## Réglages par défaut (modifiables sans mettre à jour l'app)

| Variable | Défaut | Rôle |
|---|---|---|
| `COACH_MODEL` | `claude-opus-5-5` | Modèle utilisé |
| `COACH_EFFORT` | `medium` | Profondeur de réflexion (`low`, `medium`, `high`) |
| `COACH_FREE_DAILY_LIMIT` | `2` | Questions par jour, version gratuite |
| `COACH_PREMIUM_DAILY_LIMIT` | `40` | Questions par jour, Premium |

Le repli automatique d'Anthropic (`fallbacks: "default"`) est activé : si ses filtres de sécurité refusent une requête, elle est relancée sur un autre modèle au lieu d'échouer.

Coût indicatif : une question coûte de l'ordre de quelques centimes ; le prompt système (environ 6 000 jetons) est mis en cache. La vue `coach_cost_by_day` du tableau de bord Supabase donne le coût réel par jour.

## Mise en place (sans terminal)

1. **Supabase** : crée un compte sur <https://supabase.com>, puis un projet **New project**, région **Central EU (Frankfurt)**. Note le **mot de passe de la base** que tu choisis.
2. Dans le projet : **Authentication › Sign In / Providers**, active **Allow anonymous sign-ins**.
3. **Project Settings › General** : copie le **Project ID** (référence du projet).
4. Sur <https://supabase.com/dashboard/account/tokens> : **Generate new token**, copie-le.
5. **Anthropic** : sur <https://console.anthropic.com>, crée une clé API (rubrique **API Keys**) et ajoute un moyen de paiement. Fixe une **limite de dépense mensuelle** dans **Billing › Limits**.
6. **GitHub** : dans <https://github.com/tenma-j/growtin-ios/settings/secrets/actions>, ajoute :

   | Secret | Valeur |
   |---|---|
   | `SUPABASE_PROJECT_REF` | le Project ID |
   | `SUPABASE_ACCESS_TOKEN` | le jeton de l'étape 4 |
   | `SUPABASE_DB_PASSWORD` | le mot de passe de la base |
   | `ANTHROPIC_API_KEY` | la clé Anthropic |

7. Lance **Actions › Backend › Run workflow**.
8. Dans Supabase, **Project Settings › API** : donne-moi l'**URL du projet** et la clé **anon public**. Ces deux valeurs sont publiques par conception (elles vont dans l'app) ; ne me donne jamais la clé `service_role` ni la clé Anthropic.

## Tests

```bash
node --experimental-strip-types --test backend/supabase/functions/coach/logic.test.ts
```

## Lecture de photo

La fonction `coach` accepte aussi `{"kind": "photo", "zone": …, "image": <JPEG base64>, "previousImage"?: …}`.
L'image est transmise au modèle puis oubliée : elle n'est ni enregistrée ni journalisée. La réponse est un JSON
structuré (conditions, constats visuels, comparaison, conseils de prise de vue, besoin d'un avis médical rapide),
contrôlé par une liste de vocabulaire interdit (diagnostic, stade, pourcentages, pronostic, traitements).
Une lecture compte comme une question dans le quota quotidien.

Dans App Store Connect › Confidentialité de l'app, déclarer en plus « Photos ou vidéos » (fonctionnalité de l'app,
non liées à l'identité, pas de suivi).
