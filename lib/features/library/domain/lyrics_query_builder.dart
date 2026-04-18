/// Умный генератор поисковых запросов.
///
/// Решает проблему грязных метаданных из YouTube и других источников.
/// Пример:
///   title:  "5opka - ЛИМУЗИН (Хитяра 2020)"
///   artist: "ФУГА TV"
/// Результат:
///   ["ФУГА TV ЛИМУЗИН", "5opka ЛИМУЗИН", "ЛИМУЗИН", ...]
class LyricsQueryBuilder {

  // ── Регулярки ─────────────────────────────────────────────────────────────

  /// Всё внутри скобок — (Live), [Remastered], {Bonus Track} и т.д.
  static final _brackets = RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]');

  /// Двойные и более пробелы
  static final _multiSpace = RegExp(r'\s{2,}');

  /// Разделители типа "Артист - Трек"
  static final _dashSep = RegExp(r'\s+[-–—]\s+');

  /// Мусор в конце артиста: "- Topic", "VEVO", "Official"
  static final _artistSuffix = RegExp(
    r'\s*[-–—]\s*(topic|official|music|vevo|official\s*channel|official\s*music)$',
    caseSensitive: false,
  );

  // ── Публичный API ─────────────────────────────────────────────────────────

  /// Строит список уникальных поисковых запросов.
  ///
  /// Возвращает запросы от наиболее точных к наиболее широким.
  List<String> build(String rawTitle, String rawArtist) {
    final pool = <String>{};

    // Шаг 1: Санитизация
    final cleanTitle  = _sanitizeTitle(rawTitle);
    final cleanArtist = _sanitizeArtist(rawArtist);

    // Шаг 2: Пытаемся разбить заголовок по тире
    String? splitArtist;
    String? splitTitle;

    final dashParts = cleanTitle.split(_dashSep);
    if (dashParts.length >= 2) {
      splitArtist = dashParts.first.trim();
      splitTitle  = dashParts.sublist(1).join(' ').trim();
    }

    // Шаг 3: Генерация пула запросов

    // Запрос 1: оригинальный артист + очищенное название
    _addIfNotEmpty(pool, '$cleanArtist $cleanTitle');

    // Запрос 2: артист из тире + часть после тире
    if (splitArtist != null && splitTitle != null) {
      _addIfNotEmpty(pool, '$splitArtist $splitTitle');
    }

    // Запрос 3: только очищенное название (мусор в артисте)
    _addIfNotEmpty(pool, cleanTitle);

    // Запрос 4: только часть после тире
    if (splitTitle != null) {
      _addIfNotEmpty(pool, splitTitle);
    }

    // Запрос 5: часть из тире как артист + чистый артист как фоллбэк
    if (splitArtist != null && splitTitle != null) {
      _addIfNotEmpty(pool, '$cleanArtist $splitTitle');
    }

    return pool.toList();
  }

  // ── Санитизация ───────────────────────────────────────────────────────────

  String _sanitizeTitle(String raw) {
    return raw
        .replaceAll(_brackets, '')   // убираем (скобки) и [скобки]
        .replaceAll(_multiSpace, ' ')
        .trim();
  }

  String _sanitizeArtist(String raw) {
    return raw
        .replaceAll(_brackets, '')
        .replaceAll(_artistSuffix, '')
        .replaceAll(_multiSpace, ' ')
        .trim();
  }

  void _addIfNotEmpty(Set<String> pool, String query) {
    final cleaned = query.replaceAll(_multiSpace, ' ').trim();
    if (cleaned.isNotEmpty) pool.add(cleaned);
  }
}