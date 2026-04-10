// lib/features/media/presentation/screens/media_creator_screen.dart
// KanMon GO — Media Creator (Foto & Video dengan AI)
// Fitur:
//   📷 Foto langsung dari kamera + AI analisis/edit
//   🎬 Rekam video dengan kamera
//   🖼️  Pilih & edit foto dari galeri
//   🎞️  Pilih & analisis video dari galeri
//   💾 Simpan ke galeri HP
//   🤖 AI analisis & deskripsi konten visual
// =============================================================================

import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/data/services/ai_service.dart';
import 'package:kanmongo/data/services/file_processor_service.dart';
import 'package:kanmongo/data/services/media_edit_service.dart';
import 'package:kanmongo/data/services/tool_installer_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:kanmongo/shared/utils/top_snack.dart';

class MediaCreatorScreen extends ConsumerStatefulWidget {
  const MediaCreatorScreen({super.key});
  @override
  ConsumerState<MediaCreatorScreen> createState() => _MediaCreatorState();
}

class _MediaCreatorState extends ConsumerState<MediaCreatorScreen>
    with TickerProviderStateMixin {
  final _picker = ImagePicker();
  final _ai     = AiService.instance;

  late TabController _tabs;

  // State
  File?   _currentImage;
  File?   _currentVideo;
  String  _aiResult    = '';
  bool    _analyzing   = false;
  bool    _saving      = false;
  String? _saveMsg;

  // Gallery
  final List<_MediaItem> _gallery = [];

  // Native Edit state
  File?   _editInputFile;
  String  _editOperation  = 'compress';
  String  _editResult     = '';
  String? _editOutputPath;
  bool    _editing        = false;
  final Map<String, dynamic> _editParams = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  // ── Ambil foto dari kamera ────────────────────────────────────────────────
  Future<void> _takePhoto() async {
    final xfile = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (xfile == null) return;
    final file = File(xfile.path);
    if (mounted) setState(() {
      _currentImage = file;
      _currentVideo = null;
      _aiResult     = '';
    });
    _gallery.insert(0, _MediaItem(file: file, type: MediaType.photo));
    if (mounted) setState(() {});
  }

  // ── Ambil foto dari galeri ────────────────────────────────────────────────
  Future<void> _pickPhoto() async {
    final xfile = await _picker.pickImage(source: ImageSource.gallery);
    if (xfile == null) return;
    final file = File(xfile.path);
    if (mounted) setState(() {
      _currentImage = file;
      _currentVideo = null;
      _aiResult     = '';
    });
    _gallery.insert(0, _MediaItem(file: file, type: MediaType.photo));
    if (mounted) setState(() {});
  }

  // ── Rekam video ───────────────────────────────────────────────────────────
  Future<void> _recordVideo() async {
    final xfile = await _picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 10),
    );
    if (xfile == null) return;
    final file = File(xfile.path);
    if (mounted) setState(() {
      _currentVideo = file;
      _currentImage = null;
      _aiResult     = '';
    });
    _gallery.insert(0, _MediaItem(file: file, type: MediaType.video));
    if (mounted) setState(() {});
  }

  // ── Pilih video dari galeri ───────────────────────────────────────────────
  Future<void> _pickVideo() async {
    final xfile = await _picker.pickVideo(source: ImageSource.gallery);
    if (xfile == null) return;
    final file = File(xfile.path);
    if (mounted) setState(() {
      _currentVideo = file;
      _currentImage = null;
      _aiResult     = '';
    });
    _gallery.insert(0, _MediaItem(file: file, type: MediaType.video));
    if (mounted) setState(() {});
  }

  // ── Analisis dengan AI ────────────────────────────────────────────────────
  Future<void> _analyzeWithAi({String? customPrompt}) async {
    final imageFile = _currentImage;
    if (imageFile == null) {
      if (mounted) setState(() => _aiResult = '⚠️ Pilih atau ambil foto dulu.');
      return;
    }

    if (mounted) setState(() { _analyzing = true; _aiResult = ''; });

    try {
      final bytes = await imageFile.readAsBytes();
      final ext   = p.extension(imageFile.path).toLowerCase();
      final mime  = ext == '.png' ? 'image/png'
                  : ext == '.webp' ? 'image/webp'
                  : ext == '.gif' ? 'image/gif'
                  : 'image/jpeg';

      final processed = ProcessedFile(
        filename:  p.basename(imageFile.path),
        mimeType:  mime,
        category:  FileCategory.image,
        rawBytes:  bytes,
        sizeBytes: bytes.length,
      );

      final prompt = customPrompt ??
          'Analisis gambar ini secara detail. Jelaskan:\n'
          '1. Apa yang terlihat dalam gambar\n'
          '2. Warna, komposisi, dan elemen visual utama\n'
          '3. Konteks atau situasi yang terlihat\n'
          '4. Saran jika gambar ini perlu diperbaiki';

      final sb = StringBuffer();
      if (mounted) setState(() => _aiResult = '🤔 AI menganalisis...');

      await for (final token in _ai.sendChatWithFileStream(
        systemPrompt: 'Kamu adalah AI visual analyst yang detail dan membantu. '
            'Analisis gambar dengan seksama dan berikan respons dalam Bahasa Indonesia.',
        history: [],
        userMessage: prompt,
        file: processed,
        maxTokens: 1024,
      )) {
        sb.write(token);
        if (mounted) setState(() => _aiResult = sb.toString());
      }
    } catch (e) {
      if (mounted) setState(() => _aiResult = '❌ Error: $e');
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  // ── Simpan ke galeri HP ───────────────────────────────────────────────────
  Future<void> _saveToGallery() async {
    final file = _currentImage ?? _currentVideo;
    if (file == null) return;
    if (mounted) setState(() { _saving = true; _saveMsg = null; });

    try {
      final fileName = 'kanmon_${DateTime.now().millisecondsSinceEpoch}${file.path.contains('.') ? file.path.substring(file.path.lastIndexOf('.')) : ''}';
      final result = await SaverGallery.saveFile(
        filePath: file.path,
        fileName: fileName,
        androidRelativePath: 'Pictures/KanMonGO',
        skipIfExists: false,
      );
      if (result.isSuccess) {
        if (mounted) setState(() => _saveMsg = '✅ Tersimpan ke galeri!');
      } else {
        if (mounted) setState(() => _saveMsg = '❌ Gagal menyimpan: ${result.errorMessage}');
      }
    } catch (e) {
      if (mounted) setState(() => _saveMsg = '❌ Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
      if (mounted) {
        showTopSnack(context, _saveMsg ?? '', isError: _saveMsg?.startsWith('✅') != true);
      }
    }
  }

  // ── Simpan AI result ke file ──────────────────────────────────────────────
  Future<void> _saveAiResult() async {
    if (_aiResult.isEmpty) return;
    try {
      final dir  = await getApplicationDocumentsDirectory();
      final fn   = 'ai_analysis_${DateTime.now().millisecondsSinceEpoch}.txt';
      final file = File(p.join(dir.path, fn));
      await file.writeAsString(_aiResult);
      if (mounted) {
        showTopSnack(context, '✅ Disimpan: $fn');
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c      = KmColors.of(context);
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: c.text, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Media & AI',
            style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TabBar(
              controller: _tabs,
              indicator: BoxDecoration(
                  color: cs.primary, borderRadius: BorderRadius.circular(10)),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: c.textMuted,
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              dividerColor: Colors.transparent,
              padding: const EdgeInsets.all(3),
              tabs: const [
                Tab(icon: Icon(Icons.camera_alt_rounded, size: 18), text: 'Foto'),
                Tab(icon: Icon(Icons.videocam_rounded, size: 18), text: 'Video'),
                Tab(icon: Icon(Icons.photo_library_rounded, size: 18), text: 'Galeri'),
                Tab(icon: Icon(Icons.auto_fix_high_rounded, size: 18), text: 'Edit'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildPhotoTab(c, cs, isDark),
          _buildVideoTab(c, cs, isDark),
          _buildGalleryTab(c, cs, isDark),
          _buildEditTab(c, cs, isDark),
        ],
      ),
    );
  }

  // ── Tab Foto ──────────────────────────────────────────────────────────────
  Widget _buildPhotoTab(KmColors c, ColorScheme cs, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tombol aksi
          Row(children: [
            Expanded(
              child: _ActionBtn(
                icon: Icons.camera_alt_rounded,
                label: 'Ambil Foto',
                color: cs.primary,
                onTap: _takePhoto,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionBtn(
                icon: Icons.photo_library_rounded,
                label: 'Dari Galeri',
                color: const Color(0xFF10B981),
                onTap: _pickPhoto,
              ),
            ),
          ]),

          const SizedBox(height: 16),

          // Preview foto
          if (_currentImage != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(_currentImage!,
                  fit: BoxFit.cover, height: 280),
            ),
            const SizedBox(height: 10),

            // Action buttons bawah foto
            Row(children: [
              _SmallBtn(Icons.save_alt_rounded, 'Simpan',
                  _saving ? null : _saveToGallery, cs),
              const SizedBox(width: 8),
              _SmallBtn(Icons.copy_rounded, 'Copy Path',
                  () => Clipboard.setData(
                      ClipboardData(text: _currentImage!.path)), cs),
              const SizedBox(width: 8),
              _SmallBtn(Icons.share_rounded, 'Share', null, cs),
            ]),
            const SizedBox(height: 16),
          ],

          // AI Analysis section
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Text('🤖', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text('Analisis AI',
                      style: TextStyle(fontSize: 14,
                          fontWeight: FontWeight.w700, color: c.text)),
                  if (_analyzing) ...[
                    const SizedBox(width: 8),
                    SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: cs.primary)),
                  ],
                  const Spacer(),
                  if (_aiResult.isNotEmpty)
                    GestureDetector(
                      onTap: _saveAiResult,
                      child: Icon(Icons.save_rounded, color: cs.primary, size: 18),
                    ),
                ]),
                const SizedBox(height: 10),

                // Prompt shortcuts
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final (label, prompt) in _aiPrompts)
                    GestureDetector(
                      onTap: _currentImage == null ? null
                          : () => _analyzeWithAi(customPrompt: prompt),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: cs.primary.withValues(alpha: 0.2)),
                        ),
                        child: Text(label,
                            style: TextStyle(fontSize: 11,
                                color: _currentImage == null
                                    ? c.textMuted : cs.primary,
                                fontWeight: FontWeight.w500)),
                      ),
                    ),
                ]),

                if (_aiResult.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SelectableText(
                      _aiResult,
                      style: TextStyle(fontSize: 13, color: c.text, height: 1.5),
                    ),
                  ),
                ] else if (!_analyzing) ...[
                  const SizedBox(height: 8),
                  Text(
                    _currentImage == null
                        ? 'Ambil atau pilih foto dulu, lalu pilih jenis analisis.'
                        : 'Pilih jenis analisis di atas.',
                    style: TextStyle(fontSize: 12, color: c.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _aiPrompts = [
    ('🔍 Analisis Umum',     'Analisis gambar ini secara detail dan menyeluruh dalam Bahasa Indonesia.'),
    ('📝 Deskripsi',          'Buat deskripsi singkat gambar ini dalam 2-3 kalimat.'),
    ('💡 Identifikasi Objek', 'Identifikasi semua objek yang terlihat dalam gambar ini.'),
    ('📊 Analisis Data',      'Jika ada data, grafik, atau teks dalam gambar ini, baca dan analisis isinya.'),
    ('🎨 Analisis Estetika',  'Analisis kualitas estetika gambar: komposisi, pencahayaan, warna, dan saran perbaikan.'),
    ('📖 Baca Teks',          'Baca dan transkripsikan semua teks yang ada dalam gambar ini.'),
    ('🌍 Kenali Tempat',      'Identifikasi lokasi, landmark, atau tempat yang terlihat dalam gambar.'),
    ('😊 Analisis Ekspresi',  'Jika ada orang dalam gambar, analisis ekspresi dan suasana hati mereka.'),
  ];

  // ── Tab Video ─────────────────────────────────────────────────────────────
  Widget _buildVideoTab(KmColors c, ColorScheme cs, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: _ActionBtn(
                icon: Icons.videocam_rounded,
                label: 'Rekam Video',
                color: const Color(0xFFEF4444),
                onTap: _recordVideo,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionBtn(
                icon: Icons.video_library_rounded,
                label: 'Dari Galeri',
                color: const Color(0xFFF59E0B),
                onTap: _pickVideo,
              ),
            ),
          ]),

          const SizedBox(height: 16),

          if (_currentVideo != null) ...[
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(alignment: Alignment.center, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(color: Colors.black.withValues(alpha: 0.87)),
                ),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.movie_rounded, color: Colors.white54, size: 48),
                  const SizedBox(height: 8),
                  Text(p.basename(_currentVideo!.path),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(_getFileSize(_currentVideo!),
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ]),
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              _SmallBtn(Icons.save_alt_rounded, 'Simpan ke Galeri',
                  _saving ? null : _saveToGallery, cs),
            ]),
            const SizedBox(height: 16),
          ],

          // Info video AI
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Text('🎬', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text('Analisis Video AI',
                      style: TextStyle(fontSize: 14,
                          fontWeight: FontWeight.w700, color: c.text)),
                ]),
                const SizedBox(height: 8),
                Text(
                  'Rekam atau pilih video, lalu AI akan menganalisis isinya. '
                  'Video dikirim ke Gemini untuk pemahaman visual & audio.\n\n'
                  '⚠️ Membutuhkan koneksi internet untuk analisis video.',
                  style: TextStyle(fontSize: 12.5, color: c.textMuted, height: 1.5),
                ),
                if (_currentVideo != null) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _analyzing ? null : _analyzeVideo,
                    icon: _analyzing
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.play_arrow_rounded, size: 20),
                    label: Text(_analyzing ? 'Menganalisis...' : 'Analisis Video'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  if (_aiResult.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: SelectableText(_aiResult,
                          style: TextStyle(fontSize: 13, color: c.text, height: 1.5)),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _analyzeVideo() async {
    final videoFile = _currentVideo;
    if (videoFile == null) return;
    if (mounted) setState(() { _analyzing = true; _aiResult = ''; });
    try {
      final bytes = await videoFile.readAsBytes();
      if (bytes.length > 19 * 1024 * 1024) {
        if (mounted) setState(() => _aiResult = '⚠️ Video terlalu besar (maks 19MB untuk analisis langsung). '
            'Potong video dulu atau gunakan OCR screen.');
        return;
      }
      final processed = ProcessedFile(
        filename: p.basename(videoFile.path),
        mimeType: 'video/mp4',
        category: FileCategory.video,
        rawBytes: bytes,
        sizeBytes: bytes.length,
      );
      final sb = StringBuffer();
      await for (final token in _ai.sendChatWithFileStream(
        systemPrompt: 'Kamu adalah AI video analyst. Analisis video dengan detail.',
        history: [],
        userMessage: 'Analisis video ini: apa yang terjadi, siapa yang ada, '
            'apa yang dibicarakan (jika ada audio), dan ringkasan isinya.',
        file: processed,
      )) {
        sb.write(token);
        if (mounted) setState(() => _aiResult = sb.toString());
      }
    } catch (e) {
      if (mounted) setState(() => _aiResult = '❌ Error: $e');
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  // ── Tab Edit (Native File Editor) ─────────────────────────────────────────
  // Operasi nyata menggunakan ffmpeg via TerminalService — bukan mock/palsu.
  Widget _buildEditTab(KmColors c, ColorScheme cs, bool isDark) {
    // Operasi yang tersedia
    const ops = [
      ('compress',       '🗜️',  'Kompres',        'Kurangi ukuran file'),
      ('resize',         '📐',  'Resize',          'Ubah dimensi'),
      ('rotate',         '🔄',  'Rotasi 90°',      'Putar 90 derajat'),
      ('grayscale',      '⬛',  'Grayscale',       'Hitam putih'),
      ('flip',           '↔️',  'Flip H',          'Balik horizontal'),
      ('convert',        '🔀',  'Convert',         'Ubah format'),
      ('trim',           '✂️',  'Trim Video',      'Potong durasi'),
      ('extract_audio',  '🎵',  'Extract Audio',   'Ambil audio dari video'),
      ('thumbnail',      '🖼️',  'Thumbnail',       'Buat thumbnail video'),
      ('brightness',     '☀️',  'Brightness',      'Atur kecerahan'),
      ('blur',           '🌫️',  'Blur',            'Efek blur'),
      ('watermark',      '💧',  'Watermark',       'Tambah teks watermark'),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Header info
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color(0xFF6C5CE7).withValues(alpha: 0.15), const Color(0xFF00CEC9).withValues(alpha: 0.1)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF6C5CE7).withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            const Text('⚡', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Editor Media Native', style: TextStyle(color: c.text, fontSize: 14, fontWeight: FontWeight.w700)),
              Text('Edit foto & video langsung di perangkat\nmenggunakan ffmpeg — hasil nyata, bukan mock.',
                style: TextStyle(color: c.textMuted, fontSize: 11, height: 1.4)),
            ])),
          ]),
        ),

        const SizedBox(height: 16),

        // Pilih file input
        Row(children: [
          Expanded(child: _ActionBtn(
            icon: Icons.upload_file_rounded,
            label: 'Pilih File',
            color: const Color(0xFF6C5CE7),
            onTap: () async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.media,
                allowMultiple: false,
              );
              if (result != null && result.files.single.path != null) {
                if (mounted) setState(() {
                  _editInputFile = File(result.files.single.path!);
                  _editResult = '';
                  _editOutputPath = null;
                });
              }
            },
          )),
          const SizedBox(width: 10),
          Expanded(child: _ActionBtn(
            icon: Icons.camera_alt_rounded,
            label: 'Dari Kamera',
            color: const Color(0xFF00CEC9),
            onTap: () async {
              final xfile = await ImagePicker().pickImage(source: ImageSource.camera);
              if (xfile != null) {
                if (mounted) setState(() {
                  _editInputFile = File(xfile.path);
                  _editResult = '';
                  _editOutputPath = null;
                });
              }
            },
          )),
        ]),

        // Preview file yang dipilih
        if (_editInputFile != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              const Text('📁', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.basename(_editInputFile!.path),
                  style: TextStyle(color: c.text, fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
                Text(_getFileSize(_editInputFile!),
                  style: TextStyle(color: c.textMuted, fontSize: 11)),
              ])),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => setState(() { _editInputFile = null; _editResult = ''; _editOutputPath = null; }),
                color: c.textMuted,
              ),
            ]),
          ),
        ],

        const SizedBox(height: 16),

        // Pilih operasi
        Text('Pilih Operasi Edit', style: TextStyle(color: c.textSub, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.4,
          children: ops.map((op) {
            final (opKey, emoji, label, desc) = op;
            final sel = _editOperation == opKey;
            return GestureDetector(
              onTap: () => setState(() => _editOperation = opKey),
              child: Container(
                decoration: BoxDecoration(
                  color: sel ? const Color(0xFF6C5CE7).withValues(alpha: 0.15) : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: sel ? const Color(0xFF6C5CE7) : cs.outline.withValues(alpha: 0.2),
                    width: sel ? 1.5 : 1,
                  ),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(emoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(height: 3),
                  Text(label, style: TextStyle(color: sel ? const Color(0xFF6C5CE7) : c.text, fontSize: 11, fontWeight: FontWeight.w600)),
                  Text(desc, style: TextStyle(color: c.textMuted, fontSize: 9), textAlign: TextAlign.center),
                ]),
              ),
            );
          }).toList(),
        ),

        // Parameter khusus per operasi
        const SizedBox(height: 12),
        _buildEditParams(c, cs, isDark),

        const SizedBox(height: 16),

        // Tombol Edit
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (_editInputFile == null || _editing) ? null : _runNativeEdit,
            icon: _editing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Icon(Icons.auto_fix_high_rounded, size: 20),
            label: Text(
              _editing ? 'Sedang memproses...' : 'Jalankan Edit',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C5CE7),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF6C5CE7).withValues(alpha: 0.4),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),

        // Hasil edit
        if (_editResult.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _editResult.startsWith('✅')
                  ? Colors.green.withValues(alpha: 0.08)
                  : Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _editResult.startsWith('✅')
                    ? Colors.green.withValues(alpha: 0.3)
                    : Colors.red.withValues(alpha: 0.3),
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SelectableText(_editResult,
                style: TextStyle(color: c.text, fontSize: 13, height: 1.5)),
              if (_editOutputPath != null) ...[
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        final bytes = await File(_editOutputPath!).readAsBytes();
                        final ext = p.extension(_editOutputPath!).toLowerCase();
                        final isImage = ['.jpg', '.jpeg', '.png', '.webp', '.bmp'].contains(ext);
                        if (isImage) {
                          await SaverGallery.saveImage(bytes,
                            quality: 100,
                            fileName: p.basenameWithoutExtension(_editOutputPath!),
                            androidRelativePath: 'Pictures/KanMonGO',
                            skipIfExists: false,
                          );
                        } else {
                          await SaverGallery.saveFile(
                            filePath: _editOutputPath!,
                            fileName: p.basename(_editOutputPath!),
                            androidRelativePath: 'Movies/KanMonGO',
                            skipIfExists: false,
                          );
                        }
                        if (mounted) showTopSnack(context, '✅ Disimpan ke galeri!');
                      } catch (e) {
                        if (mounted) showTopSnack(context, '❌ Gagal simpan: $e', isError: true);
                      }
                    },
                    icon: const Icon(Icons.save_alt_rounded, size: 18),
                    label: const Text('Simpan ke Galeri'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  )),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _editOutputPath!));
                      showTopSnack(context, 'Path disalin', duration: Duration(seconds: 1));
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy Path'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary.withValues(alpha: 0.15),
                      foregroundColor: cs.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ]),
              ],
            ]),
          ),
        ],

        const SizedBox(height: 20),
      ]),
    );
  }

  // Parameter khusus berdasarkan operasi yang dipilih
  Widget _buildEditParams(KmColors c, ColorScheme cs, bool isDark) {
    final params = _editParams;
    switch (_editOperation) {
      case 'resize':
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Ukuran Target', style: TextStyle(color: c.textSub, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(children: [
            for (final size in ['480', '720', '1080', '1920'])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => setState(() { params['width'] = int.parse(size); params['height'] = -1; }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: params['width'].toString() == size
                          ? cs.primary : cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(size, style: TextStyle(
                      color: params['width'].toString() == size ? Colors.white : cs.primary,
                      fontSize: 12, fontWeight: FontWeight.w700,
                    )),
                  ),
                ),
              ),
          ]),
        ]);
      case 'rotate':
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Arah Rotasi', style: TextStyle(color: c.textSub, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(children: [
            for (final (label, val) in [('90° CW', '90'), ('180°', '180'), ('90° CCW', '270')])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => setState(() => params['angle'] = int.parse(val)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: params['angle']?.toString() == val ? cs.primary : cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(label, style: TextStyle(
                      color: params['angle']?.toString() == val ? Colors.white : cs.primary,
                      fontSize: 11, fontWeight: FontWeight.w700,
                    )),
                  ),
                ),
              ),
          ]),
        ]);
      case 'trim':
        params['start'] ??= 0;
        params['duration'] ??= 30;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Trim Video: ${params['start']}s — ${(params['start'] as int) + (params['duration'] as int)}s', style: TextStyle(color: c.textSub, fontSize: 12, fontWeight: FontWeight.w600)),
          Slider(
            value: (params['start'] as int? ?? 0).toDouble(),
            min: 0, max: 300,
            divisions: 60,
            label: 'Mulai: ${params['start']}s',
            onChanged: (v) => setState(() => params['start'] = v.round()),
          ),
          Slider(
            value: (params['duration'] as int? ?? 30).toDouble(),
            min: 1, max: 120,
            divisions: 119,
            label: 'Durasi: ${params['duration']}s',
            onChanged: (v) => setState(() => params['duration'] = v.round()),
          ),
        ]);
      case 'convert':
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Format Output', style: TextStyle(color: c.textSub, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            for (final fmt in ['mp4', 'mkv', 'webm', 'mp3', 'jpg', 'png', 'webp', 'gif'])
              GestureDetector(
                onTap: () => setState(() => params['format'] = fmt),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: params['format'] == fmt ? cs.primary : cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('.${fmt.toUpperCase()}', style: TextStyle(
                    color: params['format'] == fmt ? Colors.white : cs.primary,
                    fontSize: 11, fontWeight: FontWeight.w700,
                  )),
                ),
              ),
          ]),
        ]);
      case 'watermark':
        params['text'] ??= 'KanMon GO';
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Teks Watermark', style: TextStyle(color: c.textSub, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: TextEditingController(text: params['text'] as String? ?? '')
              ..selection = TextSelection.collapsed(offset: (params['text'] as String? ?? '').length),
            style: TextStyle(color: c.text, fontSize: 13),
            onChanged: (v) => params['text'] = v,
            decoration: InputDecoration(
              hintText: 'Teks watermark...',
              hintStyle: TextStyle(color: c.textMuted),
              filled: true,
              fillColor: cs.outline.withValues(alpha: 0.1),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ]);
      case 'brightness':
        params['brightness'] ??= 0.1;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Kecerahan: ${((params['brightness'] as double? ?? 0.1) * 100).round()}%', style: TextStyle(color: c.textSub, fontSize: 12, fontWeight: FontWeight.w600)),
          Slider(
            value: (params['brightness'] as double? ?? 0.1),
            min: -0.5, max: 0.5,
            divisions: 20,
            onChanged: (v) => setState(() => params['brightness'] = v),
          ),
        ]);
      default:
        return const SizedBox.shrink();
    }
  }

  // Jalankan native edit menggunakan MediaEditService (ffmpeg, bukan mock)
  Future<void> _runNativeEdit() async {
    final inputFile = _editInputFile;
    if (inputFile == null) return;

    if (mounted) setState(() { _editing = true; _editResult = ''; _editOutputPath = null; });

    try {
      // 1. Cek dan install tool
      if (mounted) setState(() => _editResult = '🔍 Memeriksa tool...');
      final toolCheck = await ToolInstallerService.instance.ensureToolForOperation(_editOperation);
      if (!toolCheck.success) {
        if (mounted) setState(() => _editResult = '⬇️ Menginstall ffmpeg...');
        bool installOk = false;
        await for (final chunk in ToolInstallerService.instance.installToolStream('ffmpeg')) {
          if (mounted) setState(() => _editResult = '⬇️ $chunk');
          if (chunk.contains('✅') || chunk.contains('berhasil')) installOk = true;
        }
        if (!installOk) {
          final recheck = await ToolInstallerService.instance.ensureToolForOperation(_editOperation);
          if (!recheck.success) {
            if (mounted) setState(() => _editResult = '❌ ffmpeg tidak berhasil diinstall.\n${recheck.installHint ?? ''}');
            return;
          }
        }
      }

      // 2. Jalankan edit
      if (mounted) setState(() => _editResult = '⚙️ Memproses file...');
      final result = await MediaEditService.instance.edit(
        inputPath: inputFile.path,
        operation: _editOperation,
        params: Map<String, dynamic>.from(_editParams),
      );

      if (result.success) {
        if (mounted) setState(() {
          _editResult = '✅ Edit selesai!\n${result.details}\n\nOutput: ${result.outputPath}';
          _editOutputPath = result.outputPath;
        });
      } else {
        if (mounted) setState(() => _editResult = '❌ Gagal: ${result.error}');
      }
    } catch (e) {
      if (mounted) setState(() => _editResult = '❌ Error: $e');
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  // ── Tab Galeri ────────────────────────────────────────────────────────────
  Widget _buildGalleryTab(KmColors c, ColorScheme cs, bool isDark) {
    if (_gallery.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('📷', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 12),
          Text('Belum ada media',
              style: TextStyle(color: c.textMuted, fontSize: 14)),
          const SizedBox(height: 8),
          Text('Foto & video yang kamu ambil atau pilih\nakan muncul di sini.',
              style: TextStyle(color: c.textMuted, fontSize: 12),
              textAlign: TextAlign.center),
        ]),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: _gallery.length,
      itemBuilder: (_, i) {
        final item = _gallery[i];
        return GestureDetector(
          onTap: () {
            if (mounted) setState(() {
              if (item.type == MediaType.photo) {
                _currentImage = item.file;
                _currentVideo = null;
                _aiResult = '';
                _tabs.animateTo(0);
              } else {
                _currentVideo = item.file;
                _currentImage = null;
                _aiResult = '';
                _tabs.animateTo(1);
              }
            });
          },
          child: Stack(fit: StackFit.expand, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: item.type == MediaType.photo
                  ? Image.file(item.file, fit: BoxFit.cover)
                  : Container(
                      color: Colors.black.withValues(alpha: 0.87),
                      child: const Icon(Icons.movie_rounded,
                          color: Colors.white54, size: 32)),
            ),
            if (item.type == MediaType.video)
              Positioned(
                bottom: 4, right: 4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                      color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 14),
                ),
              ),
          ]),
        );
      },
    );
  }

  String _getFileSize(File f) {
    try {
      final b = f.lengthSync();
      if (b < 1024 * 1024) return '${(b/1024).toStringAsFixed(0)} KB';
      return '${(b/(1024*1024)).toStringAsFixed(1)} MB';
    } catch (_) { return ''; }
  }
}

// ── Helper Widgets ────────────────────────────────────────────────────────────
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.label,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: color,
              fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final ColorScheme cs;
  const _SmallBtn(this.icon, this.label, this.onTap, this.cs);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16,
              color: onTap == null
                  ? cs.onSurface.withValues(alpha: 0.3)
                  : cs.primary),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12,
              color: onTap == null
                  ? cs.onSurface.withValues(alpha: 0.3)
                  : cs.onSurface,
              fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

enum MediaType { photo, video }

class _MediaItem {
  final File file;
  final MediaType type;
  _MediaItem({required this.file, required this.type});
}
