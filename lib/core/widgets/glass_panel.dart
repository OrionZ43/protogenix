// lib/core/widgets/glass_panel.dart
//
// Тёмное стекло: размытый фон под полупрозрачным чёрным и тонкая рамка — как
// шторки и баннер обновления. Для плашек, диалогов и подсказок поверх
// приложения. Светлое стекло для карточек в списках — GlassCard
// (player/presentation/widgets/glass_card.dart).

import 'dart:ui';

import 'package:flutter/material.dart';

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.borderColor,
    this.padding = EdgeInsets.zero,
    this.alpha = 180,
  });

  final Widget child;
  final double borderRadius;

  /// Рамка: по умолчанию белая, для акцента — цвет обложки.
  final Color? borderColor;
  final EdgeInsetsGeometry padding;

  /// Плотность чёрного слоя, 0–255: шторки — 200, плашки — 180.
  final int alpha;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(alpha),
            borderRadius: radius,
            border:
                Border.all(color: borderColor ?? Colors.white.withAlpha(30)),
          ),
          child: child,
        ),
      ),
    );
  }
}
