// lib/features/library/data/providers/kugou_provider.dart
//
// Kugou (lyrics.kugou.com) — тексты KRC с таймингами слов. Сильнее всего на
// западной и китайской музыке; русских песен в проверке 2026-09-12 не нашлось.
//   /search   — кандидаты по строке «артист - название» и длительности;
//   /download — текст KRC (kugou_krc.dart расшифровывает и переводит в YRC).
// Ищет только по полям: «The Weeknd Starboy» и «Starboy» дают 0 кандидатов,
// «The Weeknd - Starboy» — 10 (проверено 2026-09-12).
// Текст скачивается только для правдоподобных кандидатов (не больше двух).
// Неофициальный API — та же серая зона, что у NetEase.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../domain/lyrics_models.dart';
import '../lyrics_provider.dart';
import 'kugou_krc.dart';

class KugouProvider implements LyricsProvider {
  KugouProvider()
      : _dio = Dio(BaseOptions(
          baseUrl: 'https://lyrics.kugou.com',
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 10),
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          },
        ));

  final Dio _dio;

  // Для скольких кандидатов скачивать текст и с какого правдоподобия
  static const int _kMaxDownloads = 2;
  static const double _kMinRelevance = 0.45;

  @override
  String get name => 'kugou';

  @override
  Set<LyricsSearchMode> get modes => const {LyricsSearchMode.fielded};

  @override
  Future<List<LyricsMetadata>> search(LyricsSearchRequest request) async {
    final title = request.title;
    final artist = request.artist;
    if (request.mode != LyricsSearchMode.fielded ||
        title == null ||
        title.isEmpty ||
        artist == null ||
        artist.isEmpty) {
      return [];
    }
    final keyword = '$artist - $title';
    try {
      final resp = await _dio.get('/search', queryParameters: {
        'ver': 1,
        'man': 'yes',
        'client': 'pc',
        'keyword': keyword,
        if (request.durationMs != null) 'duration': request.durationMs,
        'hash': '',
      });
      final data = _json(resp.data);
      final candidates = data is Map ? data['candidates'] as List? : null;
      if (candidates == null || candidates.isEmpty) return [];

      final relevance = request.relevance;
      final picked = <({Map candidate, double score})>[];
      final seen = <String>{};
      for (final c in candidates) {
        if (c is! Map) continue;
        final song = c['song'] as String? ?? '';
        final singer = c['singer'] as String? ?? '';
        final durationMs = (c['duration'] as num?)?.toInt();
        // Одна и та же запись часто лежит под разными id — качаем одну копию,
        // а место отдаём другой версии (например, с подходящей длительностью).
        if (!seen.add('$singer|$song|${(durationMs ?? 0) ~/ 1000}')) continue;
        final score =
            relevance == null ? 1.0 : relevance(song, singer, durationMs);
        if (score >= _kMinRelevance) picked.add((candidate: c, score: score));
      }
      picked.sort((a, b) => b.score.compareTo(a.score));

      debugPrint('[$name] "$keyword" → ${candidates.length} кандидатов, '
          'правдоподобных ${picked.length}');

      final results = await Future.wait(
          picked.take(_kMaxDownloads).map((p) => _download(p.candidate)));
      return results.whereType<LyricsMetadata>().toList();
    } catch (e) {
      debugPrint('[$name] Ошибка при поиске "$keyword": $e');
      return [];
    }
  }

  Future<LyricsMetadata?> _download(Map candidate) async {
    try {
      final id = candidate['id']?.toString();
      final accessKey = candidate['accesskey']?.toString();
      if (id == null || id.isEmpty || accessKey == null) return null;

      final resp = await _dio.get('/download', queryParameters: {
        'ver': 1,
        'client': 'pc',
        'id': id,
        'accesskey': accessKey,
        'fmt': 'krc',
        'charset': 'utf8',
      });
      final data = _json(resp.data);
      final content = data is Map ? data['content'] as String? : null;
      if (content == null || content.isEmpty) return null;

      final yrc = KugouKrc.toYrc(KugouKrc.decrypt(content));
      if (yrc.trim().isEmpty) return null;

      return LyricsMetadata(
        id: '${name}_$id',
        trackName: candidate['song'] as String? ?? '',
        artistName: candidate['singer'] as String? ?? '',
        durationMs: (candidate['duration'] as num?)?.toInt(),
        content: yrc,
        type: LyricsType.syllable,
        source: name,
      );
    } catch (e) {
      debugPrint('[$name] Ошибка получения текста: $e');
      return null;
    }
  }

  /// Ответ может прийти строкой, если сервер не пометит его как JSON.
  static dynamic _json(dynamic data) =>
      data is String ? jsonDecode(data) : data;
}
