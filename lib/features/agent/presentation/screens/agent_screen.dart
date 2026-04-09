// lib/features/agent/presentation/screens/agent_screen.dart
// KanMon GO — AI Agent Screen (Claude-like UI)
//
// Fitur baru mirip Claude AI:
//  • Sidebar riwayat task agent (Drawer kiri)
//  • Status bar bawah yang menampilkan langkah saat ini + spinner berputar
//  • "Sedang berpikir…" animasi pulsing di step thinking
//  • Step card yang lebih ekspresif dengan timeline vertikal
//  • Tombol New Task di AppBar
//  • Semua fitur lama dipertahankan (tools, memory, settings, file attach, dll)
// =============================================================================

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/data/services/agent_service.dart';
import 'package:kanmongo/data/services/agent_memory_service.dart';
import 'package:kanmongo/data/services/export_service.dart';
import 'package:kanmongo/data/services/file_processor_service.dart';
import 'package:kanmongo/data/services/model_manager_service.dart';
import 'package:kanmongo/data/services/llama_service.dart';
import 'package:kanmongo/core/ai/llama_context.dart';
import 'package:kanmongo/data/services/ai_service.dart';
import 'package:kanmongo/shared/widgets/ai_source_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:kanmongo/shared/utils/top_snack.dart';

// ── Task History Model ────────────────────────────────────────────────────────

class _TaskRecord {
  final String         id;
  final String         title;
  final DateTime       createdAt;
  final List<AgentStep> steps;

  const _TaskRecord({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.steps,
  });
}

// ── Agent Screen ──────────────────────────────────────────────────────────────

class AgentScreen extends ConsumerStatefulWidget {
  const AgentScreen({super.key});
  @override
  ConsumerState<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends ConsumerState<AgentScreen> {
  final _inputCtrl   = TextEditingController();
  final _scroll      = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _svc         = AgentService.instance;

  final List<AgentStep>   _steps    = [];
  final List<_TaskRecord> _history  = [];
  bool    _running  = false;
  bool    _canSend  = false;
  String  _statusText = '';
  StreamSubscription? _sub;

  ProcessedFile? _pendingFile;
  bool _processingFile = false;
  String _processingFileName = '';

  @override
  void initState() {
    super.initState();
    _svc.loadConfig();
    _inputCtrl.addListener(() =>
        setState(() => _canSend = _inputCtrl.text.trim().isNotEmpty && !_processingFile));
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scroll.dispose();
    AgentService.instance.forceStop();
    _sub?.cancel();
    super.dispose();
  }

  void _addStep(AgentStep s) {
    setState(() {
      _steps.add(s);
      _statusText = _stepLabel(s);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  String _stepLabel(AgentStep s) {
    switch (s.type) {
      case AgentStepType.thinking:   return '💭 Sedang berpikir…';
      case AgentStepType.planning:   return '📋 Merencanakan langkah…';
      case AgentStepType.toolCall:   return '🔧 Menggunakan tools…';
      case AgentStepType.toolResult: return '📊 Memproses hasil…';
      case AgentStepType.answer:     return '✅ Menyusun jawaban…';
      case AgentStepType.error:      return '❌ Terjadi error';
      case AgentStepType.fileOutput: return '📎 Membuat file output…';
      case AgentStepType.installing: return '⬇️ Menginstal tools…';
    }
  }

  // ── File picking ──────────────────────────────────────────────────────────

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any, allowMultiple: false);
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
    final filename = p.basename(path);
    setState(() {
      _processingFile     = true;
      _processingFileName = filename;
      _canSend            = false;
    });
    try {
      final processed = await FileProcessorService.instance
          .process(path)
          .timeout(const Duration(seconds: 30), onTimeout: () => ProcessedFile(
            filename: filename,
            mimeType: 'application/octet-stream',
            category: FileCategory.other,
            sizeBytes: 0,
            error: 'Timeout: file terlalu besar untuk diproses',
          ));
      if (mounted) {
        setState(() {
          _pendingFile        = processed;
          _processingFile     = false;
          _processingFileName = '';
          _canSend            = true;
        });
        showTopSnack(context, processed.error != null ? '⚠️ \${processed.error}' : '✅ File siap: \${processed.filename} (\${processed.sizeLabel})', duration: const Duration(seconds: 3), isError: processed.error != null);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _processingFile     = false;
          _processingFileName = '';
          _canSend            = _inputCtrl.text.trim().isNotEmpty;
        });
        showTopSnack(context, '❌ Gagal memproses file: $e', isError: true);
      }
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
              Text('Lampirkan File', style: TextStyle(color: c.text,
                  fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Wrap(spacing: 12, runSpacing: 12, children: [
                _AttachOption(icon: Icons.image_rounded, label: 'Galeri',
                    color: const Color(0xFF10B981),
                    onTap: () { Navigator.pop(context); _pickImage(); }),
                _AttachOption(icon: Icons.camera_alt_rounded, label: 'Kamera',
                    color: const Color(0xFF0EA5E9),
                    onTap: () { Navigator.pop(context); _pickCamera(); }),
                _AttachOption(icon: Icons.picture_as_pdf_rounded, label: 'PDF',
                    color: const Color(0xFFEF4444),
                    onTap: () { Navigator.pop(context); _pickFile(); }),
                _AttachOption(icon: Icons.description_rounded, label: 'Dokumen',
                    color: const Color(0xFF6366F1),
                    onTap: () { Navigator.pop(context); _pickFile(); }),
                _AttachOption(icon: Icons.table_chart_rounded, label: 'Spreadsheet',
                    color: const Color(0xFF059669),
                    onTap: () { Navigator.pop(context); _pickFile(); }),
                _AttachOption(icon: Icons.code_rounded, label: 'Kode',
                    color: const Color(0xFFF59E0B),
                    onTap: () { Navigator.pop(context); _pickFile(); }),
                _AttachOption(icon: Icons.audio_file_rounded, label: 'Audio',
                    color: const Color(0xFFEC4899),
                    onTap: () { Navigator.pop(context); _pickFile(); }),
                _AttachOption(icon: Icons.folder_rounded, label: 'File Lainnya',
                    color: const Color(0xFF64748B),
                    onTap: () { Navigator.pop(context); _pickFile(); }),
              ]),
              const SizedBox(height: 8),
              Text('Semua format didukung: gambar, PDF, DOCX, XLSX, audio, video, kode, dan lainnya.',
                  style: TextStyle(color: c.textMuted, fontSize: 11)),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ── Run task ──────────────────────────────────────────────────────────────

  Future<void> _runTask(String task) async {
    if (task.trim().isEmpty && _pendingFile == null) return;
    if (_running) return;
    if (_processingFile) return; // jangan kirim saat file sedang diproses

    // Validasi: jika ada file error, warn user dan bersihkan
    if (_pendingFile != null && _pendingFile!.error != null) {
      showTopSnack(context, '⚠️ File bermasalah: ${_pendingFile!.error}\nFile dilepas dari task.', duration: const Duration(seconds: 4), isError: true)
      setState(() => _pendingFile = null);
      if (task.trim().isEmpty) return;
    }

    String fullTask = task.trim();
    final file = _pendingFile;
    setState(() {
      _pendingFile  = null;
      _running      = true;
      _canSend      = false;
      _statusText   = '🤖 Agent memulai…';
    });

    if (file != null) {
      final header = '\n\n=== FILE: ${file.filename} ===\n\n';
      final body   = file.hasText && file.textContent != null
          ? (file.textContent!.length > 8000
              ? '${file.textContent!.substring(0, 8000)}\n... [terpotong]'
              : file.textContent!)
          : '[File: ${file.filename} — ${file.sizeLabel}]';
      fullTask = fullTask.isNotEmpty
          ? '$fullTask$header$body'
          : 'Analisis file berikut dan berikan insight yang berguna:$header$body';
    }

    _inputCtrl.clear();

    // Simpan ke history
    final taskId    = DateTime.now().millisecondsSinceEpoch.toString();
    final taskTitle = fullTask.length > 50
        ? '${fullTask.substring(0, 50)}…' : fullTask;
    final record    = _TaskRecord(
      id: taskId, title: taskTitle,
      createdAt: DateTime.now(), steps: [],
    );
    _history.insert(0, record);

    _sub = _svc.run(task: fullTask).listen(
      (step) {
        _addStep(step);
        record.steps.add(step);
      },
      onDone: () => setState(() {
        _running    = false;
        _statusText = '✅ Task selesai';
      }),
      onError: (_) => setState(() {
        _running    = false;
        _statusText = '';
      }),
    );
  }

  void _stop() {
    _sub?.cancel();
    // Reset flag di AgentService agar run() berikutnya tidak melihat sisa flag
    AgentService.instance.forceStop();
    setState(() { _running = false; _statusText = ''; });
    _addStep(AgentStep(type: AgentStepType.error,
        content: '⛔ Agent dihentikan oleh user.', time: DateTime.now()));
  }

  void _newTask() {
    _stop();
    setState(() {
      _steps.clear();
      _statusText  = '';
      _pendingFile = null;
      _canSend     = false;
    });
  }

  void _loadHistory(_TaskRecord record) {
    // Drawer sudah menutup dirinya sendiri sebelum memanggil callback ini.
    // Jangan panggil Navigator.pop lagi — akan menyebabkan AgentScreen ikut ter-pop.
    setState(() {
      _steps
        ..clear()
        ..addAll(record.steps);
      _running    = false;
      _statusText = '';
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c      = KmColors.of(context);
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: c.bg,
      drawer: _AgentHistoryDrawer(
        history: _history,
        c: c,
        onNewTask: _newTask,
        onLoad: _loadHistory,
      ),
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.menu_rounded, color: c.textSub),
          tooltip: 'Riwayat Task',
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: 10, height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _running ? Colors.amber : const Color(0xFF10B981),
              boxShadow: _running ? [
                BoxShadow(color: Colors.amber.withValues(alpha: 0.5), blurRadius: 6)
              ] : [],
            ),
          ),
          const SizedBox(width: 8),
          Text('AI Agent', style: TextStyle(
              color: c.text, fontWeight: FontWeight.w700, fontSize: 17)),
        ]),
        actions: [
          // Tombol New Task
          IconButton(
            icon: Icon(Icons.add_task_rounded, color: c.textSub),
            tooltip: 'Task Baru',
            onPressed: _newTask,
          ),
          _AiModeBadge(child: AiSourcePickerButton(onTap: () => showAiSourcePicker(context, ref))),
          if (_running)
            TextButton.icon(
              onPressed: _stop,
              icon: const Icon(Icons.stop_rounded, size: 16, color: Colors.red),
              label: const Text('Stop',
                  style: TextStyle(color: Colors.red, fontSize: 13)),
            ),
          IconButton(
            icon: Icon(Icons.settings_rounded, color: c.textMuted, size: 20),
            onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => const AgentSettingsScreen())),
          ),
          if (_steps.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_sweep_rounded, color: c.textMuted, size: 20),
              onPressed: () => setState(() => _steps.clear()),
            ),
        ],
      ),
      body: Stack(children: [
        Column(children: [
        // Agent info bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: isDark
              ? Colors.white.withValues(alpha: 0.03)
              : Colors.black.withValues(alpha: 0.02),
          child: Row(children: [
            const Text('🤖', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_svc.config.name} — ${_svc.config.enabledTools.length} tools aktif',
                style: TextStyle(fontSize: 12, color: c.textMuted),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _running
                    ? Colors.amber.withValues(alpha: 0.15)
                    : const Color(0xFF10B981).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_running ? 'RUNNING' : 'READY',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: _running ? Colors.amber : const Color(0xFF10B981))),
            ),
          ]),
        ),

        // Steps list
        Expanded(
          child: _steps.isEmpty
              ? _buildEmpty(c)
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: _steps.length + (_running ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == _steps.length && _running) {
                      return _ThinkingStepCard(c: c, isDark: isDark);
                    }
                    return _StepCard(step: _steps[i], isDark: isDark,
                        isLast: i == _steps.length - 1);
                  },
                ),
        ),

        // Status bar bawah
        if (_running || _statusText.isNotEmpty)
          _AgentStatusBar(running: _running, statusText: _statusText, c: c),

        // Input
        _buildInput(c, cs),
        ]),

        // ── Overlay loading saat memproses file ──────────────────────────
        if (_processingFile)
          Positioned.fill(
            child: AbsorbPointer(
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 20),
                        Text('Membaca file…',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: c.text)),
                        const SizedBox(height: 8),
                        Text(
                          _processingFileName,
                          style: TextStyle(fontSize: 12, color: c.textMuted),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _buildEmpty(KmColors c) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('🤖', style: TextStyle(fontSize: 56)),
        const SizedBox(height: 16),
        Text('AI Agent Siap', style: TextStyle(fontSize: 18,
            fontWeight: FontWeight.w700, color: c.text)),
        const SizedBox(height: 8),
        Text(
          'Berikan task apapun — Agent akan merencanakan, '
          'mencari di internet, mengedit file, mendownload, dan melaporkan hasilnya.',
          style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center,
          children: _examples.map((eg) => GestureDetector(
            onTap: () => _runTask(eg),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
              ),
              child: Text(eg, style: const TextStyle(
                  fontSize: 12, color: Color(0xFF6366F1))),
            ),
          )).toList()),
      ]),
    ),
  );

  static const _examples = [
    'Cari berita AI terbaru hari ini',
    'Buat laporan harga Bitcoin hari ini',
    'Download dan ringkas artikel dari URL',
    'Cari 5 tools AI gratis terbaik 2025',
    'Scrape dan ekspor data dari website',
  ];

  Widget _buildInput(KmColors c, ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inputBg = isDark ? const Color(0xFF2A2A2A) : Colors.white;
    final border  = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.12);
    final iconCol  = isDark ? Colors.white54 : Colors.black45;
    final hintCol  = isDark ? Colors.white38 : Colors.black38;
    final textCol  = isDark ? Colors.white.withValues(alpha: 0.87) : Colors.black.withValues(alpha: 0.87);
    final sendEnabled = (_canSend || (_pendingFile != null && !_processingFile)) && !_running && !_processingFile;
    final activeSend = isDark ? Colors.white : Colors.black;
    final activeIcon = isDark ? Colors.black : Colors.white;

    return Container(
      color: c.bg,
      padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 12),
      child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_pendingFile != null)
          _AgentFilePreviewBar(file: _pendingFile!, onRemove: _removePendingFile, c: c),
        Container(
          decoration: BoxDecoration(
            color: inputBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
            boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
                blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 8),
              child: IconButton(
                icon: Icon(Icons.add_rounded, color: iconCol, size: 22),
                onPressed: _running ? null : _showAttachMenu,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34))),
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                maxLines: 4, minLines: 1,
                style: TextStyle(color: textCol, fontSize: 15, height: 1.4),
                textInputAction: TextInputAction.newline,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  hintText: _running ? 'Agent sedang bekerja…'
                      : _pendingFile != null
                          ? 'Instruksi untuk file ini…'
                          : 'Berikan task untuk AI Agent…',
                  hintStyle: TextStyle(color: hintCol, fontSize: 15),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14)),
                enabled: !_running,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 8),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _running
                    ? GestureDetector(
                        key: const ValueKey('stop'),
                        onTap: _stop,
                        child: Container(width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4))),
                          child: const Icon(Icons.stop_rounded, color: Color(0xFFEF4444), size: 18)))
                    : GestureDetector(
                        key: const ValueKey('send'),
                        onTap: sendEnabled ? () => _runTask(_inputCtrl.text) : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: sendEnabled ? activeSend : (isDark ? Colors.white12 : Colors.black12),
                            borderRadius: BorderRadius.circular(8)),
                          child: Icon(Icons.arrow_upward_rounded,
                            color: sendEnabled ? activeIcon : (isDark ? Colors.white24 : Colors.black26),
                            size: 18))),
              )),
          ]),
        ),
      ])),
    );
  }
}

// ── Agent History Drawer ──────────────────────────────────────────────────────

class _AgentHistoryDrawer extends StatelessWidget {
  final List<_TaskRecord>         history;
  final KmColors                  c;
  final VoidCallback              onNewTask;
  final void Function(_TaskRecord) onLoad;

  const _AgentHistoryDrawer({
    required this.history, required this.c,
    required this.onNewTask, required this.onLoad,
  });

  @override
  Widget build(BuildContext context) {
    // Selalu dark sidebar seperti Claude
    const sideBg    = Color(0xFF171717);
    const sideText  = Color(0xFFECECEC);
    const sideMuted = Color(0xFF8A8A8A);
    const sideBrd   = Color(0xFF2A2A2A);

    return Drawer(
      backgroundColor: sideBg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
              child: Row(children: [
                Container(width: 28, height: 28,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF4F46E5)]),
                    borderRadius: BorderRadius.circular(7)),
                  child: const Icon(Icons.precision_manufacturing_rounded,
                      color: Colors.white, size: 14)),
                const SizedBox(width: 10),
                const Text('Riwayat Task',
                    style: TextStyle(color: sideText, fontSize: 15, fontWeight: FontWeight.w600)),
                const Spacer(),
                GestureDetector(onTap: () {
                    Scaffold.of(context).closeDrawer();
                    onNewTask();
                  },
                  child: Container(width: 30, height: 30,
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(7)),
                    child: const Icon(Icons.add_task_rounded, color: sideMuted, size: 16))),
              ]),
            ),
            // New task button
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              child: GestureDetector(onTap: () {
                  Scaffold.of(context).closeDrawer();
                  onNewTask();
                },
                child: Container(width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: sideBrd)),
                  child: const Row(children: [
                    Icon(Icons.add_rounded, color: sideMuted, size: 16),
                    SizedBox(width: 8),
                    Text('Task Baru', style: TextStyle(color: sideText, fontSize: 13.5)),
                  ])))),
            Padding(padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: const Text('RIWAYAT',
                  style: TextStyle(color: sideMuted, fontSize: 10,
                      fontWeight: FontWeight.w700, letterSpacing: 1.2))),
            const Divider(color: sideBrd, height: 1),
            if (history.isEmpty)
              Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: const [
                Icon(Icons.history_rounded, color: sideMuted, size: 30),
                SizedBox(height: 8),
                Text('Belum ada riwayat task',
                    style: TextStyle(color: sideMuted, fontSize: 12)),
              ])))
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  itemCount: history.length,
                  itemBuilder: (_, i) {
                    final r = history[i];
                    return GestureDetector(
                      onTap: () {
                          // Tutup drawer via Scaffold — BUKAN Navigator.pop
                          // (Navigator.pop di sini akan pop AgentScreen itu sendiri)
                          Scaffold.of(context).closeDrawer();
                          onLoad(r);
                        },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
                        child: Row(children: [
                          const Text('🤖', style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(r.title, style: const TextStyle(fontSize: 13, color: sideText),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(_fmtDate(r.createdAt),
                                style: const TextStyle(fontSize: 10.5, color: sideMuted)),
                          ])),
                        ]),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    final now = DateTime.now();
    if (now.difference(dt).inDays == 0)
      return 'Hari ini ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    if (now.difference(dt).inDays == 1) return 'Kemarin';
    return DateFormat('d MMM yyyy', 'id').format(dt);
  }
}

class _AgentStatusBar extends StatefulWidget {
  final bool running; final String statusText; final KmColors c;
  const _AgentStatusBar({required this.running, required this.statusText, required this.c});
  @override State<_AgentStatusBar> createState() => _AgentStatusBarState();
}

class _AgentStatusBarState extends State<_AgentStatusBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final runColor  = const Color(0xFFF59E0B);
    final doneColor = const Color(0xFF10B981);
    final color = widget.running ? runColor : doneColor;
    final bg = isDark
        ? Colors.white.withValues(alpha: 0.03)
        : Colors.black.withValues(alpha: 0.02);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      color: bg,
      child: Row(children: [
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Container(width: 6, height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle,
              color: widget.running
                  ? runColor.withValues(alpha: 0.4 + 0.6 * math.sin(_ctrl.value * 2 * math.pi).abs())
                  : doneColor))),
        const SizedBox(width: 10),
        Expanded(child: Text(widget.statusText,
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}


class _ThinkingStepCard extends StatefulWidget {
  final KmColors c; final bool isDark;
  const _ThinkingStepCard({required this.c, required this.isDark});
  @override State<_ThinkingStepCard> createState() => _ThinkingStepCardState();
}

class _ThinkingStepCardState extends State<_ThinkingStepCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Timeline dot animasi
        Container(width: 26, height: 26,
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3))),
          child: AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => Icon(Icons.more_horiz_rounded,
                size: 14,
                color: const Color(0xFF6366F1).withValues(alpha: 0.5 + 0.5 * _anim.value)))),
        const SizedBox(width: 12),
        Expanded(child: Padding(padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            _MiniDots(isDark: widget.isDark),
            const SizedBox(width: 10),
            Text('Sedang berpikir…',
                style: TextStyle(color: c.textMuted, fontSize: 13,
                    fontStyle: FontStyle.italic)),
            const SizedBox(width: 8),
          ])),
        ),
      ]),
    );
  }
}

class _MiniDots extends StatefulWidget {
  final bool isDark;
  const _MiniDots({required this.isDark});
  @override State<_MiniDots> createState() => _MiniDotsState();
}

class _MiniDotsState extends State<_MiniDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1200))..repeat();
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final dotColor = widget.isDark ? Colors.white54 : Colors.black45;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final delay = i / 3.0;
          final t = ((_ctrl.value - delay) % 1.0).clamp(0.0, 1.0);
          final opacity = 0.2 + 0.8 * math.sin(t * math.pi).clamp(0.0, 1.0);
          final scale   = 0.8 + 0.2 * math.sin(t * math.pi).clamp(0.0, 1.0);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Transform.scale(scale: scale,
              child: Container(width: 5, height: 5,
                decoration: BoxDecoration(
                  color: dotColor.withValues(alpha: opacity),
                  shape: BoxShape.circle))));
        }),
      ),
    );
  }
}

// ── Step Card ─────────────────────────────────────────────────────────────────

class _StepCard extends StatelessWidget {
  final AgentStep step; final bool isDark; final bool isLast;
  const _StepCard({required this.step, required this.isDark, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    final (icon, color, bg) = switch (step.type) {
      AgentStepType.thinking   => ('💭', const Color(0xFF6366F1), const Color(0xFF6366F1)),
      AgentStepType.planning   => ('📋', const Color(0xFF0EA5E9), const Color(0xFF0EA5E9)),
      AgentStepType.toolCall   => ('🔧', const Color(0xFFF59E0B), const Color(0xFFF59E0B)),
      AgentStepType.toolResult => ('📊', const Color(0xFF10B981), const Color(0xFF10B981)),
      AgentStepType.answer     => ('✅', const Color(0xFF10B981), const Color(0xFF10B981)),
      AgentStepType.error      => ('❌', Colors.red, Colors.red),
      AgentStepType.fileOutput => ('📎', const Color(0xFF8B5CF6), const Color(0xFF8B5CF6)),
      AgentStepType.installing => ('⬇️', const Color(0xFFF59E0B), const Color(0xFFF59E0B)),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Timeline kiri
        Column(children: [
          Container(width: 26, height: 26,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.25))),
            child: Center(child: Text(icon, style: const TextStyle(fontSize: 11)))),
          if (!isLast)
            Container(width: 1.5, height: 16, margin: const EdgeInsets.symmetric(vertical: 3),
                color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.07)),
        ]),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
              child: Text(step.type.name.toUpperCase(),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                      color: color, letterSpacing: 0.5))),
            const Spacer(),
            Text(
              '${step.time.hour.toString().padLeft(2,'0')}:'
              '${step.time.minute.toString().padLeft(2,'0')}:'
              '${step.time.second.toString().padLeft(2,'0')}',
              style: TextStyle(fontSize: 10, color: c.textMuted)),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => Clipboard.setData(ClipboardData(text: step.content)),
              child: Icon(Icons.copy_rounded, size: 13, color: c.textMuted)),
          ]),
          const SizedBox(height: 7),
          SelectableText(step.content,
              style: TextStyle(fontSize: 13.5, color: c.text, height: 1.55)),
        // Download button
        if (step.type == AgentStepType.fileOutput && step.outputFilePath != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: GestureDetector(
              onTap: () => _shareFile(context, step.outputFilePath!),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)]),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.download_rounded, size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(step.outputFilePath!.split('/').last,
                      style: const TextStyle(fontSize: 12, color: Colors.white,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        // Export buttons
        if (step.type == AgentStepType.answer ||
            step.type == AgentStepType.toolResult)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              for (final fmt in ['txt', 'md', 'json'])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => _export(context, step.content, fmt),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: bg.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: bg.withValues(alpha: 0.2)),
                      ),
                      child: Text('Ekspor $fmt',
                          style: TextStyle(fontSize: 10, color: color,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
            ]),
          ),
        ])),
      ]),
    );
  }

  Future<void> _export(BuildContext ctx, String content, String format) async {
    final result = await ExportService.instance.export(data: content, format: format);
    if (result.isSuccess && ctx.mounted) {
      showTopSnack(ctx, '✅ Ekspor: ${result.filename}', duration: const Duration(seconds: 4)).instance.shareFile(result.path);
        }),
      ));
    }
  }

  Future<void> _shareFile(BuildContext ctx, String filePath) async {
    try {
      await ExportService.instance.shareFile(filePath);
    } catch (e) {
      if (ctx.mounted) {
        showTopSnack(ctx, '❌ Gagal berbagi file: $e', isError: true);
      }
    }
  }
}

// ── Agent File Preview Bar ────────────────────────────────────────────────────

class _AgentFilePreviewBar extends StatelessWidget {
  final ProcessedFile file; final VoidCallback onRemove; final KmColors c;
  const _AgentFilePreviewBar({required this.file, required this.onRemove, required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        if (file.rawBytes != null && file.mimeType.startsWith('image/'))
          ClipRRect(borderRadius: BorderRadius.circular(6),
            child: Image.memory(file.rawBytes!, width: 40, height: 40, fit: BoxFit.cover))
        else
          Container(width: 40, height: 40,
            decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: Text(file.icon, style: const TextStyle(fontSize: 20))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(file.filename, style: TextStyle(fontSize: 13,
              fontWeight: FontWeight.w600, color: c.text),
              overflow: TextOverflow.ellipsis),
          Text('${file.sizeLabel} · ${file.mimeType.split('/').last.toUpperCase()}',
              style: TextStyle(fontSize: 11, color: c.textMuted)),
        ])),
        IconButton(icon: Icon(Icons.close_rounded, size: 18, color: c.textMuted),
          onPressed: onRemove, padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
      ]),
    );
  }
}

// ── Agent Icon Button ─────────────────────────────────────────────────────────

class _AgentIconBtn extends StatelessWidget {
  final IconData icon; final Color color, bgColor; final VoidCallback? onTap;
  const _AgentIconBtn({required this.icon, required this.color,
      required this.bgColor, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(width: 40, height: 40,
        decoration: BoxDecoration(shape: BoxShape.circle, color: bgColor),
        child: Icon(icon, color: onTap != null ? color : color.withValues(alpha: 0.35),
            size: 22)),
    );
  }
}

// ── Attach Option ─────────────────────────────────────────────────────────────

class _AttachOption extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _AttachOption({required this.icon, required this.label,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(width: 72,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 52, height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: color, size: 26)),
          const SizedBox(height: 5),
          Text(label, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5,
                  color: KmColors.of(context).text, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

// ── AI Mode Badge ─────────────────────────────────────────────────────────────

class _AiModeBadge extends StatelessWidget {
  final Widget child;
  const _AiModeBadge({required this.child});

  @override
  Widget build(BuildContext context) {
    final mode = AiService.instance.currentMode;
    final (label, color) = switch (mode) {
      AiMode.offline => ('OFF', Colors.teal),
      AiMode.online  => ('ON',  const Color(0xFF10B981)),
      AiMode.bulkApi => ('API', const Color(0xFF6366F1)),
      AiMode.none    => ('?',   Colors.grey),
    };
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: 4,
          top: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 7,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// AGENT SETTINGS SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class AgentSettingsScreen extends StatefulWidget {
  const AgentSettingsScreen({super.key});
  @override State<AgentSettingsScreen> createState() => _AgentSettingsState();
}

class _AgentSettingsState extends State<AgentSettingsScreen> {
  final _svc = AgentService.instance;
  late AgentConfig _cfg;
  final _nameCtrl    = TextEditingController();
  final _promptCtrl  = TextEditingController();
  final _apiKeyCtrl  = TextEditingController();
  final _apiNameCtrl = TextEditingController();

  static const _allTools = {
    'web_search':         ('🔍', 'Web Search', 'Cari di Google/DuckDuckGo'),
    'web_fetch':          ('🌐', 'Web Fetch', 'Ambil konten halaman web'),
    'read_file':          ('📖', 'Read File', 'Baca file di workspace'),
    'write_file':         ('✏️', 'Write File', 'Tulis & buat file'),
    'append_file':        ('➕', 'Append File', 'Tambah konten ke file'),
    'list_files':         ('📋', 'List Files', 'Tampilkan daftar file'),
    'run_command':        ('💻', 'Run Command', 'Jalankan shell command'),
    'download_file':      ('⬇️', 'Download', 'Download file dari internet'),
    'export_data':        ('📤', 'Export Data', 'Ekspor data ke file'),
    'remember':           ('🧠', 'Remember', 'Simpan ke memori jangka panjang'),
    'recall':             ('💡', 'Recall', 'Ambil dari memori'),
    'api_call':           ('🔌', 'API Call', 'Panggil REST API eksternal'),
    'edit_media':         ('🎬', 'Edit Media', 'Edit gambar/video/audio via ffmpeg'),
    'check_install_tool': ('🔧', 'Install Tool', 'Cek & install tool sistem'),
    'send_file_to_user':  ('📎', 'Send File', 'Kirim file hasil ke user'),
    'list_workspace':     ('🗂️', 'List Workspace', 'Tampilkan semua file di workspace KanMonAI'),
  };

  @override
  void initState() {
    super.initState();
    _cfg = _svc.config;
    _nameCtrl.text   = _cfg.name;
    _promptCtrl.text = _cfg.systemPrompt;
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _promptCtrl.dispose();
    _apiKeyCtrl.dispose(); _apiNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final updated = _cfg.copyWith(
      name: _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : 'KanMon Agent',
      systemPrompt: _promptCtrl.text.trim(),
    );
    await _svc.saveConfig(updated);
    if (mounted) {
      Navigator.pop(context);
      showTopSnack(context, '✅ Pengaturan agent disimpan');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c      = KmColors.of(context);
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg, elevation: 0,
        title: Text('Pengaturan Agent', style: TextStyle(
            color: c.text, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: c.text, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(onPressed: _save,
              child: Text('Simpan', style: TextStyle(color: cs.primary,
                  fontWeight: FontWeight.w700))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(title: '🧠 Model AI', isDark: isDark, c: c, children: [
            _AgentModelPicker(isDark: isDark, c: c, cs: cs),
          ]),
          const SizedBox(height: 16),
          _Section(title: '🤖 Identitas Agent', isDark: isDark, c: c, children: [
            _Field(label: 'Nama Agent', controller: _nameCtrl, hint: 'Contoh: KanMon Agent'),
            const SizedBox(height: 12),
            _Field(label: 'System Prompt (opsional)', controller: _promptCtrl,
                hint: 'Instruksi khusus untuk agent ini.\nKosongkan untuk gunakan default.',
                maxLines: 4),
          ]),
          const SizedBox(height: 16),
          _Section(title: '⚙️ Perilaku Agent', isDark: isDark, c: c, children: [
            _ToggleRow(label: 'Auto Approve Tools',
                subtitle: 'Agent jalankan tools tanpa persetujuan tiap langkah',
                value: _cfg.autoApproveTools,
                onChanged: (v) => setState(() => _cfg = _cfg.copyWith(autoApproveTools: v))),
            _ToggleRow(label: 'Gunakan Memori',
                subtitle: 'Agent ingat konteks dari task sebelumnya',
                value: _cfg.useMemory,
                onChanged: (v) => setState(() => _cfg = _cfg.copyWith(useMemory: v))),
            _ToggleRow(label: 'Simpan History',
                subtitle: 'Simpan hasil task ke memori jangka panjang',
                value: _cfg.saveHistory,
                onChanged: (v) => setState(() => _cfg = _cfg.copyWith(saveHistory: v))),
            const SizedBox(height: 8),
            Row(children: [
              Text('Maks langkah per task:',
                  style: TextStyle(color: c.text, fontSize: 14)),
              const Spacer(),
              DropdownButton<int>(
                value: _cfg.maxSteps,
                dropdownColor: c.surface,
                style: TextStyle(color: c.text, fontSize: 14),
                underline: const SizedBox(),
                items: [5, 10, 15, 20, 30, 50, 100, 200, 500, 1000].map((n) =>
                    DropdownMenuItem(value: n, child: Text('$n'))).toList(),
                onChanged: (v) => setState(() => _cfg = _cfg.copyWith(maxSteps: v ?? 10)),
              ),
            ]),
          ]),
          const SizedBox(height: 16),
          _Section(title: '🔧 Tools yang Diaktifkan', isDark: isDark, c: c, children: [
            for (final entry in _allTools.entries) ...[
              _ToolToggle(
                icon: entry.value.$1, name: entry.value.$2,
                desc: entry.value.$3, toolKey: entry.key,
                enabled: _cfg.enabledTools.contains(entry.key),
                onChanged: (v) {
                  final tools = List<String>.from(_cfg.enabledTools);
                  if (v) tools.add(entry.key); else tools.remove(entry.key);
                  setState(() => _cfg = _cfg.copyWith(enabledTools: tools));
                },
              ),
              if (entry.key != _allTools.keys.last)
                Divider(color: c.border, height: 1),
            ],
          ]),
          const SizedBox(height: 16),
          _Section(title: '🔑 API Keys', isDark: isDark, c: c, children: [
            Text('Tambahkan API key untuk services yang digunakan agent.\n'
                 'Contoh: openai, news_api, weather, currency',
                style: TextStyle(fontSize: 12, color: c.textMuted)),
            const SizedBox(height: 12),
            for (final entry in _cfg.apiKeys.entries)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border),
                ),
                child: Row(children: [
                  const Icon(Icons.key_rounded, size: 16, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(entry.key, style: TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w600, color: c.text)),
                    Text('${entry.value.substring(0, entry.value.length.clamp(0, 8))}••••••••',
                        style: TextStyle(fontSize: 11, color: c.textMuted,
                            fontFamily: 'monospace')),
                  ])),
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded,
                        color: Colors.red.shade400, size: 18),
                    onPressed: () {
                      final keys = Map<String, String>.from(_cfg.apiKeys);
                      keys.remove(entry.key);
                      setState(() => _cfg = _cfg.copyWith(apiKeys: keys));
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                  ),
                ]),
              ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(flex: 2,
                child: TextField(controller: _apiNameCtrl,
                  style: TextStyle(color: c.text, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Nama (misal: openai)',
                    hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                    filled: true,
                    fillColor: isDark ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.03),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: c.border)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                  ))),
              const SizedBox(width: 6),
              Expanded(flex: 3,
                child: TextField(controller: _apiKeyCtrl, obscureText: true,
                  style: TextStyle(color: c.text, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'API Key',
                    hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                    filled: true,
                    fillColor: isDark ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.03),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: c.border)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                  ))),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () {
                  final name = _apiNameCtrl.text.trim();
                  final key  = _apiKeyCtrl.text.trim();
                  if (name.isEmpty || key.isEmpty) return;
                  final keys = Map<String, String>.from(_cfg.apiKeys);
                  keys[name] = key;
                  setState(() => _cfg = _cfg.copyWith(apiKeys: keys));
                  _apiNameCtrl.clear(); _apiKeyCtrl.clear();
                },
                child: Container(width: 36, height: 36,
                  decoration: BoxDecoration(color: cs.primary,
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.add_rounded, color: Colors.white, size: 20)),
              ),
            ]),
          ]),
          const SizedBox(height: 16),
          _Section(title: '🧠 Memori Agent', isDark: isDark, c: c, children: [
            Row(children: [
              Expanded(child: Text('Hapus semua memori agent',
                  style: TextStyle(color: c.text, fontSize: 14))),
              OutlinedButton.icon(
                onPressed: () async {
                  await AgentMemoryService.instance.clear();
                  if (context.mounted) {
                    showTopSnack(context, '✅ Memori dihapus');
                  }
                },
                icon: const Icon(Icons.delete_forever_rounded, size: 16),
                label: const Text('Hapus', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.red.shade400),
                    foregroundColor: Colors.red.shade400),
              ),
            ]),
          ]),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_rounded, size: 20),
            label: const Text('Simpan Pengaturan',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Shared Widgets ────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title; final bool isDark; final KmColors c;
  final List<Widget> children;
  const _Section({required this.title, required this.isDark,
      required this.c, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
          color: c.text)),
      const SizedBox(height: 8),
      Container(
        width: double.infinity, padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.04)
              : Colors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).colorScheme.outline
              .withValues(alpha: 0.15)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: children),
      ),
    ]);
  }
}

class _Field extends StatelessWidget {
  final String label; final TextEditingController controller;
  final String hint; final int maxLines;
  const _Field({required this.label, required this.controller,
      required this.hint, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    final c  = KmColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, color: c.textMuted,
          fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      TextField(controller: controller, maxLines: maxLines, minLines: 1,
        style: TextStyle(color: c.text, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: c.textMuted, fontSize: 13),
          filled: true,
          fillColor: isDark ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.03),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.25))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: cs.primary, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        )),
    ]);
  }
}

class _ToggleRow extends StatelessWidget {
  final String label, subtitle; final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({required this.label, required this.subtitle,
      required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 14, color: c.text)),
          Text(subtitle, style: TextStyle(fontSize: 11, color: c.textMuted)),
        ])),
        Switch.adaptive(value: value, onChanged: onChanged,
            activeColor: Theme.of(context).colorScheme.primary),
      ]),
    );
  }
}

class _ToolToggle extends StatelessWidget {
  final String icon, name, desc, toolKey;
  final bool enabled; final ValueChanged<bool> onChanged;
  const _ToolToggle({required this.icon, required this.name, required this.desc,
      required this.toolKey, required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: TextStyle(fontSize: 13,
              fontWeight: FontWeight.w600, color: c.text)),
          Text(desc, style: TextStyle(fontSize: 11, color: c.textMuted)),
        ])),
        Switch.adaptive(value: enabled, onChanged: onChanged,
            activeColor: Theme.of(context).colorScheme.primary),
      ]),
    );
  }
}

class _AgentModelPicker extends StatefulWidget {
  final bool isDark; final KmColors c; final ColorScheme cs;
  const _AgentModelPicker({required this.isDark, required this.c, required this.cs});
  @override State<_AgentModelPicker> createState() => _AgentModelPickerState();
}

class _AgentModelPickerState extends State<_AgentModelPicker> {
  final _modelSvc = ModelManagerService.instance;

  @override
  void initState() {
    super.initState();
    _modelSvc.load().then((_) { if (mounted) setState(() {}); });
  }

  @override
  Widget build(BuildContext context) {
    final models = _modelSvc.models;
    final c  = widget.c; final cs = widget.cs; final isDark = widget.isDark;

    if (models.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.04)
              : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Row(children: [
          const Text('🤖', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Belum ada model AI', style: TextStyle(color: c.text,
                fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('Import model di Settings → Model Manager\nlalu aktifkan untuk dipakai Agent.',
                style: TextStyle(color: c.textMuted, fontSize: 11, height: 1.4)),
          ])),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Pilih model yang akan digunakan Agent:',
          style: TextStyle(color: c.textMuted, fontSize: 12)),
      const SizedBox(height: 8),
      ...models.map((model) {
        final isActive = model.id == ModelManagerService.instance.activeModel?.id;
        return GestureDetector(
          onTap: () async {
            await _modelSvc.setActive(model.id);
            // Muat model aktif menggunakan LlamaService (arsitektur PocketPal)
            final activeModel = ModelManagerService.instance.activeModel;
            if (activeModel != null) {
              await LlamaService.instance.loadModel(activeModel);
            }
            if (mounted) setState(() {});
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isActive ? cs.primary.withValues(alpha: 0.1)
                  : isDark ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive ? cs.primary.withValues(alpha: 0.4) : c.border,
                width: isActive ? 1.5 : 1,
              ),
            ),
            child: Row(children: [
              Text(model.format == 'gguf' || model.format == 'ggml' ? '🤖' : '📦',
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(model.name, style: TextStyle(color: c.text,
                    fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                Text('${model.format.toUpperCase()} · ${model.sizeLabel}',
                    style: TextStyle(color: c.textMuted, fontSize: 11)),
              ])),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Aktif', style: TextStyle(color: cs.primary,
                      fontSize: 10, fontWeight: FontWeight.w700)),
                )
              else
                Icon(Icons.radio_button_unchecked_rounded,
                    color: c.textMuted, size: 18),
            ]),
          ),
        );
      }),
    ]);
  }
}
