// lib/core/widgets/glass_back_button.dart
//
// Кнопка «Назад» в стеклянной плашке — для страниц поверх оболочки
// («Настройки», «О приложении»). Стоит на месте, а не в прокрутке, поэтому
// размытие здесь допустимо (performance.md, правило 5).

import 'dart:ui';

import 'package:flutter/material.dart';

class GlassBackButton extends StatelessWidget {
  const GlassBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: Colors.white.withAlpha(217),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withAlpha(26),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.white.withAlpha(38)),
            ),
          ),
          tooltip: 'Назад',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}
