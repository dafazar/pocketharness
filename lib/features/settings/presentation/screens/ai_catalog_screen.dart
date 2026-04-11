// lib/features/settings/presentation/screens/ai_catalog_screen.dart
// KanMon GO — AI Model Catalog Screen
// Search, filter, download 50+ model AI untuk Android
// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/data/models/ai_catalog_model.dart';
import 'package:kanmongo/data/services/model_manager_service.dart';
import 'package:kanmongo/shared/utils/top_snack.dart';

class AiCatalogScreen extends StatefulWidget {
  const AiCatalogScreen({super.key});
  @override
  State<AiCatalogScreen> createState() => _AiCatalogScreenState();
}

class _AiCatalogScreenState extends State<AiCatalogScreen> {
  final _searchCtrl = TextEditingController();
  final _svc = ModelManagerService.instance;

  // Filter state
  String _search = '';
  final Set<ModelVariant> _variantFilter = {};
  final Set<String> _formatFilter = {};
  ModelSize? _maxSize;
  int? _maxRam;
  final Set<ModelLang> _langFilter = {};
  String _sortBy = 'popularity';

  // Download state
  final Map<String, DownloadProgress> _downloads = {};
  final Map<String, StreamSubscription> _subs = {};

  // Filtered list
  List<CatalogModel> get _filtered => filterCatalog(
    search: _search.isEmpty ? null : _search,
    variants: _variantFilter.isEmpty ? null : _variantFilter,
    formats: _formatFilter.isEmpty ? null : _formatFilter,
    maxSize: _maxSize,
    maxRamGb: _maxRam,
    languages: _langFilter.isEmpty ? null : _langFilter,
    sortBy: _sortBy,
  );

  @override
  void initState() {
    super.initState();
    _svc.load();
    _searchCtrl.addListener(() =>
        if (mounted) setState(() => _search = _searchCtrl.text.trim()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    for (final s in _subs.values) s.cancel();
    super.dispose();
  }

  bool _isDownloaded(CatalogModel m) =>
      _svc.models.any((sm) => sm.name == m.name);

  bool _isDownloading(CatalogModel m) =>
      _downloads.containsKey(m.id);

  void _startDownload(CatalogModel model) {
    if (_isDownloaded(model) || _isDownloading(model)) return;
    if (mounted) setState(() => _downloads[model.id] =
        DownloadProgress(taskId: model.id, bytesDownloaded: 0, totalBytes: 0, percent: 0, speedBytesPerSec: 0, etaSeconds: 0));

    final sub = _svc.downloadFromUrl(
      url: model.downloadUrl,
      modelId: model.id,
      customName: model.name,
    ).listen(
      (prog) {
        if (mounted) setState(() => _downloads[model.id] = prog);
        if (prog.isComplete) {
          _subs[model.id]?.cancel();
          _subs.remove(model.id);
          if (mounted) {
            if (mounted) setState(() => _downloads.remove(model.id));
            showTopSnack(context, '✅ ${model.name} berhasil didownload!');
          }
        }
        if (prog.hasError) {
          _subs[model.id]?.cancel();
          _subs.remove(model.id);
          if (mounted) {
            if (mounted) setState(() => _downloads.remove(model.id));
            showTopSnack(context, '❌ Download gagal: ${prog.error}', isError: true);
          }
        }
      },
    );
    _subs[model.id] = sub;
  }

  void _copyLink(CatalogModel model) {
    Clipboard.setData(ClipboardData(text: model.downloadUrl));
    showTopSnack(context, '✅ Link disalin! Buka Chrome dan paste di address bar.', duration: Duration(seconds: 3));
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: KmColors.of(context).surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _FilterSheet(
        variantFilter: _variantFilter,
        formatFilter: _formatFilter,
        maxSize: _maxSize,
        maxRam: _maxRam,
        langFilter: _langFilter,
        sortBy: _sortBy,
        onApply: (variants, formats, maxSize, maxRam, langs, sortBy) {
          if (mounted) setState(() {
            _variantFilter
              ..clear()
              ..addAll(variants);
            _formatFilter
              ..clear()
              ..addAll(formats);
            _maxSize = maxSize;
            _maxRam  = maxRam;
            _langFilter
              ..clear()
              ..addAll(langs);
            _sortBy  = sortBy;
          });
        },
        onReset: () => setState(() {
          _variantFilter.clear();
          _formatFilter.clear();
          _maxSize = null;
          _maxRam  = null;
          _langFilter.clear();
          _sortBy  = 'popularity';
        }),
      ),
    );
  }

  // ── Active filter count
  int get _filterCount =>
      _variantFilter.length +
      _formatFilter.length +
      (_maxSize != null ? 1 : 0) +
      (_maxRam != null ? 1 : 0) +
      _langFilter.length +
      (_sortBy != 'popularity' ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    final c      = KmColors.of(context);
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final models = _filtered;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: c.text, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Katalog Model AI',
            style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
        actions: [
          // Filter button with badge
          Stack(alignment: Alignment.topRight, children: [
            IconButton(
              icon: Icon(Icons.tune_rounded, color: c.text, size: 22),
              onPressed: _showFilterSheet,
            ),
            if (_filterCount > 0)
              Positioned(
                right: 8, top: 8,
                child: Container(
                  width: 16, height: 16,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, color: cs.primary),
                  alignment: Alignment.center,
                  child: Text('$_filterCount',
                      style: const TextStyle(color: Colors.white,
                          fontSize: 9, fontWeight: FontWeight.w700)),
                ),
              ),
          ]),
        ],
      ),
      body: Column(children: [
        // ── Search bar ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            style: TextStyle(color: c.text, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Cari model... (Llama, Qwen, Mistral, dll)',
              hintStyle: TextStyle(color: c.textMuted, fontSize: 13),
              prefixIcon: Icon(Icons.search_rounded, color: c.textMuted, size: 20),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear_rounded, color: c.textMuted, size: 18),
                      onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); },
                    )
                  : null,
              filled: true,
              fillColor: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Colors.black.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
            ),
          ),
        ),

        // ── Active filter chips ──────────────────────────────────────────────
        if (_filterCount > 0 || _variantFilter.isNotEmpty)
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                if (_variantFilter.contains(ModelVariant.uncensored))
                  _ActiveChip('🔓 Uncensored', cs, onRemove: () {
                    if (mounted) setState(() => _variantFilter.remove(ModelVariant.uncensored));
                  }),
                if (_variantFilter.contains(ModelVariant.standard))
                  _ActiveChip('🛡️ Standard', cs, onRemove: () {
                    if (mounted) setState(() => _variantFilter.remove(ModelVariant.standard));
                  }),
                if (_variantFilter.contains(ModelVariant.reasoning))
                  _ActiveChip('🧠 Reasoning', cs, onRemove: () {
                    if (mounted) setState(() => _variantFilter.remove(ModelVariant.reasoning));
                  }),
                if (_variantFilter.contains(ModelVariant.coding))
                  _ActiveChip('💻 Coding', cs, onRemove: () {
                    if (mounted) setState(() => _variantFilter.remove(ModelVariant.coding));
                  }),
                if (_variantFilter.contains(ModelVariant.multilingual))
                  _ActiveChip('🌐 Multilingual', cs, onRemove: () {
                    if (mounted) setState(() => _variantFilter.remove(ModelVariant.multilingual));
                  }),
                if (_variantFilter.contains(ModelVariant.tiny))
                  _ActiveChip('🪶 Ultra Ringan', cs, onRemove: () {
                    if (mounted) setState(() => _variantFilter.remove(ModelVariant.tiny));
                  }),
                if (_variantFilter.contains(ModelVariant.vision))
                  _ActiveChip('👁️ Vision', cs, onRemove: () {
                    if (mounted) setState(() => _variantFilter.remove(ModelVariant.vision));
                  }),
                for (final f in _formatFilter)
                  _ActiveChip(f, cs, onRemove: () {
                    if (mounted) setState(() => _formatFilter.remove(f));
                  }),
                if (_maxSize != null)
                  _ActiveChip('Max: ${_maxSize!.name}', cs, onRemove: () {
                    if (mounted) setState(() => _maxSize = null);
                  }),
                if (_maxRam != null)
                  _ActiveChip('RAM ≤${_maxRam}GB', cs, onRemove: () {
                    if (mounted) setState(() => _maxRam = null);
                  }),
                if (_sortBy != 'popularity')
                  _ActiveChip('Sort: $_sortBy', cs, onRemove: () {
                    if (mounted) setState(() => _sortBy = 'popularity');
                  }),
                if (_filterCount > 1)
                  GestureDetector(
                    onTap: () => setState(() {
                      _variantFilter.clear(); _formatFilter.clear();
                      _maxSize = null; _maxRam = null; _langFilter.clear();
                      _sortBy = 'popularity';
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.shade700.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('Reset semua',
                          style: TextStyle(fontSize: 11,
                              color: Colors.red.shade400,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
          ),

        // ── Count ────────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: Row(children: [
            Text('${models.length} model ditemukan',
                style: TextStyle(fontSize: 12, color: c.textMuted)),
            const Spacer(),
            if (_downloads.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('⬇️ ${_downloads.length} downloading',
                    style: const TextStyle(fontSize: 11, color: Colors.amber)),
              ),
          ]),
        ),

        // ── Model list ────────────────────────────────────────────────────────
        Expanded(
          child: models.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('🔍', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    Text('Tidak ada model yang cocok',
                        style: TextStyle(color: c.textMuted, fontSize: 14)),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => setState(() {
                        _searchCtrl.clear(); _search = '';
                        _variantFilter.clear(); _formatFilter.clear();
                        _maxSize = null; _maxRam = null;
                      }),
                      child: const Text('Reset filter'),
                    ),
                  ]),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  itemCount: models.length,
                  itemBuilder: (_, i) {
                    final m       = models[i];
                    final dl      = _downloads[m.id];
                    final done    = _isDownloaded(m);
                    final loading = _isDownloading(m);

                    return _CatalogCard(
                      model: m,
                      isDark: isDark,
                      c: c,
                      cs: cs,
                      isDownloaded: done,
                      isDownloading: loading,
                      progress: dl,
                      onDownload: done ? null : () => _startDownload(m),
                      onCopyLink: () => _copyLink(m),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

// ── Active filter chip ────────────────────────────────────────────────────────
class _ActiveChip extends StatelessWidget {
  final String label;
  final ColorScheme cs;
  final VoidCallback onRemove;
  const _ActiveChip(this.label, this.cs, {required this.onRemove});

  @override
  Widget build(BuildContext ctx) => Container(
    margin: const EdgeInsets.only(right: 6),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: cs.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: TextStyle(fontSize: 11, color: cs.primary,
          fontWeight: FontWeight.w600)),
      const SizedBox(width: 4),
      GestureDetector(
        onTap: onRemove,
        child: Icon(Icons.close_rounded, size: 13, color: cs.primary),
      ),
    ]),
  );
}

// ── Catalog Card ──────────────────────────────────────────────────────────────
class _CatalogCard extends StatelessWidget {
  final CatalogModel model;
  final bool isDark, isDownloaded, isDownloading;
  final KmColors c;
  final ColorScheme cs;
  final DownloadProgress? progress;
  final VoidCallback? onDownload;
  final VoidCallback onCopyLink;

  const _CatalogCard({
    required this.model, required this.isDark, required this.c,
    required this.cs, required this.isDownloaded, required this.isDownloading,
    this.progress, this.onDownload, required this.onCopyLink,
  });

  Color get _variantColor {
    if (model.variants.contains(ModelVariant.uncensored))
      return const Color(0xFFFF6B35);
    if (model.variants.contains(ModelVariant.reasoning))
      return const Color(0xFF8B5CF6);
    if (model.variants.contains(ModelVariant.coding))
      return const Color(0xFF10B981);
    if (model.variants.contains(ModelVariant.vision))
      return const Color(0xFF0EA5E9);
    if (model.variants.contains(ModelVariant.tiny))
      return const Color(0xFF6366F1);
    return const Color(0xFF64748B);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDownloaded
            ? const Color(0xFF10B981).withValues(alpha: 0.05)
            : isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDownloaded
              ? const Color(0xFF10B981).withValues(alpha: 0.3)
              : cs.outline.withValues(alpha: 0.12),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        Row(children: [
          Text(model.emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(model.name,
                      style: TextStyle(fontSize: 14,
                          fontWeight: FontWeight.w700, color: c.text),
                      overflow: TextOverflow.ellipsis),
                ),
                if (model.isRecommended)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('⭐ Pick',
                        style: TextStyle(fontSize: 9, color: cs.primary,
                            fontWeight: FontWeight.w700)),
                  ),
              ]),
              Text(model.maker,
                  style: TextStyle(fontSize: 11, color: c.textMuted)),
            ]),
          ),
        ]),

        const SizedBox(height: 6),
        Text(model.description,
            style: TextStyle(fontSize: 12.5, color: c.textMuted, height: 1.4)),

        const SizedBox(height: 8),

        // Tags/variants
        Wrap(spacing: 5, runSpacing: 5, children: [
          // Format chip
          _InfoChip(model.format, const Color(0xFF6366F1)),
          // Size chip
          _InfoChip('💾 ${model.sizeStr}', const Color(0xFF0EA5E9)),
          // RAM chip
          _InfoChip('🧠 ${model.ramStr}', const Color(0xFFF59E0B)),
          // Variant chips
          for (final v in model.variants)
            _InfoChip(_variantLabel(v), _variantChipColor(v)),
          // Lang chips
          if (model.languages.contains(ModelLang.indonesian))
            _InfoChip('🇮🇩 Indonesia', const Color(0xFFFF2400)),
          if (model.languages.contains(ModelLang.multilingual) &&
              !model.languages.contains(ModelLang.indonesian))
            _InfoChip('🌐 Multi-lang', const Color(0xFF10B981)),
        ]),

        // Download progress
        if (isDownloading && progress != null) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (progress?.fraction ?? 0) > 0 ? progress!.fraction : null,
              backgroundColor: cs.outline.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '⬇️ ${progress!.percentLabel} — ${_mb(progress!.received)} / ${_mb(progress!.total)}',
            style: TextStyle(fontSize: 11, color: c.textMuted),
          ),
        ],

        const SizedBox(height: 10),

        // Action buttons
        Row(children: [
          // Download button
          if (!isDownloaded && !isDownloading)
            Expanded(
              child: FilledButton.icon(
                onPressed: onDownload,
                icon: const Icon(Icons.download_rounded, size: 16),
                label: Text('Download ${model.sizeStr}',
                    style: const TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(38),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            )
          else if (isDownloaded)
            Expanded(
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                ),
                alignment: Alignment.center,
                child: Text('✓ Sudah Didownload',
                    style: TextStyle(fontSize: 12,
                        color: const Color(0xFF10B981),
                        fontWeight: FontWeight.w600)),
              ),
            )
          else
            Expanded(
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: cs.primary)),
                  const SizedBox(width: 8),
                  Text('Downloading...', style: TextStyle(
                      fontSize: 12, color: cs.primary)),
                ]),
              ),
            ),

          const SizedBox(width: 8),

          // Copy link button
          GestureDetector(
            onTap: onCopyLink,
            child: Container(
              height: 38, width: 38,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
              ),
              child: Icon(Icons.link_rounded, size: 18, color: c.textMuted),
            ),
          ),
        ]),
      ]),
    );
  }

  String _variantLabel(ModelVariant v) {
    switch (v) {
      case ModelVariant.uncensored: return '🔓 Uncensored';
      case ModelVariant.standard:   return '🛡️ Standard';
      case ModelVariant.reasoning:  return '🧠 Reasoning';
      case ModelVariant.coding:     return '💻 Coding';
      case ModelVariant.multilingual: return '🌐 Multi';
      case ModelVariant.vision:     return '👁️ Vision';
      case ModelVariant.tiny:       return '🪶 Tiny';
    }
  }

  Color _variantChipColor(ModelVariant v) {
    switch (v) {
      case ModelVariant.uncensored:   return const Color(0xFFFF6B35);
      case ModelVariant.reasoning:    return const Color(0xFF8B5CF6);
      case ModelVariant.coding:       return const Color(0xFF10B981);
      case ModelVariant.vision:       return const Color(0xFF0EA5E9);
      case ModelVariant.tiny:         return const Color(0xFF6366F1);
      default:                        return const Color(0xFF64748B);
    }
  }

  String _mb(int bytes) {
    if (bytes <= 0) return '0MB';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)}MB';
  }
}

class _InfoChip extends StatelessWidget {
  final String text;
  final Color color;
  const _InfoChip(this.text, this.color);

  @override
  Widget build(BuildContext ctx) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Text(text, style: TextStyle(fontSize: 10.5, color: color,
        fontWeight: FontWeight.w600)),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// FILTER BOTTOM SHEET
// ══════════════════════════════════════════════════════════════════════════════
class _FilterSheet extends StatefulWidget {
  final Set<ModelVariant> variantFilter;
  final Set<String> formatFilter;
  final ModelSize? maxSize;
  final int? maxRam;
  final Set<ModelLang> langFilter;
  final String sortBy;
  final Function(Set<ModelVariant>, Set<String>, ModelSize?, int?,
      Set<ModelLang>, String) onApply;
  final VoidCallback onReset;

  const _FilterSheet({
    required this.variantFilter,
    required this.formatFilter,
    required this.maxSize,
    required this.maxRam,
    required this.langFilter,
    required this.sortBy,
    required this.onApply,
    required this.onReset,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Set<ModelVariant> _variants;
  late Set<String>       _formats;
  ModelSize?             _maxSize;
  int?                   _maxRam;
  late Set<ModelLang>    _langs;
  late String            _sortBy;

  @override
  void initState() {
    super.initState();
    _variants = Set.from(widget.variantFilter);
    _formats  = Set.from(widget.formatFilter);
    _maxSize  = widget.maxSize;
    _maxRam   = widget.maxRam;
    _langs    = Set.from(widget.langFilter);
    _sortBy   = widget.sortBy;
  }

  void _toggle<T>(Set<T> set, T value) {
    if (mounted) setState(() => set.contains(value) ? set.remove(value) : set.add(value));
  }

  @override
  Widget build(BuildContext context) {
    final c      = KmColors.of(context);
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          // Handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: cs.outline.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              Text('Filter & Urutkan',
                  style: TextStyle(fontSize: 16,
                      fontWeight: FontWeight.w700, color: c.text)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  widget.onReset();
                  Navigator.pop(context);
                },
                child: Text('Reset', style: TextStyle(color: cs.primary)),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [

                // ── Versi / Variant ──────────────────────────────────────
                _SectionTitle('Versi Model', c),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _FilterChip('🛡️ Standard', _variants.contains(ModelVariant.standard),
                      cs, () => _toggle(_variants, ModelVariant.standard)),
                  _FilterChip('🔓 Uncensored (tanpa filter)', _variants.contains(ModelVariant.uncensored),
                      cs, () => _toggle(_variants, ModelVariant.uncensored)),
                  _FilterChip('🧠 Reasoning', _variants.contains(ModelVariant.reasoning),
                      cs, () => _toggle(_variants, ModelVariant.reasoning)),
                  _FilterChip('💻 Coding', _variants.contains(ModelVariant.coding),
                      cs, () => _toggle(_variants, ModelVariant.coding)),
                  _FilterChip('🌐 Multilingual', _variants.contains(ModelVariant.multilingual),
                      cs, () => _toggle(_variants, ModelVariant.multilingual)),
                  _FilterChip('🪶 Ultra Ringan (<500MB)', _variants.contains(ModelVariant.tiny),
                      cs, () => _toggle(_variants, ModelVariant.tiny)),
                  _FilterChip('👁️ Vision (support gambar)', _variants.contains(ModelVariant.vision),
                      cs, () => _toggle(_variants, ModelVariant.vision)),
                ]),

                const SizedBox(height: 16),

                // ── Format ───────────────────────────────────────────────
                _SectionTitle('Format', c),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _FilterChip('GGUF', _formats.contains('GGUF'), cs,
                      () => _toggle(_formats, 'GGUF')),
                  _FilterChip('TFLite/.task', _formats.contains('TFLite'), cs,
                      () => _toggle(_formats, 'TFLite')),
                  _FilterChip('ONNX', _formats.contains('ONNX'), cs,
                      () => _toggle(_formats, 'ONNX')),
                ]),

                const SizedBox(height: 16),

                // ── Ukuran file ───────────────────────────────────────────
                _SectionTitle('Maks Ukuran File', c),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _FilterChip('< 500MB', _maxSize == ModelSize.tiny, cs,
                      () => setState(() => _maxSize = _maxSize == ModelSize.tiny ? null : ModelSize.tiny)),
                  _FilterChip('< 1.5GB', _maxSize == ModelSize.small, cs,
                      () => setState(() => _maxSize = _maxSize == ModelSize.small ? null : ModelSize.small)),
                  _FilterChip('< 3GB', _maxSize == ModelSize.medium, cs,
                      () => setState(() => _maxSize = _maxSize == ModelSize.medium ? null : ModelSize.medium)),
                  _FilterChip('< 5GB', _maxSize == ModelSize.large, cs,
                      () => setState(() => _maxSize = _maxSize == ModelSize.large ? null : ModelSize.large)),
                ]),

                const SizedBox(height: 16),

                // ── RAM ───────────────────────────────────────────────────
                _SectionTitle('Maks RAM yang Dibutuhkan', c),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _FilterChip('≤ 2GB RAM', _maxRam == 2, cs,
                      () => setState(() => _maxRam = _maxRam == 2 ? null : 2)),
                  _FilterChip('≤ 4GB RAM', _maxRam == 4, cs,
                      () => setState(() => _maxRam = _maxRam == 4 ? null : 4)),
                  _FilterChip('≤ 6GB RAM', _maxRam == 6, cs,
                      () => setState(() => _maxRam = _maxRam == 6 ? null : 6)),
                  _FilterChip('≤ 8GB RAM', _maxRam == 8, cs,
                      () => setState(() => _maxRam = _maxRam == 8 ? null : 8)),
                ]),

                const SizedBox(height: 16),

                // ── Bahasa ────────────────────────────────────────────────
                _SectionTitle('Bahasa', c),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _FilterChip('🇮🇩 Bahasa Indonesia', _langs.contains(ModelLang.indonesian),
                      cs, () => _toggle(_langs, ModelLang.indonesian)),
                  _FilterChip('🌐 Multilingual', _langs.contains(ModelLang.multilingual),
                      cs, () => _toggle(_langs, ModelLang.multilingual)),
                  _FilterChip('🇬🇧 English Only', _langs.contains(ModelLang.english),
                      cs, () => _toggle(_langs, ModelLang.english)),
                  _FilterChip('🇨🇳 Chinese', _langs.contains(ModelLang.chinese),
                      cs, () => _toggle(_langs, ModelLang.chinese)),
                ]),

                const SizedBox(height: 16),

                // ── Sort ──────────────────────────────────────────────────
                _SectionTitle('Urutkan', c),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _FilterChip('⭐ Popularitas', _sortBy == 'popularity', cs,
                      () => setState(() => _sortBy = 'popularity')),
                  _FilterChip('📦 Ukuran Kecil → Besar', _sortBy == 'size_asc', cs,
                      () => setState(() => _sortBy = 'size_asc')),
                  _FilterChip('📦 Ukuran Besar → Kecil', _sortBy == 'size_desc', cs,
                      () => setState(() => _sortBy = 'size_desc')),
                  _FilterChip('🔤 Nama A-Z', _sortBy == 'name', cs,
                      () => setState(() => _sortBy = 'name')),
                ]),

                const SizedBox(height: 24),

                FilledButton(
                  onPressed: () {
                    widget.onApply(_variants, _formats, _maxSize, _maxRam, _langs, _sortBy);
                    Navigator.pop(context);
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Terapkan Filter',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final KmColors c;
  const _SectionTitle(this.title, this.c);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title, style: TextStyle(
        fontSize: 13, fontWeight: FontWeight.w700, color: c.text)),
  );
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ColorScheme cs;
  final VoidCallback onTap;
  const _FilterChip(this.label, this.selected, this.cs, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? cs.primary : cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? cs.primary : cs.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Text(label, style: TextStyle(
          fontSize: 12,
          color: selected ? Colors.white : cs.onSurface.withValues(alpha: 0.7),
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
    ),
  );
}
