// lib/features/settings/presentation/screens/online_ai_screen.dart
// KanMon GO — AI Online (Puter.js)
// Pilih model AI cloud: Claude, Gemini, Grok, GPT-4o, Llama, dll
// =============================================================================

import 'package:flutter/material.dart';
import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/data/services/ai/puter_ai_service.dart';
import 'package:kanmongo/data/services/ai/ai_source_settings_service.dart';
import 'package:kanmongo/shared/utils/top_snack.dart';

class OnlineAiScreen extends StatefulWidget {
  const OnlineAiScreen({super.key});
  @override
  State<OnlineAiScreen> createState() => _OnlineAiScreenState();
}

class _OnlineAiScreenState extends State<OnlineAiScreen>
    with SingleTickerProviderStateMixin {
  final _svc = PuterAiService.instance;

  String _selectedProvider = 'Semua';
  String _search           = '';
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: kPuterProviders.length, vsync: this);
    _svc.loadSettings().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  List<PuterAiModel> get _filtered {
    var list = kPuterModels;
    if (_selectedProvider != 'Semua') {
      list = list.where((m) => m.provider == _selectedProvider).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((m) =>
        m.name.toLowerCase().contains(q) ||
        m.provider.toLowerCase().contains(q) ||
        m.description.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  Future<void> _selectModel(PuterAiModel model) async {
    await _svc.saveSettings(selectedModel: model.id);
    // Sinkronisasi ke AiSourceSettingsService agar picker ikut update
    await AiSourceSettingsService.instance.pullOnlineFromService();
    if (mounted) {
      setState(() {});
      showTopSnack(context, '${model.emoji} ${model.name} dipilih', duration: const Duration(seconds: 2));
    }
  }

  @override
  Widget build(BuildContext context) {
    final kfc    = KmColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: kfc.bg,
      appBar: AppBar(
        backgroundColor: kfc.card,
        title: Text('AI Online',
            style: TextStyle(color: kfc.text, fontWeight: FontWeight.bold)),
        iconTheme: IconThemeData(color: kfc.text),
        actions: [
          // Indicator aktif/tidak
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _svc.isEnabled
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 6, height: 6, decoration: const BoxDecoration(
                        color: Colors.green, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text('Aktif', style: TextStyle(
                          color: Colors.green.shade400, fontSize: 12,
                          fontWeight: FontWeight.w700)),
                    ]),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Text('Nonaktif',
                        style: TextStyle(color: Colors.orange.shade400,
                            fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(color: kfc.border, height: 1),
        ),
      ),
      body: Column(children: [

        // ── Header info + toggle aktif ─────────────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF6C5CE7).withValues(alpha: 0.15),
                const Color(0xFF00B4D8).withValues(alpha: 0.10),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: const Color(0xFF6C5CE7).withValues(alpha: 0.3)),
          ),
          child: Column(children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C5CE7).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('🌐', style: TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Puter.js AI Online',
                    style: TextStyle(color: kfc.text, fontWeight: FontWeight.bold,
                        fontSize: 15)),
                Text('Akses ${kPuterModels.length}+ model AI cloud tanpa infrastruktur sendiri',
                    style: TextStyle(color: kfc.textSub, fontSize: 12)),
              ])),
              Switch(
                value: _svc.isEnabled,
                onChanged: (v) async {
                  await _svc.saveSettings(enabled: v);
                  // Sinkronisasi ke AiSourceSettingsService agar picker ikut update
                  await AiSourceSettingsService.instance.pullOnlineFromService();
                  setState(() {});
                },
                activeColor: const Color(0xFF6C5CE7),
              ),
            ]),
            if (!_svc.isEnabled) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded,
                      color: Colors.orange.shade400, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'Aktifkan AI Online untuk menggunakan model cloud. '
                    'Butuh API Key Puter.js.',
                    style: TextStyle(color: Colors.orange.shade300,
                        fontSize: 11),
                  )),
                ]),
              ),
            ],
          ]),
        ),

        // ── Model aktif saat ini ───────────────────────────────────────────
        if (_svc.isEnabled) ...[
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: kfc.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kfc.border),
            ),
            child: Row(children: [
              Text(_svc.selectedModel?.emoji ?? '🤖',
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Model Aktif',
                    style: TextStyle(color: kfc.textMuted, fontSize: 11)),
                Text(_svc.selectedModel?.name ?? _svc.selectedModelId,
                    style: TextStyle(color: kfc.text, fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ])),
              Text(_svc.selectedModel?.provider ?? '',
                  style: TextStyle(color: kfc.textSub, fontSize: 12)),
            ]),
          ),
        ],

        // ── Search bar ─────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            onChanged: (v) => setState(() => _search = v),
            style: TextStyle(color: kfc.text, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Cari model...',
              hintStyle: TextStyle(color: kfc.textMuted),
              prefixIcon: Icon(Icons.search_rounded, color: kfc.textMuted, size: 20),
              filled: true,
              fillColor: kfc.inputFill,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: kfc.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: kfc.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF6C5CE7), width: 1.5)),
            ),
          ),
        ),

        // ── Provider filter chips ──────────────────────────────────────────
        SizedBox(
          height: 44,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            scrollDirection: Axis.horizontal,
            itemCount: kPuterProviders.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final p = kPuterProviders[i];
              final sel = _selectedProvider == p;
              return GestureDetector(
                onTap: () => setState(() => _selectedProvider = p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel
                        ? const Color(0xFF6C5CE7)
                        : kfc.inputFill,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: sel
                            ? const Color(0xFF6C5CE7)
                            : kfc.border),
                  ),
                  child: Text(p,
                    style: TextStyle(
                      color: sel ? Colors.white : kfc.textSub,
                      fontSize: 12,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
                    )),
                ),
              );
            },
          ),
        ),

        // ── Model list ─────────────────────────────────────────────────────
        Expanded(
          child: _filtered.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('🔍', style: const TextStyle(fontSize: 40)),
                  const SizedBox(height: 12),
                  Text('Tidak ada model ditemukan',
                      style: TextStyle(color: kfc.textSub)),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) => _ModelCard(
                    model: _filtered[i],
                    isSelected: _svc.selectedModelId == _filtered[i].id,
                    isEnabled: _svc.isEnabled,
                    onTap: () => _selectModel(_filtered[i]),
                    kfc: kfc,
                  ),
                ),
        ),
      ]),
    );
  }
}

// ── Model Card ────────────────────────────────────────────────────────────────
class _ModelCard extends StatelessWidget {
  final PuterAiModel model;
  final bool         isSelected;
  final bool         isEnabled;
  final VoidCallback onTap;
  final KmColors     kfc;

  const _ModelCard({
    required this.model,
    required this.isSelected,
    required this.isEnabled,
    required this.onTap,
    required this.kfc,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = const Color(0xFF6C5CE7);

    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: 0.12)
              : kfc.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? accentColor.withValues(alpha: 0.5)
                : kfc.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          // ── Emoji + provider ─────────────────────────────────────────────
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isSelected
                  ? accentColor.withValues(alpha: 0.15)
                  : kfc.inputFill,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(model.emoji, style: const TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: 12),

          // ── Info ─────────────────────────────────────────────────────────
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(model.name,
                  style: TextStyle(
                    color: isSelected ? accentColor : kfc.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              if (model.isNew)  _badge('NEW',  Colors.green),
              if (model.isBest) _badge('BEST', accentColor),
              if (model.isFast) _badge('FAST', Colors.blue),
            ]),
            const SizedBox(height: 3),
            Text(model.provider,
                style: TextStyle(color: kfc.textSub, fontSize: 11,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(model.description,
                style: TextStyle(color: kfc.textMuted, fontSize: 12),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.token_outlined, size: 12, color: kfc.textMuted),
              const SizedBox(width: 4),
              Text('${model.contextLength}K ctx',
                  style: TextStyle(color: kfc.textMuted, fontSize: 11)),
            ]),
          ])),

          // ── Selected indicator ────────────────────────────────────────────
          const SizedBox(width: 8),
          if (isSelected)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 14),
            )
          else if (!isEnabled)
            Icon(Icons.lock_outline_rounded,
                color: kfc.textMuted, size: 18)
          else
            Icon(Icons.chevron_right_rounded,
                color: kfc.textMuted, size: 20),
        ]),
      ),
    );
  }

  Widget _badge(String label, Color color) => Container(
    margin: const EdgeInsets.only(right: 4),
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(label,
        style: TextStyle(color: color, fontSize: 9,
            fontWeight: FontWeight.w800)),
  );
}
