import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'edge_tts_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TTS SERVICE — Layanan TTS terpusat dengan:
//   • Deteksi bahasa otomatis (Jepang vs Indonesia)
//   • Pembersihan tanda kurung () [] 【】「」 sebelum dibaca
//   • Koreksi partikel romaji → kana agar diucapkan benar
//   • speakSequence: urutan lengkap (kata JP → arti ID → contoh + spell per kata)
// ─────────────────────────────────────────────────────────────────────────────
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  bool _speaking = false;

  bool get isSpeaking => _speaking;

  // ── Init ───────────────────────────────────────────────────────────────────
  String _engine = 'google'; // 'edge' | 'google'

  Future<void> init() async {
    if (_ready) return;
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    _tts.setStartHandler(() => _speaking = true);
    _tts.setCompletionHandler(() => _speaking = false);
    _tts.setCancelHandler(() => _speaking = false);
    _ready = true;
    // Load engine preference
    _engine = await TtsEnginePrefs.getEngine();
  }

  /// Refresh engine setting (panggil setelah user ubah di Settings)
  Future<void> reloadEngine() async {
    _engine = await TtsEnginePrefs.getEngine();
  }

  bool get isEdgeTts => _engine == 'edge';

  Future<void> stop() async {
    await _tts.stop();
    await EdgeTtsService.instance.stop();
    _speaking = false;
  }

  /// Dipanggil saat app masuk background (AppLifecycleState.paused/inactive).
  /// Sama dengan stop() tapi semantiknya eksplisit untuk lifecycle handler.
  Future<void> stopOnPause() async {
    await _tts.stop();
    _speaking = false;
  }

  /// Expose completion handler agar screen bisa track state selesai bicara
  void setCompletionHandler(VoidCallback handler) {
    _tts.setCompletionHandler(() {
      _speaking = false;
      handler();
    });
  }

  void dispose() {
    _tts.stop();
    _speaking = false;
  }

  // ── DETEKSI BAHASA OTOMATIS ────────────────────────────────────────────────
  /// Deteksi apakah teks Jepang (mengandung hiragana/katakana/kanji)
  /// atau Indonesia (huruf latin). Fallback ke Indonesia.
  static bool isJapanese(String text) {
    // Cek apakah ada karakter Jepang: hiragana, katakana, kanji
    return RegExp(r'[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF]').hasMatch(text);
  }

  static String detectLang(String text) {
    return isJapanese(text) ? 'ja-JP' : 'id-ID';
  }

  // ── PEMBERSIH TEKS SEBELUM TTS ─────────────────────────────────────────────
  /// Hapus semua isi tanda kurung karena mengganggu pengucapan:
  ///   • (tes) → ''
  ///   • [tes] → ''
  ///   • 【tes】→ ''
  ///   • 「tes」→ ''
  ///   • （tes）→ ''  (fullwidth)
  /// Juga normalisasi "/" → " atau " untuk teks Indonesia
  static String cleanForTts(String text, {bool isId = false}) {
    String s = text
        // Hapus isi kurung biasa () dan fullwidth （）
        .replaceAll(RegExp(r'\（[^）]*）'), '')
        .replaceAll(RegExp(r'\([^)]*\)'), '')
        // Hapus isi kurung kotak [] dan 【】
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'【[^】]*】'), '')
        // Hapus isi 「」dan 『』
        .replaceAll(RegExp(r'「[^」]*」'), '')
        .replaceAll(RegExp(r'『[^』]*』'), '')
        // Hapus tanda kurung yang tersisa (kosong)
        .replaceAll(RegExp(r'[（）\(\)\[\]【】「」『』]'), '')
        // Bersihkan spasi berlebih
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();

    if (isId) {
      s = s.replaceAll('/', ' atau ').replaceAll('  ', ' ').trim();
    }
    return s;
  }

  // ── SPEAK DENGAN DETEKSI OTOMATIS ─────────────────────────────────────────
  /// Speak teks apapun — bahasa dideteksi otomatis dari isi teks.
  /// Tanda kurung dihapus sebelum dibaca.
  Future<void> speakAuto(String text, {double? rate}) async {
    final cleaned = cleanForTts(text, isId: !isJapanese(text));
    if (cleaned.isEmpty) return;
    final isJP = isJapanese(cleaned);
    if (_engine == 'edge') {
      final ok = await EdgeTtsService.instance.speak(cleaned, isJapanese: isJP);
      if (ok) return;
    }
    final lang = detectLang(cleaned);
    final spd = rate ?? (lang == 'ja-JP' ? 0.45 : 0.5);
    await _tts.stop();
    await _tts.setLanguage(lang);
    await _tts.setSpeechRate(spd);
    await _tts.speak(cleaned);
  }

  // ── SPEAK JEPANG ──────────────────────────────────────────────────────────
  Future<void> speakJP(String text, {double rate = 0.45, bool slow = false}) async {
    final cleaned = cleanForTts(text);
    if (cleaned.isEmpty) return;
    // Coba Edge TTS dulu jika aktif
    if (_engine == 'edge') {
      final ok = await EdgeTtsService.instance.speak(cleaned, isJapanese: true);
      if (ok) return;
      // Fallback ke Google TTS jika Edge gagal
    }
    await _tts.stop();
    await _tts.setLanguage('ja-JP');
    await _tts.setSpeechRate(slow ? 0.3 : rate);
    await _tts.speak(cleaned);
  }

  // ── SPEAK INDONESIA ───────────────────────────────────────────────────────
  Future<void> speakID(String text, {double rate = 0.5}) async {
    final cleaned = cleanForTts(text, isId: true);
    if (cleaned.isEmpty) return;
    if (_engine == 'edge') {
      final ok = await EdgeTtsService.instance.speak(cleaned, isJapanese: false);
      if (ok) return;
    }
    await _tts.stop();
    await _tts.setLanguage('id-ID');
    await _tts.setSpeechRate(rate);
    await _tts.speak(cleaned);
  }

  // ── SPEAK ITEM + TUNGGU + JEDA ─────────────────────────────────────────────
  /// Speak satu item lalu tunggu estimasi selesai + jeda
  Future<void> speakItem(String text, String lang, double rate, {int pauseMs = 850}) async {
    final isId = lang == 'id-ID';
    final cleaned = cleanForTts(text, isId: isId);
    if (cleaned.isEmpty) return;
    await _tts.stop();
    await _tts.setLanguage(lang);
    await _tts.setSpeechRate(rate);
    await _tts.speak(cleaned);
    final speakWait = 800 + (cleaned.length * 80).clamp(0, 4000);
    await Future.delayed(Duration(milliseconds: speakWait + pauseMs));
  }

  // ── KONVERSI ROMAJI → HIRAGANA ───────────────────────────────────────────
  /// Konversi kata romaji ke hiragana agar TTS Jepang membaca dengan benar.
  /// Menangani double consonant (tte→って), combo 3-char (chi,shi,tsu),
  /// combo 2-char (ka,te,de...), dan vokal tunggal.
  static String romajiToHiragana(String romaji) {
    const map3 = <String, String>{
      'chi': 'ち', 'tsu': 'つ', 'shi': 'し',
      'cha': 'ちゃ', 'chu': 'ちゅ', 'cho': 'ちょ',
      'sha': 'しゃ', 'shu': 'しゅ', 'sho': 'しょ',
      'tya': 'ちゃ', 'tyu': 'ちゅ', 'tyo': 'ちょ',
      'kya': 'きゃ', 'kyu': 'きゅ', 'kyo': 'きょ',
      'nya': 'にゃ', 'nyu': 'にゅ', 'nyo': 'にょ',
      'hya': 'ひゃ', 'hyu': 'ひゅ', 'hyo': 'ひょ',
      'mya': 'みゃ', 'myu': 'みゅ', 'myo': 'みょ',
      'rya': 'りゃ', 'ryu': 'りゅ', 'ryo': 'りょ',
      'gya': 'ぎゃ', 'gyu': 'ぎゅ', 'gyo': 'ぎょ',
      'bya': 'びゃ', 'byu': 'びゅ', 'byo': 'びょ',
      'pya': 'ぴゃ', 'pyu': 'ぴゅ', 'pyo': 'ぴょ',
      'dya': 'ぢゃ', 'dyu': 'ぢゅ', 'dyo': 'ぢょ',
      'zya': 'じゃ', 'zyu': 'じゅ', 'zyo': 'じょ',
      'jya': 'じゃ', 'jyu': 'じゅ', 'jyo': 'じょ',
    };
    const map2 = <String, String>{
      'ka': 'か', 'ki': 'き', 'ku': 'く', 'ke': 'け', 'ko': 'こ',
      'sa': 'さ', 'si': 'し', 'su': 'す', 'se': 'せ', 'so': 'そ',
      'ta': 'た', 'ti': 'ち', 'te': 'て', 'to': 'と', 'tu': 'つ',
      'na': 'な', 'ni': 'に', 'nu': 'ぬ', 'ne': 'ね', 'no': 'の',
      'ha': 'は', 'hi': 'ひ', 'fu': 'ふ', 'hu': 'ふ', 'he': 'へ', 'ho': 'ほ',
      'ma': 'ま', 'mi': 'み', 'mu': 'む', 'me': 'め', 'mo': 'も',
      'ya': 'や', 'yu': 'ゆ', 'yo': 'よ',
      'ra': 'ら', 'ri': 'り', 'ru': 'る', 're': 'れ', 'ro': 'ろ',
      'wa': 'わ', 'wi': 'ゐ', 'we': 'ゑ', 'wo': 'を',
      'ga': 'が', 'gi': 'ぎ', 'gu': 'ぐ', 'ge': 'げ', 'go': 'ご',
      'za': 'ざ', 'zi': 'じ', 'zu': 'ず', 'ze': 'ぜ', 'zo': 'ぞ',
      'ja': 'じゃ', 'ji': 'じ', 'ju': 'じゅ', 'jo': 'じょ',
      'da': 'だ', 'di': 'ぢ', 'du': 'づ', 'de': 'で', 'do': 'ど',
      'ba': 'ば', 'bi': 'び', 'bu': 'ぶ', 'be': 'べ', 'bo': 'ぼ',
      'pa': 'ぱ', 'pi': 'ぴ', 'pu': 'ぷ', 'pe': 'ぺ', 'po': 'ぽ',
    };
    const map1 = <String, String>{
      'a': 'あ', 'i': 'い', 'u': 'う', 'e': 'え', 'o': 'お', 'n': 'ん',
    };
    const vowels = {'a', 'i', 'u', 'e', 'o'};

    final buf = StringBuffer();
    final s = romaji.toLowerCase().trim();
    int i = 0;
    while (i < s.length) {
      final ch = s[i];
      // Tanda baca / spasi — lewati
      if (!RegExp(r'[a-z]').hasMatch(ch)) { buf.write(ch); i++; continue; }
      // Double consonant (kk, tt, ss, cc, dll.) → っ lalu proses lagi dari konsonan kedua
      if (i + 1 < s.length && ch == s[i + 1] && !vowels.contains(ch) && ch != 'n') {
        buf.write('っ');
        i++;
        continue;
      }
      // Coba 3-char
      bool matched = false;
      if (i + 3 <= s.length) {
        final tri = s.substring(i, i + 3);
        final hit = map3[tri];
        if (hit != null) { buf.write(hit); i += 3; matched = true; }
      }
      // Coba 2-char
      if (!matched && i + 2 <= s.length) {
        final bi = s.substring(i, i + 2);
        final hit = map2[bi];
        if (hit != null) { buf.write(hit); i += 2; matched = true; }
      }
      // Coba 1-char
      if (!matched) {
        final hit = map1[ch];
        buf.write(hit ?? ch); // fallback: tulis apa adanya
        i++;
      }
    }
    return buf.toString();
  }

  // ── PECAH ROMAJI → HIRAGANA PER KATA ─────────────────────────────────────
  /// Pecah teks romaji per kata lalu konversi tiap kata ke hiragana.
  /// Hasilnya diucapkan TTS ja-JP dengan benar (itte→って, au→あう, dll.)
  static List<String> splitRomaji(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[.。、！？!?\(\)\[\]]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.trim().isNotEmpty)
        .map((word) => romajiToHiragana(word))
        .toList();
  }

  /// Fallback: pecah kalimat Jepang berdasarkan spasi atau tanda baca
  static List<String> splitJPSentence(String text) {
    final clean = text
        .replaceAll('。', '')
        .replaceAll('！', '')
        .replaceAll('？', '')
        .replaceAll('、', ' ');
    if (clean.contains(' ')) {
      return clean.split(RegExp(r'\s+')).where((v) => v.trim().isNotEmpty).toList();
    }
    return clean.isNotEmpty ? [clean] : [];
  }

  // ── SPEAK SEQUENCE LENGKAP ─────────────────────────────────────────────────
  /// Urutan TTS lengkap (Flashcard Vocab & Kanji):
  ///  1. 🇯🇵 Kata/Kana (rate 0.85)
  ///  2. 🇮🇩 Arti (rate 1.0)
  ///  3. 🇯🇵 Kalimat contoh penuh (rate 0.8)
  ///  4. 🇯🇵 Spell per kata via romaji + koreksi partikel (rate 0.65)
  ///  5. 🇮🇩 Arti contoh kalimat (rate 1.0)
  ///
  /// [cancelCheck] → fungsi yang return true jika harus berhenti
  Future<void> speakSequence({
    required String jpWord,
    required String meaning,
    String example = '',
    String exampleRomaji = '',
    String exampleMeaning = '',
    bool Function()? cancelCheck,
  }) async {
    bool cancelled() => cancelCheck?.call() ?? false;

    // STEP 1 — Kata/Kana JP
    if (jpWord.isNotEmpty && !cancelled()) {
      await speakItem(jpWord, 'ja-JP', 0.85, pauseMs: 850);
      if (cancelled()) return;
    }

    // STEP 2 — Arti ID
    if (meaning.isNotEmpty && !cancelled()) {
      final artiClean = cleanForTts(meaning, isId: true);
      await speakItem(artiClean, 'id-ID', 1.0, pauseMs: 850);
      if (cancelled()) return;
    }

    if (example.isNotEmpty) {
      // STEP 3 — Kalimat contoh penuh JP
      if (!cancelled()) {
        await speakItem(example, 'ja-JP', 0.8, pauseMs: 850);
        if (cancelled()) return;
      }

      // STEP 4 — Spell per kata + koreksi partikel
      final words = exampleRomaji.isNotEmpty
          ? splitRomaji(exampleRomaji)
          : splitJPSentence(example);
      for (final word in words) {
        if (cancelled()) return;
        await speakItem(word, 'ja-JP', 0.65, pauseMs: 850);
      }
      if (cancelled()) return;

      // STEP 5 — Arti contoh ID
      if (exampleMeaning.isNotEmpty && !cancelled()) {
        final artiKalimat = cleanForTts(exampleMeaning, isId: true);
        await speakItem(artiKalimat, 'id-ID', 1.0, pauseMs: 850);
      }
    }
  }
}
