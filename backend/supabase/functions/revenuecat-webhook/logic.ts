// Traduction des événements RevenueCat en droits Premium (testée avec Node, exécutée par Deno).

export interface RevenueCatEvent {
  type: string;
  app_user_id?: string;
  original_app_user_id?: string;
  aliases?: string[];
  entitlement_ids?: string[] | null;
  entitlement_id?: string | null;
  expiration_at_ms?: number | null;
  event_timestamp_ms?: number;
  transferred_from?: string[];
  transferred_to?: string[];
}

export interface EntitlementUpdate {
  userID: string;
  premium: boolean;
  eventMs: number;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Identifiants Supabase (UUID) concernés par l'événement ; les identifiants anonymes RevenueCat sont ignorés. */
function userIDs(event: RevenueCatEvent): string[] {
  const ids = [event.app_user_id, event.original_app_user_id, ...(event.aliases ?? [])].filter((id): id is string => !!id && UUID.test(id));
  return [...new Set(ids)];
}

export function updatesFor(event: RevenueCatEvent, entitlementID: string, nowMs: number): EntitlementUpdate[] {
  const eventMs = event.event_timestamp_ms ?? nowMs;
  if (event.type === "TEST") return [];
  if (event.type === "TRANSFER") {
    const from = (event.transferred_from ?? []).filter((id) => UUID.test(id)).map((userID) => ({ userID, premium: false, eventMs }));
    const to = (event.transferred_to ?? []).filter((id) => UUID.test(id)).map((userID) => ({ userID, premium: true, eventMs }));
    return [...from, ...to];
  }
  const entitlements = event.entitlement_ids ?? (event.entitlement_id ? [event.entitlement_id] : []);
  if (!entitlements.includes(entitlementID)) return [];
  // CANCELLATION et BILLING_ISSUE n'arrêtent pas l'accès : il reste actif jusqu'à l'expiration (ou pendant la période de grâce).
  const active = event.type !== "EXPIRATION" && (event.expiration_at_ms == null || event.expiration_at_ms > nowMs);
  return userIDs(event).map((userID) => ({ userID, premium: active, eventMs }));
}

/** Comparaison en temps constant du secret d'autorisation. */
export function sameSecret(a: string, b: string): boolean {
  if (!a || !b || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
