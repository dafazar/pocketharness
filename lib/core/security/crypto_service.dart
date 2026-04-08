// lib/core/security/crypto_service.dart
//
// DEPRECATED: AES-256-GCM encryption tidak lagi digunakan sejak migrasi ke
// plain SQLite asset (km_content.db). File ini dipertahankan sebagai stub
// agar tidak ada import error jika ada referensi sisa.
//
// Jika enkripsi diperlukan kembali, tambahkan pointycastle ke pubspec.yaml
// dan restore implementasi penuh dari git history.

class CryptoService {
  CryptoService._();
  static final CryptoService instance = CryptoService._();
  static bool get isEncryptionEnabled => false;
}
