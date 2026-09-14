// lib/core/utils/system_insets.dart
//
// Отступ снизу над системной панелью Android. Приложение рисуется от края до
// края (edge-to-edge, main.dart), поэтому нижние кнопки и шторки обходят
// панель навигации сами: с тремя кнопками она 48 dp, с жестами — около 24.
// Постоянный отступ в 32 dp под три кнопки не хватал (отзыв после 1.0.0).

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Нижний отступ: не меньше [min] и на [gap] выше системной панели.
/// Внутри `SafeArea` панель уже учтена, тогда получается просто [min].
double bottomSafePadding(
  BuildContext context, {
  double min = 32,
  double gap = 12,
}) {
  final inset = MediaQuery.paddingOf(context).bottom;
  return math.max(min, inset + gap);
}
