// functions/src/db_key.ts
// KanMon GO — DB Key Service (Firestore Edition)
//
// PERUBAHAN ARSITEKTUR:
//   ❌ SEBELUMNYA: key disimpan via CLI (firebase functions:config:set)
//                 → tidak bisa dari ponsel
//   ✅ SEKARANG:   key disimpan di Firestore koleksi _server_config
//                 → bisa diisi langsung dari Firebase Console di ponsel/browser
//
// CARA SETUP (tanpa terminal, hanya lewat website Firebase Console):
//   1. Buka Firebase Console → Firestore Database → + Start collection
//   2. Collection ID: _server_config
//   3. Document ID: db_keys
//   4. Tambah 3 field:
//      - contentKey  (string) → isi dengan 64 karakter hex
//      - userKey     (string) → isi dengan 64 karakter hex
//      - masterKey   (string) → isi dengan 64 karakter hex
//
// GENERATE KEY (bisa di website online, tanpa install apapun):
//   Buka: https://generate.plus/en/hex?gp[length]=64
// =============================================================================

import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import * as crypto from "crypto";

const db = admin.firestore();

const CONFIG_COLLECTION = "_server_config";
const DB_KEYS_DOC       = "db_keys";

// Cache key di memory agar tidak fetch Firestore setiap request
let _cachedContentKey: string | null = null;
let _cachedMasterKey: string | null  = null;
let _cacheTime = 0;
const CACHE_TTL_MS = 5 * 60 * 1000;

async function getContentKey(): Promise<string> {
  const now = Date.now();
  if (_cachedContentKey && (now - _cacheTime) < CACHE_TTL_MS) {
    return _cachedContentKey;
  }
  const doc = await db.collection(CONFIG_COLLECTION).doc(DB_KEYS_DOC).get();
  if (!doc.exists) {
    throw new functions.https.HttpsError(
      "not-found",
      "Dokumen _server_config/db_keys belum dibuat di Firestore. Lihat panduan setup."
    );
  }
  const key = doc.data()!.contentKey as string | undefined;
  if (!key || key.length < 32) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Field contentKey di _server_config/db_keys kosong atau terlalu pendek."
    );
  }
  _cachedContentKey = key;
  _cacheTime = now;
  return key;
}

async function getMasterKey(): Promise<Buffer> {
  const now = Date.now();
  if (_cachedMasterKey && (now - _cacheTime) < CACHE_TTL_MS) {
    return Buffer.from(_cachedMasterKey, "hex").subarray(0, 32);
  }
  const doc  = await db.collection(CONFIG_COLLECTION).doc(DB_KEYS_DOC).get();
  const data = doc.data() ?? {};
  const key  = (data.masterKey ?? data.userKey) as string | undefined;
  if (!key || key.length < 32) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Field masterKey di _server_config/db_keys kosong atau terlalu pendek."
    );
  }
  _cachedMasterKey = key;
  return Buffer.from(key, "hex").subarray(0, 32);
}

export const getDbKey = functions.https.onCall(async (_data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Harus login terlebih dahulu.");
  }

  const uid = context.auth.uid;

  // Rate limiting
  const rateLimitRef = db.collection("_rate_limits").doc(uid);
  const rateLimitDoc = await rateLimitRef.get();
  if (rateLimitDoc.exists) {
    const lastReq = rateLimitDoc.data()?.lastDbKeyRequest as admin.firestore.Timestamp | null;
    if (lastReq && (Date.now() - lastReq.toMillis()) / 1000 < 30) {
      throw new functions.https.HttpsError("resource-exhausted", "Terlalu banyak request. Tunggu 30 detik.");
    }
  }
  await rateLimitRef.set({ lastDbKeyRequest: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });

  console.log(`[getDbKey] uid=${uid}`);

  const contentKey = await getContentKey();
  const userKey    = await _getOrCreateUserDbKey(uid);

  return { contentKey, userKey };
});

async function _getOrCreateUserDbKey(uid: string): Promise<string> {
  const userRef  = db.collection("users").doc(uid);
  const userDoc  = await userRef.get();
  const existing = userDoc.data()?.dbKeyEncrypted as string | undefined;

  if (existing) return await _decryptKey(existing);

  const newKey       = crypto.randomBytes(32).toString("hex");
  const encryptedKey = await _encryptKey(newKey);
  await userRef.set({ dbKeyEncrypted: encryptedKey }, { merge: true });
  console.log(`[getDbKey] Generated new user key for uid=${uid}`);
  return newKey;
}

async function _encryptKey(plainKey: string): Promise<string> {
  const masterKey = await getMasterKey();
  const iv        = crypto.randomBytes(12);
  const cipher    = crypto.createCipheriv("aes-256-gcm", masterKey, iv);
  const encrypted = Buffer.concat([cipher.update(plainKey, "utf8"), cipher.final()]);
  const authTag   = cipher.getAuthTag();
  return `${iv.toString("hex")}:${authTag.toString("hex")}:${encrypted.toString("hex")}`;
}

async function _decryptKey(encryptedData: string): Promise<string> {
  const masterKey = await getMasterKey();
  const parts     = encryptedData.split(":");
  if (parts.length !== 3) throw new Error("Format key tidak valid");
  const iv        = Buffer.from(parts[0], "hex");
  const authTag   = Buffer.from(parts[1], "hex");
  const encrypted = Buffer.from(parts[2], "hex");
  const decipher  = crypto.createDecipheriv("aes-256-gcm", masterKey, iv);
  decipher.setAuthTag(authTag);
  return decipher.update(encrypted).toString("utf8") + decipher.final("utf8");
}
