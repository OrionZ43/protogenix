// lib/features/library/data/providers/lrclib_provider.dart
//
// LRCLIB (lrclib.net) — открытая база синхронизированных текстов.
//   exact   — /api/get: лучшее совпадение по названию, артисту и длительности;
//   fielded — /api/search?track_name=&artist_name=;
//   text    — /api/search?q=.
// При перегрузке сервер отвечает 503 (замер 2026-09-12) — один повтор.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../domain/lyrics_models.dart';
import '../lyrics_provider.dart';

class LrcLibProvider implements LyricsProvider {
  LrcLibProvider()
      : _dio = Dio(BaseOptions(
          baseUrl: 'https://lrclib.net/api',
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 12),
          headers: const {
            'User-Agent': 'Protogenix (https://github.com/OrionZ43/protogenix)',
          },
        ));

  final Dio _dio;

  // Признак Enhanced LRC — теги слов <mm:ss.xx>
  static final _enhancedTag = RegExp(r'<\d{2}:\d{2}\.\d{2,3}>');

  @override
  String get name => 'lrclib.net';

  @override
  Set<LyricsSearchMode> get modes => const {
        LyricsSearchMode.exact,
        LyricsSearchMode.fielded,
        LyricsSearchMode.text,
      };

  @override
  Future<List<LyricsMetadata>> search(LyricsSearchRequest request) async {
    try {
      final title = request.title;
      final artist = request.artist;
      final durationMs = request.durationMs;

      if (request.mode == LyricsSearchMode.exact) {
        if (title == null || artist == null || durationMs == null) return [];
        final data = await _get('/get', {
          'track_name': title,
          'artist_name': artist,
          'duration': (durationMs / 1000).round(),
        });
        final item = data is Map<String, dynamic> ? _toMetadata(data) : null;
        return item == null ? [] : [item];
      }

      if (request.mode == LyricsSearchMode.fielded) {
        if (title == null) return [];
        return _list(await _get('/search', {
          'track_name': title,
          if (artist != null) 'artist_name': artist,
        }));
      }

      if (request.query.isEmpty) return [];
      return _list(await _get('/search', {'q': request.query}));
    } catch (e) {
      debugPrint('[$name] Ошибка (${request.mode.name}): $e');
      return [];
    }
  }

  /// GET с одним повтором на 503/429; 404 — «не найдено», возвращает null.
  Future<dynamic> _get(String path, Map<String, dynamic> query) async {
    for (var attempt = 0;; attempt++) {
      try {
        final response = await _dio.get(path, queryParameters: query);
        return response.data;
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status == 404) return null;
        if ((status == 503 || status == 429) && attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 800));
          continue;
        }
        rethrow;
      }
    }
  }

  List<LyricsMetadata> _list(dynamic data) {
    if (data is! List) return [];
    final result = <LyricsMetadata>[];
    for (final item in data) {
      if (item is! Map<String, dynamic>) continue;
      final meta = _toMetadata(item);
      if (meta != null) result.add(meta);
    }
    return result;
  }

  LyricsMetadata? _toMetadata(Map<String, dynamic> item) {
    if (item['instrumental'] == true) return null;
    final synced = item['syncedLyrics'] as String?;
    final plain = item['plainLyrics'] as String?;

    final String content;
    final LyricsType type;
    if (synced != null && synced.trim().isNotEmpty) {
      content = synced;
      type = _enhancedTag.hasMatch(synced)
          ? LyricsType.enhanced
          : LyricsType.synced;
    } else if (plain != null && plain.trim().isNotEmpty) {
      content = plain;
      type = LyricsType.plain;
    } else {
      return null; // Нет текста — пропускаем
    }

    final durationS = item['duration'] as num?;
    return LyricsMetadata(
      id: '${name}_${item['id']}',
      trackName: item['trackName'] as String? ?? '',
      artistName: item['artistName'] as String? ?? '',
      durationMs: durationS != null ? (durationS * 1000).round() : null,
      content: content,
      type: type,
      source: name,
    );
  }
}
