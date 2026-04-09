# 🔐 Setup SQLCipher + DB Key dari Firebase Server

Panduan ini menjelaskan cara mengamankan database KanMon GO
agar encryption key tidak pernah ada di dalam APK.

---

## Arsitektur Keamanan

```
APK (di device user)          Firebase Server
─────────────────────         ────────────────────────────
km_content.db  ← terenkripsi  Cloud Function getDbKey
kanmongo_user.db ← terenkripsi  ↓ verifikasi token
                              Firestore (simpan user key terenkripsi)
App start:
1. Login Firebase Auth ──────→ dapat ID Token
2. Panggil getDbKey() ───────→ server verifikasi token
3. Terima key ←──────────────  return key (tidak pernah ke disk)
4. Buka DB dengan key
```

---

## LANGKAH 1 — Update pubspec.yaml

Ganti `sqflite` dengan `sqflite_sqlcipher`, dan tambahkan `cloud_functions`:

```yaml
dependencies:
  # HAPUS baris ini:
  # sqflite: ^2.3.3+1

  # TAMBAH baris ini:
  sqflite_sqlcipher: ^3.0.1+2  # Pastikan versi kompatibel dengan Flutter SDK aktif
  cloud_functions: ^5.1.3
```

Jalankan:
```bash
flutter pub get
```

---

## LANGKAH 2 — Enkripsi km_content.db (sekali saja)

Database konten kamu saat ini masih **plain SQLite** (belum terenkripsi).
Kamu perlu mengenkripsinya dengan SQLCipher sebelum di-ship di APK.

### Cara mengenkripsi DB yang sudah ada:

Gunakan SQLCipher CLI atau script Python berikut:

```python
# scripts/encrypt_db.py
# Jalankan: python encrypt_db.py
# Butuh: pip install sqlcipher3

import sqlcipher3
import os

SOURCE_DB = "assets/database/km_content.db"   # DB lama (plain)
DEST_DB   = "assets/database/km_content_enc.db"  # DB baru (terenkripsi)
DB_KEY    = "YOUR_64_CHAR_HEX_KEY"            # Key yang sama dengan di Firebase

# Buka DB plain
plain = sqlcipher3.connect(SOURCE_DB)

# Buat DB terenkripsi
plain.execute(f"ATTACH DATABASE '{DEST_DB}' AS encrypted KEY '{DB_KEY}'")
plain.execute("SELECT sqlcipher_export('encrypted')")
plain.execute("DETACH DATABASE encrypted")
plain.close()

# Ganti file lama
os.replace(DEST_DB, SOURCE_DB)
print("✅ DB berhasil dienkripsi!")
```

Setelah selesai, **file `assets/database/km_content.db` sudah terenkripsi**
dan hanya bisa dibuka dengan key yang benar.

---

## LANGKAH 3 — Setup Firebase Functions Config

Jalankan perintah ini di terminal untuk menyimpan key di server:

```bash
# Generate key baru (jalankan sekali, simpan hasilnya!)
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
# Contoh output: a3f8c2d1e4b5...

# Set key untuk content DB
firebase functions:config:set dbkey.content="KEY_CONTENT_KAMU_DISINI"

# Set key untuk user DB (master key enkripsi)
firebase functions:config:set dbkey.user="KEY_USER_KAMU_DISINI"

# Set master key untuk enkripsi per-user key di Firestore
firebase functions:config:set dbkey.master="KEY_MASTER_KAMU_DISINI"

# Verifikasi
firebase functions:config:get
```

⚠️ **SIMPAN KETIGA KEY INI DI TEMPAT AMAN** (password manager, dll).
Jika hilang, database tidak bisa dibuka!

---

## LANGKAH 4 — Deploy Cloud Function

```bash
# Pastikan ada di folder root proyek
cd kanmon-go-main

# Deploy function getDbKey
firebase deploy --only functions:getDbKey

# Atau deploy semua functions
firebase deploy --only functions
```

Setelah deploy, kamu akan mendapat URL seperti:
```
https://asia-southeast1-kanmon-5e624.cloudfunctions.net/getDbKey
```

---

## LANGKAH 5 — Update main.dart

Ubah urutan inisialisasi agar fetch key dilakukan setelah login:

```dart
// lib/main.dart

// Di dalam auth_service.dart atau splash_screen.dart,
// setelah user berhasil login, tambahkan:

import 'package:kanmongo/core/security/secure_db_key_service.dart';

// Setelah login berhasil:
await SecureDbKeyService.instance.fetchKeysWithRetry();

// Baru kemudian init database:
await DatabaseService.instance.init();
```

### Update auth_service.dart — tambahkan fetchKeys setelah login:

```dart
// Di fungsi signInWithGoogle() atau signInWithEmail(),
// setelah berhasil dapat user:

final user = await FirebaseAuth.instance.signInWithCredential(...);
if (user != null) {
  // Fetch DB key dari server
  await SecureDbKeyService.instance.fetchKeysWithRetry();
}
```

### Update DatabaseService — ganti import ContentDatabase:

```dart
// lib/data/services/database_service.dart
// Ganti:
import 'package:kanmongo/core/database/content_database.dart';
// Menjadi:
import 'package:kanmongo/core/database/content_database_cipher.dart';
```

### Hapus keys saat logout:

```dart
// Di fungsi signOut():
await FirebaseAuth.instance.signOut();
SecureDbKeyService.instance.clearKeys(); // ← Tambahkan ini
```

---

## LANGKAH 6 — Update Firestore Security Rules

Tambahkan rule untuk collection `_rate_limits` yang dipakai Cloud Function:

```
match /_rate_limits/{uid} {
  // Hanya bisa diakses oleh Cloud Function (server-side admin)
  allow read, write: if false;
}
```

---

## Ringkasan Keamanan yang Didapat

| Aspek | Sebelum | Sesudah |
|-------|---------|---------|
| DB Key lokasi | Tidak ada (plain) | Server Firebase |
| DB terenkripsi | ❌ Plain SQLite | ✅ SQLCipher AES-256 |
| Key di APK | ❌ Bisa di-extract | ✅ Tidak ada di APK |
| Key di disk device | ❌ Tidak ada perlindungan | ✅ Hanya di memory |
| User DB key | ❌ Tidak ada | ✅ Per-user, unik |
| Akses tanpa login | ❌ Bebas buka DB | ✅ Tidak bisa tanpa token |

---

## FAQ

**Q: Bagaimana jika user offline dan belum fetch key?**
A: App tidak akan bisa membuka DB. Ini by design — butuh koneksi untuk
   verifikasi identitas user. `OnlineGuard` akan memblokir akses lebih dulu.

**Q: Apakah key disimpan di cache?**
A: Tidak. Key hanya ada di memory selama app berjalan. Saat app di-kill
   dan dibuka kembali, key akan di-fetch ulang dari server.

**Q: Berapa biaya Cloud Function ini?**
A: Free tier Firebase mencakup 2 juta invokasi/bulan.
   Untuk ratusan user aktif, masih gratis.

**Q: Bagaimana jika Firebase down?**
A: App tidak bisa dibuka. Pertimbangkan cache key terenkripsi di
   flutter_secure_storage sebagai fallback untuk sesi yang sudah aktif.
