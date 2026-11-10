// Webhook RevenueCat : met à jour la table `entitlements` (droit Premium) à chaque événement d'abonnement.
// RevenueCat envoie l'en-tête Authorization configuré dans son tableau de bord (secret REVENUECAT_WEBHOOK_AUTH).
import { createClient } from "npm:@supabase/supabase-js@2.119.0";
import { sameSecret, updatesFor, type RevenueCatEvent } from "./logic.ts";

const ENTITLEMENT_ID = Deno.env.get("REVENUECAT_ENTITLEMENT_ID") ?? "premium";

function serviceKey(): string {
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) return legacy;
  const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}") as Record<string, string>;
  return keys.default ?? Object.values(keys)[0] ?? "";
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response(null, { status: 405 });
  const expected = Deno.env.get("REVENUECAT_WEBHOOK_AUTH") ?? "";
  if (!sameSecret(req.headers.get("Authorization") ?? "", expected)) return new Response(null, { status: 401 });

  let event: RevenueCatEvent;
  try {
    event = ((await req.json()) as { event: RevenueCatEvent }).event;
    if (!event?.type) throw new Error("événement manquant");
  } catch {
    return new Response(JSON.stringify({ error: "Corps invalide." }), { status: 400 });
  }

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey(), { auth: { persistSession: false } });
  for (const update of updatesFor(event, ENTITLEMENT_ID, Date.now())) {
    const { error } = await admin.rpc("apply_entitlement", {
      p_user: update.userID, p_premium: update.premium, p_event_ms: update.eventMs,
    });
    if (error) console.error("Mise à jour du droit impossible", event.type, error.message);
  }
  // Toujours 200 une fois l'événement authentifié : RevenueCat réessaie sinon indéfiniment.
  return new Response(JSON.stringify({ received: true }), { headers: { "Content-Type": "application/json" } });
});
