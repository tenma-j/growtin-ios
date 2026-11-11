// Fonction serveur « coach » (Supabase Edge Function, Deno).
// La clé Anthropic n'existe que dans les secrets de la fonction : elle n'est jamais envoyée à l'app.
import Anthropic from "npm:@anthropic-ai/sdk@1.7.0";
import { createClient } from "npm:@supabase/supabase-js@2.119.0";
import sources from "./sources.json" with { type: "json" };
import {
  checkCitations, costMicros, DISTRESS_REPLY, findForbidden, needsReminder, parseRequest, RequestError, SAFE_FALLBACK_REPLY, screen,
} from "./logic.ts";
import {
  parsePhotoReading, parsePhotoRequest, PHOTO_DISCLAIMER, PHOTO_INSTRUCTIONS, PHOTO_SCHEMA, photoForbidden, photoPrompt,
  PhotoRequestError,
} from "./photo.ts";
import { COACH_INSTRUCTIONS, type Source, sourcesSection, wrapLastUserMessage } from "./prompt.ts";

const MODEL = Deno.env.get("COACH_MODEL") ?? "claude-opus-5-5";
// Effort moyen : réponses personnalisées et structurées. Réglable sans redéployer l'app.
const EFFORT = (Deno.env.get("COACH_EFFORT") ?? "medium") as "low" | "medium" | "high";
const FREE_DAILY = Number(Deno.env.get("COACH_FREE_DAILY_LIMIT") ?? "2");
const PREMIUM_DAILY = Number(Deno.env.get("COACH_PREMIUM_DAILY_LIMIT") ?? "40");

const SOURCES = sources as Source[];
const KNOWN_IDS = new Set(SOURCES.map((s) => s.id));
// Prompt stable : il est mis en cache par l'API (seule la conversation change d'une requête à l'autre).
const SYSTEM_PROMPT = `${COACH_INSTRUCTIONS}\n\n${sourcesSection(SOURCES)}`;

/** Erreur de configuration du serveur, signalée par un code sans donnée sensible. */
class ConfigError extends Error {}

function serviceKey(): string {
  // Clé de service : ancien nom, ou nouveau format de clés secrètes de Supabase.
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) return legacy;
  const keys = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (keys) {
    try {
      const parsed = JSON.parse(keys) as Record<string, string>;
      const first = parsed.default ?? Object.values(parsed)[0];
      if (first) return first;
    } catch { /* format inattendu */ }
  }
  throw new ConfigError("service_key_missing");
}

let anthropicClient: Anthropic | null = null;
function anthropic(): Anthropic {
  if (!Deno.env.get("ANTHROPIC_API_KEY")) throw new ConfigError("anthropic_key_missing");
  anthropicClient ??= new Anthropic(); // lit ANTHROPIC_API_KEY dans les secrets de la fonction
  return anthropicClient;
}

function makeAdmin() {
  return createClient(Deno.env.get("SUPABASE_URL")!, serviceKey(), { auth: { persistSession: false } });
}
let adminClient: ReturnType<typeof makeAdmin> | null = null;
function admin() {
  adminClient ??= makeAdmin();
  return adminClient;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json; charset=utf-8" } });
}

Deno.serve(async (req: Request) => {
  try {
    return await handle(req);
  } catch (error) {
    const code = error instanceof ConfigError ? error.message : "internal_error";
    console.error("Erreur du Coach", code, error instanceof Error ? error.message : String(error));
    return json({ error: "Le Coach rencontre un problème technique.", code }, 500);
  }
});

async function handle(req: Request): Promise<Response> {
  if (req.method !== "POST") return json({ error: "Méthode non autorisée." }, 405);

  // 1. Authentification : jeton Supabase de l'utilisateur.
  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  const { data: auth } = await admin().auth.getUser(token);
  const user = auth?.user;
  if (!user) return json({ error: "Session expirée. Rouvre l'application." }, 401);

  // 2. Validation de la requête.
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Requête illisible." }, 400);
  }
  if (body?.kind === "photo") return await handlePhoto(user.id, body);
  let request;
  try {
    request = parseRequest(body);
  } catch (error) {
    if (error instanceof RequestError) return json({ error: error.message }, 400);
    return json({ error: "Requête illisible." }, 400);
  }

  // 3. Signaux d'alerte, avant tout appel au modèle.
  const question = request.messages[request.messages.length - 1].content;
  const safety = screen(question);
  if (safety === "seekHelpNow") {
    return json({ message: DISTRESS_REPLY, citations: [], safety, quota: null });
  }

  // 4. Quota quotidien selon l'abonnement (table mise à jour par RevenueCat).
  const consumed = await consumeQuota(user.id);
  if (consumed instanceof Response) return consumed;
  const quota = consumed;

  // 5. Appel au modèle.
  const history = request.messages.slice(0, -1).map((m) => ({ role: m.role, content: m.content }));
  const messages: Anthropic.Beta.BetaMessageParam[] = [
    ...history,
    { role: "user", content: wrapLastUserMessage(question, request.context, { reminder: needsReminder(request.messages, safety) }) },
  ];

  let response: Anthropic.Beta.BetaMessage;
  try {
    response = await anthropic().beta.messages.create({
      model: MODEL,
      max_tokens: 2000,
      // Repli côté serveur si les classificateurs de sécurité refusent la requête.
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      output_config: { effort: EFFORT },
      system: [{ type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } }],
      messages,
    });
  } catch (error) {
    if (error instanceof Anthropic.RateLimitError) return json({ error: "Le Coach est très sollicité. Réessaie dans un instant.", quota }, 503);
    if (error instanceof Anthropic.APIError) {
      console.error("Erreur Anthropic", error.status);
      return json({ error: "Le Coach n'a pas pu répondre. Réessaie plus tard.", quota }, 502);
    }
    throw error;
  }

  // 6. Contrôles de la réponse.
  let message: string;
  let cited: string[] = [];
  if (response.stop_reason === "refusal") {
    message = "Je ne peux pas répondre à cette demande. Pour une question de santé, le plus sûr est d'en parler à un médecin ou à un dermatologue.";
  } else {
    const text = response.content
      .filter((block): block is Anthropic.Beta.BetaTextBlock => block.type === "text")
      .map((block) => block.text)
      .join("\n")
      .trim();
    const checked = checkCitations(text, KNOWN_IDS);
    if (checked.removed.length) console.warn("Citations inconnues retirées", checked.removed);
    if (findForbidden(checked.text)) {
      message = SAFE_FALLBACK_REPLY;
    } else {
      message = checked.text || "Je n'ai pas réussi à formuler une réponse. Peux-tu reformuler ta question ?";
      cited = checked.cited;
    }
  }

  // 7. Suivi des coûts (aucun contenu de conversation n'est conservé).
  await recordUsage(user.id, response.usage);

  return json({ message, citations: cited, safety, quota, model: response.model });
}

interface Quota {
  used: number;
  limit: number;
  premium: boolean;
}

/** Décompte une question (ou une lecture de photo) ; renvoie une réponse d'erreur si la limite est atteinte. */
async function consumeQuota(userID: string): Promise<Quota | Response> {
  const { data: entitlement } = await admin().from("entitlements").select("premium").eq("user_id", userID).maybeSingle();
  const limit = entitlement?.premium ? PREMIUM_DAILY : FREE_DAILY;
  const { data: consumed, error } = await admin().rpc("coach_consume", { p_user: userID, p_limit: limit });
  if (error) return json({ error: "Service momentanément indisponible." }, 503);
  const quota = { used: consumed?.[0]?.used ?? limit, limit, premium: entitlement?.premium ?? false };
  if (!consumed?.[0]?.allowed) return json({ error: "Tu as atteint la limite de questions pour aujourd'hui.", quota }, 429);
  return quota;
}

async function recordUsage(userID: string, usage: Anthropic.Beta.BetaUsage) {
  await admin().rpc("coach_record_usage", {
    p_user: userID,
    p_input: usage.input_tokens,
    p_output: usage.output_tokens,
    p_cache_read: usage.cache_read_input_tokens ?? 0,
    p_cache_write: usage.cache_creation_input_tokens ?? 0,
    p_cost_micros: costMicros(usage),
  });
}

/** Lecture de photo : les images ne sont ni journalisées ni conservées. */
async function handlePhoto(userID: string, body: Record<string, unknown>): Promise<Response> {
  let request;
  try {
    request = parsePhotoRequest(body);
  } catch (error) {
    if (error instanceof PhotoRequestError) return json({ error: error.message }, 400);
    throw error;
  }

  const quota = await consumeQuota(userID);
  if (quota instanceof Response) return quota;

  const jpeg = (data: string) => ({ type: "image" as const, source: { type: "base64" as const, media_type: "image/jpeg" as const, data } });
  const content: Anthropic.Beta.BetaContentBlockParam[] = [
    ...(request.previousImage ? [jpeg(request.previousImage)] : []),
    jpeg(request.image),
    { type: "text", text: photoPrompt(request) },
  ];

  let response: Anthropic.Beta.BetaMessage;
  try {
    response = await anthropic().beta.messages.create({
      model: MODEL,
      max_tokens: 1500,
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      output_config: { effort: "medium", format: { type: "json_schema", schema: PHOTO_SCHEMA as unknown as Record<string, unknown> } },
      system: [{ type: "text", text: PHOTO_INSTRUCTIONS, cache_control: { type: "ephemeral" } }],
      messages: [{ role: "user", content }],
    });
  } catch (error) {
    if (error instanceof Anthropic.RateLimitError) return json({ error: "Le service est très sollicité. Réessaie dans un instant.", quota }, 503);
    if (error instanceof Anthropic.APIError) {
      console.error("Erreur Anthropic (photo)", error.status);
      return json({ error: "La lecture de la photo a échoué. Réessaie plus tard.", quota }, 502);
    }
    throw error;
  }
  await recordUsage(userID, response.usage);

  const unavailable = "Je ne peux pas proposer de lecture prudente de cette photo. Un dermatologue est la bonne personne pour l'examiner.";
  if (response.stop_reason === "refusal") return json({ error: unavailable, quota }, 422);
  const text = response.content
    .filter((block): block is Anthropic.Beta.BetaTextBlock => block.type === "text")
    .map((block) => block.text)
    .join("");
  const reading = parsePhotoReading(text);
  if (!reading) return json({ error: "La lecture de la photo a échoué. Réessaie plus tard.", quota }, 502);
  const forbidden = photoForbidden(reading);
  if (forbidden) {
    console.warn("Lecture de photo écartée (vocabulaire interdit)", forbidden);
    return json({ error: unavailable, quota }, 422);
  }
  if (!request.previousImage) reading.comparison = null;
  return json({ reading, disclaimer: PHOTO_DISCLAIMER, quota, model: response.model });
}
