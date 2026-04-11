// lib/features/chat/chat_screen.dart
// KanMon GO — AI Chat Screen (PocketPal Style Lengkap)
//
// Fitur:
//   • Offline AI via LlamaService (llama.cpp JNI, streaming token)
//   • Online AI via PuterAiService
//   • Bulk API via BulkApiService
//   • ModelStatusChip di AppBar title
//   • Context usage bar (hijau/oranye/merah)
//   • TypingIndicator animasi 3 dot staggered
//   • MessageBubble dengan long-press BottomSheet
//   • MarkdownContent + code block copy button
//   • STT (speech_to_text) via mic button
//   • OCR via image_picker + google_mlkit_text_recognition
//   • Export .txt / .md via share_plus
//   • Stop button merah saat generating
//   • WelcomeCard + EmptyModelWidget
//   • AiSourcePickerButton wajib di AppBar
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kanmongo/core/ai/llama_context.dart' as llama_ctx;
import 'package:kanmongo/core/ai/inference_params_provider.dart';
import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/data/models/chat_models.dart' as chat_models;
import 'package:kanmongo/data/services/ai_service.dart';
import 'package:kanmongo/data/services/llama_service.dart';
import 'package:kanmongo/data/services/puter_ai_service.dart';
import 'package:kanmongo/data/services/bulk_api_service.dart';
import 'package:kanmongo/data/services/model_manager_service.dart';
import 'package:kanmongo/shared/widgets/ai_source_picker.dart';
import 'package:kanmongo/shared/widgets/back_handler.dart';
import 'package:kanmongo/features/settings/presentation/screens/model_manager_screen.dart';
import 'package:kanmongo/features/chat/widgets/attachment_chip_row.dart';
import 'package:kanmongo/features/chat/widgets/attachment_picker_sheet.dart';
import 'package:kanmongo/features/chat/widgets/attachment_preview.dart';
import 'package:kanmongo/features/chat/widgets/chat_history_drawer.dart';
import 'package:kanmongo/features/chat/providers/chat_session_provider.dart';
import 'package:kanmongo/features/chat/widgets/artifact_panel.dart';
import 'package:kanmongo/features/chat/widgets/code_block_widget.dart';
import 'package:kanmongo/features/chat/widgets/file_edit_response_widget.dart';
import 'package:kanmongo/data/models/chat_models.dart' as new_models;
import 'package:kanmongo/data/services/history_service.dart';
import 'package:kanmongo/features/chat/widgets/web_research_sources_card.dart';
import 'package:kanmongo/data/services/web_research_service.dart';
import 'package:kanmongo/shared/utils/top_snack.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CHAT SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class ChatScreen extends ConsumerStatefulWidget {
  final new_models.ChatSession? initialSession;
  const ChatScreen({super.key, this.initialSession});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with TickerProviderStateMixin {
  // ── Controllers ──────────────────────────────────────────────────────────
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _scrollCtrl  = ScrollController();
  final _inputCtrl   = TextEditingController();
  final _focusNode   = FocusNode();

  // Sesi aktif untuk drawer (model baru ChatSession)
  new_models.ChatSession _currentSession = new_models.ChatSession.empty();

  // ── Speech to Text ────────────────────────────────────────────────────────
  final _speech     = SpeechToText();
  bool _isListening = false;

  // ── Animasi typing indicator ──────────────────────────────────────────────
  late AnimationController _typingAnimCtrl;

  // ── State generating ──────────────────────────────────────────────────────
  bool   _isGenerating            = false;
  bool   _showRawText             = false; // toggle markdown/raw
  StreamSubscription<String>? _genSub;
  bool _genSubLocked = false;  // B-003: blokir concurrent cancel
  Timer? _autoSaveTimer; // D-008: debounce autosave
  Timer? _debounceTimer; // B-008: debounce timer
  Timer? _searchDebounce; // B-008: search debounce

  // ── File edit result (shown below last AI message after offline generation) ─
  FileEditResult? _pendingFileEditResult;

  // ── OCR ───────────────────────────────────────────────────────────────────
  bool _isProcessingOcr = false;

  // ── Web Research state ────────────────────────────────────────────────────
  bool _webResearchEnabled = false;
  bool _autoDetectSearch = true;
  String _researchStatus = '';
  List<ResearchSource> _lastSources = [];
  String _searchEngine = 'ddg';
  bool _fetchContent = true;

  // ── Pending Attachments (Sesi 2) ───────────────────────────────────────────
  List<chat_models.ChatAttachment> _pendingAttachments = [];
  // Map dari message.id → daftar attachments yang dilampirkan pada pesan itu
  final Map<String, List<chat_models.ChatAttachment>> _messageAttachments = {};

  // ── Chat Edit Mode Settings ──────────────────────────────────────────────
  ChatEditMode _editMode = ChatEditMode.adaptive;

  // ── Adaptive Edit Pipeline state ─────────────────────────────────────────
  AdaptiveEditPhase? _adaptivePhase;
  String _adaptiveStatus = '';

  // ── Web Research Sources per-pesan (index → sources) ──────────────────────
  final Map<int, List<ResearchSource>> _messageWebSources = {};

  // ── Route argument guard (6A-ii) ──────────────────────────────────────────
  bool _sessionLoaded = false;
  // ── E-002: loading session state ──────────────────────────────────────────
  bool _isLoadingSession = false;

  // ── Attachment chip row key (6B-i) ────────────────────────────────────────
  final _chipRowKey = GlobalKey<AttachmentChipRowState>();

  // ── Rename sesi (6B-ii) ───────────────────────────────────────────────────
  final _renameCtrl = TextEditingController();

  // ── Artifact Panel ─────────────────────────────────────────────────────────
  final _artifactCtrl = ArtifactPanelController();

  @override
  void initState() {
    super.initState();
    _typingAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    _loadEditMode();
    // Load initial session jika diberikan dari route argument
    if (widget.initialSession != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadSessionFromHistory(widget.initialSession!);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is new_models.ChatSession && !_sessionLoaded) {
      _sessionLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(chatSessionProvider.notifier).loadSession(arg);
        _scrollToBottom();
      });
    }
  }

  @override
  void dispose() {
    // Cancel stream subscription
    _genSub?.cancel();
    _genSub = null;
    // Cancel timers — B-008
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _searchDebounce?.cancel();
    _searchDebounce = null;
    // Stop llama jika masih generating
    if (_isGenerating) {
      LlamaService.instance.stopGeneration().catchError((_) {});
    }
    // Dispose controllers
    _scrollCtrl.dispose();
    _inputCtrl.dispose();
    _focusNode.dispose();
    _typingAnimCtrl.dispose();
    _renameCtrl.dispose();
    _artifactCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final messages  = ref.watch(chatSessionProvider).messages;
    final aiMode    = ref.watch(aiSourceProvider);
    final isOffline = (aiMode?.mode ?? AiService.instance.currentMode) == AiMode.offline;
    final modelLoaded = LlamaService.instance.isModelLoaded;

    // Tampilkan EmptyModelWidget jika mode offline tapi belum ada model
    final showEmptyModel = isOffline && !modelLoaded && messages.isEmpty;

    return ConfirmExitBack(
      message: 'Yakin ingin keluar dari chat?',
      child: Scaffold(
        key: _scaffoldKey,
        drawer: ChatHistoryDrawer(
          currentSession: _currentSession,
          onSessionSelected: _loadSessionFromHistory,
          onNewChat: _startNewChat,
        ),
        appBar: _buildAppBar(),
        body: ListenableBuilder(
          listenable: _artifactCtrl,
          builder: (context, _) {
            final panelOpen = _artifactCtrl.isOpen;
            return Stack(
              children: [
                Row(
                  children: [
                    // ── Chat column ──────────────────────────────────────────────
                    Expanded(
                      child: Column(
                        children: [
                          if (modelLoaded) _buildContextUsageBar(),
                          // Show adaptive pipeline status bar when running
                          if (_adaptivePhase != null && _adaptivePhase != AdaptiveEditPhase.done)
                            _AdaptiveStatusBar(
                              phase: _adaptivePhase!,
                              status: _adaptiveStatus,
                            ),
                          Expanded(
                            child: showEmptyModel
                                ? _EmptyModelWidget(onSwitchOnline: _switchToOnlineMode)
                                : _buildMessageList(messages),
                          ),
                          _buildInputArea(),
                        ],
                      ),
                    ),
                    // ── Artifact panel ───────────────────────────────────────────
                    if (panelOpen)
                      ArtifactPanel(
                        controller: _artifactCtrl,
                        width: MediaQuery.of(context).size.width > 900 ? 440 : 340,
                      ),
                  ],
                ),
                // ── E-002: Loading overlay saat load session dari drawer ──────
                if (_isLoadingSession)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black38,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // APP BAR
  // ─────────────────────────────────────────────────────────────────────────

  AppBar _buildAppBar() {
    final kfc = KmColors.of(context);
    final sessionTitle = _currentSession.title;
    final displayTitle = sessionTitle.length > 22
        ? '${sessionTitle.substring(0, 22)}…'
        : sessionTitle;
    return AppBar(
      backgroundColor: kfc.bg,
      foregroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 8,
      leading: IconButton(
        icon: const Icon(Icons.menu_rounded),
        tooltip: 'Riwayat Chat',
        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
      ),
      title: GestureDetector(
        onTap: _showRenameDialog,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sessionTitle.isEmpty ? 'Chat Baru' : displayTitle,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: kfc.text,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            Text(
              _getModeLabel(),
              style: TextStyle(fontSize: 11, color: kfc.textSub),
            ),
          ],
        ),
      ),
      actions: [
        // Konter token/detik — muncul saat generating
        if (_isGenerating) _TokensPerSecCounter(isGenerating: _isGenerating),
        // Tombol Terminal
        IconButton(
          icon: const Icon(Icons.terminal_rounded),
          tooltip: 'Terminal',
          onPressed: () => context.push('/terminal'),
        ),
        // ── Edit Mode Settings button ────────────────────────────────────
        _EditModeButton(
          mode: _editMode,
          onTap: _showEditModeSheet,
        ),
        // Wajib: AI Source Picker
        AiSourcePickerButton(),
        // Menu ⋮
        _ChatMenuButton(
          onNewChat:    _newChat,
          onClearChat:  _clearChatWithConfirm,
          onExportTxt:  _exportTxt,
          onExportMd:   _exportMd,
          onCopyAll:    _copyAll,
          onAiSettings: _openAiSettings,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONTEXT USAGE BAR
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildContextUsageBar() {
    final messages   = ref.watch(chatSessionProvider).messages;
    final modelConfig = ref.watch(modelConfigProvider);
    final usage = LlamaService.instance.getContextUsagePercent(
      messages.map((m) => llama_ctx.ChatMessage(
        id: m.id,
        role: m.role == 'user' ? llama_ctx.ChatRole.user
            : m.role == 'assistant' ? llama_ctx.ChatRole.assistant
            : llama_ctx.ChatRole.system,
        content: m.content,
        timestamp: m.createdAt,
      )).toList(),
    ) / 100.0;

    // Warna berdasarkan persentase
    Color barColor;
    if (usage < 0.60) {
      barColor = Colors.green;
    } else if (usage < 0.85) {
      barColor = Colors.orange;
    } else {
      barColor = Colors.red;
    }

    final totalChars   = messages.fold<int>(0, (s, m) => s + m.content.length);
    final estTokens    = (totalChars / 4).ceil();
    final tooltipLabel =
        'Konteks: ${(usage * 100).toStringAsFixed(0)}% terpakai '
        '($estTokens/${modelConfig.contextSize} token)';

    return Tooltip(
      message: tooltipLabel,
      child: LinearProgressIndicator(
        value: usage,
        minHeight: 3,
        backgroundColor: Colors.transparent,
        valueColor: AlwaysStoppedAnimation<Color>(barColor),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MESSAGE LIST
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildMessageList(List<chat_models.ChatMessage> messages) {
    if (messages.isEmpty) {
      return _EmptyStateChat(
        onAnalyzeImage: _showAttachmentPicker,
        onReviewCode: () {
          _inputCtrl.text = 'Tolong review kode ini:\n';
          _focusNode.requestFocus();
          setState(() {});
        },
        onWebSearch: () => setState(() => _webResearchEnabled = true),
        onHelpWrite: () => _focusNode.requestFocus(),
      );
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: messages.length + (_isGenerating ? 1 : 0),
      itemBuilder: (context, index) {
        // Typing indicator di akhir saat generating
        if (_isGenerating && index == messages.length) {
          return _TypingIndicator(
            animCtrl: _typingAnimCtrl,
            researchStatus: _researchStatus,
          );
        }
        final msg = messages[index];
        final isLastAssistant = msg.role == 'assistant' &&
            messages.where((m) => m.role == 'assistant').last.id == msg.id;

        final bubble = _MessageBubble(
          message:        msg,
          showRawText:    _showRawText,
          attachments:    _messageAttachments[msg.id] ?? const [],
          isLastUser:     msg.role == 'user' &&
              messages.where((m) => m.role == 'user').last.id == msg.id,
          isLastAssistant: isLastAssistant,
          onDelete:       () => _deleteMessage(msg.id),
          onResend:       () => _resendMessage(msg),
          onRegenerate:   () => _regenerateLast(),
          onToggleRaw:    () => setState(() => _showRawText = !_showRawText),
          webSources:     _messageWebSources[index],
          webResearchQuery: _getPreviousUserMessage(index),
          artifactCtrl:   _artifactCtrl,
        );

        // Show FileEditResponseWidget below the last AI message when pending
        if (isLastAssistant && _pendingFileEditResult != null && !_isGenerating) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              bubble,
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
                child: FileEditResponseWidget(result: _pendingFileEditResult!),
              ),
            ],
          );
        }

        return bubble;
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STOP BUTTON
  // ─────────────────────────────────────────────────────────────────────────

  // ─────────────────────────────────────────────────────────────────────────
  // INPUT AREA
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildInputArea() {
    final kfc = KmColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: kfc.surface,
        border: Border(top: BorderSide(color: kfc.borderSoft, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Banner Web Research
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: _webResearchEnabled ? 32 : 0,
            child: _webResearchEnabled
                ? Container(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Icon(Icons.travel_explore_rounded,
                            size: 14,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Web Research aktif',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        if (_researchStatus.isNotEmpty)
                          Text(
                            _researchStatus,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.5),
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          // Attachment chips — tampil jika ada pending attachments
          if (_pendingAttachments.isNotEmpty)
            AttachmentChipRow(
              key: _chipRowKey,
              attachments: _pendingAttachments,
              onRemove: (index) {
                _chipRowKey.currentState?.removeItem(
                  index,
                  _pendingAttachments[index],
                );
                setState(() => _pendingAttachments.removeAt(index));
              },
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Tombol Web Research (36x36)
              GestureDetector(
                onTap: () => setState(() => _webResearchEnabled = !_webResearchEnabled),
                onLongPress: _showWebResearchSettings,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _webResearchEnabled
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
                        : Colors.transparent,
                    border: Border.all(
                      color: _webResearchEnabled
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline.withOpacity(0.3),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.travel_explore_rounded,
                    size: 18,
                    color: _webResearchEnabled
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Tombol "+" lampiran
              _buildAttachButton(kfc),
              const SizedBox(width: 6),
              // TextField input
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: kfc.inputFill,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kfc.borderSoft),
                  ),
                  child: TextField(
                    controller: _inputCtrl,
                    focusNode:  _focusNode,
                    maxLines:   6,
                    minLines:   1,
                    style: TextStyle(color: kfc.text, fontSize: 14),
                    decoration: InputDecoration(
                      hintText:       'Ketik pesan...',
                      hintStyle:      TextStyle(color: kfc.textMuted, fontSize: 14),
                      border:         InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.newline,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Mic (teks kosong) atau Send (ada teks)
              _buildActionButton(kfc),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttachButton(KmColors kfc) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: _isProcessingOcr
          ? Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: kfc.accent,
                ),
              ),
            )
          : IconButton(
              icon: Icon(Icons.add_circle_outline_rounded, color: kfc.textSub, size: 22),
              tooltip: 'Lampirkan file',
              onPressed: _isGenerating ? null : _showAttachmentPicker,
            ),
    );
  }

  void _showWebResearchSettings() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Pengaturan Web Research',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              SwitchListTile(
                title: const Text('Auto-detect query'),
                subtitle: const Text(
                    'Otomatis cari web untuk pertanyaan tentang berita/harga/terbaru'),
                value: _autoDetectSearch,
                onChanged: (v) {
                  setModalState(() => _autoDetectSearch = v);
                  setState(() => _autoDetectSearch = v);
                },
              ),
              SwitchListTile(
                title: const Text('Baca konten halaman'),
                subtitle: const Text(
                    'Fetch & baca isi halaman (lebih akurat, lebih lambat)'),
                value: _fetchContent,
                onChanged: (v) {
                  setModalState(() => _fetchContent = v);
                  setState(() => _fetchContent = v);
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: DropdownButtonFormField<String>(
                  value: _searchEngine,
                  decoration: const InputDecoration(
                    labelText: 'Search Engine',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'ddg', child: Text('DuckDuckGo')),
                    DropdownMenuItem(value: 'google', child: Text('Google')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setModalState(() => _searchEngine = v);
                      setState(() => _searchEngine = v);
                    }
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ElevatedButton.icon(
                  onPressed: () {
                    WebResearchService.instance.clearCache();
                    Navigator.pop(ctx);
                    showTopSnack(context, 'Cache web research dibersihkan');
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Bersihkan Cache'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showAttachmentPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AttachmentPickerSheet(
        onAttachmentsPicked: (atts) {
          final startIndex = _pendingAttachments.length;
          setState(() => _pendingAttachments.addAll(atts));
          // Trigger slide-in animasi untuk setiap attachment baru
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final total = _pendingAttachments.length;
            final displayCount = total > 5 ? 4 : total;
            for (var i = startIndex; i < displayCount; i++) {
              _chipRowKey.currentState?.addItem(i);
            }
          });
        },
      ),
    );
  }

  Widget _buildActionButton(KmColors kfc) {
    // ── Stop button (saat AI sedang generate) ────────────────────────────────
    if (_isGenerating) {
      return GestureDetector(
        onTap: _stopGeneration,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: kfc.wrong,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.circular(3)),
              ),
            ),
          ),
        ),
      );
    }

    final hasText = _inputCtrl.text.trim().isNotEmpty;
    if (hasText) {
      // Tombol kirim
      return GestureDetector(
        onTap: _sendMessage,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: kfc.accent,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
        ),
      );
    } else {
      // Tombol mic
      return GestureDetector(
        onTap: _toggleSpeech,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _isListening ? Colors.red : kfc.card,
            shape: BoxShape.circle,
            border: Border.all(
              color: _isListening ? Colors.red : kfc.borderSoft,
            ),
          ),
          child: Icon(
            _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
            color: _isListening ? Colors.white : kfc.textSub,
            size: 20,
          ),
        ),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LOGIC: SEND MESSAGE
  // ─────────────────────────────────────────────────────────────────────────

  // ── Helper: ganti pesan asisten terakhir ─────────────────────────────────
  void _replaceLastWith(String content) {
    ref.read(chatSessionProvider.notifier).replaceLastAssistantMessage(
      chat_models.ChatMessage(
        id: const Uuid().v4(),
        role: 'assistant',
        content: content,
        createdAt: DateTime.now(),
        isError: true,
      ),
    );
  }

  Future<void> _sendMessage() async {
    // Capture BEFORE any clearing — B1
    final rawInputText        = _inputCtrl.text.trim();
    final attachmentsSnapshot = List<chat_models.ChatAttachment>.from(_pendingAttachments);

    if (rawInputText.isEmpty && attachmentsSnapshot.isEmpty) return;
    if (_isGenerating) return;

    // Clear previous file edit result when user sends a new message
    if (_pendingFileEditResult != null) {
      setState(() { _pendingFileEditResult = null; });
    }

    // ── Adaptive Edit Mode: full pipeline — B3 ──────────────────────────────
    if (_editMode == ChatEditMode.adaptive && attachmentsSnapshot.isNotEmpty) {
      setState(() {
        _pendingAttachments = [];
        _isGenerating       = true;
      });
      _inputCtrl.clear();

      await _runAdaptiveEditPipeline(
        userRequest:  rawInputText,
        attachments:  attachmentsSnapshot,
        historyForAi: _buildHistoryForAi(),
      );
      return;
    }

    // ── Normal path: clear state ─────────────────────────────────────────────
    _inputCtrl.clear();
    setState(() {
      _pendingAttachments = [];
      _isGenerating       = true;
    });

    // ── Build augmented prompt: teks + konten file (text-based) ─────────────
    String fullPrompt = rawInputText;

    for (final att in attachmentsSnapshot) {
      if (att.hasText) {
        final snippet = att.extractedText!.length > 8000
            ? att.extractedText!.substring(0, 8000)
            : att.extractedText!;
        fullPrompt += '\n\n---\n📎 [${att.filename}]\n```\n$snippet\n```';
      }
    }

    String effectiveText = fullPrompt.isEmpty ? '(file dilampirkan)' : fullPrompt;

    // ── Default mode with attachments — B5 ───────────────────────────────────
    if (_editMode == ChatEditMode.defaultMode && attachmentsSnapshot.isNotEmpty) {
      effectiveText = '$rawInputText\n\n'
          '[Direct execution mode: provide the complete result without explanation]';
    }

    final String augmentedText = effectiveText;

    // ── 1. User message ──────────────────────────────────────────────────────
    final userMsg = chat_models.ChatMessage(
      id: const Uuid().v4(),
      role: 'user',
      content: augmentedText,
      createdAt: DateTime.now(),
    );
    ref.read(chatSessionProvider.notifier).addMessage(userMsg);

    if (attachmentsSnapshot.isNotEmpty) {
      _messageAttachments[userMsg.id] = attachmentsSnapshot;
    }

    // ── 2. Placeholder AI (streaming) ────────────────────────────────────────
    ref.read(chatSessionProvider.notifier).addMessage(chat_models.ChatMessage(
      id: const Uuid().v4(),
      role: 'assistant',
      content: '',
      createdAt: DateTime.now(),
      isStreaming: true,
    ));
    _scrollToBottom();

    // ── 3. Pilih mode & build history ────────────────────────────────────────
    final choice  = ref.read(aiSourceProvider);
    final history = ref.read(chatSessionProvider).messages
        .where((m) => m.content.isNotEmpty && m.role != 'system')
        .toList()
        .reversed
        .skip(2)            // skip placeholder + user terbaru
        .toList()
        .reversed
        .take(10)
        .map((m) => <String, dynamic>{
              'role':    m.role == 'user' ? 'user' : 'assistant',
              'content': m.content,
            })
        .toList();

    // ── 4. Cek apakah perlu web search ───────────────────────────────────────
    final shouldSearch = _webResearchEnabled ||
        (_autoDetectSearch &&
            attachmentsSnapshot.isEmpty &&
            WebResearchService.instance.needsWebSearch(augmentedText));

    try {
      if (shouldSearch) {
        await _generateWithWebResearch(augmentedText, choice);
      } else if (attachmentsSnapshot.isNotEmpty) {
        // Coba route ke BulkApi/Offline dengan attachment support
        final mode = choice?.mode ?? AiService.instance.currentMode;
        if (mode == AiMode.bulkApi) {
          final payloads = await _buildPayloads(attachmentsSnapshot);
          await _generateBulkApi(augmentedText, choice, payloads: payloads);
        } else if (mode == AiMode.offline) {
          final payloads = await _buildPayloads(attachmentsSnapshot);
          await _generateOffline(payloads: payloads);
        } else {
          // Delegasikan ke vision handler (online/puter)
          await _generateWithVision(rawInputText, attachmentsSnapshot, choice);
        }
      } else {
        final mode = choice?.mode ?? AiService.instance.currentMode;
        switch (mode) {
          case AiMode.offline:
            await _generateOffline();
          case AiMode.online:
            await _generateOnline(augmentedText);
          case AiMode.bulkApi:
            await _generateBulkApi(augmentedText, choice);
          default:
            _replaceLastWith(
              '❌ Tidak ada sumber AI yang tersedia.\n\n'
              'Pilih sumber AI lewat tombol di AppBar, atau aktifkan salah satu mode di Settings.',
            );
        }
      }
    } catch (e) {
      debugPrint('[ChatScreen] _sendMessage error: $e');
      _replaceLastWith('❌ Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _isGenerating = false);

      // ── Auto-generate title dari pesan pertama ───────────────────────────
      final msgs = ref.read(chatSessionProvider).messages;
      if ((_currentSession.title == 'Chat Baru' || _currentSession.title.isEmpty) &&
          msgs.length >= 2) {
        final firstUser = msgs.firstWhere(
          (m) => m.role == 'user' && m.content.isNotEmpty,
          orElse: () => msgs.first,
        );
        final raw   = firstUser.content.trim().replaceAll('\n', ' ');
        final title = raw.length > 50 ? '${raw.substring(0, 50)}…' : raw;
        if (mounted) setState(() => _currentSession = _currentSession.copyWith(title: title));
      }

      // ── Auto-save ────────────────────────────────────────────────────────
      unawaited(_autoSaveCurrentSession(ref.read(chatSessionProvider).messages));
    }
  }

  // ─── Helper: build AI history from current session ────────────────────────

  List<Map<String, String>> _buildHistoryForAi() {
    final messages = ref.read(chatSessionProvider).messages;
    return messages
        .where((m) => m.role != 'system' && m.content.isNotEmpty)
        .take(12)
        .map((m) => <String, String>{
              'role':    m.role == 'user' ? 'user' : 'assistant',
              'content': m.content,
            })
        .toList();
  }

  // ─── Adaptive Edit Pipeline ───────────────────────────────────────────────

  Future<void> _runAdaptiveEditPipeline({
    required String userRequest,
    required List<chat_models.ChatAttachment> attachments,
    required List<Map<String, String>> historyForAi,
  }) async {
    if (!mounted) return;

    // Add user message to chat
    final userMsg = chat_models.ChatMessage(
      id: const Uuid().v4(),
      role: 'user',
      content: userRequest,
      createdAt: DateTime.now(),
    );
    ref.read(chatSessionProvider.notifier).addMessage(userMsg);
    if (attachments.isNotEmpty) {
      _messageAttachments[userMsg.id] = attachments;
    }
    setState(() {
      _isGenerating   = true;
      _adaptivePhase  = AdaptiveEditPhase.analyzing;
      _adaptiveStatus = 'Memulai adaptive edit...';
    });
    _scrollToBottom();

    // Add placeholder assistant message
    ref.read(chatSessionProvider.notifier).addMessage(chat_models.ChatMessage(
      id: const Uuid().v4(),
      role: 'assistant',
      content: '',
      createdAt: DateTime.now(),
      isStreaming: true,
    ));

    final buffer = StringBuffer();

    try {
      await for (final event in AiService.instance.executeAdaptiveEdit(
        userRequest: userRequest,
        attachments: attachments,
        history:     historyForAi,
      )) {
        if (!mounted) break;

        switch (event.phase) {
          case AdaptiveEditPhase.analyzing:
          case AdaptiveEditPhase.researching:
          case AdaptiveEditPhase.planning:
            setState(() {
              _adaptivePhase  = event.phase;
              _adaptiveStatus = event.statusText ?? '';
            });
            break;

          case AdaptiveEditPhase.executing:
            if (event.token != null && event.token!.isNotEmpty) {
              buffer.write(event.token);
              ref.read(chatSessionProvider.notifier)
                  .updateLastAssistantMessage(event.token!);
              setState(() {
                _adaptivePhase  = AdaptiveEditPhase.executing;
                _adaptiveStatus = '⚙️ AI sedang mengeksekusi edit...';
              });
              _scrollToBottom();
            }
            break;

          case AdaptiveEditPhase.done:
            setState(() {
              _adaptivePhase  = null;
              _adaptiveStatus = '';
              _isGenerating   = false;
            });
            break;

          case AdaptiveEditPhase.error:
            final errText = event.errorText ?? '❌ Unknown error';
            ref.read(chatSessionProvider.notifier)
                .replaceLastAssistantMessage(chat_models.ChatMessage(
                  id: const Uuid().v4(),
                  role: 'assistant',
                  content: errText,
                  createdAt: DateTime.now(),
                  isError: true,
                ));
            setState(() {
              _adaptivePhase  = null;
              _adaptiveStatus = '';
              _isGenerating   = false;
            });
            break;
        }
      }
    } catch (e) {
      debugPrint('[ChatScreen] _runAdaptiveEditPipeline error: $e');
      if (mounted) {
        setState(() {
          _adaptivePhase  = null;
          _adaptiveStatus = '';
          _isGenerating   = false;
        });
        _showSnackbar('❌ Error pipeline: $e');
      }
    } finally {
      if (mounted && _isGenerating) {
        setState(() => _isGenerating = false);
      }
      unawaited(_autoSaveCurrentSession(ref.read(chatSessionProvider).messages));
    }
  }

  // ─── Vision: attachment gambar via sendWithAttachments ───────────────────

  Future<void> _generateWithVision(
    String userText,
    List<chat_models.ChatAttachment> attachments,
    dynamic sourceChoice,
  ) async {
    try {
      final messages     = ref.read(chatSessionProvider).messages;
      final systemPrompt = ref.read(systemPromptProvider) ?? '';
      final history = messages
          .where((m) => m.content.isNotEmpty &&
              messages.indexOf(m) < messages.length - 2)
          .map((m) => {
                'role': m.role == 'user' ? 'user' : 'assistant',
                'content': m.content,
              })
          .toList();

      final aiMode         = sourceChoice?.mode as AiMode? ?? AiService.instance.currentMode;
      final forceBulkKeyId = sourceChoice?.bulkKeyId as String?;
      final forceProvider  = sourceChoice?.bulkProvider as BulkApiProvider?;

      _genSub = AiService.instance
          .sendWithAttachments(
            userText:       userText,
            attachments:    attachments,
            history:        history,
            forceMode:      aiMode,
            forceBulkKeyId: forceBulkKeyId,
            forceProvider:  forceProvider,
          )
          .listen(
        (token) {
          ref.read(chatSessionProvider.notifier).updateLastAssistantMessage(token);
          _scrollToBottom();
        },
        onDone: () {
          if (!mounted) return;
          setState(() { _isGenerating = false; });
          _genSub = null;
          _autoSaveCurrentSession(ref.read(chatSessionProvider).messages);
        },
        onError: (Object e) {
          if (!mounted) return;
          ref.read(chatSessionProvider.notifier).replaceLastAssistantMessage(
            chat_models.ChatMessage(
              id: const Uuid().v4(),
              role: 'assistant',
              content: '❌ Vision error: $e',
              createdAt: DateTime.now(),
              isError: true,
            ),
          );
          setState(() { _isGenerating = false; });
          _genSub = null;
        },
      );
    } catch (e) {
      debugPrint('[ChatScreen] _generateWithVision error: $e');
      if (!mounted) return;
      ref.read(chatSessionProvider.notifier).replaceLastAssistantMessage(
          chat_models.ChatMessage(
            id: const Uuid().v4(),
            role: 'assistant',
            content: '❌ Error: $e',
            createdAt: DateTime.now(),
            isError: true,
          ),
        );
      setState(() { _isGenerating = false; });
    }
  }

  // ─── Web Research: via AiService.sendWithWebResearch ─────────────────────

  Future<void> _generateWithWebResearch(
    String userText,
    AiSourceChoice? sourceChoice,
  ) async {
    List<ResearchSource> receivedSources = [];

    try {
      final messages     = ref.read(chatSessionProvider).messages;
      final aiMode         = sourceChoice?.mode ?? AiService.instance.currentMode;
      final forceBulkKeyId = sourceChoice?.bulkKeyId;
      final forceProvider  = sourceChoice?.bulkProvider;

      // Build history: semua pesan kecuali 2 terakhir (user baru + placeholder)
      final allMsgs = messages
          .where((m) => m.role != 'system')
          .toList();
      final histList = allMsgs.length > 2
          ? allMsgs.sublist(0, allMsgs.length - 2)
          : <chat_models.ChatMessage>[];
      final historyMaps = histList
          .map((m) => {
                'role': m.role == 'user' ? 'user' : 'assistant',
                'content': m.content,
              })
          .toList();

      final stream = AiService.instance.sendWithWebResearch(
        userQuery: userText,
        history: historyMaps,
        onResearchProgress: (status) {
          if (mounted) setState(() => _researchStatus = status);
        },
        searchEngine: _searchEngine,
        fetchContent: _fetchContent,
        forceMode: aiMode,
        forceBulkKeyId: forceBulkKeyId,
        forceProvider: forceProvider,
      );

      await for (final event in stream) {
        if (!mounted) break;

        switch (event.type) {
          case WebResearchEventType.status:
            setState(() => _researchStatus = event.statusText ?? '');
            break;

          case WebResearchEventType.sources:
            receivedSources = event.sources ?? [];
            setState(() => _lastSources = receivedSources);
            break;

          case WebResearchEventType.token:
            ref.read(chatSessionProvider.notifier).updateLastAssistantMessage(
              event.tokenText ?? '',
            );
            _scrollToBottom();
            break;

          case WebResearchEventType.done:
            final currentMessages = ref.read(chatSessionProvider).messages;
            final lastIdx = currentMessages.length - 1;
            if (lastIdx >= 0 && receivedSources.isNotEmpty) {
              setState(() {
                _messageWebSources[lastIdx] = receivedSources;
              });
            }
            setState(() {
              _researchStatus = '';
              _isGenerating   = false;
            });
            _autoSaveCurrentSession(ref.read(chatSessionProvider).messages);
            break;
        }
      }
    } on TimeoutException catch (e) {
      // B-007 fix: handle timeout agar UI tidak stuck
      debugPrint('[ChatScreen] _generateWithWebResearch timeout: $e');
      if (mounted) {
        ref.read(chatSessionProvider.notifier).replaceLastAssistantMessage(
          chat_models.ChatMessage(
            id: const Uuid().v4(),
            role: 'assistant',
            content: '⏰ Web research timeout. Silakan coba lagi.',
            createdAt: DateTime.now(),
            isError: true,
          ),
        );
        setState(() {
          _researchStatus = '';
          _isGenerating   = false;
        });
      }
    } catch (e) {
      debugPrint('[ChatScreen] _generateWithWebResearch error: $e');
      if (mounted) {
        ref.read(chatSessionProvider.notifier).replaceLastAssistantMessage(
          chat_models.ChatMessage(
            id: const Uuid().v4(),
            role: 'assistant',
            content: '❌ Web research error: $e',
            createdAt: DateTime.now(),
            isError: true,
          ),
        );
        setState(() {
          _researchStatus = '';
          _isGenerating   = false;
        });
      }
    }
  }

  Future<void> _generateOffline({List<ChatAttachmentPayload> payloads = const []}) async {
    // ── Guard: model must be loaded ───────────────────────────────────────────
    // If model is still loading (e.g., auto-load in progress at startup),
    // wait up to 30 seconds for it to finish before giving up.
    if (!LlamaService.instance.isModelLoaded) {
      if (LlamaService.instance.status == llama_ctx.ModelStatus.loading) {
        debugPrint('[ChatScreen] _generateOffline: model is loading — waiting up to 30s');
        bool didLoad = false;
        for (int i = 0; i < 60; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
          if (LlamaService.instance.isModelLoaded) { didLoad = true; break; }
          if (LlamaService.instance.status == llama_ctx.ModelStatus.error) break;
        }
        if (!didLoad) {
          if (mounted) {
            ref.read(chatSessionProvider.notifier).replaceLastAssistantMessage(
          chat_models.ChatMessage(
            id: const Uuid().v4(),
            role: 'assistant',
            content: '⚠️ Model AI gagal dimuat.\n\nBuka Settings → Model Manager untuk memilih model .gguf.',
            createdAt: DateTime.now(),
            isError: true,
          ),
        );
            setState(() { _isGenerating = false; });
          }
          return;
        }
      } else {
        ref.read(chatSessionProvider.notifier).replaceLastAssistantMessage(
          chat_models.ChatMessage(
            id: const Uuid().v4(),
            role: 'assistant',
            content: '⚠️ Model AI belum dimuat.\n\nBuka Settings → Model Manager untuk memilih dan memuat model.',
            createdAt: DateTime.now(),
            isError: true,
          ),
        );
        setState(() { _isGenerating = false; });
        return;
      }
    }

    final messages     = ref.read(chatSessionProvider).messages;
    final config       = ref.read(inferenceConfigProvider);
    final systemPrompt = ref.read(systemPromptProvider);

    // Inject file context into the last user message if payloads present
    List<chat_models.ChatMessage> msgToSend = messages
        .where((m) => m.role != 'assistant' || m.content.isNotEmpty)
        .toList();

    if (payloads.isNotEmpty) {
      final fileContext = _buildOfflineFileContext(payloads);
      final lastUserIdx = msgToSend.lastIndexWhere((m) => m.role == 'user');
      if (lastUserIdx >= 0 && fileContext.isNotEmpty) {
        final orig = msgToSend[lastUserIdx];
        msgToSend = List<chat_models.ChatMessage>.from(msgToSend);
        msgToSend[lastUserIdx] = orig.copyWith(
          content: '$fileContext${orig.content}',
        );
      }
    }

    final llamaMsgs = msgToSend.map((m) => llama_ctx.ChatMessage(
      id: m.id,
      role: m.role == 'user'
          ? llama_ctx.ChatRole.user
          : m.role == 'assistant'
              ? llama_ctx.ChatRole.assistant
              : llama_ctx.ChatRole.system,
      content: m.content,
      timestamp: m.createdAt,
    )).toList();

    _genSub = LlamaService.instance.generateStream(
      messages:             llamaMsgs,
      config:               config,
      systemPromptOverride: systemPrompt,
    ).listen(
      (token) {
        ref.read(chatSessionProvider.notifier).updateLastAssistantMessage(token);
        _scrollToBottom();
      },
      onDone: () {
        if (!mounted) return;
        setState(() { _isGenerating = false; });
        _genSub = null;
        _autoSaveCurrentSession(ref.read(chatSessionProvider).messages);

        // ── File edit result detection ───────────────────────────────────────
        // If text-based files were attached, offer to save the AI response as a file.
        if (payloads.isNotEmpty) {
          const textExts = {
            'txt', 'md', 'dart', 'py', 'js', 'ts', 'html', 'css', 'json',
            'xml', 'csv', 'kt', 'java', 'cpp', 'c', 'h', 'yaml', 'yml',
            'toml', 'ini', 'log', 'sql', 'sh', 'bat',
          };
          final textPayloads = payloads
              .where((pl) => pl.textContent != null && pl.textContent!.isNotEmpty)
              .toList();
          if (textPayloads.isNotEmpty) {
            final first = textPayloads.first;
            final ext = first.filename.contains('.')
                ? first.filename.split('.').last.toLowerCase()
                : 'txt';
            if (textExts.contains(ext)) {
              final currentMsgs = ref.read(chatSessionProvider).messages;
              final lastAi = currentMsgs.lastWhere(
                (m) => m.role == 'assistant',
                orElse: () => chat_models.ChatMessage(
      id: const Uuid().v4(),
      role: 'assistant',
      content: '',
      createdAt: DateTime.now(),
      isStreaming: true,
    ),
              );
              if (lastAi.content.isNotEmpty && mounted) {
                setState(() {
                  _pendingFileEditResult = FileEditResult(
                    originalFilename: first.filename,
                    textContent:      lastAi.content,
                    outputExtension:  ext == 'md' ? 'md' : 'txt',
                    description:      'Hasil edit AI untuk: ${first.filename}',
                  );
                });
              }
            }
          }
        }
      },
      onError: (Object e) {
        if (!mounted) return;
        ref.read(chatSessionProvider.notifier).replaceLastAssistantMessage(
          chat_models.ChatMessage(
            id: const Uuid().v4(),
            role: 'assistant',
            content: '❌ Error: $e',
            createdAt: DateTime.now(),
            isError: true,
          ),
        );
        setState(() { _isGenerating = false; });
        _genSub = null;
      },
    );
  }

  // ─── Online: via PuterAiService ───────────────────────────────────────────

  Future<void> _generateOnline(String userText) async {
    final messages     = ref.read(chatSessionProvider).messages;
    final systemPrompt = ref.read(systemPromptProvider) ?? '';

    // Bangun history dari messages (kecuali 2 terakhir: user baru + placeholder)
    final history = messages
        .where((m) => m.role != 'system')
        .toList();
    // Hapus 2 terakhir (user baru + placeholder asisten)
    final historyForApi = history.length > 2
        ? history.sublist(0, history.length - 2)
        : <chat_models.ChatMessage>[];

    final historyMaps = historyForApi
        .map((m) => {
              'role': m.role == 'user' ? 'user' : 'assistant',
              'content': m.content,
            })
        .toList();

    _genSub = PuterAiService.instance.chatStream(
      systemPrompt: systemPrompt,
      history:      historyMaps,
      userMessage:  userText,
    ).listen(
      (token) {
        ref.read(chatSessionProvider.notifier).updateLastAssistantMessage(token);
        _scrollToBottom();
      },
      onDone: () {
        if (!mounted) return;
        setState(() { _isGenerating = false; });
        _genSub = null;
        _autoSaveCurrentSession(ref.read(chatSessionProvider).messages);
      },
      onError: (Object e) {
        if (!mounted) return;
        ref.read(chatSessionProvider.notifier).replaceLastAssistantMessage(
          chat_models.ChatMessage(
            id: const Uuid().v4(),
            role: 'assistant',
            content: '❌ Error online: $e',
            createdAt: DateTime.now(),
            isError: true,
          ),
        );
        setState(() { _isGenerating = false; });
        _genSub = null;
      },
    );
  }

  // ─── Bulk API: via BulkApiService ─────────────────────────────────────────

  Future<void> _generateBulkApi(
    String userText,
    AiSourceChoice? choice, {
    List<ChatAttachmentPayload> payloads = const [],
  }) async {
    final systemPrompt = ref.read(systemPromptProvider) ?? '';
    final messages     = ref.read(chatSessionProvider).messages;

    final historyForApi = messages
        .where((m) => m.role != 'system')
        .toList();
    final histMaps = historyForApi.length > 2
        ? historyForApi
            .sublist(0, historyForApi.length - 2)
            .map((m) => {
                  'role': m.role == 'user' ? 'user' : 'assistant',
                  'content': m.content,
                })
            .toList()
        : <Map<String, String>>[];

    _genSub = BulkApiService.instance.sendChatStream(
      userMessage:       userText,
      systemPrompt:      systemPrompt,
      history:           histMaps,
      preferredProvider: choice?.bulkProvider,
      attachments:       payloads,
    ).listen(
      (token) {
        ref.read(chatSessionProvider.notifier).updateLastAssistantMessage(token);
        _scrollToBottom();
      },
      onDone: () {
        if (!mounted) return;
        setState(() { _isGenerating = false; });
        _genSub = null;
        _autoSaveCurrentSession(ref.read(chatSessionProvider).messages);
      },
      onError: (Object e) {
        if (!mounted) return;
        ref.read(chatSessionProvider.notifier).replaceLastAssistantMessage(
          chat_models.ChatMessage(
            id: const Uuid().v4(),
            role: 'assistant',
            content: '❌ Error Bulk API: $e',
            createdAt: DateTime.now(),
            isError: true,
          ),
        );
        setState(() { _isGenerating = false; });
        _genSub = null;
      },
    );
  }

  // ─── Attachment payload helpers ───────────────────────────────────────────

  Future<List<ChatAttachmentPayload>> _buildPayloads(
    List<chat_models.ChatAttachment> attachments,
  ) async {
    final payloads = <ChatAttachmentPayload>[];
    for (final att in attachments) {
      final file = File(att.path);
      if (!file.existsSync()) continue;

      final bytes = await file.readAsBytes();
      final mimeType = att.mimeType ?? _guessMime(att.path);
      final isImg = mimeType.startsWith('image/');
      final isTxt = ['text/', 'application/json', 'application/xml']
              .any((p) => mimeType.startsWith(p)) ||
          _isCodeFile(att.path);
      final isVideo = mimeType.startsWith('video/');

      String? textContent;
      if (isVideo) {
        textContent =
            '[Video file: ${att.filename}, ${_formatSize(bytes.length)}. '
            'Video playback is not supported in AI chat. '
            'Please describe what you need.]';
      } else if (isTxt) {
        textContent = utf8.decode(bytes, allowMalformed: true);
      }

      payloads.add(ChatAttachmentPayload(
        filename: att.filename,
        mimeType: mimeType,
        base64Data:
            isImg && bytes.length <= 5 * 1024 * 1024 ? base64Encode(bytes) : null,
        textContent: textContent,
        sizeBytes: bytes.length,
      ));
    }
    return payloads;
  }

  String _guessMime(String path) {
    final ext = path.split('.').last.toLowerCase();
    const map = {
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
      'gif': 'image/gif', 'webp': 'image/webp', 'bmp': 'image/bmp',
      'mp4': 'video/mp4', 'avi': 'video/avi', 'mov': 'video/quicktime',
      'txt': 'text/plain', 'md': 'text/markdown', 'json': 'application/json',
      'dart': 'text/x-dart', 'py': 'text/x-python',
      'js': 'text/javascript', 'ts': 'text/typescript',
      'html': 'text/html', 'css': 'text/css', 'xml': 'application/xml',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  bool _isCodeFile(String path) {
    const codeExts = {
      'dart', 'py', 'js', 'ts', 'kt', 'java', 'cpp', 'c', 'h',
      'swift', 'go', 'rs', 'rb', 'php', 'sh', 'bash', 'yaml',
      'yml', 'toml', 'json', 'xml', 'html', 'css', 'md', 'txt',
    };
    return codeExts.contains(path.split('.').last.toLowerCase());
  }

  String _buildOfflineFileContext(List<ChatAttachmentPayload> payloads) {
    if (payloads.isEmpty) return '';
    final sb = StringBuffer();
    sb.writeln('### Attached Files ###');
    for (final p in payloads) {
      if (p.isText && p.textContent != null) {
        sb.writeln('\n#### ${p.filename}');
        sb.writeln('```');
        sb.writeln(p.textContent!.length > 8000
            ? '${p.textContent!.substring(0, 8000)}\n...[truncated]'
            : p.textContent);
        sb.writeln('```');
      } else if (p.isImage) {
        sb.writeln('\n[Image attached: ${p.filename} — ${_formatSize(p.sizeBytes)}]');
        sb.writeln('Note: Offline AI cannot view images. Describe it in your message.');
      } else {
        sb.writeln('\n[File attached: ${p.filename} — ${_formatSize(p.sizeBytes)}]');
      }
    }
    sb.writeln('### End Attached Files ###\n');
    return sb.toString();
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // B-003: Cancel helper — blokir concurrent stream cancel
  // ─────────────────────────────────────────────────────────────────────────

  static const int _kMaxRetry = 2;
  static const Duration _kRetryDelay = Duration(seconds: 2);

  Future<void> _cancelAndClearGenSub() async {
    if (_genSubLocked) return;
    _genSubLocked = true;
    try {
      await _genSub?.cancel();
      _genSub = null;
    } finally {
      _genSubLocked = false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // B-004: Retry helper
  // ─────────────────────────────────────────────────────────────────────────

  Future<T> _withRetry<T>(
    Future<T> Function() fn, {
    int maxRetries = _kMaxRetry,
    bool Function(Object)? retryIf,
  }) async {
    int attempt = 0;
    while (true) {
      try {
        return await fn();
      } catch (e) {
        attempt++;
        final shouldRetry = retryIf != null ? retryIf(e) : true;
        if (attempt > maxRetries || !shouldRetry) rethrow;
        debugPrint('[ChatScreen] retry attempt $attempt after error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Koneksi bermasalah, mencoba ulang ($attempt/$maxRetries)...'),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.orange,
            ),
          );
        }
        await Future.delayed(_kRetryDelay * attempt);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // B-005: Error message granular
  // ─────────────────────────────────────────────────────────────────────────

  String _friendlyError(Object error) {
    final s = error.toString().toLowerCase();
    if (s.contains('socketexception') ||
        s.contains('network') ||
        s.contains('connection refused') ||
        s.contains('failed host lookup')) {
      return '❌ Tidak ada koneksi internet. Periksa jaringan Anda.';
    }
    if (s.contains('timeout') || s.contains('timeoutexception')) {
      return '⏰ Request timeout. Server lambat merespons, coba lagi.';
    }
    if (s.contains('rate limit') || s.contains('429') || s.contains('too many')) {
      return '⚡ Rate limit tercapai. Tunggu sebentar lalu coba lagi.';
    }
    if (s.contains('401') || s.contains('unauthorized') || s.contains('api key')) {
      return '🔑 API Key tidak valid. Periksa pengaturan di Settings → API.';
    }
    if (s.contains('403') || s.contains('forbidden')) {
      return '🚫 Akses ditolak. Periksa izin API Anda.';
    }
    if (s.contains('500') || s.contains('internal server') || s.contains('503')) {
      return '🔧 Server AI sedang bermasalah. Coba beberapa menit lagi.';
    }
    if (s.contains('model not loaded') || s.contains('no model')) {
      return '🤖 Model belum dimuat. Buka Settings → Offline AI untuk memuat model.';
    }
    if (s.contains('out of memory') || s.contains('oom')) {
      return '💾 Memori tidak cukup. Tutup aplikasi lain atau gunakan model lebih kecil.';
    }
    if (s.contains('context') &&
        (s.contains('exceed') || s.contains('limit') || s.contains('too long'))) {
      return '📏 Konteks terlalu panjang. Mulai chat baru atau hapus beberapa pesan lama.';
    }
    return '❗ Terjadi kesalahan: $error';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // B-009: Cek context limit sebelum generate offline
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool> _checkContextLimitBeforeGenerate(List<new_models.ChatMessage> messages) async {
    final maxCtx = ref.read(modelConfigProvider).contextSize;

    // Estimasi: 1 token ≈ 3.5 karakter
    final totalChars = messages.fold<int>(0, (sum, m) => sum + m.content.length);
    final estimatedTokens = (totalChars / 3.5).ceil();

    // Batas aman 85% dari max context
    final safeLimit = (maxCtx * 0.85).toInt();

    if (estimatedTokens <= safeLimit) return true;

    if (!mounted) return false;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ Context Hampir Penuh'),
        content: Text(
          'Estimasi token: ~$estimatedTokens\n'
          'Batas aman: $safeLimit dari $maxCtx token\n\n'
          'Respons mungkin terpotong atau model tidak stabil.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Lanjutkan'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            onPressed: () {
              final currentMsgs = ref.read(chatSessionProvider).messages;
              final kept = currentMsgs.length > 4
                  ? currentMsgs.sublist(currentMsgs.length - 4)
                  : currentMsgs;
              final currentSession = ref.read(chatSessionProvider);
              ref.read(chatSessionProvider.notifier)
                  .loadSession(currentSession.copyWith(messages: kept));
              Navigator.pop(ctx, true);
            },
            child: const Text('Trim & Lanjutkan'),
          ),
        ],
      ),
    );
    return proceed ?? false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // D-004: Hapus pesan dengan Undo
  // ─────────────────────────────────────────────────────────────────────────

  void _deleteMessageWithUndo(String id) {
    final msgs = ref.read(chatSessionProvider).messages;
    final deletedIndex = msgs.indexWhere((m) => m.id == id);
    if (deletedIndex < 0) return;
    final deletedMsg = msgs[deletedIndex];

    _deleteMessage(id);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Pesan dihapus'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () {
            final currentMsgs = List<new_models.ChatMessage>.from(
              ref.read(chatSessionProvider).messages,
            );
            final insertAt = deletedIndex.clamp(0, currentMsgs.length);
            currentMsgs.insert(insertAt, deletedMsg);
            final currentSession = ref.read(chatSessionProvider);
            ref.read(chatSessionProvider.notifier).loadSession(
              currentSession.copyWith(messages: currentMsgs),
            );
          },
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LOGIC: STOP GENERATION
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _stopGeneration() async {
    await _cancelAndClearGenSub();  // B-003: gunakan helper
    // E-006 fix: hentikan adaptive edit pipeline jika sedang berjalan
    if (_adaptivePhase != null) {
      setState(() { _adaptivePhase = null; });
    }
    await LlamaService.instance.stopGeneration();
    setState(() { _isGenerating = false; });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LOGIC: SCROLL, DELETE, RESEND, REGENERATE
  // ─────────────────────────────────────────────────────────────────────────

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

  String _getPreviousUserMessage(int assistantMsgIndex) {
    final messages = ref.read(chatSessionProvider).messages;
    if (assistantMsgIndex > 0 && assistantMsgIndex < messages.length) {
      final prev = messages[assistantMsgIndex - 1];
      if (prev.role == 'user') {
        return prev.content;
      }
    }
    return '';
  }

  void _deleteMessage(String id) {
    // D-002/D-007 fix: cleanup Maps saat pesan dihapus
    _messageAttachments.remove(id);
    _messageWebSources.removeWhere((k, v) => false); // indeks bisa bergeser, bersihkan semua stale
    ref.read(chatSessionProvider.notifier).deleteMessage(id);
  }

  Future<void> _resendMessage(_unused) async {
    final messages = ref.read(chatSessionProvider).messages;
    if (messages.isEmpty) return;
    // Ambil pesan user terakhir
    final lastUser = messages.lastWhere(
      (m) => m.role == 'user',
      orElse: () => messages.last,
    );
    _inputCtrl.text = lastUser.content;
    setState(() {});
    _focusNode.requestFocus();
  }

  Future<void> _regenerateLast() async {
    final messages = ref.read(chatSessionProvider).messages;
    if (messages.isEmpty) return;
    // Hapus pesan asisten terakhir
    final lastAssistant = messages.lastWhere(
      (m) => m.role == 'assistant',
      orElse: () => messages.last,
    );
    ref.read(chatSessionProvider.notifier).deleteMessage(lastAssistant.id);
    // Tambah ulang placeholder
    final placeholder = chat_models.ChatMessage(
      id: const Uuid().v4(),
      role: 'assistant',
      content: '',
      createdAt: DateTime.now(),
      isStreaming: true,
    );
    ref.read(chatSessionProvider.notifier).addMessage(placeholder);
    setState(() { _isGenerating = true; });
    await _generateOffline();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LOGIC: SPEECH TO TEXT
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _toggleSpeech() async {
    if (_isListening) {
      _speech.stop();
      setState(() { _isListening = false; });
      return;
    }

    final available = await _speech.initialize(
      onError: (e) => setState(() { _isListening = false; }),
    );
    if (!available) return;

    setState(() { _isListening = true; });
    _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          setState(() {
            _inputCtrl.text = result.recognizedWords;
            _isListening    = false;
          });
        }
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LOGIC: OCR (Image Picker + ML Kit)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _pickImageForOcr() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ImageSourceSheet(),
    );
    if (source == null) return;

    final picked = await picker.pickImage(source: source, imageQuality: 90);
    if (picked == null) return;

    setState(() { _isProcessingOcr = true; });
    try {
      final inputImage  = InputImage.fromFilePath(picked.path);
      final recognizer  = TextRecognizer(script: TextRecognitionScript.latin);
      final recognized  = await recognizer.processImage(inputImage);
      await recognizer.close();

      final teks = recognized.text.trim();
      if (teks.isNotEmpty) {
        _inputCtrl.text = _inputCtrl.text.isEmpty
            ? teks
            : '${_inputCtrl.text}\n\n$teks';
        setState(() {});
      } else {
        _showSnackbar('Tidak ada teks yang terdeteksi di gambar.');
      }
    } catch (e) {
      _showSnackbar('Gagal mengenali teks: $e');
    } finally {
      setState(() { _isProcessingOcr = false; });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LOGIC: MENU ACTIONS
  // ─────────────────────────────────────────────────────────────────────────

  // Subtitle AppBar: mode + nama model/provider (6B-ii)
  String _getModeLabel() {
    final aiMode = ref.read(aiSourceProvider);
    final mode = aiMode?.mode ?? AiService.instance.currentMode;
    switch (mode) {
      case AiMode.offline:
        final modelName = LlamaService.instance.currentModel?.name ?? '';
        return modelName.isNotEmpty
            ? '💾 Offline — $modelName'
            : '💾 Offline';
      case AiMode.online:
        final label = aiMode?.label ?? '';
        return label.isNotEmpty ? '🌐 Online — $label' : '🌐 Online';
      case AiMode.bulkApi:
        return '⚡ Bulk API';
      case AiMode.none:
        return '🤖 Pilih sumber AI';
    }
  }

  // Dialog rename sesi (6B-ii)
  void _showRenameDialog() {
    _renameCtrl.text = _currentSession.title;
    final kfc = KmColors.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kfc.card,
        title: Text('Ganti nama sesi', style: TextStyle(color: kfc.text)),
        content: TextField(
          controller: _renameCtrl,
          autofocus: true,
          style: TextStyle(color: kfc.text),
          decoration: InputDecoration(
            hintText: 'Nama sesi baru',
            hintStyle: TextStyle(color: kfc.textMuted),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: kfc.border),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: kfc.accent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Batal', style: TextStyle(color: kfc.textSub)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kfc.accent),
            onPressed: () {
              final newTitle = _renameCtrl.text.trim();
              if (newTitle.isNotEmpty) {
                // E-008 fix: persist ke DB via HistoryService langsung
                HistoryService.instance
                    .updateSessionTitle(_currentSession.id, newTitle)
                    .catchError((e) => debugPrint('[ChatScreen] rename error: $e'));
                ref
                    .read(chatSessionProvider.notifier)
                    .setTitle(newTitle);
                setState(() {
                  _currentSession =
                      _currentSession.copyWith(title: newTitle);
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('Simpan',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Mulai chat baru: auto-save session aktif jika ada pesan, lalu reset
  Future<void> _startNewChat() async {
    final msgs = ref.read(chatSessionProvider).messages;
    if (msgs.isNotEmpty) {
      await _autoSaveCurrentSession(msgs);
    }
    if (mounted) {
      ref.read(chatSessionProvider.notifier).clearSession();
      // D-002/D-007 fix: bersihkan Maps saat mulai chat baru
      _messageAttachments.clear();
      _messageWebSources.clear();
      setState(() {
        _pendingAttachments = [];
        _currentSession = new_models.ChatSession.empty();
      });
      _inputCtrl.clear();
    }
  }

  // Auto-save session aktif ke DB menggunakan model baru ChatSession
  // D-008 fix: debounce 2 detik agar tidak flood DB saat streaming
  Future<void> _autoSaveCurrentSession(List<chat_models.ChatMessage> msgs) async {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 2), () async {
      await _doAutoSave(msgs);
    });
  }

  Future<void> _doAutoSave(List<chat_models.ChatMessage> msgs) async {
    try {
      final now = DateTime.now();
      final title = _currentSession.title == 'Chat Baru' && msgs.isNotEmpty
          ? _generateTitleFromMessages(msgs)
          : _currentSession.title;
      final updated = _currentSession.copyWith(
        title: title,
        messages: msgs,
        updatedAt: now,
      );
      await HistoryService.instance.saveChatSession(updated);
      if (mounted) setState(() => _currentSession = updated);
    } catch (e) {
      debugPrint('[ChatScreen] _autoSaveCurrentSession error: $e');
    }
  } // end _doAutoSave

  String _generateTitleFromMessages(List<chat_models.ChatMessage> msgs) {
    final firstUser = msgs.firstWhere(
      (m) => m.role == 'user' && m.content.isNotEmpty,
      orElse: () => msgs.first,
    );
    final raw = firstUser.content.trim().replaceAll('\n', ' ');
    return raw.length > 50 ? '${raw.substring(0, 50)}…' : raw;
  }

  // Load sesi dari history drawer ke chat aktif
  Future<void> _loadSessionFromHistory(new_models.ChatSession session) async {
    // E-002: guard concurrent load
    if (_isLoadingSession) return;
    if (!mounted) return;
    setState(() => _isLoadingSession = true);

    try {
      // Stop generation dulu jika sedang berjalan
      if (_isGenerating) await _stopGeneration();

      // Auto-save sesi aktif sebelum ganti
      final currentMsgs = ref.read(chatSessionProvider.notifier).state.messages;
      if (currentMsgs.isNotEmpty) {
        // Trigger save via canonical notifier
        await ref.read(chatSessionProvider.notifier).autoSave();
      }
      // Load session baru via canonical loadSession
      await ref.read(chatSessionProvider.notifier).loadSession(session);
      if (mounted) {
        setState(() => _currentSession = session);
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } finally {
      if (mounted) setState(() => _isLoadingSession = false);
    }
  }

  void _newChat() {
    _startNewChat();
  }

  Future<void> _clearChatWithConfirm() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bersihkan Riwayat?'),
        content: const Text('Semua pesan akan dihapus permanen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      ref.read(chatSessionProvider.notifier).clearSession();
    }
  }

  Future<void> _exportTxt() async {
    final messages = ref.read(chatSessionProvider).messages;
    if (messages.isEmpty) return;
    final sb = StringBuffer();
    for (final m in messages) {
      final peran = m.role == 'user' ? 'Kamu' : 'AI';
      final waktu = DateFormat('HH:mm').format(m.createdAt);
      sb.writeln('[$waktu] $peran: ${m.content}');
      sb.writeln();
    }
    await Share.share(sb.toString(), subject: 'Chat Export KanMon GO');
  }

  Future<void> _exportMd() async {
    final messages = ref.read(chatSessionProvider).messages;
    if (messages.isEmpty) return;
    final sb = StringBuffer();
    sb.writeln('# Chat Export — KanMon GO\n');
    for (final m in messages) {
      final peran  = m.role == 'user' ? '**Kamu**' : '**AI**';
      final waktu  = DateFormat('HH:mm').format(m.createdAt);
      sb.writeln('### $peran [$waktu]\n');
      sb.writeln('${m.content}\n');
      sb.writeln('---\n');
    }
    await Share.share(sb.toString(), subject: 'Chat Export KanMon GO.md');
  }

  void _copyAll() {
    final messages = ref.read(chatSessionProvider).messages;
    if (messages.isEmpty) return;
    final sb = StringBuffer();
    for (final m in messages) {
      final peran = m.role == 'user' ? 'Kamu' : 'AI';
      sb.writeln('$peran: ${m.content}');
    }
    Clipboard.setData(ClipboardData(text: sb.toString()));
    _showSnackbar('Seluruh percakapan disalin ke clipboard.');
  }

  void _openAiSettings() {
    // Navigasi ke halaman parameter inferensi AI (GoRouter)
    context.push('/settings/ai-params');
  }

  void _switchToOnlineMode() {
    // Pindah ke mode online
    final choice = AiSourceChoice(mode: AiMode.online, label: 'Online');
    ref.read(aiSourceProvider.notifier).state = choice;
    AiService.instance.setSource(choice);
  }

  void _fillSuggestion(String text) {
    _inputCtrl.text = text;
    setState(() {});
    _focusNode.requestFocus();
  }

  void _showSnackbar(String msg) {
    if (!mounted) return;
    showTopSnack(context, msg, duration: const Duration(seconds: 3));
  }

  // ── Chat Edit Mode persistence ─────────────────────────────────────────────

  Future<void> _loadEditMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('chat_edit_mode') ?? 'adaptive';
    if (mounted) {
      setState(() {
        _editMode = saved == 'defaultMode'
            ? ChatEditMode.defaultMode
            : ChatEditMode.adaptive;
      });
    }
  }

  Future<void> _saveEditMode(ChatEditMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('chat_edit_mode', mode.name);
  }

  // ── Edit Mode Bottom Sheet ─────────────────────────────────────────────────

  void _showEditModeSheet() {
    final c = KmColors.of(context);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: c.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Title
                Text(
                  'Mode Pengeditan AI',
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Pilih bagaimana AI menangani pengeditan file, kode, foto, dan video.',
                  style: TextStyle(color: c.textSub, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 16),
                // Mode Cards
                ...ChatEditMode.values.map((mode) {
                  final selected = _editMode == mode;
                  final color = mode.colorFn(c);
                  return GestureDetector(
                    onTap: () {
                      setState(() => _editMode = mode);
                      setSheetState(() {});
                      _saveEditMode(mode);
                      Navigator.pop(ctx);
                      _showSnackbar(
                        '${mode == ChatEditMode.adaptive ? "✨" : "🔧"} Mode: ${mode.label} aktif',
                      );
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: selected
                            ? color.withValues(alpha: 0.08)
                            : c.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected ? color : c.border,
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(mode.icon, color: color, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      mode.label,
                                      style: TextStyle(
                                        color: c.text,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (selected) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          'Aktif',
                                          style: TextStyle(
                                            color: color,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  mode.description,
                                  style: TextStyle(
                                    color: c.textSub,
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (selected)
                            Icon(Icons.check_circle_rounded,
                                color: color, size: 20),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 4),
                // Capability table
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Kemampuan per mode:',
                        style: TextStyle(
                            color: c.textSub,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      _CapabilityRow(
                        c: c,
                        label: 'Edit Kode / File Teks',
                        defaultOk: true,
                        adaptiveOk: true,
                      ),
                      _CapabilityRow(
                        c: c,
                        label: 'Edit Foto (resize/crop/filter)',
                        defaultOk: true,
                        adaptiveOk: true,
                      ),
                      _CapabilityRow(
                        c: c,
                        label: 'Edit Video (trim/compress)',
                        defaultOk: true,
                        adaptiveOk: true,
                      ),
                      _CapabilityRow(
                        c: c,
                        label: 'Web Research + AI Consultation',
                        defaultOk: false,
                        adaptiveOk: true,
                      ),
                      _CapabilityRow(
                        c: c,
                        label: 'Prompt Komprehensif Otomatis',
                        defaultOk: false,
                        adaptiveOk: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET: Model Status Chip (AppBar title)
// ─────────────────────────────────────────────────────────────────────────────

class _ModelStatusChip extends ConsumerWidget {
  final VoidCallback? onTap;
  const _ModelStatusChip({this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kfc    = KmColors.of(context);
    final status = LlamaService.instance.status;
    final model  = LlamaService.instance.currentModel;

    String label;
    Color  dotColor;
    Widget? loading;

    switch (status) {
      case llama_ctx.ModelStatus.loaded:
      case llama_ctx.ModelStatus.generating:
        label    = model?.name ?? 'Model Aktif';
        dotColor = Colors.green;
        break;
      case llama_ctx.ModelStatus.loading:
        label    = 'Memuat...';
        dotColor = Colors.orange;
        loading  = SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Colors.orange,
          ),
        );
        break;
      case llama_ctx.ModelStatus.error:
        label    = 'Error Model';
        dotColor = Colors.red;
        break;
      case llama_ctx.ModelStatus.notLoaded:
      default:
        label    = 'Belum ada model';
        dotColor = Colors.grey;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: kfc.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kfc.borderSoft),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            loading ??
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: kfc.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more, size: 14, color: kfc.textMuted),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET: Token Per Second Counter
// ─────────────────────────────────────────────────────────────────────────────

class _TokensPerSecCounter extends StatefulWidget {
  final bool isGenerating;
  const _TokensPerSecCounter({required this.isGenerating});

  @override
  State<_TokensPerSecCounter> createState() => _TokensPerSecCounterState();
}

class _TokensPerSecCounterState extends State<_TokensPerSecCounter> {
  double? _tps;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final metrics = LlamaService.instance.lastMetrics;
      if (metrics != null && mounted) {
        setState(() { _tps = metrics.tokensPerSecond; });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_tps == null || _tps! <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Text(
        '${_tps!.toStringAsFixed(1)} tok/s',
        style: const TextStyle(
          color: Colors.green,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET: Chat Menu Button
// ─────────────────────────────────────────────────────────────────────────────

class _ChatMenuButton extends StatelessWidget {
  final VoidCallback onNewChat;
  final VoidCallback onClearChat;
  final VoidCallback onExportTxt;
  final VoidCallback onExportMd;
  final VoidCallback onCopyAll;
  final VoidCallback onAiSettings;

  const _ChatMenuButton({
    required this.onNewChat,
    required this.onClearChat,
    required this.onExportTxt,
    required this.onExportMd,
    required this.onCopyAll,
    required this.onAiSettings,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (val) {
        switch (val) {
          case 'new':        onNewChat();    break;
          case 'clear':      onClearChat();  break;
          case 'export_txt': onExportTxt();  break;
          case 'export_md':  onExportMd();   break;
          case 'copy_all':   onCopyAll();    break;
          case 'settings':   onAiSettings(); break;
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'new',        child: Text('💬 Chat Baru')),
        const PopupMenuItem(value: 'clear',      child: Text('🗑️ Bersihkan Riwayat')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'export_txt', child: Text('📄 Export .txt')),
        const PopupMenuItem(value: 'export_md',  child: Text('📝 Export .md')),
        const PopupMenuItem(value: 'copy_all',   child: Text('📋 Salin Semua')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'settings',   child: Text('⚙️ Pengaturan AI')),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET: Welcome Card (empty state)
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET: Empty State Chat (6A-ii) — tampil saat messages.isEmpty
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyStateChat extends StatelessWidget {
  final VoidCallback onAnalyzeImage;
  final VoidCallback onReviewCode;
  final VoidCallback onWebSearch;
  final VoidCallback onHelpWrite;

  const _EmptyStateChat({
    required this.onAnalyzeImage,
    required this.onReviewCode,
    required this.onWebSearch,
    required this.onHelpWrite,
  });

  @override
  Widget build(BuildContext context) {
    final kfc = KmColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Logo dengan fallback ke icon
            Builder(builder: (ctx) {
              try {
                return Image.asset(
                  'assets/images/kanmonai_logo.png',
                  width: 80,
                  height: 80,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.psychology_rounded,
                    size: 80,
                    color: kfc.accent,
                  ),
                );
              } catch (_) {
                return Icon(
                  Icons.psychology_rounded,
                  size: 80,
                  color: kfc.accent,
                );
              }
            }),
            const SizedBox(height: 16),
            Text(
              'Apa yang ingin kamu tanyakan?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: kfc.text,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                _SuggestionCard(
                  emoji: '📷',
                  label: 'Analisis gambar',
                  onTap: onAnalyzeImage,
                ),
                _SuggestionCard(
                  emoji: '💻',
                  label: 'Review kode',
                  onTap: onReviewCode,
                ),
                _SuggestionCard(
                  emoji: '🌐',
                  label: 'Cari di web',
                  onTap: onWebSearch,
                ),
                _SuggestionCard(
                  emoji: '✏️',
                  label: 'Bantu menulis',
                  onTap: onHelpWrite,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET: Suggestion Card (6A-ii)
// ─────────────────────────────────────────────────────────────────────────────

class _SuggestionCard extends StatelessWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;

  const _SuggestionCard({
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final kfc = KmColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: kfc.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kfc.border),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(fontSize: 13, color: kfc.text),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET: Empty Model Widget (mode offline, belum ada model)
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyModelWidget extends StatelessWidget {
  final VoidCallback onSwitchOnline;
  const _EmptyModelWidget({required this.onSwitchOnline});

  @override
  Widget build(BuildContext context) {
    final kfc = KmColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.smart_toy_outlined, size: 64, color: kfc.textMuted),
            const SizedBox(height: 16),
            Text(
              'Belum ada model AI yang dimuat',
              style: TextStyle(
                  color: kfc.text, fontSize: 17, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Pilih dan unduh model untuk mulai chat offline',
              style: TextStyle(color: kfc.textSub, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ModelManagerScreen()),
              ),
              icon: const Icon(Icons.download_rounded),
              label: const Text('Pilih Model'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kfc.accent,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onSwitchOnline,
              icon: Icon(Icons.cloud_rounded, color: kfc.textSub),
              label: Text('Ganti ke AI Online',
                  style: TextStyle(color: kfc.textSub)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: kfc.borderSoft),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET: Message Bubble
// ─────────────────────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final chat_models.ChatMessage message;
  final bool showRawText;
  final bool isLastUser;
  final bool isLastAssistant;
  final List<chat_models.ChatAttachment> attachments;
  final VoidCallback onDelete;
  final VoidCallback onResend;
  final VoidCallback onRegenerate;
  final VoidCallback onToggleRaw;
  final List<ResearchSource>? webSources;
  final String webResearchQuery;
  final ArtifactPanelController artifactCtrl;

  const _MessageBubble({
    required this.message,
    required this.showRawText,
    required this.isLastUser,
    required this.isLastAssistant,
    this.attachments = const [],
    required this.onDelete,
    required this.onResend,
    required this.onRegenerate,
    required this.onToggleRaw,
    this.webSources,
    this.webResearchQuery = '',
    required this.artifactCtrl,
  });

  @override
  Widget build(BuildContext context) {
    final kfc    = KmColors.of(context);
    final isUser = message.role == 'user';

    return GestureDetector(
      onLongPress: () => _showMessageSheet(context, kfc),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment:
              isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Avatar AI
            if (!isUser) ...[
              Container(
                width: 30,
                height: 30,
                margin: const EdgeInsets.only(right: 8, bottom: 4),
                decoration: BoxDecoration(
                  color: kfc.accentSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.smart_toy_rounded,
                    size: 16, color: kfc.accent),
              ),
            ],
            // Konten bubble
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.78,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isUser ? kfc.accent : kfc.card,
                  borderRadius: BorderRadius.only(
                    topLeft:     const Radius.circular(16),
                    topRight:    const Radius.circular(16),
                    bottomLeft:  Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                  border: isUser
                      ? null
                      : Border.all(color: kfc.borderSoft),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Attachment previews (Sesi 2)
                    if (attachments.isNotEmpty) ...[
                      ...attachments.map((att) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: AttachmentPreview(
                          attachment: att,
                          isUserBubble: isUser,
                        ),
                      )),
                      const Divider(height: 1, thickness: 1),
                      const SizedBox(height: 6),
                    ],
                    // Web Research Sources Card (Sesi 5C-D)
                    if (webSources != null && webSources!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: WebResearchSourcesCard(
                          sources: webSources!,
                          query: webResearchQuery,
                        ),
                      ),
                    // Konten pesan
                    if (message.isError)
                      Row(
                        children: [
                          const Icon(Icons.error_rounded,
                              color: Colors.red, size: 16),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              message.content,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 13),
                            ),
                          ),
                        ],
                      )
                    else if (isUser || showRawText)
                      Text(
                        message.content,
                        style: TextStyle(
                          color: isUser ? Colors.white : kfc.text,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      )
                    else
                      _MarkdownContent(
                          text: message.content, kfc: kfc,
                          artifactCtrl: artifactCtrl),
                    const SizedBox(height: 5),
                    // Timestamp
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DateFormat('HH:mm').format(message.createdAt),
                          style: TextStyle(
                            color: isUser
                                ? Colors.white70
                                : kfc.textMuted,
                            fontSize: 10,
                          ),
                        ),

                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMessageSheet(BuildContext context, KmColors kfc) {
    showModalBottomSheet(
      context:           context,
      backgroundColor:   Colors.transparent,
      isScrollControlled: false,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: kfc.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: kfc.borderSoft,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Opsi
              ListTile(
                leading: Icon(Icons.copy_rounded, color: kfc.accent),
                title: Text('Salin pesan',
                    style: TextStyle(color: kfc.text)),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(
                      ClipboardData(text: message.content));
                  showTopSnack(context, 'Pesan disalin.');
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_rounded,
                    color: Colors.red),
                title: Text('Hapus pesan',
                    style: TextStyle(color: kfc.text)),
                onTap: () {
                  Navigator.pop(context);
                  onDelete();
                },
              ),
              if (isLastUser)
                ListTile(
                  leading:
                      Icon(Icons.refresh_rounded, color: kfc.textSub),
                  title: Text('Kirim ulang',
                      style: TextStyle(color: kfc.text)),
                  onTap: () {
                    Navigator.pop(context);
                    onResend();
                  },
                ),
              if (isLastAssistant)
                ListTile(
                  leading:
                      Icon(Icons.replay_rounded, color: kfc.textSub),
                  title: Text('Regenerate',
                      style: TextStyle(color: kfc.text)),
                  onTap: () {
                    Navigator.pop(context);
                    onRegenerate();
                  },
                ),
              ListTile(
                leading: Icon(Icons.share_rounded, color: kfc.textSub),
                title:
                    Text('Bagikan', style: TextStyle(color: kfc.text)),
                onTap: () {
                  Navigator.pop(context);
                  Share.share(message.content);
                },
              ),
              ListTile(
                leading: Icon(Icons.code_rounded, color: kfc.textSub),
                title: Text('Lihat teks mentah',
                    style: TextStyle(color: kfc.text)),
                onTap: () {
                  Navigator.pop(context);
                  onToggleRaw();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET: Markdown Content
// ─────────────────────────────────────────────────────────────────────────────

class _MarkdownContent extends StatelessWidget {
  final String   text;
  final KmColors kfc;
  final ArtifactPanelController? artifactCtrl;
  const _MarkdownContent({
    required this.text,
    required this.kfc,
    this.artifactCtrl,
  });

  @override
  Widget build(BuildContext context) {
    // Parse teks menjadi blok
    final bloks = _parseMarkdown(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: bloks.map((b) => _buildBlock(context, b)).toList(),
    );
  }

  // Blok markdown sederhana
  List<_MdBlock> _parseMarkdown(String src) {
    final lines  = src.split('\n');
    final blocks = <_MdBlock>[];
    final buf    = StringBuffer();
    bool inCode  = false;
    String codeLang = '';

    for (final line in lines) {
      if (line.startsWith('```')) {
        if (!inCode) {
          // Flush teks biasa
          if (buf.isNotEmpty) {
            blocks.add(_MdBlock.text(buf.toString().trimRight()));
            buf.clear();
          }
          inCode   = true;
          codeLang = line.substring(3).trim();
        } else {
          // Tutup blok kode
          blocks.add(_MdBlock.code(buf.toString(), codeLang));
          buf.clear();
          inCode   = false;
          codeLang = '';
        }
        continue;
      }
      if (inCode) {
        buf.writeln(line);
      } else {
        buf.writeln(line);
      }
    }
    // Flush sisa
    if (buf.isNotEmpty) {
      if (inCode) {
        blocks.add(_MdBlock.code(buf.toString(), codeLang));
      } else {
        blocks.add(_MdBlock.text(buf.toString().trimRight()));
      }
    }
    return blocks;
  }

  Widget _buildBlock(BuildContext context, _MdBlock block) {
    if (block.isCode) {
      return CodeBlockWidget(
          code: block.content,
          language: block.lang,
          artifactCtrl: artifactCtrl);
    }
    // Render teks dengan inline markdown
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: _InlineMarkdown(text: block.content, kfc: kfc),
    );
  }
}

// ─── Model blok markdown ─────────────────────────────────────────────────────

class _MdBlock {
  final bool   isCode;
  final String content;
  final String lang;
  const _MdBlock._({required this.isCode, required this.content, required this.lang});
  factory _MdBlock.text(String t) => _MdBlock._(isCode: false, content: t, lang: '');
  factory _MdBlock.code(String c, String l) => _MdBlock._(isCode: true, content: c, lang: l);
}


// ─── Inline Markdown Renderer ─────────────────────────────────────────────────

class _InlineMarkdown extends StatelessWidget {
  final String   text;
  final KmColors kfc;
  const _InlineMarkdown({required this.text, required this.kfc});

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) => _buildLine(context, line)).toList(),
    );
  }

  Widget _buildLine(BuildContext context, String line) {
    // Heading
    if (line.startsWith('### ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Text(
          line.substring(4),
          style: TextStyle(
              color: kfc.text,
              fontSize: 15,
              fontWeight: FontWeight.w700),
        ),
      );
    }
    if (line.startsWith('## ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Text(
          line.substring(3),
          style: TextStyle(
              color: kfc.text,
              fontSize: 16,
              fontWeight: FontWeight.w700),
        ),
      );
    }
    if (line.startsWith('# ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Text(
          line.substring(2),
          style: TextStyle(
              color: kfc.text,
              fontSize: 18,
              fontWeight: FontWeight.w700),
        ),
      );
    }
    // List item
    if (line.startsWith('- ') || line.startsWith('* ')) {
      return Padding(
        padding: const EdgeInsets.only(left: 8, top: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• ', style: TextStyle(color: kfc.accent, fontSize: 14)),
            Flexible(child: _buildInlineSpans(context, line.substring(2))),
          ],
        ),
      );
    }
    // Baris kosong
    if (line.trim().isEmpty) {
      return const SizedBox(height: 6);
    }
    // Teks biasa dengan inline formatting
    return _buildInlineSpans(context, line);
  }

  Widget _buildInlineSpans(BuildContext context, String line) {
    final spans = <InlineSpan>[];
    final re    = RegExp(r'(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`)');
    int cursor  = 0;

    for (final m in re.allMatches(line)) {
      // Tambah teks sebelum match
      if (m.start > cursor) {
        spans.add(TextSpan(
          text:  line.substring(cursor, m.start),
          style: TextStyle(color: kfc.text, fontSize: 14, height: 1.45),
        ));
      }
      final match = m.group(0)!;
      if (match.startsWith('**')) {
        // Bold
        spans.add(TextSpan(
          text: match.substring(2, match.length - 2),
          style: TextStyle(
              color: kfc.text,
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w700),
        ));
      } else if (match.startsWith('*')) {
        // Italic
        spans.add(TextSpan(
          text: match.substring(1, match.length - 1),
          style: TextStyle(
              color: kfc.text,
              fontSize: 14,
              height: 1.45,
              fontStyle: FontStyle.italic),
        ));
      } else if (match.startsWith('`')) {
        // Inline code
        spans.add(WidgetSpan(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              match.substring(1, match.length - 1),
              style: const TextStyle(
                color: Colors.greenAccent,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
            ),
          ),
        ));
      }
      cursor = m.end;
    }
    // Sisa teks
    if (cursor < line.length) {
      spans.add(TextSpan(
        text:  line.substring(cursor),
        style: TextStyle(color: kfc.text, fontSize: 14, height: 1.45),
      ));
    }

    if (spans.isEmpty) {
      return Text(line,
          style: TextStyle(color: kfc.text, fontSize: 14, height: 1.45));
    }
    return RichText(text: TextSpan(children: spans));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET: Typing Indicator (3 dot staggered)
// ─────────────────────────────────────────────────────────────────────────────

class _TypingIndicator extends StatelessWidget {
  final AnimationController animCtrl;
  final String researchStatus;

  const _TypingIndicator({
    required this.animCtrl,
    this.researchStatus = '',
  });

  @override
  Widget build(BuildContext context) {
    final kfc = KmColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar AI
          Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(right: 8, bottom: 4),
            decoration: BoxDecoration(
              color: kfc.accentSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.smart_toy_rounded, size: 16, color: kfc.accent),
          ),
          // Bubble indikator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: kfc.card,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
              ),
              border: Border.all(color: kfc.borderSoft),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Dots animation
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    return AnimatedBuilder(
                      animation: animCtrl,
                      builder: (_, __) {
                        // Stagger setiap dot 120ms
                        final offset = ((animCtrl.value + i * 0.15) % 1.0);
                        final dy = -4.0 *
                            (offset < 0.5
                                ? offset * 2
                                : (1.0 - offset) * 2);
                        return Transform.translate(
                          offset: Offset(0, dy),
                          child: Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: kfc.textMuted,
                              shape: BoxShape.circle,
                            ),
                          ),
                        );
                      },
                    );
                  }),
                ),
                // Research status (tampil hanya saat ada teks)
                if (researchStatus.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Text(
                            researchStatus,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.5),
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET: Image Source Sheet (kamera / galeri)
// ─────────────────────────────────────────────────────────────────────────────

class _ImageSourceSheet extends StatelessWidget {
  const _ImageSourceSheet();

  @override
  Widget build(BuildContext context) {
    final kfc = KmColors.of(context);
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kfc.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Text('Pilih Sumber Gambar',
              style: TextStyle(
                  color: kfc.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ListTile(
            leading: Icon(Icons.camera_alt_rounded, color: kfc.accent),
            title: Text('Kamera', style: TextStyle(color: kfc.text)),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: Icon(Icons.photo_library_rounded, color: kfc.accent),
            title: Text('Galeri', style: TextStyle(color: kfc.text)),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// ATTACHMENT CHIP (di input area, sebelum kirim)
// ─────────────────────────────────────────────────────────────────────────────

class _AttachmentChip extends StatelessWidget {
  final chat_models.ChatAttachment attachment;
  final KmColors kfc;
  final VoidCallback onRemove;

  const _AttachmentChip({
    required this.attachment,
    required this.kfc,
    required this.onRemove,
  });

  String get _shortName {
    final name = attachment.filename;
    return name.length > 14 ? '${name.substring(0, 12)}…' : name;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: kfc.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kfc.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(attachment.icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(
            _shortName,
            style: TextStyle(
              color: kfc.text,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close_rounded, size: 16, color: kfc.textSub),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET: Adaptive Edit Status Bar
// ─────────────────────────────────────────────────────────────────────────────

class _AdaptiveStatusBar extends StatelessWidget {
  final AdaptiveEditPhase phase;
  final String status;

  const _AdaptiveStatusBar({required this.phase, required this.status});

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);

    final Color color;
    final IconData icon;

    switch (phase) {
      case AdaptiveEditPhase.analyzing:
        color = c.info;
        icon  = Icons.folder_open_rounded;
        break;
      case AdaptiveEditPhase.researching:
        color = c.gold;
        icon  = Icons.travel_explore_rounded;
        break;
      case AdaptiveEditPhase.planning:
        color = c.accent;
        icon  = Icons.psychology_rounded;
        break;
      case AdaptiveEditPhase.executing:
        color = c.correct;
        icon  = Icons.auto_fix_high_rounded;
        break;
      default:
        color = c.textSub;
        icon  = Icons.info_outline_rounded;
    }

    return Container(
      margin:     const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding:    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          SizedBox(
            width:  16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          ),
          const SizedBox(width: 8),
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              status,
              style: TextStyle(
                color:      color,
                fontSize:   12,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ENUM: ChatEditMode
// ─────────────────────────────────────────────────────────────────────────────

enum ChatEditMode {
  /// Gunakan arsitektur native bawaan aplikasi.
  defaultMode,

  /// AI-powered adaptive mode — research, konsultasi, prompt komprehensif, eksekusi.
  adaptive,
}

extension ChatEditModeX on ChatEditMode {
  String get label {
    switch (this) {
      case ChatEditMode.defaultMode: return 'Default';
      case ChatEditMode.adaptive:    return 'Adaptive';
    }
  }

  String get description {
    switch (this) {
      case ChatEditMode.defaultMode:
        return 'Gunakan arsitektur native bawaan aplikasi.\n'
            'Kode: editor bawaan. Foto/Video: ffmpeg langsung.';
      case ChatEditMode.adaptive:
        return 'AI (offline/online/bulk) akan research, konsultasi, '
            'buat prompt komprehensif, lalu eksekusi pengeditan.';
    }
  }

  IconData get icon {
    switch (this) {
      case ChatEditMode.defaultMode: return Icons.build_rounded;
      case ChatEditMode.adaptive:    return Icons.auto_awesome_rounded;
    }
  }

  Color Function(KmColors) get colorFn {
    switch (this) {
      case ChatEditMode.defaultMode: return (c) => c.info;
      case ChatEditMode.adaptive:    return (c) => c.accent;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET: _EditModeButton (AppBar)
// ─────────────────────────────────────────────────────────────────────────────

class _EditModeButton extends StatelessWidget {
  final ChatEditMode mode;
  final VoidCallback onTap;

  const _EditModeButton({required this.mode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    final color = mode.colorFn(c);

    return Tooltip(
      message: 'Mode Edit: ${mode.label}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              Icon(mode.icon, color: color, size: 22),
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.bg, width: 1),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET: _CapabilityRow (inside bottom sheet)
// ─────────────────────────────────────────────────────────────────────────────

class _CapabilityRow extends StatelessWidget {
  final KmColors c;
  final String label;
  final bool defaultOk;
  final bool adaptiveOk;

  const _CapabilityRow({
    required this.c,
    required this.label,
    required this.defaultOk,
    required this.adaptiveOk,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(color: c.textSub, fontSize: 11)),
          ),
          _check(defaultOk, c.info),
          const SizedBox(width: 16),
          _check(adaptiveOk, c.accent),
        ],
      ),
    );
  }

  Widget _check(bool ok, Color color) {
    return ok
        ? Icon(Icons.check_circle_rounded, color: color, size: 14)
        : Icon(Icons.radio_button_unchecked_rounded,
            color: c.border, size: 14);
  }
}
