// lib/features/tools/tools_dashboard_screen.dart
// KanMon AI — Tools Dashboard Screen
//
// Menampilkan semua bundled CLI tools dengan status, versi, dan aksi.
// Diakses dari Settings → Developer Tools.
// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/core/tools/tools_service.dart';
import 'package:kanmongo/core/tools/native_tools_manager.dart';
import 'package:kanmongo/shared/utils/top_snack.dart';

// ── Providers ─────────────────────────────────────────────────────────────────
final _toolsHealthProvider =
    FutureProvider.autoDispose<List<ToolHealth>>((ref) async {
  if (!ToolsService.instance.isReady) {
    await ToolsService.instance.initialize();
  }
  return NativeToolsManager.instance.checkAll(
    categories: [
      ToolCategory.runtime,
      ToolCategory.aiCode,
      ToolCategory.ide,
      ToolCategory.vcs,
    ],
  );
});

// ── Screen ────────────────────────────────────────────────────────────────────
class ToolsDashboardScreen extends ConsumerStatefulWidget {
  const ToolsDashboardScreen({super.key});

  @override
  ConsumerState<ToolsDashboardScreen> createState() =>
      _ToolsDashboardScreenState();
}

class _ToolsDashboardScreenState extends ConsumerState<ToolsDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  List<ToolHealth>? _fullHealth;
  bool _runningFullCheck = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _runFullCheck() async {
    setState(() => _runningFullCheck = true);
    try {
      final results = await NativeToolsManager.instance.checkAll();
      setState(() => _fullHealth = results);
    } finally {
      setState(() => _runningFullCheck = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kmc = KmColors.of(context);
    final health = ref.watch(_toolsHealthProvider);

    return Scaffold(
      backgroundColor: kmc.bg,
      appBar: AppBar(
        backgroundColor: kmc.card,
        foregroundColor: kmc.text,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Row(children: [
          Icon(Icons.construction_rounded, size: 20, color: kmc.accent),
          const SizedBox(width: 8),
          Text('Developer Tools',
              style: TextStyle(
                  color: kmc.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w600)),
        ]),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: kmc.accent,
          unselectedLabelColor: kmc.textMuted,
          indicatorColor: kmc.accent,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [
            Tab(text: 'Status'),
            Tab(text: 'Semua Tools'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _StatusTab(health: health, kmc: kmc),
          _AllToolsTab(
            fullHealth: _fullHealth,
            running: _runningFullCheck,
            onCheck: _runFullCheck,
            kmc: kmc,
          ),
        ],
      ),
    );
  }
}

// ── Status Tab ────────────────────────────────────────────────────────────────
class _StatusTab extends StatelessWidget {
  final AsyncValue<List<ToolHealth>> health;
  final KmColors kmc;
  const _StatusTab({required this.health, required this.kmc});

  @override
  Widget build(BuildContext context) {
    return health.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error: $e',
            style: TextStyle(color: kmc.textSub, fontSize: 13)),
      ),
      data: (list) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SummaryCard(list: list, kmc: kmc),
          const SizedBox(height: 16),
          _ManifestCard(kmc: kmc),
          const SizedBox(height: 16),
          Text('Core Tools',
              style: TextStyle(
                  color: kmc.textSub,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5)),
          const SizedBox(height: 8),
          ...list.map((h) => _ToolCard(health: h, kmc: kmc)),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final List<ToolHealth> list;
  final KmColors kmc;
  const _SummaryCard({required this.list, required this.kmc});

  @override
  Widget build(BuildContext context) {
    final healthy = list.where((h) => h.isHealthy).length;
    final total = list.length;
    final allOk = healthy == total;
    final color = allOk ? const Color(0xFF10B981) : kmc.accent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            allOk ? Icons.check_circle_rounded : Icons.warning_rounded,
            color: color,
            size: 28,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              allOk ? 'Semua tools siap' : '$healthy dari $total tools siap',
              style: TextStyle(
                  color: kmc.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 3),
            Text(
              allOk
                  ? 'Claude Code & VS Code bisa dijalankan natively.'
                  : 'Beberapa tools perlu perhatian — rebuild APK jika diperlukan.',
              style: TextStyle(color: kmc.textSub, fontSize: 12),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _ManifestCard extends StatelessWidget {
  final KmColors kmc;
  const _ManifestCard({required this.kmc});

  @override
  Widget build(BuildContext context) {
    final manifest = ToolsService.instance.manifest;
    if (manifest == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kmc.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kmc.border),
        ),
        child: Row(children: [
          Icon(Icons.info_outline, color: kmc.textMuted, size: 18),
          const SizedBox(width: 10),
          Text('Bundle tools tidak ditemukan dalam APK.',
              style: TextStyle(color: kmc.textSub, fontSize: 13)),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kmc.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kmc.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _ManRow(kmc: kmc, label: 'Node.js', value: manifest.nodeVersion),
        _ManRow(kmc: kmc, label: 'Claude Code', value: manifest.claudeCodeVersion),
        _ManRow(kmc: kmc, label: 'code-server', value: manifest.codeServerVersion),
        _ManRow(kmc: kmc, label: 'Built at', value: manifest.builtAt),
        _ManRow(kmc: kmc, label: 'Run ID', value: manifest.runId, mono: true),
        _ManRow(
          kmc: kmc,
          label: 'ABI',
          value: manifest.abis.join(', '),
          isLast: true,
        ),
      ]),
    );
  }
}

class _ManRow extends StatelessWidget {
  final KmColors kmc;
  final String label;
  final String value;
  final bool mono;
  final bool isLast;
  const _ManRow({
    required this.kmc,
    required this.label,
    required this.value,
    this.mono = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
      child: Row(children: [
        SizedBox(
          width: 110,
          child: Text(label,
              style: TextStyle(
                  color: kmc.textMuted, fontSize: 12)),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: kmc.text,
              fontSize: 12,
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ),
      ]),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final ToolHealth health;
  final KmColors kmc;
  const _ToolCard({required this.health, required this.kmc});

  @override
  Widget build(BuildContext context) {
    final color = health.isHealthy
        ? const Color(0xFF10B981)
        : health.exists
            ? const Color(0xFFF59E0B)
            : kmc.textMuted;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: kmc.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kmc.border),
      ),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            health.isHealthy
                ? Icons.check_circle_rounded
                : Icons.error_outline_rounded,
            color: color,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(health.tool.displayName,
                style: TextStyle(
                    color: kmc.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            if (health.version != null)
              Text(health.version!,
                  style: TextStyle(
                      color: kmc.textSub,
                      fontSize: 11,
                      fontFamily: 'monospace'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            if (health.error != null)
              Text(health.error!,
                  style: const TextStyle(
                      color: Color(0xFFEF4444), fontSize: 11),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
          ]),
        ),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: health.tool.path));
            TopSnack.show(context, 'Path disalin!');
          },
          child: Icon(Icons.copy_rounded, size: 16, color: kmc.textMuted),
        ),
      ]),
    );
  }
}

// ── All Tools Tab ─────────────────────────────────────────────────────────────
class _AllToolsTab extends StatelessWidget {
  final List<ToolHealth>? fullHealth;
  final bool running;
  final VoidCallback onCheck;
  final KmColors kmc;
  const _AllToolsTab({
    required this.fullHealth,
    required this.running,
    required this.onCheck,
    required this.kmc,
  });

  @override
  Widget build(BuildContext context) {
    final manager = NativeToolsManager.instance;
    final byCategory = manager.byCategory;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Run full check button
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton.icon(
            onPressed: running ? null : onCheck,
            icon: running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.health_and_safety_rounded,
                    size: 18, color: Colors.white),
            label: Text(
              running ? 'Memeriksa...' : 'Cek Semua Tools',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: kmc.accent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Stats if available
        if (fullHealth != null) ...[
          _FullHealthSummary(list: fullHealth!, kmc: kmc),
          const SizedBox(height: 16),
        ],

        // By category
        for (final entry in byCategory.entries) ...[
          _CategoryHeader(category: entry.key, kmc: kmc),
          const SizedBox(height: 6),
          ...entry.value.map((t) => _AnyToolRow(
                tool: t,
                health: fullHealth
                    ?.where((h) => h.tool.name == t.name)
                    .firstOrNull,
                kmc: kmc,
              )),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _FullHealthSummary extends StatelessWidget {
  final List<ToolHealth> list;
  final KmColors kmc;
  const _FullHealthSummary({required this.list, required this.kmc});

  @override
  Widget build(BuildContext context) {
    final healthy = list.where((h) => h.isHealthy).length;
    final total = list.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFF10B981).withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        const Icon(Icons.check_circle_rounded,
            size: 18, color: Color(0xFF10B981)),
        const SizedBox(width: 10),
        Text(
          'Health Check: $healthy/$total tools berfungsi',
          style: TextStyle(
              color: kmc.text, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  final ToolCategory category;
  final KmColors kmc;
  const _CategoryHeader({required this.category, required this.kmc});

  static String _label(ToolCategory c) => switch (c) {
        ToolCategory.runtime => '⚡ Runtime',
        ToolCategory.aiCode  => '🤖 AI Tools',
        ToolCategory.ide     => '💻 IDE',
        ToolCategory.vcs     => '🌿 Version Control',
        ToolCategory.search  => '🔍 Search',
        ToolCategory.media   => '🎬 Media',
        ToolCategory.archive => '📦 Archive',
        ToolCategory.language => '🐍 Language',
        ToolCategory.network => '🌐 Network',
        ToolCategory.util    => '🔧 Utilities',
        ToolCategory.debug   => '🐛 Debug',
      };

  @override
  Widget build(BuildContext context) {
    return Text(
      _label(category),
      style: TextStyle(
          color: kmc.textSub,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4),
    );
  }
}

class _AnyToolRow extends StatelessWidget {
  final NativeTool tool;
  final ToolHealth? health;
  final KmColors kmc;
  const _AnyToolRow(
      {required this.tool, required this.health, required this.kmc});

  @override
  Widget build(BuildContext context) {
    final exists = tool.existsOnDisk;
    final isHealthy = health?.isHealthy ?? false;

    final dotColor = health != null
        ? (isHealthy
            ? const Color(0xFF10B981)
            : const Color(0xFFEF4444))
        : (exists
            ? const Color(0xFFF59E0B)
            : kmc.textMuted.withValues(alpha: 0.4));

    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: tool.path));
        TopSnack.show(context, 'Path disalin: ${tool.path}');
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: kmc.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kmc.border),
        ),
        child: Row(children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 10),
            decoration:
                BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(tool.displayName,
                  style: TextStyle(
                      color: exists ? kmc.text : kmc.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              if (tool.description != null)
                Text(tool.description!,
                    style:
                        TextStyle(color: kmc.textMuted, fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              if (health?.version != null)
                Text(health!.version!,
                    style: TextStyle(
                        color: kmc.textSub,
                        fontSize: 10,
                        fontFamily: 'monospace'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
            ]),
          ),
          Text(
            exists ? 'ada' : 'tidak ada',
            style: TextStyle(
                color: dotColor,
                fontSize: 10,
                fontWeight: FontWeight.w600),
          ),
        ]),
      ),
    );
  }
}
