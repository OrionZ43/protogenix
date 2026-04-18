import '../domain/lyrics_models.dart';

/// Абстрактный провайдер текстов песен.
/// Каждая реализация — отдельный источник (LRCLIB, NetEase, и т.д.)
abstract class LyricsProvider {
  /// Название источника для отладки и UI
  String get name;

  /// Ищет тексты по поисковому запросу.
  /// Никогда не бросает исключений — возвращает пустой список при ошибке.
  Future<List<LyricsMetadata>> search(String query);
}