# 🔥 Panduan Setup Firebase Backend — KanMon GO (Free Tier)

## Langkah 1 — Authentication

1. Buka Firebase Console → **Build → Authentication → Get started**
2. Tab **Sign-in method**, aktifkan satu per satu:
   - **Email/Password** → klik → Enable → Save
   - **Google** → klik → Enable → isi email kamu → Save
   - **Phone** → klik → Enable → Save
3. Untuk Google Sign-In, daftarkan SHA-1:
   - Project Settings (⚙️) → Your apps → Android → Add fingerprint
   - Jalankan di komputer: `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android`
   - Salin nilai SHA1 → paste → Save

---

## Langkah 2 — Firestore Database

1. **Build → Firestore Database → Create database**
2. Pilih **Production mode** → Next
3. Lokasi: **asia-southeast1 (Singapore)** → Enable
4. Setelah terbuat → klik tab **Rules**
5. Hapus semua isi rules lama, paste ini:

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

6. Klik **Publish**

---

## Langkah 3 — Remote Config

1. **Build → Remote Config → Create configuration**
2. Tambahkan parameter berikut satu per satu (klik Add parameter):

| Key | Type | Default |
|-----|------|---------|
| free_quiz_limit_per_day | Number | 10 |
| free_ai_messages_per_day | Number | 5 |
| free_flashcard_decks | Number | 3 |
| show_premium_banner | Boolean | true |
| monthly_price_idr | Number | 49900 |
| lifetime_price_idr | Number | 299000 |

3. Setelah semua ditambah → klik **Publish changes**

---

## Langkah 4 — Push Repo & Build APK

```bash
cd kanmongo
git init
git add .
git commit -m "KanMon GO — Firebase ready"
git remote add origin https://github.com/USERNAME/kanmongo.git
git push -u origin main

# Atau trigger manual:
# GitHub → Actions → 🚀 Build KanMon GO → Run workflow
```

Lalu di GitHub → **Actions → 🚀 Build KanMon GO → Run workflow**

---

## Kuota Free Tier (Spark Plan)

| Service | Gratis |
|---------|--------|
| Authentication | Unlimited user |
| Firestore | 1 GB storage, 50.000 reads/hari |
| Remote Config | Gratis sepenuhnya |
| Analytics | Gratis sepenuhnya |
| Crashlytics | Gratis sepenuhnya |

Cukup untuk ratusan pengguna aktif!

