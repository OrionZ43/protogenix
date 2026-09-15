// lib/features/importer/data/youtube_match.dart
//
// Какой ролик YouTube скачать для трека из Яндекс Музыки или Spotify.
//
// Раньше брался первый ролик той же длины, а среди них — с «Topic» или VEVO
// в имени канала, без проверки исполнителя и версии. Для «Tears For Fears —
// Everybody Wants To Rule The World» так скачался кавер с канала «Blue
// Fashion - Topic», для «KALEO — Way Down We Go» — запись с концерта
// (отзыв после 1.0.0).
//
// Теперь заголовки разбираются так же, как при подборе текстов
// (track_query.dart), но правила строже: для текста кавер той же длины
// подходит, для звука — нет.
//   1. То же название (сходство ≥ 0.8) и тот же исполнитель (≥ 0.5 — из
//      заголовка «Артист - Название» или из имени канала без « - Topic»).
//      Исполнитель неизвестен — нужна длительность ±3 с.
//   2. Та же версия: чужой live, cover, remix, extended, karaoke, stripped —
//      другая запись; и наоборот, для ремикса оригинал не подходит.
//   3. Длительность, если известна, расходится не больше чем на 45 с —
//      отсекает «1 HOUR» и записи с передач.
// Порядок среди подходящих: длительность (±3 с → неизвестна → ±15 с →
// дальше) → официальный источник (канал исполнителя, «Артист Official»,
// «Артист - Topic», VEVO) → сходство и точность длительности.
// Запросы — findYoutubeUpload (в конце файла): второй, с «topic», если
// лучший ролик первого не с официального канала.

import '../../library/domain/lyrics_text.dart';
import '../../library/domain/track_query.dart';

class YoutubeCandidate {
  const YoutubeCandidate({
    required this.id,
    required this.title,
    required this.author,
    this.durationMs,
  });

  final String id;
  final String title;

  /// Имя канала.
  final String author;
  final int? durationMs;
}

class YoutubeTrackMatcher {
  YoutubeTrackMatcher({
    required String title,
    required String artist,
    int? durationMs,
  })  : _query = TrackQueryParser.interpretations(title, artist),
        _durationMs = durationMs != null && durationMs > 0 ? durationMs : null;

  static const _sameTitle = 0.8;
  static const _sameArtist = 0.5;
  static const _officialArtist = 0.8;
  static const _goodDiffMs = 3000;
  static const _okDiffMs = 15000;
  static const _maxDiffMs = 45000;
  static final _officialSuffix =
      RegExp(r'\s*\bofficial\s*$', caseSensitive: false);

  final List<ParsedTrack> _query;
  final int? _durationMs;

  /// Лучший ролик или null — подходящей записи в выдаче нет.
  YoutubeCandidate? pick(Iterable<YoutubeCandidate> candidates) {
    final matches = <_Match>[];
    for (final candidate in candidates) {
      final match = _evaluate(candidate);
      if (match != null) matches.add(match);
    }
    matches.sort(_compare);
    return matches.isEmpty ? null : matches.first.candidate;
  }

  _Match? _evaluate(YoutubeCandidate c) {
    final parsed = TrackQueryParser.interpretations(c.title, c.author);

    // Лучшая пара прочтений (наше × ролика) по названию и артисту вместе
    var titleSim = 0.0;
    double? artistSim;
    var bestPair = -1.0;
    for (final q in _query) {
      for (final p in parsed) {
        var t = 0.0;
        for (final title in q.titles) {
          final s = textSimilarity(title, p.title);
          if (s > t) t = s;
        }
        final a = q.artists.isEmpty || p.artists.isEmpty
            ? null
            : artistSimilarity(q.artists, p.artists);
        final pair = t * 100 + (a ?? 0.5) * 60;
        if (pair > bestPair) {
          bestPair = pair;
          titleSim = t;
          artistSim = a;
        }
      }
    }
    if (titleSim < _sameTitle) return null;

    final ours = _query.first.variants;
    final theirs = parsed.first.variants;
    if (ours.length != theirs.length || !ours.containsAll(theirs)) return null;

    final ourMs = _durationMs;
    final theirMs = c.durationMs;
    final diff =
        ourMs == null || theirMs == null ? null : (theirMs - ourMs).abs();
    if (diff != null && diff > _maxDiffMs) return null;

    if (artistSim == null) {
      if (diff == null || diff > _goodDiffMs) return null;
    } else if (artistSim < _sameArtist) {
      return null;
    }

    return _Match(
      candidate: c,
      durationTier: diff == null
          ? 1
          : diff <= _goodDiffMs
              ? 0
              : diff <= _okDiffMs
                  ? 2
                  : 3,
      official: _isOfficial(c.author),
      score: titleSim * 100 + (artistSim ?? 0.5) * 60 - (diff ?? 0) / 1000,
    );
  }

  /// Ролик с канала самого исполнителя, «Артист - Topic» или VEVO.
  bool isOfficial(YoutubeCandidate candidate) => _isOfficial(candidate.author);

  /// Канал самого исполнителя (в том числе «Артист - Topic» — там альбомные
  /// записи) или VEVO.
  bool _isOfficial(String author) {
    if (author.toLowerCase().contains('vevo')) return true;
    final ourArtists = _query.first.artists;
    if (ourArtists.isEmpty) return false;
    // «Queen Official» — тоже канал исполнителя (живая проверка 2026-09-14:
    // без этого его ролики проигрывали перезаливу фаната). parse с пустым
    // названием отдаёт артистов из имени канала без « - Topic»
    final uploader = TrackQueryParser.parse(
            '-', author.replaceFirst(_officialSuffix, ''))
        .artists;
    return uploader.isNotEmpty &&
        artistSimilarity(ourArtists, uploader) >= _officialArtist;
  }

  static int _compare(_Match a, _Match b) {
    final tier = a.durationTier.compareTo(b.durationTier);
    if (tier != 0) return tier;
    if (a.official != b.official) return a.official ? -1 : 1;
    return b.score.compareTo(a.score);
  }
}

/// Ролик для трека: запрос «Артист - Название», а если подходящего нет или
/// он не с официального канала (перезалив фаната, канал с текстами) — ещё
/// «Артист Название topic»: он выводит записи с канала исполнителя. Из обеих
/// выдач вместе выбирает [YoutubeTrackMatcher.pick] — длительность, потом
/// официальный канал; первый же ролик официальный — второго запроса нет.
/// [search] — поиск YouTube, в тестах подменяется. Упал добавочный запрос —
/// остаётся то, что уже нашлось. null — подходящей записи нет.
Future<YoutubeCandidate?> findYoutubeUpload({
  required YoutubeTrackMatcher matcher,
  required String title,
  required String artist,
  required Future<List<YoutubeCandidate>> Function(String query) search,
}) async {
  final artists = splitArtists(artist);
  final mainArtist = artists.isEmpty ? '' : artists.first;
  final queries = mainArtist.isEmpty
      ? [title]
      : ['$mainArtist - $title', '$mainArtist $title topic'];
  final seen = <String, YoutubeCandidate>{};
  YoutubeCandidate? picked;
  for (final query in queries) {
    final List<YoutubeCandidate> results;
    try {
      results = await search(query);
    } catch (_) {
      if (picked != null) break;
      rethrow;
    }
    for (final c in results.take(15)) {
      seen.putIfAbsent(c.id, () => c);
    }
    picked = matcher.pick(seen.values);
    if (picked != null && matcher.isOfficial(picked)) break;
  }
  return picked;
}

class _Match {
  const _Match({
    required this.candidate,
    required this.durationTier,
    required this.official,
    required this.score,
  });

  final YoutubeCandidate candidate;
  final int durationTier;
  final bool official;
  final double score;
}
