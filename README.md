# KanMon GO — Aplikasi Belajar Bahasa Jepang dengan AI

<p align="center">
  <img src="assets/icons/logo/icon_theme_light.svg" width="96" alt="KanMon GO Logo"/>
</p>

**KanMon GO** adalah aplikasi Android untuk belajar bahasa Jepang secara komprehensif,
dilengkapi AI offline (llama.cpp) dan online (Puter.js + Bulk API), quiz JLPT/JFT,
flashcard FSRS-5, kanji, kosakata, grammar, dan banyak lagi.

---

## ✨ Fitur Utama

| Kategori | Fitur |
|----------|-------|
| 🤖 **AI** | Offline AI (llama.cpp GGUF), Online AI (Puter.js 20+ model), Bulk API (Groq, Gemini, Claude, OpenRouter) |
| 📚 **Konten** | Kanji N5–N1, Kosakata, Grammar (Bunpou), Partikel, Hiragana/Katakana |
| 🎯 **Latihan** | Quiz JLPT & JFT, Flashcard FSRS-5, Writing stroke order, Mensetsu |
| 🔬 **Tools** | OCR Scan (ML Kit), Reader (PDF/DOCX/TXT), E-Book, Notes, Terminal |
| 📊 **Progress** | Skill Tree, Analytics heatmap 365 hari, XP & streak system |
| ☁️ **Cloud** | Firebase Auth, Firestore sync, Remote Config, Crashlytics |

---

## 🏗️ Arsitektur

```
lib/
├── core/          → auth, config, router, theme, lifecycle, security
├── data/
│   ├── models/    → data models
│   ├── repositories/ → data access layer
│   └── services/  → business logic (singleton pattern)
├── features/      → UI screens per fitur
└── shared/
    └── widgets/   → reusable widgets
```

**Stack:** Flutter · Dart · Riverpod · GoRouter · Firebase · SQLite · llama.cpp JNI

---

## 🤖 AI Offline (llama.cpp)

Model GGUF berjalan langsung di device tanpa internet:

| Model | Ukuran | RAM Min | Rekomendasi |
|-------|--------|---------|-------------|
| Qwen3 0.6B Q4_K_M | 430MB | 2GB | ✅ Low-end |
| Qwen3 1.7B Q4_K_M | 1.1GB | 4GB | ✅ Mid-range |
| Gemma 3 1B | 650MB | 3GB | ✅ Semua device |
| Phi-4 Mini 3.8B Q4_K_M | 2.5GB | 6GB | ⭐ High-end |

**Setup:**
1. Settings → Model Manager → Download atau Import GGUF
2. Tap **Aktifkan** → model otomatis load
3. Buka Chat → pilih source **Offline**

---

## ☁️ AI Online & Bulk API

| Provider | Cara Setup |
|----------|-----------|
| Puter.js (20+ model) | Otomatis — tidak perlu API key |
| Groq | Settings → Bulk API → masukkan key |
| Gemini | Settings → Bulk API → masukkan key |
| Anthropic Claude | Settings → Bulk API → masukkan key |
| OpenRouter | Settings → Bulk API → masukkan key |
| LM Studio / Ollama | Settings → Bulk API → custom endpoint |

---

## 🔨 Build

### GitHub Actions (Rekomendasi)

Push ke `main` → Actions → **🚀 Build KanMon GO** otomatis berjalan.

**Secrets yang diperlukan:**

| Secret | Keterangan |
|--------|-----------|
| `KEYSTORE_BASE64` | Keystore JKS dalam base64 |
| `KEY_STORE_PASSWORD` | Password keystore |
| `KEY_ALIAS` | Alias key |
| `KEY_PASSWORD` | Password key |

### Build Lokal

```bash
git clone https://github.com/USERNAME/KanMonAI.git
cd KanMonAI

# Setup llama.cpp source
bash scripts/setup_llama.sh

# Install dependencies
flutter pub get

# Generate SQLite DB konten
python3 scripts/build_sqlite_db.py

# Run debug
flutter run

# Build release APK
flutter build apk --release
```

---

## 🐛 Build Error History

| Build | Error | Fix |
|-------|-------|-----|
| #103 | `themePackProvider` ambiguous import (`theme_provider.dart` vs `theme_providers.dart`) | Delete `theme_providers.dart`, tambah `sharedPreferencesProvider` ke `theme_provider.dart`, hapus import di `main.dart` |
| #104 | `llama_kv_self_clear` / `llama_kv_self_seq_rm` / `llama_kv_self_seq_add` undeclared | Migrate ke Memory V2 API — hapus `#ifdef` dual-branch di `llama_jni.cpp` |

---

## 📦 Dependencies Utama

```yaml
flutter_riverpod, go_router          # State & Navigation
firebase_core, firebase_auth         # Auth & Backend
cloud_firestore, firebase_crashlytics
sqflite, path_provider               # Local Database
google_mlkit_text_recognition        # OCR
syncfusion_flutter_pdfviewer         # PDF Viewer
audioplayers, video_player, chewie   # Media
purchases_flutter                    # RevenueCat (Membership)
http, share_plus, file_picker        # Network & File
```

---

## 📜 Lisensi

Proprietary — © 2026 KanMon GO. All rights reserved.
