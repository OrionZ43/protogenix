import 'package:flutter/services.dart';

/// Утилита для создания сложных паттернов вибрации (Haptic Chords).
class HapticPatterns {
  HapticPatterns._();

  /// Двойной легкий удар (Double tap / Heartbeat)
  /// Отлично подходит для Play/Pause.
  static Future<void> playPause() async {
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 120));
    HapticFeedback.lightImpact();
  }

  /// Серия из нарастающих вибраций.
  /// Подходит для успешных действий, загрузки, лайков.
  static Future<void> success() async {
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 150));
    HapticFeedback.heavyImpact();
  }

  /// Очень быстрая серия микро-вибраций (tick-tick-tick).
  /// Идеально для ручной перемотки / скраббинга (seek).
  static Future<void> seek() async {
    // Встроенный selectionClick обычно очень короткий
    HapticFeedback.selectionClick();
  }
}
