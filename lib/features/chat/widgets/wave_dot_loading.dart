// lib/features/chat/widgets/wave_dot_loading.dart
// KanMon GO — Wave Dot Loading Indicator (staggered 3-dot bounce)

import 'package:flutter/material.dart';
import 'package:kanmongo/core/theme/km_colors.dart';

class WaveDotLoading extends StatefulWidget {
  const WaveDotLoading({super.key});

  @override
  State<WaveDotLoading> createState() => _WaveDotLoadingState();
}

class _WaveDotLoadingState extends State<WaveDotLoading>
    with TickerProviderStateMixin {
  late final AnimationController _ctrl0;
  late final AnimationController _ctrl1;
  late final AnimationController _ctrl2;

  late final Animation<double> _anim0;
  late final Animation<double> _anim1;
  late final Animation<double> _anim2;

  @override
  void initState() {
    super.initState();

    _ctrl0 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _ctrl1 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _ctrl2 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _anim0 = Tween<double>(begin: 4, end: -4).animate(
      CurvedAnimation(parent: _ctrl0, curve: Curves.easeInOut),
    );
    _anim1 = Tween<double>(begin: 4, end: -4).animate(
      CurvedAnimation(parent: _ctrl1, curve: Curves.easeInOut),
    );
    _anim2 = Tween<double>(begin: 4, end: -4).animate(
      CurvedAnimation(parent: _ctrl2, curve: Curves.easeInOut),
    );

    // Stagger: dot 0 starts immediately, dot 1 after 150ms, dot 2 after 300ms
    _ctrl0.repeat(reverse: true);
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) _ctrl1.repeat(reverse: true);
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _ctrl2.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl0.dispose();
    _ctrl1.dispose();
    _ctrl2.dispose();
    super.dispose();
  }

  Widget _dot(Animation<double> anim, Color color) {
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, anim.value),
        child: Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3.5),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = KmColors.of(context).accent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dot(_anim0, color),
        const SizedBox(width: 4),
        _dot(_anim1, color),
        const SizedBox(width: 4),
        _dot(_anim2, color),
      ],
    );
  }
}
