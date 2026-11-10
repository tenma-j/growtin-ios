// Règles du Coach indépendantes de l'environnement d'exécution (testées avec Node, exécutées par Deno).

export type ChatRole = "user" | "assistant";
export interface ChatTurn {
  role: ChatRole;
  content: string;
}

export interface CoachRequest {
  messages: ChatTurn[];
  /** Contexte partagé par l'utilisateur (vide si la personnalisation est désactivée). */
  context: string;
  personalization: boolean;
}

export const LIMITS = {
  maxTurns: 20,
  maxCharsPerTurn: 2000,
  maxContextChars: 6000,
};

export class RequestError extends Error {}

/** Valide et nettoie le corps de la requête envoyée par l'app. */
export function parseRequest(body: unknown): CoachRequest {
  if (typeof body !== "object" || body === null) throw new RequestError("Corps de requête invalide.");
  const raw = body as Record<string, unknown>;
  if (!Array.isArray(raw.messages) || raw.messages.length === 0) throw new RequestError("Aucun message.");
  const messages: ChatTurn[] = raw.messages.slice(-LIMITS.maxTurns).map((m: unknown) => {
    const turn = m as Record<string, unknown>;
    if ((turn.role !== "user" && turn.role !== "assistant") || typeof turn.content !== "string") {
      throw new RequestError("Message invalide.");
    }
    const content = turn.content.trim().slice(0, LIMITS.maxCharsPerTurn);
    if (!content) throw new RequestError("Message vide.");
    return { role: turn.role, content };
  });
  // Le premier message doit venir de l'utilisateur, le dernier aussi.
  while (messages.length && messages[0].role !== "user") messages.shift();
  if (!messages.length || messages[messages.length - 1].role !== "user") {
    throw new RequestError("Le dernier message doit venir de l'utilisateur.");
  }
  const personalization = raw.personalization === true;
  const context = personalization && typeof raw.context === "string" ? raw.context.slice(0, LIMITS.maxContextChars) : "";
  return { messages, context, personalization };
}

// ─── Signaux d'alerte (même logique que SafetyScreener côté app) ───

export type SafetyLevel = "none" | "consultDoctor" | "seekHelpNow";

const DISTRESS = ["suicid", "envie de mourir", "me tuer", "en finir", "plus envie de vivre", "me faire du mal", "mettre fin a mes jours"];
const CONSULT = [
  "plaque", "pelade", "zone sans cheveux", "douleur", "douloureu", "brulure", "ca brule", "rougeur", "pus", "croute",
  "squame", "inflamm", "suintement", "infection", "par poignee", "touffe", "chute brutale", "chute massive",
  "sourcil", "mes cils", "effet secondaire", "effets secondaires", "effet indesirable", "effets indesirables",
  "libido", "erection", "palpitation", "vertige",
];

export function normalize(text: string): string {
  return text.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/’/g, "'").toLowerCase();
}

export function screen(text: string): SafetyLevel {
  const t = normalize(text);
  if (DISTRESS.some((k) => t.includes(k))) return "seekHelpNow";
  if (CONSULT.some((k) => t.includes(k))) return "consultDoctor";
  return "none";
}

export const DISTRESS_REPLY =
  "Je suis désolé que tu traverses un moment aussi difficile. Ce que tu ressens compte, et tu n'as pas à rester seul·e avec ça. " +
  "Appelle le 3114, le numéro national de prévention du suicide : il est gratuit et joignable 24 h/24. " +
  "En cas de danger immédiat, appelle le 112. Si tu le peux, parles-en aussi à une personne de confiance. " +
  "Je reste là si tu veux parler de tes cheveux plus tard, mais ta sécurité passe avant tout.";

// ─── Contrôle des réponses ───

const CITATION = /\[S:([a-z0-9-]+)\]/g;

/** Retire les citations inconnues de la base vérifiée et renvoie les identifiants conservés. */
export function checkCitations(text: string, knownIDs: Set<string>): { text: string; cited: string[]; removed: string[] } {
  const cited = new Set<string>();
  const removed = new Set<string>();
  const cleaned = text.replace(CITATION, (match, id: string) => {
    if (knownIDs.has(id)) {
      cited.add(id);
      return match;
    }
    removed.add(id);
    return "";
  }).replace(/ +([.,;:!?])/g, "$1").replace(/ {2,}/g, " ");
  return { text: cleaned.trim(), cited: [...cited], removed: [...removed] };
}

/** Formulations interdites : promesses de résultat, dosages, consignes d'arrêt de traitement. */
const FORBIDDEN: RegExp[] = [
  /repousse garantie/i,
  /garanti[e]? (de|une) repousse/i,
  /(stoppe|arr[eê]te) (la|ta) chute/i,
  /gu[ée]ri(t|r) (la |l'|ton |ta )?(calvitie|alop[ée]cie)/i,
  /\b\d+([.,]\d+)?\s?(mg|µg|mcg)\s?(par|\/)\s?(jour|j)\b/i,
  /\b(minoxidil|finast[ée]ride|dutast[ée]ride)\b[^.]{0,40}\b\d+([.,]\d+)?\s?(%|mg)/i,
  /(arr[eê]t(e|er|ez|es)|stopp(e|er|ez)|interromp(s|re|ez))[^.]{0,30}(ton|ta|tes|le|la|les|votre) (traitement|m[ée]dicament)/i,
];
const STOP_TREATMENT = FORBIDDEN[FORBIDDEN.length - 1];

/** Une consigne d'arrêt formulée à la négative (« n'arrête pas… », « ne modifie pas… ») est un conseil de prudence. */
function isNegated(text: string, index: number): boolean {
  const before = normalize(text.slice(Math.max(0, index - 6), index));
  return /(n'|ne )\s*$/.test(before);
}

export function findForbidden(text: string): string | null {
  for (const pattern of FORBIDDEN) {
    const global = new RegExp(pattern.source, pattern.flags.includes("g") ? pattern.flags : pattern.flags + "g");
    for (const match of text.matchAll(global)) {
      if (pattern === STOP_TREATMENT && isNegated(text, match.index ?? 0)) continue;
      return match[0];
    }
  }
  return null;
}

export const SAFE_FALLBACK_REPLY =
  "Je préfère ne pas répondre à cette question de cette façon : elle touche à un traitement ou à un résultat que seul un professionnel de santé peut évaluer pour toi. " +
  "Un dermatologue pourra t'expliquer les options adaptées à ta situation. Je peux en revanche t'expliquer ce que disent les études, ou t'aider sur tes habitudes.";

// ─── Coûts (Claude Opus 5.5 : 4 $ / 20 $ par million de jetons, lecture du cache 0,20 $, écriture 1,25 × l'entrée) ───

export interface UsageLike {
  input_tokens: number;
  output_tokens: number;
  cache_read_input_tokens?: number | null;
  cache_creation_input_tokens?: number | null;
}

export const PRICES_PER_MTOK = { input: 4, output: 20, cacheRead: 0.2, cacheWrite: 5 };

/** Coût estimé en micro-dollars (millionièmes de dollar). */
export function costMicros(usage: UsageLike, prices = PRICES_PER_MTOK): number {
  const dollars =
    (usage.input_tokens * prices.input +
      usage.output_tokens * prices.output +
      (usage.cache_read_input_tokens ?? 0) * prices.cacheRead +
      (usage.cache_creation_input_tokens ?? 0) * prices.cacheWrite) / 1_000_000;
  return Math.round(dollars * 1_000_000);
}
