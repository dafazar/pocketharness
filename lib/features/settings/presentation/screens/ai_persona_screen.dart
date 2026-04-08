// lib/features/settings/presentation/screens/ai_persona_screen.dart
// KanMon GO — AI Persona & Parameter Tuning Screen
// =============================================================================

import 'package:flutter/material.dart';
import 'package:kanmongo/core/theme/km_colors.dart';
import 'package:kanmongo/data/services/ai_persona_service.dart';
import 'package:uuid/uuid.dart';

class AiPersonaScreen extends StatefulWidget {
  const AiPersonaScreen({super.key});
  @override
  State<AiPersonaScreen> createState() => _AiPersonaScreenState();
}

class _AiPersonaScreenState extends State<AiPersonaScreen>
    with SingleTickerProviderStateMixin {
  final _svc   = AiPersonaService.instance;
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _svc.load().then((_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c  = KmColors.of(context);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        title: Text('AI Persona & Tuning',
            style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: c.text, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
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
              tabs: const [Tab(text: 'Persona'), Tab(text: 'Parameter')],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _PersonaTab(svc: _svc, onChanged: () => setState(() {})),
          _ParameterTab(svc: _svc, onChanged: () => setState(() {})),
        ],
      ),
    );
  }
}

// ── Tab 1: Persona ────────────────────────────────────────────────────────────
class _PersonaTab extends StatefulWidget {
  final AiPersonaService svc;
  final VoidCallback onChanged;
  const _PersonaTab({required this.svc, required this.onChanged});
  @override
  State<_PersonaTab> createState() => _PersonaTabState();
}

class _PersonaTabState extends State<_PersonaTab> {
  void _createCustom() {
    showDialog(
      context: context,
      builder: (_) => _CustomPersonaDialog(
        onSave: (persona) async {
          await widget.svc.saveCustomPersona(persona);
          setState(() {});
          widget.onChanged();
        },
      ),
    );
  }

  void _editCustom(AiPersona persona) {
    showDialog(
      context: context,
      builder: (_) => _CustomPersonaDialog(
        existing: persona,
        onSave: (p) async {
          await widget.svc.saveCustomPersona(p);
          setState(() {});
          widget.onChanged();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c      = KmColors.of(context);
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final active = widget.svc.activePersonaId;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Info
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
          ),
          child: Row(children: [
            const Text('💡', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'Persona menentukan kepribadian & cara AI menjawab. '
              'Pilih sesuai kebutuhan atau buat custom sendiri.',
              style: TextStyle(fontSize: 12.5, color: c.textMuted, height: 1.4),
            )),
          ]),
        ),

        // Builtin personas
        Text('Persona Bawaan', style: TextStyle(fontSize: 13,
            fontWeight: FontWeight.w700, color: c.textMuted)),
        const SizedBox(height: 8),

        for (final p in kBuiltinPersonas)
          _PersonaCard(
            persona: p,
            isActive: active == p.id,
            isDark: isDark,
            c: c,
            cs: cs,
            onTap: () async {
              await widget.svc.setActive(p.id);
              setState(() {});
              widget.onChanged();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('✅ Persona aktif: ${p.emoji} ${p.name}'),
                  duration: const Duration(seconds: 2),
                ));
              }
            },
          ),

        const SizedBox(height: 16),

        // Custom personas
        Row(children: [
          Text('Persona Custom', style: TextStyle(fontSize: 13,
              fontWeight: FontWeight.w700, color: c.textMuted)),
          const Spacer(),
          GestureDetector(
            onTap: _createCustom,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_rounded, size: 16, color: cs.primary),
                const SizedBox(width: 4),
                Text('Buat Persona',
                    style: TextStyle(fontSize: 12, color: cs.primary,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 8),

        if (widget.svc.allPersonas.where((p) => p.isCustom).isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(children: [
                Text('✍️', style: const TextStyle(fontSize: 36)),
                const SizedBox(height: 8),
                Text('Belum ada persona custom',
                    style: TextStyle(color: c.textMuted, fontSize: 13)),
                const SizedBox(height: 4),
                Text('Klik "Buat Persona" untuk membuat AI dengan karakter kamu sendiri',
                    style: TextStyle(color: c.textMuted, fontSize: 11),
                    textAlign: TextAlign.center),
              ]),
            ),
          )
        else
          for (final p in widget.svc.allPersonas.where((p) => p.isCustom))
            _PersonaCard(
              persona: p,
              isActive: active == p.id,
              isDark: isDark,
              c: c,
              cs: cs,
              onTap: () async {
                await widget.svc.setActive(p.id);
                setState(() {});
                widget.onChanged();
              },
              onEdit: () => _editCustom(p),
              onDelete: () async {
                await widget.svc.deleteCustomPersona(p.id);
                setState(() {});
                widget.onChanged();
              },
            ),

        const SizedBox(height: 32),
      ],
    );
  }
}

// ── Persona Card ──────────────────────────────────────────────────────────────
class _PersonaCard extends StatelessWidget {
  final AiPersona persona;
  final bool isActive, isDark;
  final KmColors c;
  final ColorScheme cs;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _PersonaCard({
    required this.persona, required this.isActive,
    required this.isDark, required this.c, required this.cs,
    required this.onTap, this.onEdit, this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isActive
              ? cs.primary.withValues(alpha: 0.1)
              : isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? cs.primary.withValues(alpha: 0.5) : cs.outline.withValues(alpha: 0.15),
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Text(persona.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(persona.name, style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: isActive ? cs.primary : c.text)),
                if (isActive) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.primary, borderRadius: BorderRadius.circular(8)),
                    child: const Text('AKTIF', style: TextStyle(
                        fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ],
              ]),
              const SizedBox(height: 3),
              Text(persona.description, style: TextStyle(
                  fontSize: 12, color: c.textMuted)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, children: [
                _Chip('🌡 ${persona.temperature}', cs),
                _Chip('📝 ${persona.maxTokens} tok', cs),
              ]),
            ]),
          ),
          if (onEdit != null || onDelete != null)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: c.textMuted, size: 18),
              color: c.surface,
              onSelected: (v) {
                if (v == 'edit') onEdit?.call();
                if (v == 'delete') onDelete?.call();
              },
              itemBuilder: (_) => [
                if (onEdit != null)
                  const PopupMenuItem(value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit_rounded, size: 16),
                        SizedBox(width: 8), Text('Edit')])),
                if (onDelete != null)
                  PopupMenuItem(value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_rounded, size: 16, color: Colors.red),
                        const SizedBox(width: 8),
                        const Text('Hapus', style: TextStyle(color: Colors.red))])),
              ],
            ),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final ColorScheme cs;
  const _Chip(this.text, this.cs);
  @override
  Widget build(BuildContext ctx) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(text, style: TextStyle(fontSize: 10,
        color: cs.onSurface.withValues(alpha: 0.6))),
  );
}

// ── Tab 2: Parameter Tuning ───────────────────────────────────────────────────
class _ParameterTab extends StatefulWidget {
  final AiPersonaService svc;
  final VoidCallback onChanged;
  const _ParameterTab({required this.svc, required this.onChanged});
  @override
  State<_ParameterTab> createState() => _ParameterTabState();
}

class _ParameterTabState extends State<_ParameterTab> {
  late AiParameterConfig _p;

  @override
  void initState() {
    super.initState();
    _p = widget.svc.params;
  }

  Future<void> _save() async {
    await widget.svc.saveParams(_p);
    widget.onChanged();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Parameter disimpan')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c      = KmColors.of(context);
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            const Text('⚙️', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'Parameter ini mempengaruhi semua model AI. '
              'Perubahan berlaku untuk online dan offline.',
              style: TextStyle(fontSize: 12, color: c.textMuted),
            )),
          ]),
        ),

        // Temperature
        _SliderParam(
          isDark: isDark, c: c, cs: cs,
          label: '🌡️ Temperature',
          description: 'Kreativitas jawaban. Rendah = lebih fokus & deterministik. '
              'Tinggi = lebih kreatif & beragam.',
          value: _p.temperature,
          min: 0.0, max: 2.0, divisions: 20,
          valueLabel: _p.temperature.toStringAsFixed(1),
          onChanged: (v) => setState(() => _p = AiParameterConfig(
            temperature: v, maxTokens: _p.maxTokens, topP: _p.topP,
            topK: _p.topK, repeatPenalty: _p.repeatPenalty, contextSize: _p.contextSize,
          )),
          presets: [
            ('Deterministik', 0.1), ('Seimbang', 0.7),
            ('Kreatif', 1.0), ('Bebas', 1.5),
          ],
        ),

        const SizedBox(height: 16),

        // Max Tokens
        _SliderParam(
          isDark: isDark, c: c, cs: cs,
          label: '📝 Max Output Tokens',
          description: 'Panjang maksimum jawaban. Lebih tinggi = jawaban lebih panjang '
              '(tapi lebih lambat dan lebih banyak quota).',
          value: _p.maxTokens.toDouble(),
          min: 256, max: 4096, divisions: 15,
          valueLabel: '${_p.maxTokens}',
          onChanged: (v) => setState(() => _p = AiParameterConfig(
            temperature: _p.temperature, maxTokens: v.round(), topP: _p.topP,
            topK: _p.topK, repeatPenalty: _p.repeatPenalty, contextSize: _p.contextSize,
          )),
          presets: [
            ('Singkat', 512), ('Normal', 1024),
            ('Panjang', 2048), ('Sangat Panjang', 4096),
          ],
        ),

        const SizedBox(height: 16),

        // Top P
        _SliderParam(
          isDark: isDark, c: c, cs: cs,
          label: '🎯 Top-P (Nucleus Sampling)',
          description: 'Probabilitas kumulatif token yang dipertimbangkan. '
              '0.9 = baik untuk sebagian besar kasus.',
          value: _p.topP,
          min: 0.1, max: 1.0, divisions: 9,
          valueLabel: _p.topP.toStringAsFixed(1),
          onChanged: (v) => setState(() => _p = AiParameterConfig(
            temperature: _p.temperature, maxTokens: _p.maxTokens, topP: v,
            topK: _p.topK, repeatPenalty: _p.repeatPenalty, contextSize: _p.contextSize,
          )),
        ),

        const SizedBox(height: 16),

        // Top K
        _SliderParam(
          isDark: isDark, c: c, cs: cs,
          label: '🔢 Top-K',
          description: 'Jumlah token teratas yang dipertimbangkan. '
              'Untuk GGUF/lokal. 40 = standar.',
          value: _p.topK.toDouble(),
          min: 1, max: 100, divisions: 9,
          valueLabel: '${_p.topK}',
          onChanged: (v) => setState(() => _p = AiParameterConfig(
            temperature: _p.temperature, maxTokens: _p.maxTokens, topP: _p.topP,
            topK: v.round(), repeatPenalty: _p.repeatPenalty, contextSize: _p.contextSize,
          )),
        ),

        const SizedBox(height: 16),

        // Repeat Penalty (untuk GGUF)
        _SliderParam(
          isDark: isDark, c: c, cs: cs,
          label: '🔁 Repeat Penalty (GGUF)',
          description: 'Hukuman untuk pengulangan kata. '
              'Berlaku untuk model GGUF offline. 1.1 = standar.',
          value: _p.repeatPenalty,
          min: 1.0, max: 2.0, divisions: 10,
          valueLabel: _p.repeatPenalty.toStringAsFixed(1),
          onChanged: (v) => setState(() => _p = AiParameterConfig(
            temperature: _p.temperature, maxTokens: _p.maxTokens, topP: _p.topP,
            topK: _p.topK, repeatPenalty: v, contextSize: _p.contextSize,
          )),
        ),

        const SizedBox(height: 16),

        // Context Size (untuk GGUF)
        _SliderParam(
          isDark: isDark, c: c, cs: cs,
          label: '🧠 Context Size (GGUF)',
          description: 'Ukuran window konteks untuk model lokal. '
              'Lebih besar = ingat lebih banyak history (tapi lebih berat).',
          value: _p.contextSize.toDouble(),
          min: 512, max: 8192, divisions: 7,
          valueLabel: '${_p.contextSize}',
          onChanged: (v) => setState(() => _p = AiParameterConfig(
            temperature: _p.temperature, maxTokens: _p.maxTokens, topP: _p.topP,
            topK: _p.topK, repeatPenalty: _p.repeatPenalty, contextSize: v.round(),
          )),
        ),

        const SizedBox(height: 20),

        // Reset button
        OutlinedButton.icon(
          onPressed: () => setState(() => _p = const AiParameterConfig()),
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Reset ke Default'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_rounded, size: 20),
          label: const Text('Simpan Parameter',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _SliderParam extends StatelessWidget {
  final bool isDark;
  final KmColors c;
  final ColorScheme cs;
  final String label, description, valueLabel;
  final double value, min, max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final List<(String, double)>? presets;

  const _SliderParam({
    required this.isDark, required this.c, required this.cs,
    required this.label, required this.description,
    required this.value, required this.min, required this.max,
    required this.divisions, required this.valueLabel,
    required this.onChanged, this.presets,
  });

  @override
  Widget build(BuildContext ctx) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(label, style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600, color: c.text))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(valueLabel, style: TextStyle(
              fontSize: 13, color: cs.primary, fontWeight: FontWeight.w700,
              fontFamily: 'monospace')),
        ),
      ]),
      const SizedBox(height: 4),
      Text(description, style: TextStyle(fontSize: 11, color: c.textMuted, height: 1.4)),
      Slider(
        value: value.clamp(min, max),
        min: min, max: max,
        divisions: divisions,
        activeColor: cs.primary,
        onChanged: onChanged,
      ),
      if (presets != null)
        Wrap(spacing: 6, children: [
          for (final (name, val) in presets!)
            GestureDetector(
              onTap: () => onChanged(val),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: (value - val).abs() < 0.05
                      ? cs.primary.withValues(alpha: 0.15)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (value - val).abs() < 0.05
                        ? cs.primary.withValues(alpha: 0.3)
                        : Colors.transparent,
                  ),
                ),
                child: Text(name, style: TextStyle(
                    fontSize: 11,
                    color: (value - val).abs() < 0.05 ? cs.primary : c.textMuted,
                    fontWeight: FontWeight.w500)),
              ),
            ),
        ]),
    ]),
  );
}

// ── Dialog: Custom Persona ────────────────────────────────────────────────────
class _CustomPersonaDialog extends StatefulWidget {
  final AiPersona? existing;
  final Future<void> Function(AiPersona) onSave;
  const _CustomPersonaDialog({this.existing, required this.onSave});
  @override
  State<_CustomPersonaDialog> createState() => _CustomPersonaDialogState();
}

class _CustomPersonaDialogState extends State<_CustomPersonaDialog> {
  final _nameCtrl   = TextEditingController();
  final _emojiCtrl  = TextEditingController();
  final _descCtrl   = TextEditingController();
  final _promptCtrl = TextEditingController();
  double _temp      = 0.7;
  int    _maxTok    = 1024;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _nameCtrl.text   = widget.existing!.name;
      _emojiCtrl.text  = widget.existing!.emoji;
      _descCtrl.text   = widget.existing!.description;
      _promptCtrl.text = widget.existing!.systemPrompt;
      _temp            = widget.existing!.temperature;
      _maxTok          = widget.existing!.maxTokens;
    } else {
      _emojiCtrl.text = '✨';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _emojiCtrl.dispose();
    _descCtrl.dispose(); _promptCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c      = KmColors.of(context);
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(widget.existing == null ? 'Buat Persona Custom' : 'Edit Persona',
          style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            SizedBox(
              width: 60,
              child: TextField(
                controller: _emojiCtrl,
                style: const TextStyle(fontSize: 24),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: 'Emoji',
                  labelStyle: TextStyle(color: c.textMuted, fontSize: 11),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _nameCtrl,
                style: TextStyle(color: c.text),
                decoration: InputDecoration(
                  labelText: 'Nama',
                  labelStyle: TextStyle(color: c.textMuted),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _descCtrl,
            style: TextStyle(color: c.text, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Deskripsi singkat',
              labelStyle: TextStyle(color: c.textMuted),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _promptCtrl,
            maxLines: 6, minLines: 4,
            style: TextStyle(color: c.text, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'System Prompt',
              labelStyle: TextStyle(color: c.textMuted),
              hintText: 'Kamu adalah... Kamu bisa... Cara kamu menjawab...',
              hintStyle: TextStyle(color: c.textMuted.withValues(alpha: 0.5), fontSize: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Temp: ${_temp.toStringAsFixed(1)}',
                    style: TextStyle(fontSize: 12, color: c.textMuted)),
                Slider(
                  value: _temp, min: 0.0, max: 2.0, divisions: 20,
                  activeColor: cs.primary,
                  onChanged: (v) => setState(() => _temp = v),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Max Tok: $_maxTok',
                    style: TextStyle(fontSize: 12, color: c.textMuted)),
                Slider(
                  value: _maxTok.toDouble(), min: 256, max: 4096, divisions: 15,
                  activeColor: cs.primary,
                  onChanged: (v) => setState(() => _maxTok = v.round()),
                ),
              ]),
            ),
          ]),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Batal', style: TextStyle(color: c.textMuted)),
        ),
        FilledButton(
          onPressed: () async {
            if (_nameCtrl.text.isEmpty || _promptCtrl.text.isEmpty) return;
            final persona = AiPersona(
              id:           widget.existing?.id ?? const Uuid().v4(),
              name:         _nameCtrl.text.trim(),
              emoji:        _emojiCtrl.text.trim().isNotEmpty ? _emojiCtrl.text.trim() : '✨',
              description:  _descCtrl.text.trim(),
              systemPrompt: _promptCtrl.text.trim(),
              temperature:  _temp,
              maxTokens:    _maxTok,
              isCustom:     true,
            );
            Navigator.pop(context);
            await widget.onSave(persona);
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
