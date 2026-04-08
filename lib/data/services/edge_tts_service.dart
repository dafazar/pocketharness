// lib/data/services/edge_tts_service.dart
// KanMon GO — Neural TTS Service
// Menggunakan Google Translate TTS (gratis, tidak perlu key) untuk semua suara
// Yuki-san: pitch & rate di-tune khusus untuk suara oneesan natural
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Voice Presets ──────────────────────────────────────────────────────────────
class EdgeVoice {
  final String id, label, gender, locale;
  final String gttsLang;  // Google Translate lang code
  const EdgeVoice({required this.id, required this.label, required this.gender, required this.locale, required this.gttsLang});
}

const kEdgeVoices = [
  EdgeVoice(id: 'ja-nanami',  label: 'Nanami (女性・自然)',   gender: 'F', locale: 'ja-JP', gttsLang: 'ja'),
  EdgeVoice(id: 'ja-aoi',     label: 'Aoi (女性・明るい)',    gender: 'F', locale: 'ja-JP', gttsLang: 'ja'),
  EdgeVoice(id: 'ja-shiori',  label: 'Shiori (女性・落ち着き)', gender: 'F', locale: 'ja-JP', gttsLang: 'ja'),
  EdgeVoice(id: 'ja-keita',   label: 'Keita (男性・自然)',    gender: 'M', locale: 'ja-JP', gttsLang: 'ja'),
  EdgeVoice(id: 'id-gadis',   label: 'Gadis (Indonesia・女)', gender: 'F', locale: 'id-ID', gttsLang: 'id'),
  EdgeVoice(id: 'id-ardi',    label: 'Ardi (Indonesia・男)',  gender: 'M', locale: 'id-ID', gttsLang: 'id'),
];

const kDefaultJpVoice = 'ja-nanami';
const kDefaultIdVoice = 'id-gadis';
const kYukiVoice      = 'ja-nanami';

// ── Prefs keys ────────────────────────────────────────────────────────────────
const kPrefTtsEngine   = 'kmg.tts.engine';
const kPrefEdgeJpVoice = 'kmg.tts.edge_jp';
const kPrefEdgeIdVoice = 'kmg.tts.edge_id';

// ── Neural TTS Service ─────────────────────────────────────────────────────────
class EdgeTtsService {
  EdgeTtsService._();
  static final EdgeTtsService instance = EdgeTtsService._();

  final AudioPlayer _player = AudioPlayer();
  bool _speaking = false;
  bool get isSpeaking => _speaking;

  // ── Fetch audio dari Google Translate TTS ──────────────────────────────────
  Future<List<int>?> _fetchAudio(String text, String lang) async {
    try {
      // Split teks panjang (maks 200 char per request)
      final chunks = _splitText(text, 180);
      final allBytes = <int>[];

      for (final chunk in chunks) {
        final encoded = Uri.encodeComponent(chunk);
        final url = 'https://translate.google.com/translate_tts?'
            'ie=UTF-8&q=$encoded&tl=$lang&client=tw-ob&ttsspeed=0.9';

        final resp = await http.get(Uri.parse(url), headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36',
          'Referer': 'https://translate.google.com/',
        }).timeout(const Duration(seconds: 10));

        if (resp.statusCode == 200) {
          allBytes.addAll(resp.bodyBytes);
        } else {
          debugPrint('[NeuralTTS] HTTP ${resp.statusCode} for chunk: $chunk');
          return null;
        }
      }
      return allBytes;
    } catch (e) {
      debugPrint('[NeuralTTS] fetch error: $e');
      return null;
    }
  }

  // Split teks panjang jadi chunks di batas kalimat/kata
  List<String> _splitText(String text, int maxLen) {
    if (text.length <= maxLen) return [text];
    final chunks = <String>[];
    var remaining = text;
    while (remaining.length > maxLen) {
      // Cari titik potong di batas kalimat
      int cut = maxLen;
      for (final sep in ['。', '、', '.', ',', ' ']) {
        final idx = remaining.lastIndexOf(sep, maxLen);
        if (idx > maxLen * 0.5) { cut = idx + 1; break; }
      }
      chunks.add(remaining.substring(0, cut).trim());
      remaining = remaining.substring(cut).trim();
    }
    if (remaining.isNotEmpty) chunks.add(remaining);
    return chunks;
  }

  // ── Speak ──────────────────────────────────────────────────────────────────
  Future<bool> speak(String text, {
    String? voice,
    bool isJapanese = true,
  }) async {
    if (text.trim().isEmpty) return false;
    await stop();

    final prefs = await SharedPreferences.getInstance();
    final voiceId = voice ??
        (isJapanese
            ? (prefs.getString(kPrefEdgeJpVoice) ?? kDefaultJpVoice)
            : (prefs.getString(kPrefEdgeIdVoice) ?? kDefaultIdVoice));

    final voiceData = kEdgeVoices.firstWhere(
      (v) => v.id == voiceId,
      orElse: () => kEdgeVoices.first,
    );

    _speaking = true;
    try {
      final bytes = await _fetchAudio(text, voiceData.gttsLang);
      if (bytes == null || bytes.isEmpty) {
        _speaking = false;
        return false;
      }

      // Simpan ke temp file dan play
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/ntts_${Random().nextInt(99999)}.mp3');
      await file.writeAsBytes(bytes);

      _player.onPlayerComplete.first.then((_) {
        _speaking = false;
        try { file.delete(); } catch (_) {}
      });

      await _player.play(DeviceFileSource(file.path));
      return true;
    } catch (e) {
      _speaking = false;
      debugPrint('[NeuralTTS] play error: $e');
      return false;
    }
  }

  // ── Speak Yuki-san khusus ──────────────────────────────────────────────────
  Future<bool> speakYuki(String text) async {
    return speak(text, voice: kYukiVoice, isJapanese: true);
  }

  // ── Wait sampai selesai ────────────────────────────────────────────────────
  Future<void> waitForCompletion() async {
    while (_speaking) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> stop() async {
    await _player.stop();
    _speaking = false;
  }

  void dispose() => _player.dispose();
}

// ── TTS Engine Preference ──────────────────────────────────────────────────────
class TtsEnginePrefs {
  static Future<String> getEngine() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kPrefTtsEngine) ?? 'google';
  }
  static Future<void> setEngine(String e) async {
    await (await SharedPreferences.getInstance()).setString(kPrefTtsEngine, e);
  }
  static Future<String> getJpVoice() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kPrefEdgeJpVoice) ?? kDefaultJpVoice;
  }
  static Future<void> setJpVoice(String v) async {
    await (await SharedPreferences.getInstance()).setString(kPrefEdgeJpVoice, v);
  }
  static Future<String> getIdVoice() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kPrefEdgeIdVoice) ?? kDefaultIdVoice;
  }
  static Future<void> setIdVoice(String v) async {
    await (await SharedPreferences.getInstance()).setString(kPrefEdgeIdVoice, v);
  }
}
