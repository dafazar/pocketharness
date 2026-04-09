import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kanmongo/data/services/ai/ai_service.dart';
import 'package:kanmongo/data/services/ai/offline_ai_service.dart';
import 'package:kanmongo/data/services/ai/puter_ai_service.dart';
import 'package:kanmongo/data/services/content/file_processor_service.dart';
import 'package:kanmongo/data/services/ai/ai_persona_service.dart';
import 'package:kanmongo/data/services/content/export_service.dart';
import 'package:kanmongo/data/services/ai/kanmonai_system_prompt.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_file/open_file.dart';
import 'dart:io';
import 'package:uuid/uuid.dart';

import '../../../../core/theme/km_colors.dart';
import '../../../../data/services/content/database_service.dart';
import '../../../../data/services/content/model_manager_service.dart';
import '../../../../data/services/media/sfx_service.dart';
import '../../../../shared/widgets/back_handler.dart';
import '../../../../shared/widgets/km_widgets.dart';
import '../../../../shared/widgets/ai_source_picker.dart';
import 'package:kanmongo/shared/utils/top_snack.dart';

// ── Models ────────────────────────────────────

class ChatMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime time;
  final bool isLoading;
  final ProcessedFile? attachment; // file yang dilampirkan
  final String? outputFilePath;    // path file hasil edit untuk download

  const ChatMessage({
    required this.role,
    required this.content,
    required this.time,
    this.isLoading = false,
    this.attachment,
    this.outputFilePath,
  });

  bool get isUser        => role == 'user';
  bool get hasAttachment => attachment != null;
  bool get hasFileOutput => outputFilePath != null;
}

// ── Providers ─────────────────────────────────

final aiSessionIdProvider = Provider<String>((ref) => const Uuid().v4());

/// Provider untuk model yang dipilih di AI Chat (null = gunakan model aktif)
final selectedAiModelProvider = StateProvider<AiModel?>((ref) => null);

final chatMessagesProvider =
    StateNotifierProvider<ChatNotifier, List<ChatMessage>>((ref) {
  return ChatNotifier(ref.read(aiSessionIdProvider));
});

final isAiLoadingProvider = StateProvider<bool>((ref) => false);
final aiSubjectProvider = StateProvider<String>((ref) => 'Umum');

class ChatNotifier extends StateNotifier<List<ChatMessage>> {
  final String sessionId;

  ChatNotifier(this.sessionId) : super([]) {
    _loadHistory();
    _addWelcome();
  }

  Future<void> _loadHistory() async {
    final rows = await DatabaseService.instance.getAiHistory(sessionId);
    if (rows.isEmpty) return;
    final msgs = rows.map((r) => ChatMessage(
      role: r['role'] as String,
      content: r['content'] as String,
      time: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
    )).toList();
    if (mounted) state = msgs;
  }

  void _addWelcome() {
    if (state.isNotEmpty) return;
    final welcome = ChatMessage(
      role: 'assistant',
      content: 'Halo! 👋\n\nSaya **AI Chat** — asisten AI kamu.\n\nSaya bisa membantu:\n• Menjawab pertanyaan apa saja\n• Analisis dan rangkum teks\n• Bantu menulis & mengedit\n• Terjemahkan bahasa\n• Berdiskusi ide & topik\n\nMau mulai dengan apa? 😊',
      time: DateTime.now(),
    );
    state = [welcome];
  }

  void addUserMessage(String content, {ProcessedFile? attachment}) {
    state = [
      ...state,
      ChatMessage(role: 'user', content: content, time: DateTime.now(), attachment: attachment),
    ];
    DatabaseService.instance.saveAiMessage(
      sessionId: sessionId, role: 'user', content: content,
    );
  }

  void addAssistantMessage(String content) {
    // Remove loading bubble
    state = state.where((m) => !m.isLoading).toList();
    final msg = ChatMessage(
      role: 'assistant', content: content, time: DateTime.now(),
    );
    state = [...state, msg];
    DatabaseService.instance.saveAiMessage(
      sessionId: sessionId, role: 'assistant', content: content,
    );
  }

  void addLoadingBubble() {
    state = [
      ...state,
      ChatMessage(role: 'assistant', content: '', time: DateTime.now(), isLoading: true),
    ];
  }

  // [KM-FAST] Streaming: update bubble terakhir dengan token baru
  void appendStreamToken(String token) {
    if (state.isEmpty) return;
    final last = state.last;
    if (last.role != 'assistant') return;
    final updated = ChatMessage(
      role: 'assistant',
      content: last.content + token,
      time: last.time,
      isLoading: false,
    );
    state = [...state.sublist(0, state.length - 1), updated];
  }

  // [KM-FAST] Mulai streaming bubble (kosong dulu, akan diisi token)
  void startStreamingBubble() {
    state = [
      ...state.where((m) => !m.isLoading).toList(),
      ChatMessage(role: 'assistant', content: '', time: DateTime.now(), isLoading: false),
    ];
  }

  // [KM-FAST] Simpan pesan asisten terakhir ke DB (fire-and-forget)
  void saveLastAssistantMessage(String content) {
    DatabaseService.instance.saveAiMessage(
      sessionId: sessionId,
      role: 'assistant',
      content: content,
    );
  }

  // Tambah pesan khusus berisi tombol download file hasil edit
  void addFileOutputMessage(String filePath) {
    state = [
      ...state.where((m) => !m.isLoading).toList(),
      ChatMessage(
        role: 'assistant',
        content: '📎 File hasil edit siap diunduh.',
        time: DateTime.now(),
        outputFilePath: filePath,
      ),
    ];
  }

  void removeLoading() {
    state = state.where((m) => !m.isLoading).toList();
  }

  void clearHistory() {
    state = [];
    _addWelcome();
  }
}

// ── Screen ────────────────────────────────────

class AiTutorScreen extends ConsumerStatefulWidget {
  /// Jika diisi, query ini akan otomatis dikirim saat screen pertama kali dibuka.
  final String? initialQuery;
  const AiTutorScreen({super.key, this.initialQuery});

  @override
  ConsumerState<AiTutorScreen> createState() => _AiTutorScreenState();
}

class _AiTutorScreenState extends ConsumerState<AiTutorScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _canSend = false;
  int  _cooldownSec = 0;   // countdown detik sebelum bisa kirim lagi
  Timer? _cooldownTimer;
  int  _retryCount  = 0;   // jumlah retry saat 429
  ProcessedFile? _pendingFile; // file attachment yang menunggu dikirim
  bool _processingFile = false;  // sedang memproses file upload

  // ── Gemini API (Google AI Studio — gratis 60 req/menit) ──────────────────

  // Topik cepat
  static const _quickTopics = [
    '💡 Jelaskan konsep ini',
    '✍️ Bantu Menulis',
    '🔍 Analisis Teks',
    '💻 Review Kode',
    '🌐 Terjemahkan',
    '🧠 Brainstorm Ide',
  ];

  @override
  void initState() {
    super.initState();
    _inputCtrl.addListener(() {
      setState(() => _canSend = _inputCtrl.text.trim().isNotEmpty);
    });
    // ── Auto-send initialQuery jika ada (dari Reader/screen lain) ────────
    if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sendMessage(widget.initialQuery!);
      });
    }

    // ── Auto-load model aktif saat screen pertama kali dibuka ─────────────
    // Jika OfflineAiService belum siap tapi ada model aktif, muat sekarang.
    if (!OfflineAiService.instance.isReady) {
      OfflineAiService.instance.loadSettings().then((_) {
        if (ModelManagerService.instance.activeModel != null) {
          OfflineAiService.instance.initActiveModel().then((_) {
            if (mounted) setState(() {});
          }).catchError((e) {
            debugPrint('[AiTutorScreen] initActiveModel error: $e');
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Cooldown — blokir kiriman selama N detik ─────────────────────────────────
  void _startCooldown(int seconds) {
    setState(() { _cooldownSec = seconds; _canSend = false; });
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _cooldownSec--;
        if (_cooldownSec <= 0) {
          _cooldownSec = 0;
          t.cancel();
          // Re-enable send jika ada teks
          _canSend = _inputCtrl.text.trim().isNotEmpty;
        }
      });
    });
  }

  // ── Retry request dengan exponential backoff ─────────────────────────────────
  

  // ── Pick file dari storage ────────────────────────────────────────────────
  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    await _processFile(path);
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    await _processFile(picked.path);
  }

  Future<void> _pickCamera() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera);
    if (picked == null) return;
    await _processFile(picked.path);
  }

  Future<void> _processFile(String path) async {
    setState(() => _processingFile = true);
    final processed = await FileProcessorService.instance.process(path);
    if (mounted) {
      setState(() {
        _pendingFile     = processed;
        _processingFile  = false;
        _canSend         = true;
      });
    }
  }

  void _removePendingFile() => setState(() => _pendingFile = null);

  void _showAttachMenu() {
    final c = KmColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Lampirkan File',
                  style: TextStyle(color: c.text,
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12, runSpacing: 12,
                children: [
                  _AttachOption(icon: Icons.image_rounded,
                      label: 'Galeri', color: const Color(0xFF10B981),
                      onTap: () { Navigator.pop(context); _pickImage(); }),
                  _AttachOption(icon: Icons.camera_alt_rounded,
                      label: 'Kamera', color: const Color(0xFF0EA5E9),
                      onTap: () { Navigator.pop(context); _pickCamera(); }),
                  _AttachOption(icon: Icons.picture_as_pdf_rounded,
                      label: 'PDF', color: const Color(0xFFEF4444),
                      onTap: () { Navigator.pop(context); _pickFile(); }),
                  _AttachOption(icon: Icons.description_rounded,
                      label: 'Dokumen', color: const Color(0xFF6366F1),
                      onTap: () { Navigator.pop(context); _pickFile(); }),
                  _AttachOption(icon: Icons.table_chart_rounded,
                      label: 'Spreadsheet', color: const Color(0xFF059669),
                      onTap: () { Navigator.pop(context); _pickFile(); }),
                  _AttachOption(icon: Icons.code_rounded,
                      label: 'Kode', color: const Color(0xFFF59E0B),
                      onTap: () { Navigator.pop(context); _pickFile(); }),
                  _AttachOption(icon: Icons.audio_file_rounded,
                      label: 'Audio', color: const Color(0xFFEC4899),
                      onTap: () { Navigator.pop(context); _pickFile(); }),
                  _AttachOption(icon: Icons.folder_rounded,
                      label: 'File Lainnya', color: const Color(0xFF64748B),
                      onTap: () { Navigator.pop(context); _pickFile(); }),
                ],
              ),
              const SizedBox(height: 8),
              Text('Semua format didukung: gambar, PDF, DOCX, XLSX, PPTX, '
                  'audio, video, kode, dan lainnya.',
                  style: TextStyle(color: c.textMuted, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  // [KM-FAST] Streaming send — token muncul realtime seperti ChatGPT
  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty && _pendingFile == null) return;
    final inputText = text.trim().isNotEmpty ? text : ''; 
    _inputCtrl.clear();
    setState(() => _canSend = false);

    final notifier    = ref.read(chatMessagesProvider.notifier);
    final subject     = ref.read(aiSubjectProvider);
    final attachment  = _pendingFile;
    setState(() => _pendingFile = null); // clear sebelum send

    notifier.addUserMessage(inputText, attachment: attachment);
    notifier.addLoadingBubble();   // loading spinner dulu
    ref.read(isAiLoadingProvider.notifier).state = true;
    _scrollToBottom();
    SfxService.instance.play(Sfx.tap);

    // [OPTIMASI 5] Fire-and-forget DB write (tidak block UI)
    // DB write sudah dilakukan di addUserMessage secara async

    try {
      // [OPTIMASI 6] Smart history trim — ambil sebelum user message baru
      final allMsgs = ref.read(chatMessagesProvider);
      final history = allMsgs
          .where((m) => !m.isLoading && m.role != 'system' && !m.content.contains('Halo! 👋'))
          .toList();
      // Hapus pesan user terakhir (sudah ada di userMessage param)
      final histForApi = history.isEmpty ? <ChatMessage>[] : history.sublist(0, history.length - 1);

      final historyMaps = histForApi.map((m) => {
        'role': m.role == 'user' ? 'user' : 'assistant',
        'content': m.content,
      }).toList();

      // [KM-FAST] Start streaming bubble
      notifier.removeLoading();
      notifier.startStreamingBubble();

      final sb = StringBuffer();
      bool firstToken = true;

      // [OPTIMASI 3] Stream token by token
      // Pilih stream yang tepat: dengan file atau teks biasa
      // Cek apakah ini request edit media
      final isEditRequest = attachment != null &&
          _isMediaEditRequest(inputText) &&
          (attachment.mimeType.startsWith('image/') ||
           attachment.mimeType.startsWith('video/') ||
           attachment.mimeType.startsWith('audio/'));

      final Stream<String> responseStream;
      if (isEditRequest) {
        // Route ke editMediaAndReply
        final filePath = attachment!.originalPath?.isNotEmpty == true
            ? attachment.originalPath!
            : attachment.name;
        responseStream = AiService.instance.editMediaAndReply(
          filePath:     filePath,
          userRequest:  inputText,
          systemPrompt: _buildSystemPrompt(subject),
          history:      historyMaps,
        );
      } else if (attachment != null) {
        responseStream = AiService.instance.sendChatWithFileStream(
          systemPrompt: _buildSystemPrompt(subject),
          history: historyMaps,
          userMessage: inputText,
          file: attachment,
          temperature: 0.7,
          maxTokens: 2048,
        );
      } else {
        responseStream = AiService.instance.sendChatStream(
          systemPrompt: _buildSystemPrompt(subject),
          history: historyMaps,
          userMessage: inputText,
          temperature: 0.7,
          maxTokens: 1024,
        );
      }

      String? outputFilePath;

      try {
        await for (final token in responseStream) {
          // Intersep FILE_OUTPUT token — jangan render ke bubble
          if (token.startsWith('FILE_OUTPUT:')) {
            outputFilePath = token.replaceFirst('FILE_OUTPUT:', '').trim();
            continue;
          }
          sb.write(token);
          notifier.appendStreamToken(token);

          // Scroll ke bawah saat token pertama muncul
          if (firstToken) {
            firstToken = false;
            _scrollToBottom();
          }
        }
      } on TimeoutException catch (te) {
        final msg = '\n\n⏱️ Timeout: ${te.message ?? 'Respons terlalu lama.'}';
        notifier.appendStreamToken(msg);
        sb.write(msg);
      } catch (streamErr) {
        debugPrint('[AiTutor] Stream error: $streamErr');
        final msg = '\n\n❌ Error: ${streamErr.toString().replaceAll('Exception: ', '')}';
        notifier.appendStreamToken(msg);
        sb.write(msg);
      }

      // Jika ada file output, tambahkan pesan khusus dengan tombol download
      if (outputFilePath != null) {
        notifier.addFileOutputMessage(outputFilePath!);
      }

      // Simpan full response ke DB setelah streaming selesai
      // [OPTIMASI 5] Fire-and-forget
      final fullReply = sb.toString();
      if (fullReply.isNotEmpty) {
        notifier.saveLastAssistantMessage(fullReply);
        SfxService.instance.play(Sfx.notification);
      }

    } catch (e) {
      notifier.removeLoading();
      notifier.addAssistantMessage('Error: ${e.toString().replaceAll('Exception: ', '')}');
    } finally {
      ref.read(isAiLoadingProvider.notifier).state = false;
      _scrollToBottom();
    }
  }

  // Deteksi apakah user ingin edit media berdasarkan kata kunci
  bool _isMediaEditRequest(String text) {
    final t = text.toLowerCase();
    const keywords = [
      'resize', 'crop', 'potong', 'rotate', 'putar', 'flip', 'balik',
      'compress', 'kompress', 'kompres', 'trim', 'convert', 'konversi',
      'watermark', 'thumbnail', 'grayscale', 'hitam putih', 'blur',
      'speed', 'kecepatan', 'volume', 'audio', 'extract audio', 'merge',
      'edit', 'ubah ukuran', 'kecilkan', 'perkecil', 'besarkan', 'perbesar',
      'pangkas', 'potong video', 'potong gambar', 'cerahkan', 'gelapkan',
    ];
    return keywords.any((kw) => t.contains(kw));
  }

  String _buildSystemPrompt(String subject) {
    // Gunakan persona aktif dari AiPersonaService
    final personaPrompt = AiPersonaService.instance.buildSystemPrompt(subject: subject);
    if (personaPrompt.isNotEmpty) return personaPrompt;
    // Fallback: KanMonAI identity + tutor context
    return '$kKanMonAIShortSystemPrompt\n\n'
        'Kepribadianmu sebagai tutor:\n'
        '- Hangat, antusias, dan mendukung semangat belajar\n'
        '- Memberikan contoh praktis dan relatable\n'
        '- Format respons jelas dan terstruktur dengan **bold** untuk penekanan\n'
        '- Akhiri dengan pertanyaan follow-up atau tantangan kecil\n\n'
        'Fokus topik saat ini: $subject\n'
        'Jangan pernah memberikan jawaban yang terlalu panjang. Prioritaskan kejelasan.';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    final messages = ref.watch(chatMessagesProvider);
    final isLoading = ref.watch(isAiLoadingProvider);

    return ConfirmExitBack(
      message: 'Keluar dari AI Chat?',
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          backgroundColor: c.bg,
          foregroundColor: c.text,
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7B2FF7), Color(0xFF2F7BF7)],
                  ),
                ),
                child: Stack(
                  children: [
                    const Center(
                      child: Text(
                        '先',
                        style: TextStyle(
                                                    fontSize: 18,
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF00D060),
                          border: Border.all(color: c.bg, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI Chat',
                    style: TextStyle(
                      color: c.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    isLoading ? 'Sedang mengetik...' : '● Online',
                    style: TextStyle(
                      color: isLoading ? c.gold : const Color(0xFF00D060),
                      fontSize: 10,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            // AI Source Picker
            Consumer(builder: (ctx, ref, _) {
              return AiSourcePickerButton(
                onTap: () => showAiSourcePicker(context, ref),
              );
            }),
            // Subject picker
            Consumer(builder: (ctx, ref, _) {
              final sub = ref.watch(aiSubjectProvider);
              return TextButton(
                onPressed: () => _showSubjectPicker(context, ref, c),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(sub, style: TextStyle(color: c.accent, fontSize: 12)),
                    Icon(Icons.expand_more, color: c.accent, size: 16),
                  ],
                ),
              );
            }),
            // Tombol pengaturan model
            IconButton(
              icon: Icon(Icons.tune_rounded, color: c.textMuted),
              onPressed: () => _showChatSettings(context, ref, c),
              tooltip: 'Pengaturan AI',
            ),
            IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: c.textMuted),
              onPressed: () => ref.read(chatMessagesProvider.notifier).clearHistory(),
              tooltip: 'Hapus riwayat',
            ),
          ],
        ),
        body: Column(
          children: [
            // Quick topics
            _buildQuickTopics(c),

            // Messages list
            Expanded(
              child: messages.isEmpty
                  ? KmEmptyState(
                      icon: '🤖',
                      title: 'Mulai Chat dengan AI',
                      subtitle: 'Tanyakan apa saja!',
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: messages.length,
                      itemBuilder: (ctx, i) => _ChatBubble(msg: messages[i]),
                    ),
            ),

            // Input bar
            _buildInputBar(c, isLoading),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickTopics(KmColors c) {
    // ── Tampilkan banner status model jika belum siap ─────────────────────
    final offlineSvc = OfflineAiService.instance;
    final puterSvc   = PuterAiService.instance;
    final aiSvc      = AiService.instance;
    final hasNoModel = ModelManagerService.instance.activeModel == null;
    final isLoading  = offlineSvc.isLoading;
    final notReady   = !offlineSvc.isReady && !isLoading;
    final isOnlineMode = aiSvc.currentMode == AiMode.online;

    Widget? statusBanner;
    if (isOnlineMode) {
      final modelName = puterSvc.selectedModel?.name ?? 'Online';
      statusBanner = _ModelStatusBanner(
        icon: '🌐',
        message: 'AI Online aktif: $modelName',
        color: Colors.green.shade600,
        c: c,
      );
    } else if (hasNoModel) {
      statusBanner = _ModelStatusBanner(
        icon: '🤖',
        message: 'Belum ada model. Pergi ke Settings → Model Manager',
        color: Colors.orange,
        c: c,
        onTap: () => Navigator.pushNamed(context, '/model-manager'),
      );
    } else if (isLoading) {
      statusBanner = _ModelStatusBanner(
        icon: '⏳',
        message: 'Memuat model AI... (${ModelManagerService.instance.activeModel?.name ?? ''})',
        color: const Color(0xFF7B2FF7),
        c: c,
      );
    } else if (notReady) {
      statusBanner = _ModelStatusBanner(
        icon: '⚠️',
        message: 'Model belum aktif — tap untuk muat ulang',
        color: Colors.red,
        c: c,
        onTap: () {
          OfflineAiService.instance.loadActiveModel().then((_) {
            if (mounted) setState(() {});
          });
        },
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (statusBanner != null) statusBanner,
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: _quickTopics.map((t) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => _sendMessage(t),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.inputFill,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: c.border),
                  ),
                  child: Text(
                    t,
                    style: TextStyle(color: c.textSub, fontSize: 11),
                  ),
                ),
              ),
            )).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildInputBar(KmColors c, bool isLoading) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Preview file yang akan dikirim ──────────────────────────────
          if (_pendingFile != null)
            _FilePreviewBar(
              file: _pendingFile!,
              onRemove: _removePendingFile,
              c: c,
            ),

          // ── Processing indicator ─────────────────────────────────────────
          if (_processingFile)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)),
                const SizedBox(width: 10),
                Text('Memproses file...', style: TextStyle(fontSize: 12, color: c.textMuted)),
              ]),
            ),

          // ── Input row ────────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(
              8, 8, 8, MediaQuery.of(context).viewInsets.bottom + 10,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Tombol attachment
                _IconBtn(
                  icon: Icons.add_rounded,
                  color: cs.primary,
                  bgColor: cs.primary.withValues(alpha: 0.1),
                  onTap: isLoading ? null : _showAttachMenu,
                ),
                const SizedBox(width: 6),

                // Input teks
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    decoration: BoxDecoration(
                      color: c.inputFill,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: c.border),
                    ),
                    child: TextField(
                      controller: _inputCtrl,
                      maxLines: 5,
                      minLines: 1,
                      style: TextStyle(color: c.text, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: _pendingFile != null
                            ? 'Instruksi untuk file ini... (opsional)'
                            : 'Ketik pesan atau lampirkan file...',
                        hintStyle: TextStyle(color: c.textMuted, fontSize: 13),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Tombol kirim
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (_canSend || _pendingFile != null) && !isLoading
                        ? c.accent
                        : c.inputFill,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: ((_canSend || _pendingFile != null) && !isLoading)
                          ? () => _sendMessage(_inputCtrl.text)
                          : null,
                      child: Center(
                        child: isLoading
                            ? SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: c.textMuted))
                            : Icon(Icons.send_rounded,
                                color: (_canSend || _pendingFile != null)
                                    ? Colors.white : c.textMuted,
                                size: 20),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showChatSettings(BuildContext context, WidgetRef ref, KmColors c) {
    final models = ModelManagerService.instance.models;
    final selectedModel = ref.read(selectedAiModelProvider);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.tune_rounded, color: cs.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Text('Pengaturan AI Chat',
                    style: TextStyle(color: c.text,
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 20),

              // ── Pilih Model ──────────────────────────────────────────────
              Text('Model AI',
                  style: TextStyle(color: c.textMuted, fontSize: 12,
                      fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              const SizedBox(height: 8),

              if (models.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(children: [
                    const Text('🤖', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('Belum ada model',
                            style: TextStyle(color: c.text, fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        Text('Import model di Settings → Model Manager',
                            style: TextStyle(color: c.textMuted, fontSize: 11)),
                      ]),
                    ),
                  ]),
                )
              else
                Column(
                  children: models.map((model) {
                    final isSelected = selectedModel?.id == model.id ||
                        (selectedModel == null &&
                            model.id == ModelManagerService.instance.activeModel?.id);
                    return GestureDetector(
                      onTap: () {
                        ref.read(selectedAiModelProvider.notifier).state =
                            model.toLlamaModelInfo();
                        // Aktifkan model ini di OfflineAiService
                        ModelManagerService.instance.setActive(model.id);
                        OfflineAiService.instance.loadActiveModel();
                        setModalState(() {});
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? cs.primary.withValues(alpha: 0.1)
                              : isDark
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : Colors.black.withValues(alpha: 0.02),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? cs.primary.withValues(alpha: 0.4)
                                : c.border,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(children: [
                          Text(model.format == 'gguf' || model.format == 'ggml' ? '🤖' : '📦',
                              style: const TextStyle(fontSize: 18)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(model.name,
                                  style: TextStyle(
                                      color: c.text, fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis),
                              Text('${model.format.toUpperCase()} · ${model.sizeLabel}',
                                  style: TextStyle(
                                      color: c.textMuted, fontSize: 11)),
                            ]),
                          ),
                          if (isSelected)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('Aktif',
                                  style: TextStyle(
                                      color: cs.primary, fontSize: 10,
                                      fontWeight: FontWeight.w700)),
                            ),
                        ]),
                      ),
                    );
                  }).toList(),
                ),

              const SizedBox(height: 16),

              // Tombol ke Model Manager
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pushNamed(context, '/model-manager');
                  },
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Import / Download Model'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSubjectPicker(BuildContext context, WidgetRef ref, KmColors c) {
    const subjects = ['Umum', 'Menulis', 'Analisis', 'Terjemahan', 'Rangkuman', 'Brainstorm', 'Kode', 'Sains', 'Bisnis', 'Percakapan'];
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Pilih Topik Fokus',
              style: TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: subjects.map((s) => GestureDetector(
              onTap: () {
                ref.read(aiSubjectProvider.notifier).state = s;
                Navigator.pop(ctx);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: c.inputFill,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: c.border),
                ),
                child: Text(s, style: TextStyle(color: c.text, fontSize: 13)),
              ),
            )).toList(),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Chat Bubble ───────────────────────────────

class _ChatBubble extends StatelessWidget {
  final ChatMessage msg;
  const _ChatBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    final isUser = msg.isUser;

    if (msg.isLoading) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF7B2FF7).withValues(alpha: 0.12),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            border: Border.all(color: const Color(0xFF7B2FF7).withValues(alpha: 0.2)),
          ),
          child: _TypingIndicator(),
        ),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isUser
              ? c.accent.withValues(alpha: 0.15)
              : const Color(0xFF7B2FF7).withValues(alpha: 0.12),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(isUser ? 16 : 4),
            topRight: Radius.circular(isUser ? 4 : 16),
            bottomLeft: const Radius.circular(16),
            bottomRight: const Radius.circular(16),
          ),
          border: Border.all(
            color: isUser
                ? c.accent.withValues(alpha: 0.25)
                : const Color(0xFF7B2FF7).withValues(alpha: 0.2),
          ),
        ),
        child: _buildContent(c),
      ),
    );
  }

  Widget _buildContent(KmColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Attachment preview dalam bubble
        if (msg.hasAttachment && msg.attachment != null) ...[
          _BubbleAttachment(file: msg.attachment!, c: c),
          if (msg.content.isNotEmpty) const SizedBox(height: 8),
        ],
        // Teks pesan
        if (msg.content.isNotEmpty)
          ...msg.content.split('\n').map((line) {
            if (line.isEmpty) return const SizedBox(height: 4);
            return _MarkdownLine(line: line, c: c);
          }),
        // Tombol download file hasil edit
        if (msg.hasFileOutput && msg.outputFilePath != null)
          _FileOutputButton(filePath: msg.outputFilePath!),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// WIDGET: Attachment preview di dalam bubble chat
// ══════════════════════════════════════════════════════════════════════════════
class _BubbleAttachment extends StatelessWidget {
  final ProcessedFile file;
  final KmColors c;
  const _BubbleAttachment({required this.file, required this.c});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Gambar: tampilkan thumbnail
    if (file.rawBytes != null && file.mimeType.startsWith('image/')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(file.rawBytes!,
          width: 220, fit: BoxFit.cover),
      );
    }

    // File lain: badge
    return GestureDetector(
      onTap: () => OpenFile.open(file.filename),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(file.icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(file.filename,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.text),
                overflow: TextOverflow.ellipsis),
              Text(file.sizeLabel,
                style: TextStyle(fontSize: 10, color: c.textMuted)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// WIDGET: Tombol download file hasil edit media
// ══════════════════════════════════════════════════════════════════════════════
class _FileOutputButton extends StatelessWidget {
  final String filePath;
  const _FileOutputButton({required this.filePath});

  @override
  Widget build(BuildContext context) {
    final filename = filePath.split('/').last;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GestureDetector(
        onTap: () => _share(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [
              Color(0xFF8B5CF6), Color(0xFF6D28D9),
            ]),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                blurRadius: 8, offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.download_rounded, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                filename,
                style: const TextStyle(
                  fontSize: 12, color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _share(BuildContext ctx) async {
    try {
      await ExportService.instance.shareFile(filePath);
    } catch (e) {
      if (ctx.mounted) {
        showTopSnack(ctx, '❌ Gagal berbagi: \$e', isError: true)
      }
    }
  }
}

class _MarkdownLine extends StatelessWidget {
  final String line;
  final KmColors c;
  const _MarkdownLine({required this.line, required this.c});

  @override
  Widget build(BuildContext context) {
    // Detect bold **text**
    final spans = <TextSpan>[];
    final regex = RegExp(r'\*\*(.*?)\*\*');
    int last = 0;
    for (final match in regex.allMatches(line)) {
      if (match.start > last) {
        spans.add(TextSpan(
          text: line.substring(last, match.start),
          style: TextStyle(color: c.text, fontSize: 13, height: 1.5),
        ));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: TextStyle(
          color: c.accent,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          height: 1.5,
        ),
      ));
      last = match.end;
    }
    if (last < line.length) {
      spans.add(TextSpan(
        text: line.substring(last),
        style: TextStyle(color: c.text, fontSize: 13, height: 1.5),
      ));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(
        text: line,
        style: TextStyle(color: c.text, fontSize: 13, height: 1.5),
      ));
    }
    return RichText(text: TextSpan(children: spans));
  }
}

class _TypingIndicator extends StatefulWidget {
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final delay = i * 0.2;
          final t = (_ctrl.value - delay).clamp(0.0, 1.0);
          final scale = 0.6 + 0.4 * (1 - (2 * t - 1).abs());
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF9060FF),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// WIDGET: File Preview Bar (preview file sebelum dikirim)
// ══════════════════════════════════════════════════════════════════════════════
class _FilePreviewBar extends StatelessWidget {
  final ProcessedFile file;
  final VoidCallback onRemove;
  final KmColors c;
  const _FilePreviewBar({required this.file, required this.onRemove, required this.c});

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        // Preview thumbnail jika gambar
        if (file.rawBytes != null &&
            (file.mimeType.startsWith('image/')))
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(file.rawBytes!,
                width: 40, height: 40, fit: BoxFit.cover),
          )
        else
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(file.icon, style: const TextStyle(fontSize: 20)),
          ),

        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(file.filename,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text),
              overflow: TextOverflow.ellipsis,
            ),
            Text('${file.sizeLabel} · ${file.mimeType.split('/').last.toUpperCase()}',
              style: TextStyle(fontSize: 11, color: c.textMuted)),
          ]),
        ),

        IconButton(
          icon: Icon(Icons.close_rounded, size: 18, color: c.textMuted),
          onPressed: onRemove,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// WIDGET: Attach Option Button
// ══════════════════════════════════════════════════════════════════════════════
class _AttachOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _AttachOption({required this.icon, required this.label,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 5),
            Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5,
                  color: KmColors.of(context).text,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// WIDGET: Icon Button
// ══════════════════════════════════════════════════════════════════════════════
class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bgColor;
  final VoidCallback? onTap;
  const _IconBtn({required this.icon, required this.color,
      required this.bgColor, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(shape: BoxShape.circle, color: bgColor),
        child: Icon(icon, color: onTap != null ? color : color.withValues(alpha: 0.4), size: 22),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// WIDGET: Model Status Banner — tampil di atas quick topics
// ══════════════════════════════════════════════════════════════════════════════
class _ModelStatusBanner extends StatelessWidget {
  final String icon;
  final String message;
  final Color color;
  final KmColors c;
  final VoidCallback? onTap;
  const _ModelStatusBanner({
    required this.icon,
    required this.message,
    required this.color,
    required this.c,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (onTap != null)
            Icon(Icons.arrow_forward_ios_rounded, size: 12, color: color),
        ]),
      ),
    );
  }
}
