import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:string_similarity/string_similarity.dart';
import '../domain/lyrics_models.dart';
import '../domain/lyrics_query_builder.dart';
import 'lyrics_provider.dart';
import 'providers/lrclib_provider.dart';
import 'providers/netease_provider.dart';

class LyricsService {
  LyricsService._() {
    // Регистрируем провайдеры по умолчанию
    _providers = [
      LrcLibProvider(),
      NetEaseProvider(),
    ];
  }

  static final LyricsService instance = LyricsService._();

  late final List<LyricsProvider> _providers;
  final _queryBuilder = LyricsQueryBuilder();

  // ══════════════════════════════════════════════════════════════════════════
  // ПУБЛИЧНЫЙ API
  // ══════════════════════════════════════════════════════════════════════════

  /// Основной метод поиска.
  /// Возвращает топ-10 результатов, отсортированных по score.
  Future<List<ScoredLyric>> fetchLyrics({
    required String title,
    required String artist,
    String? filePath,
    int?    trackDurationMs,
  }) async {
    debugPrint('\n╔══════════════════════════════════════════════════');
    debugPrint('║ LyricsService.fetchLyrics');
    debugPrint('║ title:    "$title"');
    debugPrint('║ artist:   "$artist"');
    debugPrint('║ duration: ${trackDurationMs != null ? "${trackDurationMs}ms" : "—"}');
    debugPrint('╚══════════════════════════════════════════════════');

    // 1. Проверяем локальный файл
    if (filePath != null) {
      final local = _readLocalLrc(filePath);
      if (local != null) {
        debugPrint('[LyricsService] ✓ Локальный .lrc файл');
        final meta = LyricsMetadata(
          id:         'local_${filePath.hashCode}',
          trackName:  title,
          artistName: artist,
          content:    local,
          type:       _classifyContent(local),
          source:     'local',
        );
        return [ScoredLyric(metadata: meta, score: 100.0)];
      }
    }

    // 2. Генерируем поисковые запросы
    final queries = _queryBuilder.build(title, artist);
    debugPrint('[LyricsService] Запросов: ${queries.length}');
    for (var i = 0; i < queries.length; i++) {
      debugPrint('[LyricsService]   ${i + 1}. "${queries[i]}"');
    }

    // 3. Параллельный поиск по всем провайдерам и запросам
    final allFutures = <Future<List<LyricsMetadata>>>[];

    for (final provider in _providers) {
      for (final query in queries) {
        allFutures.add(provider.search(query));
      }
    }

    debugPrint(
      '[LyricsService] Параллельных запросов: '
          '${_providers.length} провайдера × ${queries.length} запросов '
          '= ${allFutures.length}',
    );

    final allLists = await Future.wait(allFutures);

    // 4. Собираем и дедуплицируем результаты
    final seen    = <String>{};
    final unique  = <LyricsMetadata>[];

    for (final list in allLists) {
      for (final meta in list) {
        // Дедупликация по id провайдера
        if (seen.add(meta.id)) {
          unique.add(meta);
        }
      }
    }

    debugPrint('[LyricsService] Уникальных результатов: ${unique.length}');

    if (unique.isEmpty) {
      debugPrint('[LyricsService] ✗ Ничего не найдено');
      return [];
    }

    // 5. Scoring
    final scored = unique.map((meta) {
      final score = _calculateScore(
        meta:            meta,
        originalTitle:   title,
        originalArtist:  artist,
        trackDurationMs: trackDurationMs,
      );
      return ScoredLyric(metadata: meta, score: score);
    }).toList();

    // Сортируем по убыванию
    scored.sort((a, b) => b.score.compareTo(a.score));

    // Берём топ-10
    final top10 = scored.take(10).toList();

    debugPrint('\n[LyricsService] ══ ТОП-10 ══');
    for (var i = 0; i < top10.length; i++) {
      final s = top10[i];
      debugPrint(
        '[LyricsService] #${i + 1} '
            '"${s.metadata.artistName} — ${s.metadata.trackName}" '
            '| ${s.metadata.type} | ${s.metadata.source} '
            '| score=${s.scoreLabel}',
      );
    }

    return top10;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SCORING ENGINE
  // ══════════════════════════════════════════════════════════════════════════

  double _calculateScore({
    required LyricsMetadata meta,
    required String         originalTitle,
    required String         originalArtist,
    int?                    trackDurationMs,
  }) {
    double score = 0.0;

    // Нормализуем для сравнения
    final normTitle   = _normalize(originalTitle);
    final normArtist  = _normalize(originalArtist);
    final normMTitle  = _normalize(meta.trackName);
    final normMArtist = _normalize(meta.artistName);

    // ── Схожесть названия: до +40 баллов ─────────────────────────────────
    final titleSim = normTitle.isNotEmpty && normMTitle.isNotEmpty
        ? normTitle.similarityTo(normMTitle)
        : 0.0;
    score += titleSim * 40.0;

    // ── Схожесть артиста: до +20 баллов ──────────────────────────────────
    final artistSim = normArtist.isNotEmpty && normMArtist.isNotEmpty
        ? normArtist.similarityTo(normMArtist)
        : 0.0;
    score += artistSim * 20.0;

    // ── Бонус за длительность: до +15 баллов ─────────────────────────────
    if (trackDurationMs != null && meta.durationMs != null) {
      final diffMs  = (trackDurationMs - meta.durationMs!).abs();
      final diffSec = diffMs / 1000.0;

      if (diffSec < 3.0) {
        score += 15.0;
        debugPrint(
          '[SCORE] "${meta.trackName}" +15.0 (длит. совпадает, '
              'diff=${diffSec.toStringAsFixed(1)}s)',
        );
      } else if (diffSec < 10.0) {
        score += 5.0;
      } else if (diffSec > 60.0) {
        // Сильный штраф — явно другой трек
        score -= 10.0;
        debugPrint(
          '[SCORE] "${meta.trackName}" -10.0 '
              '(длит. сильно отличается, diff=${diffSec.toStringAsFixed(0)}s)',
        );
      }
    }

    // ── Бонус за формат ───────────────────────────────────────────────────
    final formatBonus = switch (meta.type) {
      LyricsType.syllable => 60.0,
      LyricsType.enhanced => 45.0,
      LyricsType.synced   => 25.0,
      LyricsType.plain    =>  5.0,
    };
    score += formatBonus;

    debugPrint(
      '[SCORE] "${meta.artistName} — ${meta.trackName}" '
          '| title=${(titleSim * 40).toStringAsFixed(1)} '
          'artist=${(artistSim * 20).toStringAsFixed(1)} '
          'format=$formatBonus '
          '| TOTAL=${score.toStringAsFixed(1)} [${meta.type}] [${meta.source}]',
    );

    return score;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ
  // ══════════════════════════════════════════════════════════════════════════

  /// Нормализует строку для сравнения:
  /// приводит к нижнему регистру, убирает скобки и лишние пробелы
  String _normalize(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]'), '')
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  /// Определяет тип текста по содержимому
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

  /// Читает .lrc файл рядом с аудиофайлом
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
    final dir  = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'lyrics', '$trackId.lrc'));
    await file.parent.create(recursive: true);
    await file.writeAsString(lrcContent);
    return file.path;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ОБРАТНАЯ СОВМЕСТИМОСТЬ
  // ══════════════════════════════════════════════════════════════════════════

  /// Упрощённый метод — возвращает только лучший контент или null.
  /// Используется старым кодом.
  Future<String?> getLrc({
    required String filePath,
    required String title,
    required String artist,
    int? trackDurationMs,
  }) async {
    final results = await fetchLyrics(
      title:           title,
      artist:          artist,
      filePath:        filePath,
      trackDurationMs: trackDurationMs,
    );
    return results.isEmpty ? null : results.first.metadata.content;
  }
}