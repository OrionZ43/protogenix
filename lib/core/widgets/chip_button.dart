// lib/core/widgets/chip_button.dart
//
// Кнопка-«таблетка» в стиле плеера: иконка и подпись в полупрозрачной рамке.
// С accent — заливка и рамка в цвет обложки, для главного действия (красный —
// для удаления). Можно только иконку или только подпись.

import 'package:flutter/material.dart';

class ChipButton extends StatelessWidget {
  const ChipButton({
    super.key,
    this.label,
    this.icon,
    required this.onTap,
    this.accent,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
  }) : assert(label != null || icon != null);

  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? accent;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? Colors.white;
    final strong = accent != null;
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: padding,
            decoration: BoxDecoration(
              color: color.withAlpha(strong ? 40 : 16),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withAlpha(strong ? 130 : 40)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              // По центру — если кнопку растянули (Expanded в диалоге)
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null)
                  Icon(icon, size: 16, color: strong ? color : Colors.white70),
                if (icon != null && label != null) const SizedBox(width: 7),
                if (label != null)
                  Text(
                    label!,
                    style: TextStyle(
                      color: strong ? color : Colors.white.withAlpha(215),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
