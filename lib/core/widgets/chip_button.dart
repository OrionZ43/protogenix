// lib/core/widgets/chip_button.dart
//
// Кнопка-«таблетка» в стиле плеера: иконка и подпись в полупрозрачной рамке.
// С accent — заливка и рамка в цвет обложки, для главного действия.

import 'package:flutter/material.dart';

class ChipButton extends StatelessWidget {
  const ChipButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.accent,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color? accent;

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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: color.withAlpha(strong ? 40 : 16),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withAlpha(strong ? 130 : 40)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: strong ? color : Colors.white70),
                const SizedBox(width: 7),
                Text(
                  label,
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
