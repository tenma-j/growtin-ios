// Fonction serveur « coach » (Supabase Edge Function, Deno).
// La clé Anthropic n'existe que dans les secrets de la fonction : elle n'est jamais envoyée à l'app.
import Anthropic from "npm:@anthropic-ai/sdk@1.7.0";
import { createClient } from "npm:@supabase/supabase-js@2.119.0";
import sources from "./sources.json" with { type: "json" };
import {
  checkCitations, costMicros, DISTRESS_REPLY, findForbidden, parseRequest, RequestError, SAFE_FALLBACK_REPLY, screen,
} from "./logic.ts";
import { COACH_INSTRUCTIONS, type Source, sourcesSection, wrapLastUserMessage } from "./prompt.ts";

const MODEL = Deno.env.get("COACH_MODEL") ?? "claude-opus-5-5";
// Effort bas par défaut : réponses de conversation courtes. Réglable sans redéployer l'app.
const EFFORT = (Deno.env.get("COACH_EFFORT") ?? "low") as "low" | "medium" | "high";
const FREE_DAILY = Number(Deno.env.get("COACH_FREE_DAILY_LIMIT") ?? "5");
const PREMIUM_DAILY = Number(Deno.env.get("COACH_PREMIUM_DAILY_LIMIT") ?? "40");

const SOURCES = sources as Source[];
const KNOWN_IDS = new Set(SOURCES.map((s) => s.id));
// Prompt stable : il est mis en cache par l'API (seule la conversation change d'une requête à l'autre).
const SYSTEM_PROMPT = `${COACH_INSTRUCTIONS}\n\n${sourcesSection(SOURCES)}`;

const anthropic = new Anthropic(); // lit ANTHROPIC_API_KEY dans les secrets de la fonction
const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json; charset=utf-8" } });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Méthode non autorisée." }, 405);

  // 1. Authentification : jeton Supabase de l'utilisateur.
  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  const { data: auth } = await admin.auth.getUser(token);
  const user = auth?.user;
  if (!user) return json({ error: "Session expirée. Rouvre l'application." }, 401);

  // 2. Validation de la requête.
  let request;
  try {
    request = parseRequest(await req.json());
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
  const { data: entitlement } = await admin.from("entitlements").select("premium").eq("user_id", user.id).maybeSingle();
  const limit = entitlement?.premium ? PREMIUM_DAILY : FREE_DAILY;
  const { data: consumed, error: quotaError } = await admin.rpc("coach_consume", { p_user: user.id, p_limit: limit });
  if (quotaError) return json({ error: "Service momentanément indisponible." }, 503);
  const quota = { used: consumed?.[0]?.used ?? limit, limit, premium: entitlement?.premium ?? false };
  if (!consumed?.[0]?.allowed) {
    return json({ error: "Tu as atteint la limite de questions pour aujourd'hui.", quota }, 429);
  }

  // 5. Appel au modèle.
  const history = request.messages.slice(0, -1).map((m) => ({ role: m.role, content: m.content }));
  const messages: Anthropic.Beta.BetaMessageParam[] = [
    ...history,
    { role: "user", content: wrapLastUserMessage(question, request.context) },
  ];

  let response: Anthropic.Beta.BetaMessage;
  try {
    response = await anthropic.beta.messages.create({
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
  const usage = response.usage;
  await admin.rpc("coach_record_usage", {
    p_user: user.id,
    p_input: usage.input_tokens,
    p_output: usage.output_tokens,
    p_cache_read: usage.cache_read_input_tokens ?? 0,
    p_cache_write: usage.cache_creation_input_tokens ?? 0,
    p_cost_micros: costMicros(usage),
  });

  return json({ message, citations: cited, safety, quota, model: response.model });
});
