/// Тип синхронизации текста — от высшего приоритета к низшему
enum LyricsType {
  /// Послоговая синхронизация (YRC формат NetEase) — наивысший приоритет
  syllable,

  /// Пословная синхронизация (Enhanced LRC, теги <mm:ss.xx>) — высокий
  enhanced,

  /// Построчная синхронизация (Synced LRC, теги [mm:ss.xx]) — средний
  synced,

  /// Обычный текст без таймингов — низший
  plain,
}

extension LyricsTypeExt on LyricsType {
  /// Человекочитаемое название для UI
  String get label => switch (this) {
        LyricsType.syllable => 'Syllable',
        LyricsType.enhanced => 'Word-by-Word',
        LyricsType.synced => 'Synced',
        LyricsType.plain => 'Plain',
      };

  /// Является ли текст синхронизированным (любого уровня)
  bool get isSynced => this != LyricsType.plain;
}

/// Полные метаданные найденного текста песни
class LyricsMetadata {
  final String id;
  final String trackName;
  final String artistName;
  final int? durationMs;
  final String content;
  final LyricsType type;

  /// Источник: "lrclib.net", "netease", "local"
  final String source;

  const LyricsMetadata({
    required this.id,
    required this.trackName,
    required this.artistName,
    this.durationMs,
    required this.content,
    required this.type,
    required this.source,
  });

  @override
  String toString() =>
      'LyricsMetadata("$artistName — $trackName", type: $type, source: $source)';
}

/// Найденный текст с оценкой (lyrics_matcher.dart).
class ScoredLyric {
  final LyricsMetadata metadata;

  /// Для сортировки и показа, примерно 0…200.
  final double score;

  /// Точно та же песня — можно выбирать автоматически. Остальные варианты
  /// показываются только в ручном поиске.
  final bool isConfident;

  /// ≠ 1 — текст оригинала для slowed/sped up: тайминги умножить на него.
  final double timeScale;

  /// false — тайминги от другой версии трека: показывать без синхронизации.
  final bool timingsReliable;

  const ScoredLyric({
    required this.metadata,
    required this.score,
    this.isConfident = true,
    this.timeScale = 1.0,
    this.timingsReliable = true,
  });

  String get scoreLabel => score.toStringAsFixed(1);

  @override
  String toString() =>
      'ScoredLyric(score: $scoreLabel, "${metadata.trackName}")';
}
