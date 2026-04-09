// lib/data/services/ai/agent_service.dart
// KanMon GO — AI Agent Orchestrator (ReAct loop)
// =============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kanmongo/data/services/ai/ai_service.dart';
import 'package:kanmongo/data/services/ai/offline_ai_service.dart';
import 'package:kanmongo/data/services/content/model_manager_service.dart';
import 'package:kanmongo/data/services/ai/web_scraper_service.dart';
import 'package:kanmongo/data/services/system/terminal_service.dart';
import 'package:kanmongo/data/services/content/export_service.dart';
import 'package:kanmongo/data/services/ai/agent_memory_service.dart';
import 'package:kanmongo/data/services/media/media_edit_service.dart';
import 'package:kanmongo/data/services/system/tool_installer_service.dart';
import 'package:kanmongo/data/services/content/history_service.dart';
import 'package:kanmongo/data/services/ai/kanmonai_system_prompt.dart';

// ── Tool result ───────────────────────────────────────────────────────────────
class ToolResult {
  final String toolName;
  final Map<String, dynamic> params;
  final String output;
  final bool success;
  final DateTime executedAt;

  const ToolResult({
    required this.toolName,
    required this.params,
    required this.output,
    required this.success,
    required this.executedAt,
  });
}

// ── Agent step (untuk UI) ─────────────────────────────────────────────────────
class AgentStep {
  final AgentStepType type;
  final String content;
  final ToolResult? toolResult;
  final DateTime time;
  final String? outputFilePath;

  const AgentStep({
    required this.type,
    required this.content,
    this.toolResult,
    required this.time,
    this.outputFilePath,
  });
}

enum AgentStepType {
  thinking,
  planning,
  toolCall,
  toolResult,
  answer,
  error,
  fileOutput,
  installing,
}

// ── Agent config ──────────────────────────────────────────────────────────────
class AgentConfig {
  final String name;
  final String systemPrompt;
  final int maxSteps;
  final bool autoApproveTools;
  final bool saveHistory;
  final bool useMemory;
  final List<String> enabledTools;
  final Map<String, String> apiKeys;

  const AgentConfig({
    this.name = 'KanMon Agent',
    this.systemPrompt = '',
    this.maxSteps = 10,
    this.autoApproveTools = true,
    this.saveHistory = true,
    this.useMemory = true,
    this.enabledTools = const [
      'web_search', 'web_fetch', 'read_file', 'write_file', 'append_file',
      'list_files', 'run_command', 'download_file', 'export_data',
      'remember', 'recall', 'api_call',
      'edit_media', 'check_install_tool', 'send_file_to_user', 'list_workspace',
    ],
    this.apiKeys = const {},
  });

  AgentConfig copyWith({
    String? name, String? systemPrompt, int? maxSteps,
    bool? autoApproveTools, bool? saveHistory, bool? useMemory,
    List<String>? enabledTools, Map<String, String>? apiKeys,
  }) => AgentConfig(
    name: name ?? this.name,
    systemPrompt: systemPrompt ?? this.systemPrompt,
    maxSteps: maxSteps ?? this.maxSteps,
    autoApproveTools: autoApproveTools ?? this.autoApproveTools,
    saveHistory: saveHistory ?? this.saveHistory,
    useMemory: useMemory ?? this.useMemory,
    enabledTools: enabledTools ?? this.enabledTools,
    apiKeys: apiKeys ?? this.apiKeys,
  );

  Map<String, dynamic> toJson() => {
    'name': name, 'systemPrompt': systemPrompt,
    'maxSteps': maxSteps, 'autoApproveTools': autoApproveTools,
    'saveHistory': saveHistory, 'useMemory': useMemory,
    'enabledTools': enabledTools, 'apiKeys': apiKeys,
  };

  factory AgentConfig.fromJson(Map<String, dynamic> j) => AgentConfig(
    name: j['name'] ?? 'KanMon Agent',
    systemPrompt: j['systemPrompt'] ?? '',
    maxSteps: j['maxSteps'] ?? 10,
    autoApproveTools: j['autoApproveTools'] ?? true,
    saveHistory: j['saveHistory'] ?? true,
    useMemory: j['useMemory'] ?? true,
    enabledTools: List<String>.from(j['enabledTools'] ?? []),
    apiKeys: Map<String, String>.from(j['apiKeys'] ?? {}),
  );
}

// ── Agent Service ─────────────────────────────────────────────────────────────
class AgentService {
  AgentService._();
  static final AgentService instance = AgentService._();

  static const _configKey = 'km_agent_config';

  AgentConfig _config = const AgentConfig();
  AgentConfig get config => _config;

  bool _running = false;
  bool get isRunning => _running;

  Future<void> loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_configKey);
      if (raw != null) {
        _config = AgentConfig.fromJson(jsonDecode(raw));
      }
    } catch (e) {
      debugPrint('[Agent] loadConfig error: $e');
    }
  }

  Future<void> saveConfig(AgentConfig cfg) async {
    _config = cfg;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, jsonEncode(cfg.toJson()));
  }

  /// Reset paksa flag _running — dipanggil dari UI saat stream di-cancel.
  void forceStop() {
    _running = false;
    debugPrint('[Agent] forceStop() — _running di-reset');
  }

  // ── Run Agent ─────────────────────────────────────────────────────────────
  Stream<AgentStep> run({
    required String task,
    AgentConfig? config,
    bool Function(String toolName, Map<String, dynamic> params)? onApprove,
  }) async* {
    // Jika masih running (flag tersisa dari sesi sebelumnya), reset dulu.
    // Ini mencegah "Agent sedang berjalan" palsu setelah user stop.
    if (_running) {
      debugPrint('[Agent] run() dipanggil saat _running=true — auto-reset');
      _running = false;
      // Jeda singkat agar native engine juga sempat bersih
      await Future.delayed(const Duration(milliseconds: 100));
    }

    _running = true;
    final cfg = config ?? _config;

    String memoryContext = '';
    if (cfg.useMemory) {
      final memories = await AgentMemoryService.instance.search(task);
      if (memories.isNotEmpty) {
        memoryContext = '\n\nRELEVANT MEMORIES:\n${memories.map((m) => '- ${m.content}').join('\n')}';
      }
    }

    final workspaceDir = await _getWorkspaceDir();

    final systemPrompt = '''${cfg.systemPrompt.isNotEmpty ? cfg.systemPrompt : _defaultSystemPrompt(cfg)}$memoryContext

WORKSPACE DIRECTORY: $workspaceDir

TOOLS AVAILABLE:
${_toolDescriptions(cfg.enabledTools)}

RULES:
1. Buat rencana sebelum bertindak
2. Gunakan tool yang paling tepat untuk setiap langkah
3. Setelah setiap tool, analisis hasilnya sebelum melanjutkan
4. Untuk web_search: mulai dengan query singkat, gunakan web_fetch untuk detail
5. Untuk file: gunakan path relatif (workspace) atau path absolut lengkap
6. Tulis FINAL_ANSWER: [jawaban] ketika selesai — WAJIB di setiap akhir task

FORMAT TOOL CALL (WAJIB gunakan format ini persis):
{"tool": "nama_tool", "params": {"key": "value"}}

Contoh:
{"tool": "web_search", "params": {"query": "berita teknologi terbaru", "max_results": 5}}
{"tool": "write_file", "params": {"filename": "hasil.txt", "content": "isi file"}}
{"tool": "run_command", "params": {"command": "python3 --version"}}
''';

    final history = <Map<String, String>>[];
    int step = 0;

    try {
      yield AgentStep(type: AgentStepType.thinking,
          content: '🤔 Memproses task: "$task"', time: DateTime.now());

      // ── FIX #1: Pre-load model offline sebelum loop dimulai ─────────────
      // Sama persis dengan pattern di chat_screen.dart yang sudah bekerja.
      // Tanpa ini, model tidak dimuat dan AI stream hang tanpa output.
      if (AiService.instance.currentMode == AiMode.offline) {
        if (OfflineAiService.instance.isLoading) {
          yield AgentStep(type: AgentStepType.thinking,
              content: '⏳ Menunggu model AI selesai dimuat…', time: DateTime.now());
          int waited = 0;
          while (OfflineAiService.instance.isLoading && waited < 60) {
            await Future.delayed(const Duration(seconds: 1));
            waited++;
          }
          if (!OfflineAiService.instance.isReady) {
            yield AgentStep(type: AgentStepType.error,
                content: '❌ Model tidak berhasil dimuat dalam 60 detik.\n'
                    'Restart aplikasi atau cek Settings → Model Manager.',
                time: DateTime.now());
            return;
          }
        } else if (!OfflineAiService.instance.isReady) {
          final active = ModelManagerService.instance.activeModel;
          if (active == null) {
            yield AgentStep(type: AgentStepType.error,
                content: '❌ Belum ada model offline aktif.\n\n'
                    'Buka Settings → Model Manager → import file .gguf → aktifkan.',
                time: DateTime.now());
            return;
          }
          yield AgentStep(type: AgentStepType.thinking,
              content: '⏳ Memuat model AI offline: ${active.name}…', time: DateTime.now());
          await OfflineAiService.instance.loadSettings();
          await OfflineAiService.instance.loadActiveModel();
          if (!OfflineAiService.instance.isReady) {
            yield AgentStep(type: AgentStepType.error,
                content: '❌ Gagal memuat model: ${OfflineAiService.instance.error ?? "Unknown error"}\n\n'
                    'Coba import ulang model di Settings → Model Manager.',
                time: DateTime.now());
            return;
          }
          yield AgentStep(type: AgentStepType.thinking,
              content: '✅ Model AI siap — ${active.name}', time: DateTime.now());
        }
      }

      while (step < cfg.maxSteps) {
        step++;
        final userMsg = step == 1
            ? 'Task: $task'
            : 'Lanjutkan. Langkah $step dari ${cfg.maxSteps} maksimum.';

        yield AgentStep(type: AgentStepType.thinking,
            content: '⚡ Langkah $step/${cfg.maxSteps} — AI berpikir...', time: DateTime.now());

        // ── FIX #2: Ganti await-for dengan Completer+listen ────────────────
        // await-for di dalam async* generator bisa HANG permanen karena:
        //   • EventChannel done-signal tidak propagasi saat ada backpressure
        //   • Cancellation dari luar (_sub.cancel()) tidak selalu masuk ke inner stream
        // Solusi: Completer<String> + timeout 120s, PERSIS seperti chat_screen pattern.
        final response = (await _collectAiResponse(
          systemPrompt: systemPrompt,
          history:      history,
          userMessage:  userMsg,
          temperature:  0.3,
          maxTokens:    2048,
        )).trim();
        history.add({'role': 'user', 'content': userMsg});
        history.add({'role': 'assistant', 'content': response});

        // FIX: Guard — jika response kosong, hentikan lebih awal dengan pesan jelas
        if (response.isEmpty) {
          debugPrint('[Agent] WARNING: Response kosong di step $step — kemungkinan AI tidak merespons');
          yield AgentStep(
            type: AgentStepType.error,
            content: '⚠️ AI tidak menghasilkan respons di langkah $step.\n\n'
                'Kemungkinan penyebab:\n'
                '• Model offline belum dimuat — buka Settings → Model Manager\n'
                '• Sumber AI tidak terkonfigurasi (cek ikon sumber di AppBar)\n'
                '• Context window terlalu panjang — coba task yang lebih singkat\n\n'
                'Jika model sudah aktif, coba restart aplikasi.',
            time: DateTime.now(),
          );
          break;
        }

        // Tampilkan thinking/planning text
        final thinkingText = _extractThinking(response);
        if (thinkingText.isNotEmpty) {
          yield AgentStep(type: AgentStepType.planning,
              content: thinkingText, time: DateTime.now());
        }

        // Check FINAL_ANSWER
        if (response.contains('FINAL_ANSWER:')) {
          final idx    = response.indexOf('FINAL_ANSWER:');
          final answer = response.substring(idx + 13).trim();
          yield AgentStep(type: AgentStepType.answer,
              content: answer, time: DateTime.now());

          if (cfg.useMemory && cfg.saveHistory && answer.isNotEmpty) {
            await AgentMemoryService.instance.save(
              key: 'task_${DateTime.now().millisecondsSinceEpoch}',
              content: 'Task: $task\nResult: ${answer.substring(0, answer.length.clamp(0, 300))}',
            );
          }
          break;
        }

        // Parse tool calls
        final toolCalls = _extractToolCalls(response);

        if (toolCalls.isEmpty) {
          // Tidak ada tool call
          if (step >= 2 && response.length > 50) {
            // Response cukup panjang dan bukan hasil error — anggap jawaban final
            yield AgentStep(type: AgentStepType.answer,
                content: response, time: DateTime.now());
            break;
          }
          // Step 1, atau response terlalu pendek (mungkin cuma error msg) → lanjut
          continue;
        }

        // Eksekusi tools
        for (final call in toolCalls) {
          final toolName = call['tool'] as String? ?? '';
          final params   = Map<String, dynamic>.from(call['params'] as Map? ?? {});

          if (toolName.isEmpty || !cfg.enabledTools.contains(toolName)) {
            history.add({'role': 'user',
              'content': 'Tool "$toolName" tidak dikenal atau tidak diaktifkan.'});
            continue;
          }

          yield AgentStep(
            type: AgentStepType.toolCall,
            content: '🔧 Menjalankan: **$toolName**\nParams: ${jsonEncode(params)}',
            time: DateTime.now(),
          );

          if (!cfg.autoApproveTools && onApprove != null) {
            final approved = onApprove(toolName, params);
            if (!approved) {
              history.add({'role': 'user',
                'content': 'Tool result for $toolName: Ditolak oleh user.'});
              continue;
            }
          }

          final result = await _executeTool(toolName, params, cfg);

          String? outputFilePath;
          String displayOutput = result.output;
          if (result.output.contains('FILE_OUTPUT:')) {
            final lines    = result.output.split('\n');
            final fileLine = lines.firstWhere(
                (l) => l.contains('FILE_OUTPUT:'), orElse: () => '');
            if (fileLine.isNotEmpty) {
              outputFilePath = fileLine.replaceAll(RegExp(r'.*FILE_OUTPUT:'), '').trim();
              displayOutput  = lines.where((l) => !l.contains('FILE_OUTPUT:')).join('\n');
            }
          }

          yield AgentStep(
            type: outputFilePath != null ? AgentStepType.fileOutput : AgentStepType.toolResult,
            content: result.success
                ? '✅ ${_truncate(displayOutput, 800)}'
                : '❌ Error: $displayOutput',
            toolResult: result,
            outputFilePath: outputFilePath,
            time: DateTime.now(),
          );

          history.add({
            'role': 'user',
            'content': 'Tool result for $toolName:\n${_truncate(result.output, 3000)}',
          });
        }
      }

      if (step >= cfg.maxSteps) {
        yield AgentStep(
          type: AgentStepType.error,
          content: '⚠️ Batas maksimum $step langkah tercapai.',
          time: DateTime.now(),
        );
      }

    } catch (e, st) {
      debugPrint('[Agent] run error: $e\n$st');
      yield AgentStep(type: AgentStepType.error,
          content: '❌ Agent error: $e', time: DateTime.now());
    } finally {
      _running = false;
      // Simpan ke history
      try {
        final summary = 'Agent: ${task.substring(0, task.length.clamp(0, 100))}';
        await HistoryService.instance.saveEntry(AiHistoryEntry(
          id:        0,
          sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
          feature:   'agent',
          summary:   summary,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
      } catch (e) {
        debugPrint('[AgentService] history save error: $e');
      }
    }
  }

  // ── Collect AI response via subscription (bukan await-for) ───────────────
  // Menggunakan Completer<String> + .listen() persis seperti chat_screen.dart.
  // Ini mencegah hang permanen yang terjadi saat await-for dipakai di async* generator
  // dengan EventChannel, karena backpressure dan cancellation propagation yang tidak
  // reliable di Dart dalam konteks ini.
  Future<String> _collectAiResponse({
    required String systemPrompt,
    required List<Map<String, String>> history,
    required String userMessage,
    double temperature = 0.3,
    int maxTokens = 2048,
  }) async {
    final completer = Completer<String>();
    final sb        = StringBuffer();

    StreamSubscription<String>? sub;

    sub = AiService.instance.sendChatStream(
      systemPrompt: systemPrompt,
      history:      history,
      userMessage:  userMessage,
      temperature:  temperature,
      maxTokens:    maxTokens,
    ).listen(
      (token) {
        sb.write(token);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete(sb.toString());
      },
      onError: (Object e) {
        debugPrint('[Agent] _collectAiResponse stream error: $e');
        if (!completer.isCompleted) completer.complete(sb.toString());
      },
      cancelOnError: false,
    );

    try {
      // Timeout 35 detik — sedikit lebih dari chatStream() timeout 30s [FIX-BUG6]
      return await completer.future.timeout(
        const Duration(seconds: 35),
        onTimeout: () {
          debugPrint('[Agent] _collectAiResponse TIMEOUT setelah 35s');
          return sb.isNotEmpty
              ? sb.toString()
              : '⚠️ AI tidak merespons dalam 120 detik. Coba lagi.';
        },
      );
    } finally {
      await sub.cancel();
    }
  }

  // ── Eksekusi tool ─────────────────────────────────────────────────────────
  Future<ToolResult> _executeTool(
      String toolName, Map<String, dynamic> params, AgentConfig cfg) async {
    final start = DateTime.now();

    try {
      String output = '';

      switch (toolName) {

        // ── Web Search ──────────────────────────────────────────────────────
        case 'web_search':
          final query  = params['query'] as String? ?? '';
          final engine = (params['engine'] as String? ?? 'ddg').toLowerCase();
          final maxR   = (params['max_results'] as num?)?.toInt() ?? 8;

          if (query.isEmpty) {
            output = '❌ Parameter "query" wajib diisi.';
            break;
          }

          List<SearchResult> results;
          if (engine == 'google') {
            results = await WebScraperService.instance.searchGoogle(query, maxResults: maxR);
          } else {
            results = await WebScraperService.instance.searchDDG(query, maxResults: maxR);
          }

          if (results.isEmpty) {
            output = 'Tidak ada hasil untuk: "$query"\n'
                'Coba ubah kata kunci atau gunakan engine berbeda.';
          } else {
            final sb = StringBuffer('Search results for "$query" (${results.length} hasil):\n\n');
            for (int i = 0; i < results.length; i++) {
              final r = results[i];
              sb.writeln('${i + 1}. ${r.title}');
              sb.writeln('   URL: ${r.url}');
              if (r.snippet.isNotEmpty) sb.writeln('   ${r.snippet}');
              sb.writeln();
            }
            output = sb.toString().trim();
          }
          break;

        // ── Web Fetch ───────────────────────────────────────────────────────
        case 'web_fetch':
          final url      = params['url'] as String? ?? '';
          final maxChars = (params['max_chars'] as num?)?.toInt() ?? 6000;

          if (url.isEmpty) {
            output = '❌ Parameter "url" wajib diisi.';
            break;
          }

          final page = await WebScraperService.instance.fetch(url);
          output = page.isSuccess
              ? page.toAiContext(maxChars: maxChars)
              : '❌ Gagal fetch "${url}": ${page.error ?? 'HTTP ${page.statusCode}'}';
          break;

        // ── Read File ───────────────────────────────────────────────────────
        case 'read_file':
          final filename = params['filename'] as String? ?? '';
          if (filename.isEmpty) {
            output = '❌ Parameter "filename" wajib diisi.';
            break;
          }
          try {
            // Coba workspace dulu
            output = await TerminalService.instance.readFile(filename);
          } catch (_) {
            // Coba sebagai path absolut
            try {
              final f = File(filename);
              if (f.existsSync()) {
                final size = f.lengthSync();
                if (size > 10 * 1024 * 1024) {
                  output = '❌ File terlalu besar (${(size / (1024*1024)).toStringAsFixed(1)} MB). Max 10MB.';
                } else {
                  output = await f.readAsString();
                }
              } else {
                output = '❌ File tidak ditemukan: $filename';
              }
            } catch (e2) {
              output = '❌ Gagal baca file "$filename": $e2';
            }
          }
          break;

        // ── Write File ──────────────────────────────────────────────────────
        case 'write_file':
          final filename = params['filename'] as String? ?? '';
          final content  = params['content'] as String? ?? '';
          if (filename.isEmpty) {
            output = '❌ Parameter "filename" wajib diisi.';
            break;
          }
          await TerminalService.instance.writeFile(filename, content);
          final path = await _resolveWorkspacePath(filename);
          output = '✅ File berhasil ditulis: $path\n'
              'Ukuran: ${content.length} karakter / ${(content.length / 1024).toStringAsFixed(1)} KB\n'
              'FILE_OUTPUT:$path';
          break;

        // ── Append File ─────────────────────────────────────────────────────
        case 'append_file':
          final filename = params['filename'] as String? ?? '';
          final content  = params['content'] as String? ?? '';
          if (filename.isEmpty) {
            output = '❌ Parameter "filename" wajib diisi.';
            break;
          }
          final path = await _resolveWorkspacePath(filename);
          final file = File(path);
          file.parent.createSync(recursive: true);
          await file.writeAsString(content, mode: FileMode.append);
          output = '✅ Konten ditambahkan ke: $path';
          break;

        // ── List Files ──────────────────────────────────────────────────────
        case 'list_files':
          final subdir = params['directory'] as String?;
          final files  = await TerminalService.instance.listFiles(subdir: subdir);
          if (files.isEmpty) {
            output = 'Direktori kosong atau tidak ditemukan.';
          } else {
            final sb = StringBuffer('Files in ${subdir ?? 'workspace'}:\n\n');
            for (final f in files) {
              final isDir = f is Directory;
              final name  = f.path.split('/').last;
              if (isDir) {
                sb.writeln('📁 $name/');
              } else {
                final size = File(f.path).lengthSync();
                final sizeStr = size < 1024
                    ? '${size}B'
                    : size < 1024 * 1024
                        ? '${(size / 1024).toStringAsFixed(0)}KB'
                        : '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
                sb.writeln('📄 $name ($sizeStr)');
              }
            }
            output = sb.toString().trim();
          }
          break;

        // ── Run Command ─────────────────────────────────────────────────────
        case 'run_command':
          final command = params['command'] as String? ?? '';
          final timeoutSec = (params['timeout_seconds'] as num?)?.toInt() ?? 60;
          if (command.isEmpty) {
            output = '❌ Parameter "command" wajib diisi.';
            break;
          }
          // Safety check — blokir command berbahaya
          const _blocked = ['rm -rf /', 'mkfs', 'dd if=', ':(){ :|:& };:',
              'chmod 777 /', 'chown -R', ':(){', 'fork bomb'];
          final blockedMatch = _blocked.where((b) => command.contains(b));
          if (blockedMatch.isNotEmpty) {
            output = '❌ Command diblokir demi keamanan: ${blockedMatch.first}';
            break;
          }
          try {
            final result = await TerminalService.instance.run(
              command,
              timeout: Duration(seconds: timeoutSec.clamp(1, 120)),
            );
            if (result.stdout.isEmpty && result.stderr.isEmpty) {
              output = '✅ Perintah selesai (exit code: ${result.exitCode})';
            } else {
              final raw = result.formatted;
              output = raw.isEmpty
                  ? '(tidak ada output)'
                  : raw.length > 3000
                      ? '${raw.substring(0, 3000)}\n... [output dipotong, ${raw.length - 3000} chars sisa]'
                      : raw;
            }
          } on TimeoutException {
            output = '❌ Command timeout (>${timeoutSec}s). Gunakan timeout_seconds lebih besar jika perlu.';
          } catch (e) {
            output = '❌ Error menjalankan command: $e';
          }
          break;

        // ── Download File ───────────────────────────────────────────────────
        case 'download_file':
          final url      = params['url'] as String? ?? '';
          final savePath = params['save_as'] as String?;
          if (url.isEmpty) {
            output = '❌ Parameter "url" wajib diisi.';
            break;
          }
          final sb = StringBuffer();
          String? finalPath;
          await for (final prog in TerminalService.instance.download(url, savePath: savePath)) {
            if (prog.done) {
              finalPath = savePath;
              sb.write('✅ Download selesai: ${prog.filename}');
            } else if (prog.error != null) {
              sb.write('❌ Download error: ${prog.error}');
            }
          }
          output = sb.toString();
          if (finalPath != null) {
            output += '\nFILE_OUTPUT:$finalPath';
          }
          break;

        // ── Export Data ─────────────────────────────────────────────────────
        case 'export_data':
          final data     = params['data'];
          final format   = params['format'] as String? ?? 'json';
          final filename = params['filename'] as String?;
          if (data == null) {
            output = '❌ Parameter "data" wajib diisi.';
            break;
          }
          final result = await ExportService.instance.export(
            data: data,
            format: format,
            filename: filename,
          );
          output = result.isSuccess
              ? '✅ Data berhasil diekspor: ${result.path}\n'
                'Format: ${result.format.toUpperCase()}, File: ${result.filename}\nFILE_OUTPUT:${result.path}'
              : '❌ Export error: ${result.error}';
          break;

        // ── Remember ────────────────────────────────────────────────────────
        case 'remember':
          final key     = params['key'] as String? ?? 'note_${DateTime.now().millisecondsSinceEpoch}';
          final content = params['content'] as String? ?? '';
          final tags    = (params['tags'] as List?)?.cast<String>() ?? [];
          if (content.isEmpty) {
            output = '❌ Parameter "content" wajib diisi.';
            break;
          }
          await AgentMemoryService.instance.save(key: key, content: content, tags: tags);
          output = '✅ Tersimpan di memori dengan key: "$key"';
          break;

        // ── Recall ──────────────────────────────────────────────────────────
        case 'recall':
          final query = params['query'] as String? ?? '';
          if (query.isEmpty) {
            output = '❌ Parameter "query" wajib diisi.';
            break;
          }
          final memories = await AgentMemoryService.instance.search(query);
          if (memories.isEmpty) {
            output = 'Tidak ada memori yang cocok untuk: "$query"';
          } else {
            output = 'Ditemukan ${memories.length} memori:\n\n' +
                memories.map((m) =>
                    '[${m.key}] ${m.savedAt.toLocal().toString().substring(0, 16)}\n${m.content}')
                .join('\n\n---\n\n');
          }
          break;

        // ── API Call ────────────────────────────────────────────────────────
        case 'api_call':
          final url     = params['url'] as String? ?? '';
          final method  = (params['method'] as String? ?? 'GET').toUpperCase();
          final headers = Map<String, String>.from(params['headers'] as Map? ?? {});
          final body    = params['body'] is Map
              ? jsonEncode(params['body'])
              : params['body'] as String?;

          if (url.isEmpty) {
            output = '❌ Parameter "url" wajib diisi.';
            break;
          }

          // Inject API keys dari config
          cfg.apiKeys.forEach((name, key) {
            final lName = name.toLowerCase();
            if (url.toLowerCase().contains(lName)) {
              headers['Authorization'] = 'Bearer $key';
              headers['X-API-Key'] = key;
            }
          });

          final result = await WebScraperService.instance.fetchJson(
            url, headers: headers, method: method, body: body,
          );

          if (result is Map && result.containsKey('error')) {
            output = '❌ API error: ${result['error']}';
          } else {
            final encoded = const JsonEncoder.withIndent('  ').convert(result);
            output = encoded.length > 4000 ? '${encoded.substring(0, 4000)}\n... [terpotong]' : encoded;
          }
          break;

        // ── Edit Media ──────────────────────────────────────────────────────
        case 'edit_media':
          final inputPath  = params['input_path']  as String? ?? '';
          final operation  = params['operation']   as String? ?? '';
          final editParams = Map<String, dynamic>.from(params['params'] as Map? ?? {});

          if (inputPath.isEmpty || operation.isEmpty) {
            output = '❌ Parameter "input_path" dan "operation" wajib diisi.\n'
                'Operasi tersedia: resize, crop, rotate, flip, compress, trim, '
                'convert, watermark, thumbnail, grayscale, brightness, contrast, '
                'blur, speed, volume, extract_audio, merge';
            break;
          }

          // Cek & install tool yang dibutuhkan
          final toolCheck = await ToolInstallerService.instance.ensureToolForOperation(operation);
          if (!toolCheck.success) {
            output = '❌ Tool tidak tersedia: ${toolCheck.message}\n'
                '💡 Hint: ${toolCheck.installHint}';
            break;
          }

          final editResult = await MediaEditService.instance.edit(
            inputPath:  inputPath,
            operation:  operation,
            params:     editParams,
          );

          if (editResult.success) {
            output = '✅ ${editResult.details}\nFILE_OUTPUT:${editResult.outputPath}';
          } else {
            output = '❌ Edit gagal: ${editResult.error}';
          }
          break;

        // ── Check & Install Tool ────────────────────────────────────────────
        case 'check_install_tool':
          final toolName2   = params['tool']         as String? ?? '';
          final autoInstall = params['auto_install'] as bool? ?? true;

          if (toolName2.isEmpty) {
            output = '❌ Parameter "tool" wajib diisi.';
            break;
          }

          final checkResult = await ToolInstallerService.instance.checkAndInstall(
            toolName2, autoInstall: autoInstall,
          );
          output = checkResult.success
              ? '✅ ${checkResult.message}'
              : '❌ ${checkResult.message}\n💡 ${checkResult.installHint}';
          break;

        // ── Send File to User ───────────────────────────────────────────────
        case 'send_file_to_user':
          final filePath = params['file_path'] as String? ?? '';
          final message  = params['message']   as String? ?? 'File siap diunduh.';

          if (filePath.isEmpty) {
            output = '❌ Parameter "file_path" wajib diisi.';
            break;
          }
          final targetFile = File(filePath);
          if (!targetFile.existsSync()) {
            // Coba cari di workspace
            final wsPath = await _resolveWorkspacePath(filePath);
            final wsFile = File(wsPath);
            if (!wsFile.existsSync()) {
              output = '❌ File tidak ditemukan: $filePath\n'
                  'Coba gunakan list_files untuk melihat file yang tersedia.';
              break;
            }
            // Pakai path workspace
            try {
              await ExportService.instance.shareFile(wsPath);
              final fileSize2 = wsFile.lengthSync();
              final sizeMb2   = (fileSize2 / (1024 * 1024)).toStringAsFixed(1);
              output = '📎 $message\nUkuran: ${sizeMb2}MB\nFILE_OUTPUT:$wsPath';
            } catch (e) {
              output = '❌ Gagal berbagi file: $e';
            }
            break;
          }

          try {
            await ExportService.instance.shareFile(filePath);
            final fileSize = targetFile.lengthSync();
            final sizeMb   = (fileSize / (1024 * 1024)).toStringAsFixed(1);
            output = '📎 $message\nUkuran: ${sizeMb}MB\nFILE_OUTPUT:$filePath';
          } catch (e) {
            output = '❌ Gagal berbagi file: $e';
          }
          break;

        // ── List Workspace ──────────────────────────────────────────────────
        case 'list_workspace':
          try {
            final wsDir = await _getWorkspaceDir();
            final dir   = Directory(wsDir);
            if (!dir.existsSync()) {
              output = 'Workspace kosong: $wsDir';
              break;
            }
            final entries = dir.listSync(recursive: false)
                ..sort((a, b) => a.path.compareTo(b.path));
            if (entries.isEmpty) {
              output = 'Workspace kosong: $wsDir';
            } else {
              final sb = StringBuffer('Workspace: $wsDir\n\n');
              for (final e in entries) {
                final name = e.path.split('/').last;
                if (e is Directory) {
                  sb.writeln('📁 $name/');
                } else {
                  final sz = File(e.path).lengthSync();
                  final szStr = sz < 1024 ? '${sz}B'
                      : sz < 1024 * 1024 ? '${(sz/1024).toStringAsFixed(0)}KB'
                      : '${(sz/(1024*1024)).toStringAsFixed(1)}MB';
                  sb.writeln('📄 $name ($szStr)');
                }
              }
              output = sb.toString().trim();
            }
          } catch (e) {
            output = '❌ Error listing workspace: $e';
          }
          break;

        default:
          output = '❌ Tool tidak dikenal: "$toolName"\n'
              'Tool yang tersedia: ${cfg.enabledTools.join(', ')}';
      }

      return ToolResult(
        toolName: toolName, params: params,
        output: output,
        success: !output.startsWith('❌'),
        executedAt: start,
      );

    } catch (e, st) {
      debugPrint('[Agent] _executeTool error [$toolName]: $e\n$st');
      return ToolResult(
        toolName: toolName, params: params,
        output: 'Tool error: $e',
        success: false,
        executedAt: start,
      );
    }
  }

  // ── Parse JSON tool calls dari respons AI ─────────────────────────────────
  // Lebih robust: handle nested JSON, code blocks, dan berbagai format
  List<Map<String, dynamic>> _extractToolCalls(String response) {
    final results  = <Map<String, dynamic>>[];
    final seen     = <String>{};

    void tryAdd(String jsonStr) {
      final key = jsonStr.trim();
      if (seen.contains(key)) return;
      seen.add(key);
      try {
        final obj = jsonDecode(key);
        if (obj is Map<String, dynamic> && obj.containsKey('tool')) {
          results.add(obj);
        }
      } catch (_) {}
    }

    // 1. Cari dalam code block ```json ... ```
    final codeBlockRegex = RegExp(
        r'```(?:json)?\s*\n?([\s\S]*?)\n?```',
        multiLine: true);
    for (final match in codeBlockRegex.allMatches(response)) {
      tryAdd(match.group(1)!.trim());
    }

    // 2. Cari JSON object dengan field "tool" — robust nested brace matching
    int depth = 0;
    int start = -1;
    for (int i = 0; i < response.length; i++) {
      final c = response[i];
      if (c == '{') {
        if (depth == 0) start = i;
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0 && start >= 0) {
          final candidate = response.substring(start, i + 1);
          if (candidate.contains('"tool"')) {
            tryAdd(candidate);
          }
          start = -1;
        }
      }
    }

    return results;
  }

  String _extractThinking(String response) {
    // Ambil teks sebelum JSON block pertama
    int firstJson = response.length;
    // Cari { yang membuka JSON pertama
    int depth = 0;
    for (int i = 0; i < response.length; i++) {
      if (response[i] == '{') {
        // Cek apakah ini JSON dengan "tool"
        int d = 0;
        int end = i;
        for (int j = i; j < response.length; j++) {
          if (response[j] == '{') d++;
          else if (response[j] == '}') {
            d--;
            if (d == 0) { end = j; break; }
          }
        }
        final candidate = response.substring(i, end + 1);
        if (candidate.contains('"tool"')) {
          firstJson = i;
          break;
        }
      }
      // Cek code block
      if (response.startsWith('```', i)) {
        firstJson = i;
        break;
      }
    }

    if (firstJson == 0) return '';
    return response.substring(0, firstJson).trim();
  }

  Future<String> _resolveWorkspacePath(String filename) async {
    await TerminalService.instance.init();
    return '${TerminalService.instance.cwdPath}/$filename';
  }

  Future<String> _getWorkspaceDir() async {
    await TerminalService.instance.init();
    return TerminalService.instance.cwdPath;
  }

  String _truncate(String s, int max) =>
      s.length > max ? '${s.substring(0, max)}\n... [terpotong]' : s;

  String _defaultSystemPrompt(AgentConfig cfg) =>
      '$kKanMonAIShortSystemPrompt\n\n'
      'Kamu sekarang berjalan sebagai ${cfg.name} — AI agent yang powerful dan otonom. '
      'Kamu bisa menggunakan berbagai tools untuk menyelesaikan task apapun. '
      'Selalu berpikir langkah-demi-langkah sebelum bertindak. '
      'Prioritaskan efisiensi dan hasil yang akurat. '
      'Jawab dalam Bahasa Indonesia kecuali diminta lain.';

  String _toolDescriptions(List<String> tools) {
    const all = {
      'web_search':
          'web_search(query, engine="ddg|google", max_results=8)\n'
          '  → Cari informasi di internet. Gunakan ini untuk mendapatkan data terkini.',
      'web_fetch':
          'web_fetch(url, max_chars=6000)\n'
          '  → Ambil & baca konten halaman web lengkap dari URL tertentu.',
      'read_file':
          'read_file(filename)\n'
          '  → Baca isi file. Bisa path relatif (workspace) atau path absolut.',
      'write_file':
          'write_file(filename, content)\n'
          '  → Tulis/buat file baru. Menimpa jika sudah ada.',
      'append_file':
          'append_file(filename, content)\n'
          '  → Tambahkan konten ke akhir file (tanpa menimpa).',
      'list_files':
          'list_files(directory=null)\n'
          '  → Tampilkan daftar file di workspace atau direktori tertentu.',
      'run_command':
          'run_command(command, timeout_seconds=60)\n'
          '  → Jalankan perintah shell. Mendukung semua perintah bash/Termux.',
      'download_file':
          'download_file(url, save_as=null)\n'
          '  → Download file dari internet ke workspace.',
      'export_data':
          'export_data(data, format="json|csv|txt|md", filename=null)\n'
          '  → Ekspor data ke file dengan format tertentu.',
      'remember':
          'remember(key, content, tags=[])\n'
          '  → Simpan informasi ke memori jangka panjang agent.',
      'recall':
          'recall(query)\n'
          '  → Cari informasi yang pernah disimpan di memori.',
      'api_call':
          'api_call(url, method="GET|POST|PUT|DELETE", headers={}, body=null)\n'
          '  → Panggil REST API eksternal. Body bisa string atau JSON object.',
      'edit_media':
          'edit_media(input_path, operation, params={})\n'
          '  → Edit gambar/video/audio menggunakan ffmpeg.\n'
          '  Operations: resize(width,height), crop(w,h,x,y), rotate(degrees),\n'
          '    flip(direction), compress(crf,preset), trim(start,end|duration),\n'
          '    convert(to), watermark(text,position), thumbnail(time),\n'
          '    grayscale, brightness(value), contrast(value), blur(radius),\n'
          '    speed(factor), volume(db), extract_audio, merge(audio_path)',
      'check_install_tool':
          'check_install_tool(tool, auto_install=true)\n'
          '  → Cek apakah tool sistem tersedia, install otomatis via Termux jika tidak ada.\n'
          '  Tools: ffmpeg, python, node, git, curl, wget, imagemagick, dll.',
      'send_file_to_user':
          'send_file_to_user(file_path, message)\n'
          '  → Kirim file hasil ke user untuk diunduh/dilihat via Android share sheet.',
      'list_workspace':
          'list_workspace()\n'
          '  → Tampilkan semua file di folder workspace KanMonAI.',
    };

    return all.entries
        .where((e) => tools.contains(e.key))
        .map((e) => '• ${e.value}')
        .join('\n\n');
  }
}
