import 'package:flutter/material.dart';
import '../../core/theme/km_colors.dart';

// ── KmCard ─────────────────────────────────────
/// Card premium dengan border tipis dan optional glow
class KmCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? bgColor;
  final double radius;
  final bool glowOnTap;

  const KmCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.borderColor,
    this.bgColor,
    this.radius = 16,
    this.glowOnTap = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: bgColor ?? c.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? c.border, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          splashColor: c.accentSoft,
          highlightColor: c.accentSoft,
          child: Padding(
            padding: padding ?? const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ── KmLevelBadge ──────────────────────────────
class KmLevelBadge extends StatelessWidget {
  final String level;
  final bool small;

  const KmLevelBadge({super.key, required this.level, this.small = false});

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    final color = c.levelColor(level);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 6 : 8,
        vertical: small ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Text(
        level.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: small ? 9 : 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ── KmSearchBar ───────────────────────────────
class KmSearchBar extends StatelessWidget {
  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;

  const KmSearchBar({
    super.key,
    this.controller,
    this.hint = 'Cari...',
    this.onChanged,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(color: c.text, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: c.textMuted, fontSize: 14),
          prefixIcon: Icon(Icons.search_rounded, color: c.textMuted, size: 20),
          suffixIcon: (controller?.text.isNotEmpty ?? false)
              ? IconButton(
                  icon: Icon(Icons.clear_rounded, color: c.textMuted, size: 18),
                  onPressed: () {
                    controller?.clear();
                    onClear?.call();
                    onChanged?.call('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

// ── KmLevelChips ─────────────────────────────
class KmLevelChips extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  final List<String> levels;

  const KmLevelChips({
    super.key,
    required this.selected,
    required this.onSelect,
    this.levels = const ['Semua', 'N5', 'N4', 'N3', 'N2', 'N1'],
  });

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: levels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final lvl = levels[i];
          final isSelected = lvl == selected;
          final color = lvl == 'Semua' ? c.accent : c.levelColor(lvl);
          return GestureDetector(
            onTap: () => onSelect(lvl),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? color.withValues(alpha: 0.2) : c.inputFill,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? color : c.border,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Text(
                lvl,
                style: TextStyle(
                  color: isSelected ? color : c.textSub,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── KmXpBar ───────────────────────────────────
class KmXpBar extends StatelessWidget {
  final int currentXp;
  final int maxXp;
  final int level;

  const KmXpBar({
    super.key,
    required this.currentXp,
    required this.maxXp,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    final progress = maxXp > 0 ? (currentXp / maxXp).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Level $level',
                style: TextStyle(
                  color: c.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '$currentXp / $maxXp XP',
                style: TextStyle(
                  color: c.gold,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'SpaceMono',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (_, value, __) => LinearProgressIndicator(
                value: value,
                minHeight: 6,
                backgroundColor: c.border,
                valueColor: AlwaysStoppedAnimation(c.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── KmEmptyState ─────────────────────────────
class KmEmptyState extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const KmEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              icon,
              style: const TextStyle(
                fontSize: 56,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: c.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: c.textSub, fontSize: 13, height: 1.6),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

// ── KmShimmer ────────────────────────────────
class KmShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const KmShimmerBox({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.radius = 8,
  });

  @override
  State<KmShimmerBox> createState() => _KmShimmerBoxState();
}

class _KmShimmerBoxState extends State<KmShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anim = Tween(begin: -2.0, end: 2.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = KmColors.of(context);
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment(_anim.value - 1, 0),
            end: Alignment(_anim.value, 0),
            colors: [
              c.border,
              c.borderSoft,
              c.border,
            ],
          ),
        ),
      ),
    );
  }
}
