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
}
