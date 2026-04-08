// lib/features/ocr/presentation/screens/ocr_screen.dart
// KanMon GO — OCR + AI Gemini Analysis
// Scan foto → ML Kit deteksi teks → Gemini jelaskan arti, cara baca, contoh
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:kanmongo/data/services/ai_service.dart';

import '../../../../core/theme/km_colors.dart';
import '../../../../data/services/sfx_service.dart';
import '../../../../shared/widgets/back_handler.dart';

// ── Gemini key ────────────────────────────────────────────────────────────────

// ── Token (satu kata/karakter dalam teks) ───────────────────────────────────
class _WordToken {
  final String text;
  final bool isJapanese;
  const _WordToken({required this.text, required this.isJapanese});
}

// ── AI Result ─────────────────────────────────────────────────────────────────
class _AiResult {
  final String reading;    // cara baca atau transliterasi
  final String meaning;    // arti dalam Bahasa Indonesia
  final String example;    // contoh kalimat
  final String grammar;    // catatan grammar (opsional)
  const _AiResult({required this.reading, required this.meaning, required this.example, this.grammar = ''});
}

// ── Screen ────────────────────────────────────────────────────────────────────
class OcrScreen extends ConsumerStatefulWidget {
  const OcrScreen({super.key});
  @override
  ConsumerState<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends ConsumerState<OcrScreen> with TickerProviderStateMixin {
  File? _imageFile;
  String _recognizedText = '';
  bool _isProcessing = false;
  bool _isAnalyzing = false;
  String _analyzeStatus = '';
  _AiResult? _aiResult;
  _WordToken? _selectedToken;

  final _picker = ImagePicker();
  final _tts    = FlutterTts();
  List<_WordToken> _tokens = [];

  late AnimationController _resultCtrl;
  late Animation<double> _resultAnim;

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('ja-JP');
    _tts.setSpeechRate(0.5);
    _resultCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _resultAnim = CurvedAnimation(parent: _resultCtrl, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _tts.stop();
    _resultCtrl.dispose();
    super.dispose();
  }

  // ── Pick & OCR ──────────────────────────────────────────────────────────────
  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 90);
    if (picked == null) return;

    setState(() {
      _imageFile = File(picked.path);
      _recognizedText = '';
      _tokens = [];
      _aiResult = null;
      _selectedToken = null;
      _isProcessing = true;
    });

    await _runOcr(File(picked.path));
  }

  Future<void> _runOcr(File file) async {
    try {
      final inputImage = InputImage.fromFile(file);
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final result     = await recognizer.processImage(inputImage);
      recognizer.close();

      final text = result.text.trim();
      setState(() {
        _recognizedText = text;
        _tokens         = _tokenize(text);
        _isProcessing   = false;
      });
      SfxService.instance.play(Sfx.notification);

      // Auto-analyze jika ada teks terdeteksi
      if (_tokens.isNotEmpty) {
        await _analyzeWithGemini(text);
      }
    } catch (e) {
      setState(() {
        _recognizedText = 'Gagal mengenali teks. Coba foto yang lebih jelas.';
        _isProcessing   = false;
      });
    }
  }

  // ── Gemini AI Analysis ───────────────────────────────────────────────────────
  Future<void> _analyzeWithGemini(String scannedText) async {
    setState(() { _isAnalyzing = true; _analyzeStatus = 'AI sedang menganalisis...'; });

    try {
      final prompt = '''Analisis teks berikut secara ringkas dan jelas dalam Bahasa Indonesia:

Teks: "$scannedText"

Berikan respons dalam format JSON SAJA (tanpa markdown, tanpa backtick):
{
  "reading": "teks asli atau transliterasi jika bukan Latin",
  "meaning": "arti atau penjelasan lengkap dalam Bahasa Indonesia",
  "example": "contoh penggunaan atau konteks teks ini",
  "grammar": "catatan penting jika relevan, atau kosong"
}''';

      // Firebase AI (Gemini) — generateJson untuk respons terstruktur
      final parsed = await AiService.instance.generateJson(prompt: prompt);

      if (parsed != null) {
        setState(() {
          _aiResult = _AiResult(
            reading: parsed['reading'] as String? ?? '',
            meaning: parsed['meaning'] as String? ?? '',
            example: parsed['example'] as String? ?? '',
            grammar: parsed['grammar'] as String? ?? '',
          );
          _isAnalyzing = false;
        });
        _resultCtrl.forward(from: 0);
        SfxService.instance.play(Sfx.correct);
      } else {
        // Fallback: generate teks biasa
        final rawReply = await AiService.instance.generate(prompt: prompt);
        setState(() {
          _aiResult = _AiResult(reading: '', meaning: rawReply, example: '');
          _isAnalyzing = false;
        });
        _resultCtrl.forward(from: 0);
      }
    } catch (e) {
      setState(() { _isAnalyzing = false; _analyzeStatus = 'Koneksi gagal. Coba lagi.'; });
    }
  }

  // ── Analisis token yang di-tap ────────────────────────────────────────────────
  Future<void> _analyzeToken(_WordToken token) async {
    setState(() { _selectedToken = token; _isAnalyzing = true; _aiResult = null; });
    await _tts.speak(token.text);
    await _analyzeWithGemini(token.text);
  }

  // ── Tokenizer ─────────────────────────────────────────────────────────────────
  List<_WordToken> _tokenize(String text) {
    final tokens = <_WordToken>[];
    if (text.trim().isEmpty) return tokens;

    final jpRegex = RegExp(
      r'[　-〿぀-ゟ゠-ヿ一-鿿豈-﫿＀-￯]+',
    );
    final latinRegex = RegExp(r'[a-zA-Z0-9 .,!?()|\[\]\-:;/@#]+');

    for (int lineIdx = 0; lineIdx < text.split('\n').length; lineIdx++) {
      final line = text.split('\n')[lineIdx].trim();
      if (line.isEmpty) continue;

      int pos = 0;
      while (pos < line.length) {
        final jpMatch = jpRegex.matchAsPrefix(line, pos);
        if (jpMatch != null) {
          for (final ch in jpMatch.group(0)!.split('')) {
            if (ch.trim().isNotEmpty) tokens.add(_WordToken(text: ch, isJapanese: true));
          }
          pos = jpMatch.end;
          continue;
        }
        final latMatch = latinRegex.matchAsPrefix(line, pos);
        if (latMatch != null) {
          final word = latMatch.group(0)!.trim();
          if (word.isNotEmpty) tokens.add(_WordToken(text: word, isJapanese: false));
          pos = latMatch.end;
          continue;
        }
        final ch = line[pos];
        if (ch.trim().isNotEmpty) tokens.add(_WordToken(text: ch, isJapanese: false));
        pos++;
      }

      if (lineIdx < text.split('\n').length - 1) {
        tokens.add(const _WordToken(text: '\n', isJapanese: false));
      }
    }
    return tokens;
  }

  // ── UI ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);

    return ConfirmExitBack(
      message: 'Kembali?',
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          backgroundColor: c.bg,
          foregroundColor: c.text,
          elevation: 0,
          title: Row(children: [
            Text('SCAN', style: TextStyle(color: c.accent, fontWeight: FontWeight.w900, fontSize: 14)),
            const SizedBox(width: 6),
            Text('OCR + AI', style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
          ]),
          actions: [
            if (_recognizedText.isNotEmpty) ...[
              IconButton(
                icon: Icon(Icons.volume_up_rounded, color: c.accent),
                onPressed: () => _tts.speak(_recognizedText),
                tooltip: 'Putar semua',
              ),
              if (_aiResult == null && !_isAnalyzing)
                IconButton(
                  icon: Icon(Icons.auto_awesome_rounded, color: c.gold),
                  onPressed: () => _analyzeWithGemini(_recognizedText),
                  tooltip: 'Analisis AI',
                ),
            ],
          ],
        ),
        body: Column(
          children: [
            // ── Preview gambar ──────────────────────────────────────────────
            _buildImagePreview(c),
            const SizedBox(height: 12),

            // ── Tombol Kamera & Galeri ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_rounded, size: 18),
                  label: const Text('Kamera'),
                  style: ElevatedButton.styleFrom(backgroundColor: c.accent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                )),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(
                  onPressed: _isProcessing ? null : () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_rounded, size: 18),
                  label: const Text('Galeri'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                )),
              ]),
            ),

            const SizedBox(height: 12),

            // ── Hasil OCR + AI ──────────────────────────────────────────────
            if (_isProcessing)
              Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(color: c.accent),
                const SizedBox(height: 12),
                Text('Mengenali teks...', style: TextStyle(color: c.textSub)),
              ])))
            else if (_recognizedText.isNotEmpty)
              Expanded(child: _buildResults(c))
            else
              Expanded(child: _buildEmpty(c)),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview(KmColors c) => Container(
    height: 180,
    margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
    decoration: BoxDecoration(
      color: c.card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: c.border),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: _imageFile != null
          ? Image.file(_imageFile!, fit: BoxFit.cover, width: double.infinity)
          : Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.document_scanner_rounded, color: c.textMuted, size: 40),
              const SizedBox(height: 8),
              Text('Foto atau gambar teks', style: TextStyle(color: c.textMuted, fontSize: 12)),
            ])),
    ),
  );

  Widget _buildResults(KmColors c) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // ── Label ──────────────────────────────────────────────────────────────
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Text('Teks Terdeteksi', style: TextStyle(color: c.accent, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 8),
        Text('${_tokens.length} kata · ketuk untuk analisis',
          style: TextStyle(color: c.textMuted, fontSize: 11)),
      ]),

      const SizedBox(height: 10),

      // ── Token cards ─────────────────────────────────────────────────────────
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border),
        ),
        child: Wrap(
          spacing: 4, runSpacing: 6,
          children: _tokens.map((token) {
            if (token.text == '\n') return const SizedBox(width: double.infinity, height: 2);
            final isSelected = _selectedToken?.text == token.text;
            return GestureDetector(
              onTap: token.isJapanese ? () => _analyzeToken(token) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: EdgeInsets.symmetric(
                  horizontal: token.isJapanese ? 10 : 6,
                  vertical: token.isJapanese ? 8 : 5,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? c.accent.withValues(alpha: 0.2)
                      : token.isJapanese ? c.accent.withValues(alpha: 0.08) : c.inputFill,
                  borderRadius: BorderRadius.circular(token.isJapanese ? 10 : 6),
                  border: Border.all(
                    color: isSelected ? c.accent : token.isJapanese ? c.accent.withValues(alpha: 0.35) : c.border,
                    width: isSelected ? 2 : 1.5,
                  ),
                  boxShadow: token.isJapanese ? [
                    BoxShadow(color: c.accent.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 2)),
                  ] : null,
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(token.text, style: TextStyle(
                    
                    color: isSelected ? c.accent : token.isJapanese ? c.accent : c.textSub,
                    fontSize: token.isJapanese ? 22 : 13,
                    fontWeight: token.isJapanese ? FontWeight.w900 : FontWeight.w400,
                    height: 1.2,
                  )),
                  if (token.isJapanese) ...[
                    const SizedBox(height: 2),
                    Icon(Icons.auto_awesome_rounded, size: 8, color: c.accent.withValues(alpha: 0.5)),
                  ],
                ]),
              ),
            );
          }).toList(),
        ),
      ),

      const SizedBox(height: 16),

      // ── AI Analysis Panel ────────────────────────────────────────────────────
      if (_isAnalyzing)
        _buildAnalyzingCard(c)
      else if (_aiResult != null)
        FadeTransition(opacity: _resultAnim, child: _buildAiCard(c, _aiResult!))
      else if (_analyzeStatus.isNotEmpty)
        _buildErrorCard(c),
    ]),
  );

  Widget _buildAnalyzingCard(KmColors c) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [c.accent.withValues(alpha: 0.08), c.gold.withValues(alpha: 0.05)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: c.accent.withValues(alpha: 0.2)),
    ),
    child: Row(children: [
      SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: c.accent)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('AI Analisis', style: TextStyle(color: c.accent, fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 2),
        Text(_selectedToken != null
          ? 'Menganalisis "${_selectedToken!.text}"...'
          : 'Menganalisis teks...', style: TextStyle(color: c.textSub, fontSize: 12)),
      ])),
    ]),
  );

  Widget _buildAiCard(KmColors c, _AiResult result) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [c.accent.withValues(alpha: 0.06), c.gold.withValues(alpha: 0.04)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: c.accent.withValues(alpha: 0.25)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Header
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        decoration: BoxDecoration(
          color: c.accent.withValues(alpha: 0.1),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
        ),
        child: Row(children: [
          Icon(Icons.auto_awesome_rounded, color: c.accent, size: 16),
          const SizedBox(width: 6),
          Text('Hasil Analisis AI', style: TextStyle(color: c.accent, fontWeight: FontWeight.w700, fontSize: 13)),
          if (_selectedToken != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(6)),
              child: Text(_selectedToken!.text, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
            ),
          ],
          const Spacer(),
          GestureDetector(
            onTap: () { HapticFeedback.selectionClick(); _tts.speak(_selectedToken?.text ?? _recognizedText); },
            child: Icon(Icons.volume_up_rounded, color: c.accent, size: 18),
          ),
        ]),
      ),
      // Body
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (result.reading.isNotEmpty)
            _aiRow(c, Icons.record_voice_over_rounded, 'Cara Baca', result.reading, const Color(0xFF3B82F6)),
          if (result.meaning.isNotEmpty) ...[
            const SizedBox(height: 10),
            _aiRow(c, Icons.translate_rounded, 'Arti', result.meaning, const Color(0xFF10B981)),
          ],
          if (result.example.isNotEmpty) ...[
            const SizedBox(height: 10),
            _aiRow(c, Icons.chat_bubble_outline_rounded, 'Contoh', result.example, const Color(0xFFF59E0B)),
          ],
          if (result.grammar.isNotEmpty) ...[
            const SizedBox(height: 10),
            _aiRow(c, Icons.school_rounded, 'Grammar', result.grammar, const Color(0xFF8B5CF6)),
          ],
        ]),
      ),
    ]),
  );

  Widget _aiRow(KmColors c, IconData icon, String label, String value, Color color) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 14, color: color),
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 10, color: c.textMuted, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 14, color: c.text, height: 1.5)),
      ])),
    ],
  );

  Widget _buildErrorCard(KmColors c) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
    child: Row(children: [
      Icon(Icons.wifi_off_rounded, color: c.textMuted, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text(_analyzeStatus, style: TextStyle(color: c.textSub, fontSize: 13))),
      TextButton(onPressed: () => _analyzeWithGemini(_recognizedText), child: Text('Coba lagi', style: TextStyle(color: c.accent, fontSize: 12))),
    ]),
  );

  Widget _buildEmpty(KmColors c) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Container(
      width: 80, height: 80,
      decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.08), shape: BoxShape.circle),
      child: Icon(Icons.document_scanner_rounded, color: c.accent, size: 40),
    ),
    const SizedBox(height: 16),
    Text('Scan & Analisis Teks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text)),
    const SizedBox(height: 8),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Text('Foto teks dari kamera atau galeri.\nAI akan langsung menganalisis dan menjelaskan isinya.',
        textAlign: TextAlign.center, style: TextStyle(color: c.textSub, fontSize: 13, height: 1.6)),
    ),
  ]));
}
