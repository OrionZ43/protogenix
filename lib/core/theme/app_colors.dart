import 'dart:math' as math;

import 'package:flutter/material.dart';

abstract class AppColors {
  static const Color defaultSeed = Color(0xFF7B5EA7);

  static const Color glassSurface = Color(0x1AFFFFFF);
  static const Color glassBorder = Color(0x33FFFFFF);
  static const Color glassHighlight = Color(0x0DFFFFFF);

  /// Плотное тёмное стекло там, где фон не размыть (подсказки, плашки,
  /// диалоги по умолчанию): по тону — как шторки поверх размытия.
  static const Color glassDark = Color(0xF2141420);

  static const Color neonPurple = Color(0xFFCE93D8);
  static const Color neonCyan = Color(0xFF80DEEA);

  /// Цвет акцента, пригодный для **переднего плана** на тёмном фоне.
  ///
  /// Акцент в приложении — это цвет обложки (`paletteProvider`), и он бывает
  /// тёмным: `primary` после подкрутки палитры доходит до яркости 0.2, а у
  /// блёклой обложки ещё и насыщенность около нуля. Тогда выделенная
  /// «таблетка» или иконка карточки, нарисованные этим цветом, оказываются
  /// **темнее и бледнее невыделенных** — те рисуются белым. Выглядит так,
  /// будто выбран не тот пункт (найдено 2026-09-27 на тёмной обложке).
  ///
  /// Поэтому всё, что красит акцентом текст, иконку или рамку, пропускает
  /// его через это: оттенок сохраняется, а яркость и насыщенность
  /// поднимаются до читаемых. Заливки (`AccentButton`) это не касается —
  /// там цвет держит фон, а текст подбирается по яркости.
  static Color readableAccent(Color accent) {
    final hsl = HSLColor.fromColor(accent);
    if (hsl.lightness >= 0.5 && hsl.saturation >= 0.25) return accent;
    return hsl
        .withSaturation(math.max(hsl.saturation, 0.35))
        .withLightness(math.max(hsl.lightness, 0.58))
        .toColor();
  }
}
