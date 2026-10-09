# 🔥 Pocket Harness — Panduan Instalasi Firebase

Dokumen ini menjelaskan langkah-langkah mengintegrasikan Firebase ke Pocket Harness.

---

## 📦 Services Firebase yang Digunakan

| Service | Fungsi |
|---------|--------|
| Authentication | Login Email/Password + Google |
| Cloud Firestore | Sync progress user antar device |
| Remote Config | Feature flags & konfigurasi dinamis |
| Crashlytics | Bug reporting & crash monitoring |
| Storage | Upload file user (opsional) |

---

## 🚀 Langkah Instalasi

### STEP 1 — Buat Firebase Project

1. Buka https://console.firebase.google.com
2. **Add project** → nama bebas, misalnya `pocketharness-prod`
3. Enable Google Analytics
4. **Add Android app**:
   - Package: sama dengan `applicationId` di `android/app/build.gradle`
   - Download `google-services.json`
   - **REPLACE** file `android/app/google-services.json` di repo kamu

### STEP 2 — Aktifkan Firebase Services

| Service | Cara Aktifkan |
|---------|--------------|
| **Authentication** | Authentication → Get started → aktifkan Email/Password & Google |
| **Cloud Firestore** | Firestore → Create database → **Production mode** → `asia-southeast1` |
| **Remote Config** | Remote Config → Create configuration |
| **Crashlytics** | Crashlytics → Set up Crashlytics |

### STEP 3 — Firestore Rules

Di Firestore → Rules, paste:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null
                          && request.auth.uid == userId;
      match /progress/{docId} {
        allow read, write: if request.auth.uid == userId;
      }
      match /flashcards/{cardId} {
        allow read, write: if request.auth.uid == userId;
      }
      match /notes/{noteId} {
        allow read, write: if request.auth.uid == userId;
      }
    }
    match /leaderboard/{docId} {
      allow read, write: if request.auth != null;
    }
    match /app_config/{docId} {
      allow read: if request.auth != null;
      allow write: if false;
    }
  }
}
```

### STEP 4 — Remote Config Parameters

Tambahkan parameter berikut di Remote Config:

| Key | Type | Default |
|-----|------|---------|
| `free_quiz_limit_per_day` | Number | 10 |
| `free_ai_messages_per_day` | Number | 5 |
| `free_flashcard_decks` | Number | 3 |
| `show_premium_banner` | Boolean | true |
| `monthly_price_idr` | Number | 49900 |
| `lifetime_price_idr` | Number | 299000 |

### STEP 5 — Daftarkan SHA-1 (untuk Google Sign-In)

```bash
# Debug keystore
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android

# Release keystore
keytool -list -v -keystore <path-ke-keystore-release> -alias <KEY_ALIAS>
```

Salin SHA-1 → Firebase Console → Project Settings → Android app → Add fingerprint.

### STEP 6 — Setup RevenueCat (Membership)

1. Daftar di https://app.revenuecat.com → buat project **Pocket Harness**
2. Buat **Entitlement**: `premium`
3. Buat **Products** dengan ID pilihan Anda, misalnya `pocketharness_premium_monthly`, `pocketharness_premium_yearly`, `pocketharness_lifetime`
4. Salin API Key → edit `lib/core/membership/membership_service.dart`:

```dart
const _rcAndroidKey = 'goog_XXXXXXXXXXXXXXXXXXXXXXXX';  // ← ganti ini
const _rcIosKey     = 'appl_XXXXXXXXXXXXXXXXXXXXXXXX';  // ← ganti ini
```

### STEP 7 — Build & Deploy

```bash
# Push ke GitHub, lalu jalankan workflow Build Pocket Harness secara manual di tab Actions
git add .
git commit -m "feat: Firebase integration"
git push origin main
```

---

## 🔑 Cara Pakai PremiumGate

```dart
// Opsi A — Gate seluruh widget:
PremiumGate(
  featureLabel: 'Quiz N3',
  child: QuizContent(),
)

// Opsi B — Gate dalam logika:
Future<void> _startQuiz() async {
  if (!await PremiumGate.check(context, ref, featureLabel: 'Quiz N3')) return;
  // lanjutkan...
}
```

---

## ⚠️ Checklist Sebelum Publish

- [ ] `google-services.json` asli sudah di `android/app/`
- [ ] RevenueCat API key sudah diganti di `membership_service.dart`
- [ ] `minSdkVersion 21` sudah diset di `android/app/build.gradle`
- [ ] Firestore rules sudah di-publish
- [ ] SHA-1 fingerprint sudah didaftarkan
- [ ] Test login, register, beli membership di device nyata

---

## 🆘 Troubleshooting

| Error | Solusi |
|-------|--------|
| `google-services.json` not found | Pastikan di `android/app/`, bukan `android/` |
| `FirebaseException: [core/no-app]` | `Firebase.initializeApp()` belum dipanggil di `main.dart` |
| `PlatformException: ApiException: 10` | SHA-1 fingerprint belum didaftarkan |
| Build error `minSdkVersion` | Ubah ke `minSdkVersion 21` di `android/app/build.gradle` |
| Firestore `permission-denied` | Publish ulang rules di Firebase Console |

---

## 💰 Kuota Free Tier (Spark Plan)

| Service | Gratis |
|---------|--------|
| Authentication | Unlimited user |
| Firestore | 1 GB storage, 50.000 reads/hari |
| Remote Config | Gratis sepenuhnya |
| Analytics | Gratis sepenuhnya |
| Crashlytics | Gratis sepenuhnya |
