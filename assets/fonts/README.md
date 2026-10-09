# Font Files — Pocket Harness

Direktori ini memerlukan file font berikut (tidak di-commit ke repo karena ukuran besar).

## Font yang Digunakan

### NotoSerifJP
Download dari: https://fonts.google.com/noto/specimen/Noto+Serif+JP

File yang dibutuhkan:
- `NotoSerifJP-Regular.ttf` (weight 400)
- `NotoSerifJP-Bold.ttf` (weight 700)
- `NotoSerifJP-Black.ttf` (weight 900)

**Digunakan untuk:** Tampilan kanji, kana, dan teks Jepang di seluruh app.

### SpaceMono
Download dari: https://fonts.google.com/specimen/Space+Mono

File yang dibutuhkan:
- `SpaceMono-Regular.ttf` (weight 400)
- `SpaceMono-Bold.ttf` (weight 700)

**Digunakan untuk:** Terminal screen, kode, output AI.

## Cara Install

```bash
# Download dari Google Fonts lalu extract
# Salin file .ttf ke direktori ini:
cp ~/Downloads/NotoSerifJP/*.ttf assets/fonts/
cp ~/Downloads/SpaceMono/*.ttf assets/fonts/

# Font sudah terdaftar di pubspec.yaml — tidak perlu edit apapun
flutter pub get
```

## Deklarasi di pubspec.yaml

```yaml
fonts:
  - family: NotoSerifJP
    fonts:
      - asset: assets/fonts/NotoSerifJP-Regular.ttf
        weight: 400
      - asset: assets/fonts/NotoSerifJP-Bold.ttf
        weight: 700
      - asset: assets/fonts/NotoSerifJP-Black.ttf
        weight: 900
  - family: SpaceMono
    fonts:
      - asset: assets/fonts/SpaceMono-Regular.ttf
        weight: 400
      - asset: assets/fonts/SpaceMono-Bold.ttf
        weight: 700
```

## Catatan

Tanpa font NotoSerifJP, Flutter akan fallback ke system font.
Tampilan kanji dan kana mungkin kurang optimal di beberapa device.
Font SpaceMono dibutuhkan untuk tampilan terminal yang proper.
