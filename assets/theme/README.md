# Theme Assets — Pocket Harness

Direktori ini berisi PNG asset untuk tema visual Pocket Harness.

## Struktur

```
theme/
  original/          ← Tema AMOLED Black + Red (satu-satunya pack aktif)
    backgrounds/     ← Background per screen (bg_home.png, bg_kanji.png, dll)
    banners/         ← Banner per fitur (banner_home.png, banner_kanji.png, dll)
    flashcard/       ← Cover deck flashcard
    kana/            ← Asset grid kana
    menus/           ← Icon menu home screen
    notes/           ← Background kartu catatan
    placeholders/    ← Placeholder saat asset belum tersedia
    quiz/            ← Cover deck quiz
    swatches/        ← Preview warna tema
  theme_config_original.json  ← Metadata tema (nama, warna, paths)
```

## AppThemePack

Sejak v2.0.0, Pocket Harness hanya menggunakan **1 pack tema: `original`**.
Pack lama (white, dark, sakura, amoled) sudah dihapus bersama `KmThemePack` enum.

```dart
// lib/core/theme/theme_provider.dart
enum AppThemePack {
  original;
  String get id => 'original';
  String get configPath => 'assets/theme/theme_config_original.json';
}
```

## Warna Tema Original

| Elemen | Warna |
|--------|-------|
| Background | `#000000` (AMOLED Black) |
| Aksen / Primary | `#E53935` (Red) |
| Text utama | `#FFFFFF` |
| Surface / Card | `#121212` |
| Secondary | `#1E1E1E` |

## Menambah Asset Baru

1. Taruh file PNG di subfolder yang sesuai (`backgrounds/`, `banners/`, dll)
2. Daftarkan di `assets/theme/theme_config_original.json`
3. Daftarkan path di `pubspec.yaml` jika belum tercakup wildcard

## Catatan

Tema berjalan **tanpa PNG assets** — warna diatur sepenuhnya dari `KmColors` system
di `lib/core/theme/km_colors.dart`. PNG di folder ini hanya untuk elemen dekoratif
(background screen, banner fitur, cover deck quiz/flashcard).
