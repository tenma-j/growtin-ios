import { test } from "node:test";
import assert from "node:assert/strict";
import { sameSecret, updatesFor } from "./logic.ts";

const user = "3f1c9a2e-8b7d-4c6e-9f0a-1b2c3d4e5f60";
const now = 1_800_000_000_000;

test("achat initial et renouvellement : Premium actif", () => {
  for (const type of ["INITIAL_PURCHASE", "RENEWAL", "UNCANCELLATION", "PRODUCT_CHANGE"]) {
    assert.deepEqual(updatesFor({ type, app_user_id: user, entitlement_ids: ["premium"], expiration_at_ms: now + 1000, event_timestamp_ms: now }, "premium", now),
      [{ userID: user, premium: true, eventMs: now }]);
  }
});

test("résiliation et problème de paiement : accès maintenu jusqu'à l'expiration", () => {
  for (const type of ["CANCELLATION", "BILLING_ISSUE"]) {
    assert.equal(updatesFor({ type, app_user_id: user, entitlement_ids: ["premium"], expiration_at_ms: now + 1000 }, "premium", now)[0].premium, true);
  }
});

test("expiration : Premium retiré", () => {
  assert.equal(updatesFor({ type: "EXPIRATION", app_user_id: user, entitlement_ids: ["premium"], expiration_at_ms: now - 1 }, "premium", now)[0].premium, false);
});

test("identifiants anonymes RevenueCat et autres droits ignorés", () => {
  assert.deepEqual(updatesFor({ type: "INITIAL_PURCHASE", app_user_id: "$RCAnonymousID:abc", entitlement_ids: ["premium"] }, "premium", now), []);
  assert.deepEqual(updatesFor({ type: "INITIAL_PURCHASE", app_user_id: user, entitlement_ids: ["autre"] }, "premium", now), []);
  assert.deepEqual(updatesFor({ type: "TEST" }, "premium", now), []);
});

test("transfert d'un achat entre comptes", () => {
  const other = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee";
  const updates = updatesFor({ type: "TRANSFER", transferred_from: [user], transferred_to: [other], event_timestamp_ms: now }, "premium", now);
  assert.deepEqual(updates, [{ userID: user, premium: false, eventMs: now }, { userID: other, premium: true, eventMs: now }]);
});

test("comparaison du secret", () => {
  assert.equal(sameSecret("Bearer abc", "Bearer abc"), true);
  assert.equal(sameSecret("Bearer abd", "Bearer abc"), false);
  assert.equal(sameSecret("", ""), false);
});
