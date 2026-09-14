// lib/core/widgets/accent_button.dart
//
// Главное действие шторки во всю ширину: заливка в цвет обложки. Вместо
// ElevatedButton: у того неактивная кнопка серая из темы, а на светлой обложке
// белый текст терялся.

import 'package:flutter/material.dart';

class AccentButton extends StatelessWidget {
  const AccentButton({
    super.key,
    required this.label,
    required this.accent,
    required this.onTap,
    this.icon,
    this.busy = false,
  });

  final String label;
  final Color accent;
  final VoidCallback? onTap;
  final IconData? icon;

  /// Идёт работа: вместо иконки — индикатор.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    // На светлой обложке — тёмный текст
    final foreground =
        accent.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: accent.withAlpha(enabled ? 225 : 110),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: foreground, strokeWidth: 2),
                )
              else if (icon != null)
                Icon(icon, color: foreground, size: 20),
              if (busy || icon != null) const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
