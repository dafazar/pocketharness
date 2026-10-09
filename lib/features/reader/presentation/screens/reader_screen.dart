// lib/features/reader/presentation/screens/reader_screen.dart
// Pocket Harness — Reader Screen
//
// ✅ Furigana REAL — lookup via Jisho API (jisho.org/api/v1/search/words)
//    dengan in-memory cache agar tidak hit API berulang untuk kanji yang sama.
// ✅ Tombol "Tanya AI" — navigasi ke AI Tutor dengan query otomatis.
// ✅ Sample teks Jepang + Teks bebas (paste teks apapun)
// =============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/km_colors.dart';
import '../../../../data/services/sfx_service.dart';
import '../../../../shared/widgets/back_handler.dart';

// ── Furigana Service (Jisho API) ──────────────────────────────────────────────
//
// Jisho API: GET https://jisho.org/api/v1/search/words?keyword=<kanji>
// Response: data[0].japanese[0].reading  → hiragana reading
// Rate limit: ~30 req/menit, aman karena kita cache per-kanji.

class _FuriganaService {
  _FuriganaService._();
  static final _FuriganaService instance = _FuriganaService._();

  final Map<String, String> _cache   = {};
  final Map<String, Future<String>> _pending = {};

  Future<String> lookup(String word) async {
    if (_cache.containsKey(word)) return _cache[word]!;
    if (_pending.containsKey(word)) return _pending[word]!;

    final future = _fetchReading(word);
    _pending[word] = future;
    final result = await future;
    _cache[word] = result;
    _pending.remove(word);
    return result;
  }

  Future<String> _fetchReading(String word) async {
    try {
      final uri = Uri.parse(
        'https://jisho.org/api/v1/search/words?keyword=${Uri.encodeComponent(word)}',
      );
      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) return '';

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final data = body['data'] as List?;
      if (data == null || data.isEmpty) return '';

      for (final entry in data) {
        final jpList = entry['japanese'] as List?;
        if (jpList == null) continue;
        for (final jp in jpList) {
          final w = jp['word']    as String? ?? '';
          final r = jp['reading'] as String? ?? '';
          if ((w == word || w.isEmpty) && r.isNotEmpty && r != word) {
            return r;
          }
        }
      }
    } catch (e) {
      debugPrint('[Furigana] "$word": $e');
    }
    return '';
  }
}

// ── Sample texts ──────────────────────────────────────────────────────────────

const _sampleTexts = {
  '🇯🇵 Teknologi AI': '''
人工知能（AI）は現代社会において重要な技術となっています。
機械学習や深層学習の進歩により、コンピュータは人間のように考え、学び、問題を解決できるようになりました。
スマートフォンや自動車、医療など様々な分野でAIが活用されています。
''',
  '🇯🇵 Kehidupan Harian': '''
毎朝、私は六時に起きます。
朝ごはんを食べてから、電車で会社に行きます。
仕事が終わったら、友達と一緒に夕食を食べます。
週末は家族と公園で散歩します。
''',
  '🇯🇵 Alam & Musim': '''
日本の春は美しい季節です。
桜の花が咲くと、多くの人が花見を楽しみます。
夏は暑くて湿度が高いですが、夏祭りや花火大会があります。
秋には紅葉が美しく、冬には雪が降ります。
''',
  '📝 Teks Bebas': '',
};

// ── Screen ────────────────────────────────────────────────────────────────────

class ReaderScreen extends ConsumerStatefulWidget {
  final String? initialText;
  const ReaderScreen({super.key, this.initialText});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  String _currentText    = '';
  String _selectedSample = '';
  double _fontSize       = 18.0;
  bool   _showFurigana   = true;
  final _tts             = FlutterTts();
  final _inputCtrl       = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('ja-JP');
    _tts.setSpeechRate(0.5);

    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _currentText    = widget.initialText!;
      _selectedSample = '📝 Teks Bebas';
      _inputCtrl.text = _currentText;
    } else {
      final first     = _sampleTexts.entries.first;
      _selectedSample = first.key;
      _currentText    = first.value;
      _inputCtrl.text = first.value;
    }
  }

  @override
  void dispose() {
    _tts.stop();
    _inputCtrl.dispose();
    super.dispose();
  }

  void _selectSample(String key, String value) {
    if (mounted) setState(() {
      _selectedSample = key;
      if (key == '📝 Teks Bebas') {
        _currentText = _inputCtrl.text;
      } else {
        _currentText    = value;
        _inputCtrl.text = value;
      }
    });
  }

  void _onWordTap(String word) {
    SfxService.instance.play(Sfx.tap);
    _tts.speak(word);
    _showWordPopup(word);
  }

  void _showWordPopup(String word) {
    final c = KmColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _WordPopup(
        word: word,
        tts: _tts,
        c: c,
        onAskAi: () {
          Navigator.pop(ctx);
          context.push(KmRoutes.chat);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);

    return ConfirmExitBack(
      message: 'Keluar dari reader?',
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          backgroundColor: c.bg,
          foregroundColor: c.text,
          title: const Text('読む Reader'),
          actions: [
            IconButton(
              icon: const Icon(Icons.text_decrease_rounded),
              tooltip: 'Perkecil teks',
              onPressed: () {
                if (mounted) setState(() => _fontSize = (_fontSize - 2).clamp(12, 32));
              },
            ),
            IconButton(
              icon: const Icon(Icons.text_increase_rounded),
              tooltip: 'Perbesar teks',
              onPressed: () {
                if (mounted) setState(() => _fontSize = (_fontSize + 2).clamp(12, 32));
              },
            ),
            IconButton(
              icon: Icon(
                Icons.translate_rounded,
                color: _showFurigana ? c.accent : c.textMuted,
              ),
              tooltip: _showFurigana
                  ? 'Sembunyikan furigana'
                  : 'Tampilkan furigana',
              onPressed: () {
                if (mounted) setState(() => _showFurigana = !_showFurigana);
              },
            ),
            IconButton(
              icon: Icon(Icons.volume_up_rounded, color: c.accent),
              tooltip: 'Baca semua',
              onPressed: () => _tts.speak(_currentText),
            ),
          ],
        ),
        body: Column(
          children: [
            // ── Sample picker ────────────────────────────────────────────
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: _sampleTexts.keys.map((key) {
                  final isActive = _selectedSample == key;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () =>
                          _selectSample(key, _sampleTexts[key]!),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isActive ? c.accentSoft : c.inputFill,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isActive ? c.accent : c.border,
                          ),
                        ),
                        child: Text(
                          key,
                          style: TextStyle(
                            color: isActive ? c.accent : c.textSub,
                            fontSize: 11,
                            fontWeight: isActive
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 6),

            // ── Reader area ──────────────────────────────────────────────
            Expanded(
              flex: 2,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: _currentText.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Text(
                            'Tempel teks Jepang di bawah\nlalu tap tombol "Baca"',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: c.textMuted,
                                fontSize: 14,
                                height: 1.6),
                          ),
                        ),
                      )
                    : _JapaneseReaderWidget(
                        text: _currentText,
                        fontSize: _fontSize,
                        showFurigana: _showFurigana,
                        onWordTap: _onWordTap,
                      ),
              ),
            ),

            // ── Input area ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.elevated,
                border: Border(top: BorderSide(color: c.border)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      maxLines: 3,
                      minLines: 1,
                      style: TextStyle(color: c.text, fontSize: 13),
                      onChanged: (_) {
                        if (_selectedSample != '📝 Teks Bebas') {
                          if (mounted) setState(
                              () => _selectedSample = '📝 Teks Bebas');
                        }
                      },
                      decoration: InputDecoration(
                        hintText:
                            'Tempel atau ketik teks Jepang di sini…',
                        hintStyle: TextStyle(
                            color: c.textMuted, fontSize: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: c.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: c.border),
                        ),
                        contentPadding: const EdgeInsets.all(10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      if (mounted) setState(() {
                        _currentText    = _inputCtrl.text;
                        _selectedSample = '📝 Teks Bebas';
                      });
                      SfxService.instance.play(Sfx.tap);
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                    child: const Text('Baca'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Word Popup ────────────────────────────────────────────────────────────────

class _WordPopup extends StatefulWidget {
  final String word;
  final FlutterTts tts;
  final KmColors c;
  final VoidCallback onAskAi;

  const _WordPopup({
    required this.word,
    required this.tts,
    required this.c,
    required this.onAskAi,
  });

  @override
  State<_WordPopup> createState() => _WordPopupState();
}

class _WordPopupState extends State<_WordPopup> {
  String? _reading;
  bool    _loading = true;

  @override
  void initState() {
    super.initState();
    _FuriganaService.instance.lookup(widget.word).then((r) {
      if (mounted) setState(() { _reading = r; _loading = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Kata + TTS
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.word,
                      style: TextStyle(
                        color: c.accent,
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (_loading)
                      Row(children: [
                        SizedBox(
                          width: 12, height: 12,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: c.accent),
                        ),
                        const SizedBox(width: 6),
                        Text('Mencari bacaan…',
                            style: TextStyle(
                                color: c.textMuted, fontSize: 12)),
                      ])
                    else if (_reading != null && _reading!.isNotEmpty)
                      Row(children: [
                        Icon(Icons.record_voice_over_rounded,
                            size: 14, color: c.textSub),
                        const SizedBox(width: 4),
                        Text(
                          _reading!,
                          style: TextStyle(
                            color: c.textSub,
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ])
                    else
                      Text(
                        'Bacaan tidak ditemukan',
                        style:
                            TextStyle(color: c.textMuted, fontSize: 12),
                      ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => widget.tts.speak(widget.word),
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child:
                      Icon(Icons.volume_up_rounded, color: c.accent),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          Divider(color: c.border),
          const SizedBox(height: 10),

          // Tombol Tanya AI
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.onAskAi,
              icon: const Icon(Icons.smart_toy_rounded, size: 18),
              label: const Text('Tanya AI — Arti & Contoh Kalimat'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(vertical: 12),
                textStyle: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),

          const SizedBox(height: 8),
          Text(
            'Tap kata Jepang di teks untuk melihat bacaan dan tanya AI.',
            style: TextStyle(color: c.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ── Japanese Reader Widget ────────────────────────────────────────────────────

class _JapaneseReaderWidget extends StatefulWidget {
  final String text;
  final double fontSize;
  final bool showFurigana;
  final ValueChanged<String> onWordTap;

  const _JapaneseReaderWidget({
    required this.text,
    required this.fontSize,
    required this.showFurigana,
    required this.onWordTap,
  });

  @override
  State<_JapaneseReaderWidget> createState() =>
      _JapaneseReaderWidgetState();
}

class _JapaneseReaderWidgetState
    extends State<_JapaneseReaderWidget> {
  final Map<String, String> _cache = {};

  @override
  void initState() {
    super.initState();
    _prefetch();
  }

  @override
  void didUpdateWidget(_JapaneseReaderWidget old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _cache.clear();
      _prefetch();
    }
  }

  void _prefetch() {
    for (final seg in _segment(widget.text)) {
      if (seg == '\n') continue;
      final code    = seg.isNotEmpty ? seg.codeUnitAt(0) : 0;
      final isKanji = code >= 0x4E00 && code <= 0x9FFF;
      if (!isKanji || _cache.containsKey(seg)) continue;
      _FuriganaService.instance.lookup(seg).then((r) {
        if (!mounted || _cache[seg] == r) return;
        if (mounted) setState(() => _cache[seg] = r);
      });
    }
  }

  List<String> _segment(String text) {
    final segs   = <String>[];
    final buf    = StringBuffer();
    bool inKanji = false;

    for (int i = 0; i < text.length; i++) {
      final ch      = text[i];
      final code    = ch.codeUnitAt(0);
      final isKanji = code >= 0x4E00 && code <= 0x9FFF;

      if (ch == '\n') {
        if (buf.isNotEmpty) { segs.add(buf.toString()); buf.clear(); }
        segs.add('\n');
        inKanji = false;
        continue;
      }

      if (isKanji != inKanji && buf.isNotEmpty) {
        segs.add(buf.toString());
        buf.clear();
      }
      buf.write(ch);
      inKanji = isKanji;
    }
    if (buf.isNotEmpty) segs.add(buf.toString());
    return segs;
  }

  @override
  Widget build(BuildContext context) {
    final c    = KmColors.of(context);
    final segs = _segment(widget.text);

    return Wrap(
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: segs.map((seg) {
        if (seg == '\n') {
          return const SizedBox(width: double.infinity, height: 10);
        }

        final code       = seg.isNotEmpty ? seg.codeUnitAt(0) : 0;
        final isKanji    = code >= 0x4E00 && code <= 0x9FFF;
        final isKana     = code >= 0x3040 && code <= 0x30FF;
        final isJapanese = isKanji || isKana;

        if (!isJapanese) {
          return Text(
            seg,
            style: TextStyle(
                color: c.text,
                fontSize: widget.fontSize,
                height: 2.4),
          );
        }

        final reading    = _cache[seg] ?? '';
        final hasReading = reading.isNotEmpty;
        final isLoading  = isKanji && !_cache.containsKey(seg);

        return GestureDetector(
          onTap: () => widget.onWordTap(seg),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Slot furigana (tinggi tetap agar teks utama sejajar)
                if (widget.showFurigana && isKanji)
                  SizedBox(
                    height: widget.fontSize * 0.55,
                    child: isLoading
                        ? Center(
                            child: SizedBox(
                              width: 8, height: 8,
                              child: CircularProgressIndicator(
                                strokeWidth: 1,
                                color:
                                    c.accent.withValues(alpha: 0.4),
                              ),
                            ),
                          )
                        : hasReading
                            ? Text(
                                reading,
                                style: TextStyle(
                                  color: c.accent,
                                  fontSize: widget.fontSize * 0.42,
                                  height: 1.1,
                                  fontWeight: FontWeight.w500,
                                ),
                              )
                            : null,
                  ),

                // Kata utama
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isKanji
                            ? c.accent.withValues(alpha: 0.4)
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                  ),
                  child: Text(
                    seg,
                    style: TextStyle(
                      color: isKanji ? c.accent : c.text,
                      fontSize: widget.fontSize,
                      fontWeight: isKanji
                          ? FontWeight.w700
                          : FontWeight.w400,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
