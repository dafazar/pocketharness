// functions/src/index.ts
// Pocket Harness — Cloud Functions (Fixed)
//
// PERUBAHAN dari versi sebelumnya:
//   ✅ Export getDbKey dari db_key.ts
//   ✅ onXpUpdate difix: emit List<ConnectivityResult> bukan single value
//      (tidak ada perubahan di Cloud Functions, hanya penanda)
//   ✅ Semua existing functions tetap berjalan
// =============================================================================

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();
const db = admin.firestore();

// ── DB Key Service (BARU) ─────────────────────────────────────────────────────
export { getDbKey } from "./db_key";

// ── RevenueCat Webhook ────────────────────────────────────────────────────────
export const revenuecatWebhook = functions.https.onRequest(async (req, res) => {
  try {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    const event   = req.body;
    const uid     = event.app_user_id as string;
    const type    = event.type as string;
    const expMs   = event.expiration_at_ms as number | null;
    const store   = event.store as string;

    if (!uid) {
      res.status(400).send("Missing app_user_id");
      return;
    }

    const userRef = db.collection("users").doc(uid);
    const userDoc = await userRef.get();
    if (!userDoc.exists) {
      console.warn(`User ${uid} tidak ditemukan di Firestore`);
      res.status(200).send("User not found, ignoring");
      return;
    }

    const platform = store === "APP_STORE" ? "ios" : "android";

    switch (type) {
      case "INITIAL_PURCHASE":
      case "RENEWAL":
        await userRef.update({
          "membership.tier":      "premium",
          "membership.expiresAt": expMs
            ? admin.firestore.Timestamp.fromMillis(expMs)
            : null,
          "membership.platform":  platform,
          "membership.updatedAt": admin.firestore.FieldValue.serverTimestamp(),
        });
        break;

      case "NON_RENEWING_PURCHASE":
        await userRef.update({
          "membership.tier":      "lifetime",
          "membership.expiresAt": null,
          "membership.platform":  platform,
          "membership.updatedAt": admin.firestore.FieldValue.serverTimestamp(),
        });
        break;

      case "CANCELLATION":
      case "EXPIRATION":
        await userRef.update({
          "membership.tier":      "free",
          "membership.expiresAt": null,
          "membership.updatedAt": admin.firestore.FieldValue.serverTimestamp(),
        });
        break;

      case "UNCANCELLATION":
        await userRef.update({
          "membership.tier":      "premium",
          "membership.expiresAt": expMs
            ? admin.firestore.Timestamp.fromMillis(expMs)
            : null,
          "membership.updatedAt": admin.firestore.FieldValue.serverTimestamp(),
        });
        break;

      default:
        console.log(`[${type}] Event tidak ditangani untuk uid=${uid}`);
    }

    res.status(200).send("OK");
  } catch (error) {
    console.error("Webhook error:", error);
    res.status(500).send("Internal Server Error");
  }
});

// ── Trigger: Update leaderboard saat XP berubah ───────────────────────────────
export const onXpUpdate = functions.firestore
  .document("users/{uid}")
  .onUpdate(async (change, context) => {
    const before   = change.before.data();
    const after    = change.after.data();
    const xpBefore = before?.stats?.totalXp ?? 0;
    const xpAfter  = after?.stats?.totalXp  ?? 0;
    if (xpAfter === xpBefore) return;

    const uid         = context.params.uid;
    const displayName = after?.displayName ?? "Anonim";
    const now         = new Date();
    const year        = now.getFullYear();
    const week        = getWeekNumber(now);
    const docId       = `weekly_${year}_w${String(week).padStart(2, "0")}`;
    const leaderRef   = db.collection("leaderboard").doc(docId);

    await db.runTransaction(async (t) => {
      const snap = await t.get(leaderRef);
      let entries: Array<{uid: string; displayName: string; xp: number; rank: number}> = [];
      if (snap.exists) entries = snap.data()?.entries ?? [];

      const idx = entries.findIndex((e) => e.uid === uid);
      if (idx >= 0) {
        entries[idx].xp          = xpAfter;
        entries[idx].displayName = displayName;
      } else {
        entries.push({ uid, displayName, xp: xpAfter, rank: 0 });
      }

      entries.sort((a, b) => b.xp - a.xp);
      entries.forEach((e, i) => { e.rank = i + 1; });

      t.set(leaderRef, {
        entries:   entries.slice(0, 100),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        period:    docId,
      });
    });
  });

// ── HTTP: Expire membership kadaluarsa (jalankan via Cloud Scheduler) ──────────
export const checkExpiredMemberships = functions.https.onRequest(async (req, res) => {
  const now = admin.firestore.Timestamp.now();
  const expiredQuery = await db.collection("users")
    .where("membership.tier", "==", "premium")
    .where("membership.expiresAt", "!=", null)
    .where("membership.expiresAt", "<", now)
    .get();

  const batch = db.batch();
  expiredQuery.docs.forEach((doc) => {
    batch.update(doc.ref, {
      "membership.tier":      "free",
      "membership.expiresAt": null,
    });
  });
  await batch.commit();

  res.status(200).json({
    message: `${expiredQuery.size} membership telah diexpire`,
    count:   expiredQuery.size,
  });
});

// ── Helper ────────────────────────────────────────────────────────────────────
function getWeekNumber(d: Date): number {
  const date     = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
  date.setUTCDate(date.getUTCDate() + 4 - (date.getUTCDay() || 7));
  const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
  return Math.ceil((((date.getTime() - yearStart.getTime()) / 86400000) + 1) / 7);
}
