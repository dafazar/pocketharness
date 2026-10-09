# Pocket Harness — Aplikasi AI Mobile

<p align="center">
  <img src="assets/icons/logo/icon_theme_light.svg" width="96" alt="Pocket Harness Logo"/>
</p>

**Pocket Harness** adalah aplikasi AI mobile yang menggabungkan chat AI, AI agent, terminal, Claude Code, VS Code, dan alat bantu dokumen dalam satu aplikasi. Model dapat berjalan offline langsung di perangkat (llama.cpp) atau online lewat Puter.js dan provider API.

---

## ✨ Fitur Utama

| Kategori | Fitur |
|----------|-------|
| 🤖 **AI Chat** | Chat offline (llama.cpp, GGUF), online (Puter.js), dan provider API (Groq, Gemini, Claude, OpenRouter, Ollama) |
| 🧠 **AI Agent** | Agent AI yang menjalankan tugas dengan alat bantu |
| 💻 **Terminal & Claude Code** | Terminal bawaan dan instalasi Claude Code di perangkat |
| 🧩 **VS Code** | VS Code di perangkat melalui code-server |
| 📷 **OCR & Media** | Scan teks dari gambar (ML Kit) dan Media & AI |
| 📚 **Dokumen** | Reader PDF, E-Book, dan Catatan |
| 🎙️ **Suara** | Text-to-speech dan speech-to-text |
| ☁️ **Cloud** | Firebase Auth, Cloud Firestore, Remote Config, Crashlytics |
| 💎 **Membership** | Langganan via RevenueCat |

---

## 🏗️ Arsitektur

```
lib/
├── core/          → ai, auth, config, router, security, sync, theme, membership, tools
├── data/
│   ├── models/    → data models
│   ├── repositories/ → data access layer
│   └── services/  → logika bisnis
├── features/      → layar per fitur (chat, agent, terminal, claude_code, vscode, media, ...)
└── shared/        → widget dan utilitas bersama
```

**Stack:** Flutter · Dart · Riverpod · GoRouter · Firebase · SQLite (SQLCipher) · llama.cpp JNI

---

## 🤖 AI Offline (llama.cpp)

Model GGUF berjalan langsung di perangkat tanpa internet:

| Model | Ukuran | RAM Min | Rekomendasi |
|-------|--------|---------|-------------|
| Qwen3 0.6B Q4_K_M | 430MB | 2GB | ✅ Low-end |
| Qwen3 1.7B Q4_K_M | 1.1GB | 4GB | ✅ Mid-range |
| Gemma 3 1B | 650MB | 3GB | ✅ Semua device |
| Phi-4 Mini 3.8B Q4_K_M | 2.5GB | 6GB | ⭐ High-end |

**Setup:**
1. Buka **Model Manager** → Download atau Import GGUF
2. Tap **Aktifkan** → model otomatis dimuat
3. Buka Chat → pilih source **Offline**

---

## ☁️ AI Online & Provider API

| Provider | Cara Setup |
|----------|-----------|
| Puter.js | Otomatis — tidak perlu API key |
| Groq, Gemini, Claude, OpenRouter | Setelan → Bulk API → masukkan key |
| Ollama / endpoint kustom | Setelan → Bulk API → isi endpoint |

---

## 🔨 Build

### GitHub Actions

Buka tab **Actions** → **🚀 Build Pocket Harness** → **Run workflow**. Workflow ini berjalan manual.

**Secrets yang diperlukan:**

| Secret | Keterangan |
|--------|-----------|
| `KEYSTORE_BASE64` | Keystore JKS dalam base64 |
| `KEY_STORE_PASSWORD` | Password keystore |
| `KEY_ALIAS` | Alias key |
| `KEY_PASSWORD` | Password key |

### Build Lokal

```bash
git clone https://github.com/USERNAME/pocketharness.git
cd pocketharness

# Setup sumber llama.cpp
bash scripts/setup_llama.sh

# Install dependensi
flutter pub get

# Generate database SQLite
python3 scripts/build_sqlite_db.py

# Jalankan debug
flutter run

# Build APK release
flutter build apk --release
```

---

## 📦 Dependensi Utama

```yaml
flutter_riverpod, riverpod_annotation, go_router   # State & Navigation
sqflite_sqlcipher                                  # Database terenkripsi
firebase_core, firebase_auth, firebase_analytics   # Firebase
firebase_crashlytics, firebase_remote_config       # Monitoring & konfigurasi
cloud_firestore                                    # Cloud Firestore
purchases_flutter                                  # RevenueCat (membership)
google_mlkit_text_recognition                      # OCR
syncfusion_flutter_pdfviewer                       # PDF viewer
flutter_tts, speech_to_text                        # Suara
audioplayers, video_player, file_picker, share_plus
```

---

## 📜 Lisensi

Proprietary — © 2026 Pocket Harness. All rights reserved.
