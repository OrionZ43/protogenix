import 'package:flutter/material.dart';
import 'lyrics_models.dart';
import '../../player/presentation/widgets/lyrics_selector_sheet.dart';

/// Интеллектуальный роутер: авто-выбор или ручной выбор через UI.
class LyricsSelectionLogic {

  /// Разрешает выбор текста:
  /// - Если список пуст → null
  /// - Если лучший результат выше порога → авто-возврат
  /// - Если ниже порога → показываем шторку выбора пользователю
  ///
  /// [confidenceThreshold] — порог уверенности [0.0 … 100.0]
  static Future<LyricsMetadata?> resolveLyrics(
      BuildContext context,
      List<ScoredLyric> results, {
        double confidenceThreshold = 65.0,
      }) async {
    if (results.isEmpty) return null;

    // Сортируем по убыванию score
    final sorted = List<ScoredLyric>.from(results)
      ..sort((a, b) => b.score.compareTo(a.score));

    final best = sorted.first;

    // Авто-выбор если уверенность высокая
    if (best.score >= confidenceThreshold) {
      debugPrint(
        '[LyricsRouter] Авто-выбор: "${best.metadata.trackName}" '
            '(score=${best.scoreLabel})',
      );
      return best.metadata;
    }

    // Низкая уверенность — показываем шторку
    debugPrint(
      '[LyricsRouter] Низкая уверенность (${best.scoreLabel} < $confidenceThreshold) '
          '→ ручной выбор',
    );

    if (!context.mounted) return null;

    return showLyricsSelectorSheet(context, sorted);
  }
}