// Tests de la logique du Coach : node --experimental-strip-types --test backend/supabase/functions/coach/
import { test } from "node:test";
import assert from "node:assert/strict";
import { checkCitations, costMicros, findForbidden, needsReminder, parseRequest, RequestError, screen } from "./logic.ts";
import { sourcesSection, wrapLastUserMessage } from "./prompt.ts";

test("valide et tronque la conversation", () => {
  const long = "a".repeat(5000);
  const messages = Array.from({ length: 30 }, (_, i) => ({ role: i % 2 === 0 ? "user" : "assistant", content: `m${i}` }));
  messages.push({ role: "user", content: long });
  const parsed = parseRequest({ messages, context: "ctx", personalization: true });
  assert.ok(parsed.messages.length <= 20);
  assert.equal(parsed.messages[0].role, "user");
  assert.equal(parsed.messages.at(-1)!.content.length, 2000);
  assert.equal(parsed.context, "ctx");
});

test("le contexte est ignoré sans consentement", () => {
  const parsed = parseRequest({ messages: [{ role: "user", content: "Bonjour" }], context: "données", personalization: false });
  assert.equal(parsed.context, "");
});

test("refuse les requêtes invalides", () => {
  assert.throws(() => parseRequest(null), RequestError);
  assert.throws(() => parseRequest({ messages: [] }), RequestError);
  assert.throws(() => parseRequest({ messages: [{ role: "system", content: "x" }] }), RequestError);
  assert.throws(() => parseRequest({ messages: [{ role: "user", content: "x" }, { role: "assistant", content: "y" }] }), RequestError);
});

test("signaux d'alerte, insensibles aux accents", () => {
  assert.equal(screen("J'ai plus envie de vivre"), "seekHelpNow");
  assert.equal(screen("une grosse BRÛLURE sur le crâne"), "consultDoctor");
  assert.equal(screen("Quels aliments riches en fer ?"), "none");
});

test("les citations inconnues sont retirées", () => {
  const known = new Set(["watson-2015-sleep"]);
  const result = checkCitations("Dors 7 heures [S:watson-2015-sleep]. Étude inventée [S:fake-2024] .", known);
  assert.deepEqual(result.cited, ["watson-2015-sleep"]);
  assert.deepEqual(result.removed, ["fake-2024"]);
  assert.ok(!result.text.includes("fake"));
  assert.ok(result.text.endsWith("Étude inventée."));
});

test("formulations interdites détectées", () => {
  assert.ok(findForbidden("Prends 5 mg par jour de finastéride"));
  assert.ok(findForbidden("Le minoxidil 5 % est idéal"));
  assert.ok(findForbidden("Tu peux arrêter ton traitement dès demain"));
  assert.ok(findForbidden("Ce shampoing stoppe la chute"));
  assert.equal(findForbidden("Parle de ton traitement avec ton médecin, sans le modifier toi-même."), null);
  assert.equal(findForbidden("N'arrête pas ton traitement sans en parler à ton médecin."), null);
  assert.equal(findForbidden("Surtout, ne stoppe pas ton traitement de toi-même."), null);
  assert.equal(findForbidden("Le zinc contribue au maintien de cheveux normaux [S:eu-432-2012]."), null);
});

test("coût en micro-dollars", () => {
  assert.equal(costMicros({ input_tokens: 1_000_000, output_tokens: 0 }), 4_000_000);
  assert.equal(costMicros({ input_tokens: 0, output_tokens: 1000, cache_read_input_tokens: 10_000 }), 22_000);
});

test("prompt stable et contexte encadré", () => {
  const a = sourcesSection([{ id: "b", title: "B", authors_or_org: "X", publisher_or_journal: "Y", year: null, type: "review", key_finding: "k" },
                            { id: "a", title: "A", authors_or_org: "X", publisher_or_journal: "Y", year: 2020, type: "review", key_finding: "k" }]);
  assert.ok(a.indexOf("[S:a]") < a.indexOf("[S:b]"));
  const bare = wrapLastUserMessage("Question", "");
  assert.ok(bare.startsWith("<conversation_state>") && bare.endsWith("Question") && !bare.includes("<user_context>"));
  const withContext = wrapLastUserMessage("Question", "âge : 28", { reminder: true });
  assert.ok(withContext.includes("rappel: oui") && withContext.indexOf("<user_context>") < withContext.indexOf("Question"));
});

test("rappel de prudence : première réponse ou sujet médical seulement", () => {
  const first = [{ role: "user" as const, content: "Comment mieux dormir ?" }];
  assert.equal(needsReminder(first, "none"), true);
  const later = [...first, { role: "assistant" as const, content: "…" }, { role: "user" as const, content: "Et pour le stress ?" }];
  assert.equal(needsReminder(later, "none"), false);
  const treatment = [...first, { role: "assistant" as const, content: "…" }, { role: "user" as const, content: "Le minoxidil, ça marche ?" }];
  assert.equal(needsReminder(treatment, "none"), true);
  assert.equal(needsReminder(later, "consultDoctor"), true);
});
