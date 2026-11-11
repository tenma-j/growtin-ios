// Tests de la lecture de photo : node --experimental-strip-types --test backend/supabase/functions/coach/
import { test } from "node:test";
import assert from "node:assert/strict";
import { parsePhotoReading, parsePhotoRequest, photoForbidden, photoPrompt, PhotoRequestError } from "./photo.ts";

const JPEG = "/9j/4AAQSkZJRgABAQ==";

test("requête photo validée", () => {
  const r = parsePhotoRequest({ zone: "leftTemple", image: JPEG, previousImage: JPEG, daysBetween: 30.4, conditions: "cheveux secs" });
  assert.equal(r.daysBetween, 30);
  assert.ok(photoPrompt(r).includes("tempe gauche"));
  assert.ok(photoPrompt(r).includes("30 jours"));
  const single = parsePhotoRequest({ zone: "vertex", image: JPEG, daysBetween: 12 });
  assert.equal(single.previousImage, null);
  assert.equal(single.daysBetween, null);
  assert.ok(photoPrompt(single).includes("comparison doit valoir null"));
});

test("requêtes photo refusées", () => {
  assert.throws(() => parsePhotoRequest({ zone: "nez", image: JPEG }), PhotoRequestError);
  assert.throws(() => parsePhotoRequest({ zone: "top" }), PhotoRequestError);
  assert.throws(() => parsePhotoRequest({ zone: "top", image: "iVBORw0KGgo=" }), PhotoRequestError); // PNG
  assert.throws(() => parsePhotoRequest({ zone: "top", image: "/9j/<script>" }), PhotoRequestError);
  assert.throws(() => parsePhotoRequest({ zone: "top", image: "/9j/" + "A".repeat(2_000_000) }), PhotoRequestError);
});

test("sortie du modèle bornée", () => {
  const reading = parsePhotoReading(JSON.stringify({
    conditions: "Photo nette, lumière douce.", observations: ["a", "b", "c", "d", "e"], comparison: "",
    next_photo_tips: ["x"], see_professional_soon: true,
  }));
  assert.ok(reading);
  assert.equal(reading.observations.length, 4);
  assert.equal(reading.comparison, null);
  assert.equal(reading.seeProfessionalSoon, true);
  assert.equal(parsePhotoReading("pas du json"), null);
  assert.equal(parsePhotoReading(JSON.stringify({ conditions: "", observations: [] })), null);
});

test("vocabulaire médical ou chiffré écarté", () => {
  const base = { conditions: "Photo nette.", observations: ["Le cuir chevelu apparaît un peu plus visible sur cette photo."],
                 comparison: null, nextPhotoTips: [], seeProfessionalSoon: false };
  assert.equal(photoForbidden(base), null);
  for (const bad of ["Cela ressemble à une alopécie.", "Stade 3 de Norwood.", "Environ 20 % de densité en moins.",
                     "La repousse est visible.", "Le minoxidil pourrait aider."]) {
    assert.ok(photoForbidden({ ...base, observations: [bad] }), bad);
  }
});
