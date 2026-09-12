// lib/features/library/data/lyrics_service.dart
//
// Поиск текстов: запросы к источникам (LRCLIB, NetEase, Kugou) по
// разобранному названию трека (track_query.dart), выбор — lyrics_matcher.dart.
// Два этапа: сначала точные запросы по основному прочтению; если среди
// найденного нет той же песни с совпавшей длительностью и таймингами —
// более широкие. Правила и замер — .claude/rules/lyrics.md.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../../core/services/app_paths.dart';
import '../../player/domain/lyrics_timing.dart';
import '../domain/lyrics_matcher.dart';
import '../domain/lyrics_models.dart';
import '../domain/lyrics_query_builder.dart';
import 'lyrics_provider.dart';
import 'providers/kugou_provider.dart';
import 'providers/lrclib_provider.dart';
import 'providers/netease_provider.dart';

class LyricsService {
  LyricsService._() {
    _providers = [
      LrcLibProvider(),
      NetEaseProvider(),
      KugouProvider(),
    ];
  }

  static final LyricsService instance = LyricsService._();

  late final List<LyricsProvider> _providers;
  final _queryBuilder = LyricsQueryBuilder();

  static const _requestTimeout = Duration(seconds: 12);
  static const _maxResults = 15;
  static const _maxBroadQueries = 3;
  static const _maxBroadInterpretations = 2;

  // ══════════════════════════════════════════════════════════════════════════
  // ПУБЛИЧНЫЙ API
  // ══════════════════════════════════════════════════════════════════════════

  /// Все найденные варианты по порядку выбора (lyrics_matcher.dart): первыми
  /// идут «та же песня» ([ScoredLyric.isConfident]), дальше — остальные для
  /// ручного выбора.
  Future<List<ScoredLyric>> fetchLyrics({
    required String title,
    required String artist,
    String? filePath,
    int? trackDurationMs,
  }) async {
    // 1. Локальный .lrc рядом с аудиофайлом
    if (filePath != null && filePath.isNotEmpty) {
      final local = _readLocalLrc(filePath);
      if (local != null) {
        debugPrint('[LyricsService] ✓ Локальный .lrc файл');
        final meta = LyricsMetadata(
          id: 'local_${filePath.hashCode}',
          trackName: title,
          artistName: artist,
          content: local,
          type: _classifyContent(local),
          source: 'local',
        );
        return [ScoredLyric(metadata: meta, score: 999.0)];
      }
    }

    final matcher = LyricsMatcher(
      title: title,
      artist: artist,
      durationMs: trackDurationMs,
    );
    final primary = matcher.primary;
    final queries = _queryBuilder.queries(matcher.interpretations);
    debugPrint('[LyricsService] "$title" / "$artist" → $primary, '
        'длительность ${matcher.durationMs ?? '—'} мс');

    final found = <String, LyricsMetadata>{};
    LyricsSearchRequest text(String query) => LyricsSearchRequest(
          mode: LyricsSearchMode.text,
          query: query,
          durationMs: matcher.durationMs,
          relevance: matcher.relevance,
        );
    LyricsSearchRequest fielded(String trackTitle, String? trackArtist) =>
        LyricsSearchRequest(
          mode: LyricsSearchMode.fielded,
          title: trackTitle,
          artist: trackArtist,
          durationMs: matcher.durationMs,
          relevance: matcher.relevance,
        );

    // 2. Точные запросы по основному прочтению
    final mainArtist = primary.artists.isEmpty ? null : primary.artists.first;
    await _run([
      if (mainArtist != null && matcher.durationMs != null)
        LyricsSearchRequest(
          mode: LyricsSearchMode.exact,
          title: primary.title,
          artist: mainArtist,
          durationMs: matcher.durationMs,
        ),
      fielded(primary.title, mainArtist),
      if (queries.isNotEmpty) text(queries.first),
    ], found);
    var ranked = matcher.rank(found.values);

    // 3. Широкие запросы, если точные не дали той же песни с таймингами:
    //    остальные строки свободного поиска и другие прочтения по полям.
    if (!LyricsMatcher.isGoodEnough(LyricsMatcher.best(ranked))) {
      final broad = [
        for (final q in queries.skip(1).take(_maxBroadQueries)) text(q),
        for (final t
            in matcher.interpretations.skip(1).take(_maxBroadInterpretations))
          if (t.artists.isNotEmpty) fielded(t.title, t.artists.first),
      ];
      if (broad.isNotEmpty) {
        await _run(broad, found);
        ranked = matcher.rank(found.values);
      }
    }

    for (final m in ranked.take(5)) {
      debugPrint('[LyricsService] ${m.isSameSong ? '✓' : '·'} '
          '${m.score.toStringAsFixed(0)} ${m.metadata.type.name} '
          '${m.metadata.source} "${m.metadata.artistName} — ${m.metadata.trackName}"'
          '${m.timeScale != 1.0 ? ' ×${m.timeScale.toStringAsFixed(3)}' : ''}'
          '${m.timingsReliable ? '' : ' (тайминги от другой версии)'}');
    }
    if (ranked.isEmpty || !ranked.first.isSameSong) {
      debugPrint('[LyricsService] ✗ Той же песни не найдено');
    }

    return ranked.take(_maxResults).map((m) => m.toScored()).toList();
  }

  /// Лучший вариант для автовыбора или null — «текст не найден».
  Future<ScoredLyric?> findBest({
    required String title,
    required String artist,
    String? filePath,
    int? trackDurationMs,
  }) async {
    final results = await fetchLyrics(
      title: title,
      artist: artist,
      filePath: filePath,
      trackDurationMs: trackDurationMs,
    );
    return results.isNotEmpty && results.first.isConfident
        ? results.first
        : null;
  }

  Future<void> _run(
    List<LyricsSearchRequest> requests,
    Map<String, LyricsMetadata> found,
  ) async {
    final futures = <Future<List<LyricsMetadata>>>[];
    for (final request in requests) {
      for (final provider in _providers) {
        if (!provider.modes.contains(request.mode)) continue;
        futures.add(provider.search(request).timeout(
              _requestTimeout,
              onTimeout: () => const <LyricsMetadata>[],
            ));
      }
    }
    for (final list in await Future.wait(futures)) {
      for (final meta in list) {
        found.putIfAbsent(meta.id, () => meta);
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ
  // ══════════════════════════════════════════════════════════════════════════

  /// Определяет тип текста по содержимому.
  LyricsType _classifyContent(String content) {
    if (RegExp(r'<\d{2}:\d{2}\.\d{2,3}>').hasMatch(content)) {
      return LyricsType.enhanced;
    }
    if (RegExp(r'^\[\d{2}:\d{2}\.\d{2,3}\]', multiLine: true)
        .hasMatch(content)) {
      return LyricsType.synced;
    }
    return LyricsType.plain;
  }

  /// Читает .lrc файл рядом с аудиофайлом.
  String? _readLocalLrc(String filePath) {
    try {
      final lrcFile = File('${p.withoutExtension(filePath)}.lrc');
      if (lrcFile.existsSync()) return lrcFile.readAsStringSync();
    } catch (_) {}
    return null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // СОХРАНЕНИЕ
  // ══════════════════════════════════════════════════════════════════════════

  Future<String> saveLrc(String lrcContent, String trackId) async {
    final file = File(p.join(AppPaths.lyricsDir, '$trackId.lrc'));
    await file.parent.create(recursive: true);
    await file.writeAsString(lrcContent);
    return file.path;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ОБРАТНАЯ СОВМЕСТИМОСТЬ
  // ══════════════════════════════════════════════════════════════════════════

  /// Лучший текст для сохранения при импорте или null. Текст с таймингами от
  /// другой версии не возвращается: закреплённый за треком, он бы уезжал.
  Future<String?> getLrc({
    required String filePath,
    required String title,
    required String artist,
    int? trackDurationMs,
  }) async {
    final best = await findBest(
      title: title,
      artist: artist,
      filePath: filePath,
      trackDurationMs: trackDurationMs,
    );
    if (best == null || !best.timingsReliable) return null;
    return best.metadata.type == LyricsType.plain
        ? best.metadata.content
        : withScaleTag(best.metadata.content, best.timeScale);
  }
}
