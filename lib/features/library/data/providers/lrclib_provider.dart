import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../domain/lyrics_models.dart';
import '../lyrics_provider.dart';

class LrcLibProvider implements LyricsProvider {
  LrcLibProvider()
    : _dio = Dio(
        BaseOptions(
          baseUrl: 'https://lrclib.net/api',
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

  final Dio _dio;

  // Признак Enhanced LRC — теги слов <mm:ss.xx>
  static final _enhancedTag = RegExp(r'<\d{2}:\d{2}\.\d{2,3}>');

  @override
  String get name => 'lrclib.net';

  @override
  Future<List<LyricsMetadata>> search(String query) async {
    try {
      final response = await _dio.get('/search', queryParameters: {'q': query});

      if (response.statusCode != 200 || response.data is! List) return [];

      final results = <LyricsMetadata>[];

      for (final item in response.data as List) {
        if (item is! Map<String, dynamic>) continue;

        final id = item['id']?.toString() ?? '';
        final trackName = item['trackName'] as String? ?? '';
        final artistName = item['artistName'] as String? ?? '';
        final durationS = item['duration'] as num?;
        final synced = item['syncedLyrics'] as String?;
        final plain = item['plainLyrics'] as String?;

        // Определяем контент и тип
        final String? content;
        final LyricsType type;

        if (synced != null && synced.isNotEmpty) {
          content = synced;
          type = _enhancedTag.hasMatch(synced)
              ? LyricsType.enhanced
              : LyricsType.synced;
        } else if (plain != null && plain.isNotEmpty) {
          content = plain;
          type = LyricsType.plain;
        } else {
          continue; // Нет текста — пропускаем
        }

        results.add(
          LyricsMetadata(
            id: '${name}_$id',
            trackName: trackName,
            artistName: artistName,
            durationMs: durationS != null ? (durationS * 1000).round() : null,
            content: content,
            type: type,
            source: name,
          ),
        );
      }

      debugPrint('[$name] "$query" → ${results.length} результатов');
      return results;
    } catch (e) {
      debugPrint('[$name] Ошибка при запросе "$query": $e');
      return [];
    }
  }
}
