import '../domain/lyrics_models.dart';

/// Как искать: точным запросом, поиском по полям или свободным текстом.
enum LyricsSearchMode { exact, fielded, text }

/// Запрос к источнику текстов. lyrics_service.dart строит их по разобранному
/// названию трека (track_query.dart).
class LyricsSearchRequest {
  const LyricsSearchRequest({
    required this.mode,
    this.query = '',
    this.title,
    this.artist,
    this.durationMs,
    this.relevance,
  });

  final LyricsSearchMode mode;

  /// Свободный текст для [LyricsSearchMode.text].
  final String query;

  /// Название и артист для [LyricsSearchMode.exact] и [LyricsSearchMode.fielded].
  final String? title;
  final String? artist;

  /// Длительность трека — для точного поиска LRCLIB и для поиска Kugou.
  final int? durationMs;

  /// Правдоподобие песни из выдачи, 0…1.5 (LyricsMatcher.relevance). Источники,
  /// которые скачивают текст отдельным запросом (NetEase), берут только
  /// правдоподобные песни.
  final double Function(String title, String artist, int? durationMs)?
      relevance;
}

/// Абстрактный провайдер текстов песен.
/// Каждая реализация — отдельный источник (LRCLIB, NetEase, и т.д.)
abstract class LyricsProvider {
  /// Название источника для отладки и UI
  String get name;

  /// Режимы, которые источник понимает; остальные запросы ему не отправляются.
  Set<LyricsSearchMode> get modes;

  /// Никогда не бросает исключений — возвращает пустой список при ошибке:
  /// одно исключение обнулило бы весь поиск (.claude/rules/lyrics.md).
  Future<List<LyricsMetadata>> search(LyricsSearchRequest request);
}
