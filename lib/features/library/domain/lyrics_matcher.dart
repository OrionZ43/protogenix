// lib/features/library/domain/lyrics_matcher.dart
//
// Оценка и выбор найденных текстов — в два шага:
//   1. Та ли это песня: название, артист, длительность, версия (ремикс,
//      live…). Не та — в автовыбор не попадает, даже если других вариантов
//      нет: лучше «текст не найден», чем текст чужой песни.
//   2. Среди «той же песни»: сначала совпадающая длительность (иначе тайминги
//      уедут), потом формат — слоги > слова > строки > без таймингов.
//
// Раньше формат был лишь добавкой к оценке (+15 против +5), и версия по слогам
// проигрывала той же песне по строкам из-за мелкой разницы в написании
// (замер 2026-09-12, .claude/rules/lyrics.md).

import 'lyrics_models.dart';
import 'lyrics_text.dart';
import 'track_query.dart';

class LyricsMatch {
  const LyricsMatch({
    required this.metadata,
    required this.score,
    required this.isSameSong,
    required this.titleSimilarity,
    required this.artistSimilarity,
    required this.durationDiffMs,
    required this.timeScale,
    required this.timingsReliable,
  });

  final LyricsMetadata metadata;

  /// Для сортировки и показа, примерно 0…200.
  final double score;

  /// Точно та же песня — можно выбирать автоматически.
  final bool isSameSong;

  final double titleSimilarity;

  /// null — артист неизвестен с одной из сторон.
  final double? artistSimilarity;

  final int? durationDiffMs;

  /// ≠ 1 — текст оригинала для slowed/sped up: тайминги умножить на него.
  final double timeScale;

  /// false — тайминги от другой версии трека: показывать без синхронизации.
  final bool timingsReliable;

  ScoredLyric toScored() => ScoredLyric(
        metadata: metadata,
        score: score,
        isConfident: isSameSong,
        timeScale: timeScale,
        timingsReliable: timingsReliable,
      );
}

class LyricsMatcher {
  LyricsMatcher({
    required String title,
    required String artist,
    int? durationMs,
  })  : interpretations = TrackQueryParser.interpretations(title, artist),
        durationMs = durationMs != null && durationMs > 0 ? durationMs : null;

  /// Прочтения нашего трека (track_query.dart), первое — основное.
  final List<ParsedTrack> interpretations;

  final int? durationMs;

  ParsedTrack get primary => interpretations.first;

  static const _sameTitle = 0.8;
  static const _sameArtist = 0.5;
  static const _goodDiffMs = 3000;
  static const _unreliableDiffMs = 15000;

  LyricsMatch evaluate(LyricsMetadata m) {
    final candidate =
        TrackQueryParser.interpretations(m.trackName, m.artistName);

    // Лучшая пара прочтений (наше × кандидата) по названию и артисту вместе.
    var titleSim = 0.0;
    double? artistSim;
    var bestPair = -1.0;
    for (final q in interpretations) {
      for (final c in candidate) {
        final t = _titleSimilarity(q, c);
        final a = q.artists.isEmpty || c.artists.isEmpty
            ? null
            : artistSimilarity(q.artists, c.artists);
        final pair = t * 100 + (a ?? 0.5) * 60;
        if (pair > bestPair) {
          bestPair = pair;
          titleSim = t;
          artistSim = a;
        }
      }
    }

    // Версии: чужой ремикс, live, 8D — не та песня; наш live или ремикс
    // против оригинала — слова те же, тайминги решит длительность.
    final ours = primary.variants;
    final theirs = candidate.first.variants;
    var variantScore = 0.0;
    var conflict = false;
    for (final _ in theirs.difference(ours)) {
      variantScore -= 40;
      conflict = true;
    }
    for (final v in ours.difference(theirs)) {
      if (!v.isSpeedChange) variantScore -= 10;
    }
    variantScore += 10.0 * ours.intersection(theirs).length;

    // Длительность; slowed/sped up против оригинала — растягиваем тайминги.
    final ourMs = durationMs;
    final theirMs =
        m.durationMs != null && m.durationMs! > 0 ? m.durationMs : null;
    final needsScale = ours.any((v) => v.isSpeedChange) &&
        !theirs.any((v) => v.isSpeedChange);
    int? diff;
    var timeScale = 1.0;
    var reliable = true;
    var durationScore = 0.0;
    if (ourMs != null && theirMs != null) {
      if (needsScale) {
        final ratio = ourMs / theirMs;
        if (ratio >= 0.6 && ratio <= 1.6) {
          timeScale = (ratio - 1).abs() < 0.02 ? 1.0 : ratio;
          diff = 0;
          durationScore = 15;
        } else {
          diff = (ourMs - theirMs).abs();
          durationScore = -50;
          reliable = false;
        }
      } else {
        diff = (ourMs - theirMs).abs();
        durationScore = diff <= 2000
            ? 30
            : diff <= 5000
                ? 20
                : diff <= 10000
                    ? 0
                    : diff <= 20000
                        ? -20
                        : -50;
        reliable = diff <= _unreliableDiffMs;
      }
    } else if (needsScale) {
      reliable = false; // оригинал без длительности не растянуть
    }

    final formatBonus = switch (m.type) {
      LyricsType.syllable => 6.0,
      LyricsType.enhanced => 4.0,
      LyricsType.synced => 2.0,
      LyricsType.plain => 0.0,
    };
    final score = titleSim * 100 +
        (artistSim ?? 0.5) * 60 +
        durationScore +
        variantScore +
        formatBonus;

    final durationOk = diff != null && diff <= _goodDiffMs;
    final bool sameSong;
    if (titleSim < _sameTitle || conflict) {
      sameSong = false;
    } else if (artistSim != null) {
      sameSong = artistSim >= _sameArtist || durationOk;
    } else {
      // Артист неизвестен: нужна длительность или точное длинное название —
      // короткое «42» совпадёт у десятка чужих песен.
      sameSong = durationOk ||
          (titleSim >= 0.95 && normalizeForMatch(primary.title).length >= 6);
    }

    return LyricsMatch(
      metadata: m,
      score: score,
      isSameSong: sameSong,
      titleSimilarity: titleSim,
      artistSimilarity: artistSim,
      durationDiffMs: diff,
      timeScale: timeScale,
      timingsReliable: reliable,
    );
  }

  /// Правдоподобие по метаданным из выдачи, 0…1.5 — для провайдеров, которые
  /// сами решают, у каких песен скачивать текст (NetEase).
  double relevance(String title, String artist, int? durationMs) {
    final m = evaluate(LyricsMetadata(
      id: '',
      trackName: title,
      artistName: artist,
      durationMs: durationMs,
      content: '',
      type: LyricsType.plain,
      source: '',
    ));
    return (m.score / 200).clamp(0.0, 1.0) + (m.isSameSong ? 0.5 : 0.0);
  }

  /// Все кандидаты по порядку выбора: сначала «та же песня» (длительность,
  /// потом формат), дальше остальные по оценке — для ручного выбора.
  List<LyricsMatch> rank(Iterable<LyricsMetadata> candidates) =>
      candidates.map(evaluate).toList()..sort(_compare);

  /// Лучший вариант для автовыбора или null — «текст не найден».
  static LyricsMatch? best(List<LyricsMatch> ranked) =>
      ranked.isNotEmpty && ranked.first.isSameSong ? ranked.first : null;

  /// Искать дальше не нужно: та же песня, длительность совпала, есть тайминги.
  static bool isGoodEnough(LyricsMatch? m) =>
      m != null && _durationTier(m) == 0 && m.metadata.type != LyricsType.plain;

  static int _compare(LyricsMatch a, LyricsMatch b) {
    if (a.isSameSong != b.isSameSong) return a.isSameSong ? -1 : 1;
    if (a.isSameSong) {
      final tier = _durationTier(a).compareTo(_durationTier(b));
      if (tier != 0) return tier;
      final format =
          _formatRank(a.metadata.type).compareTo(_formatRank(b.metadata.type));
      if (format != 0) return format;
    }
    return b.score.compareTo(a.score);
  }

  static int _durationTier(LyricsMatch m) {
    if (!m.timingsReliable) return 3;
    final d = m.durationDiffMs;
    if (d == null) return 1;
    return d <= _goodDiffMs ? 0 : 2;
  }

  static int _formatRank(LyricsType t) => switch (t) {
        LyricsType.syllable => 0,
        LyricsType.enhanced => 1,
        LyricsType.synced => 2,
        LyricsType.plain => 3,
      };

  // Части попурри («Intro/Starboy») берём только у нашего трека: найденное
  // «Numb / Encore» — мэшап, другая запись, а не «Numb».
  static double _titleSimilarity(ParsedTrack q, ParsedTrack c) {
    var best = 0.0;
    for (final a in q.titles) {
      final s = textSimilarity(a, c.title);
      if (s > best) best = s;
    }
    return best;
  }
}
