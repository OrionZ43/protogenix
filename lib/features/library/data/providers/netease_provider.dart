// lib/features/library/data/providers/netease_provider.dart
//
// Провайдер текстов песен от NetEase (music.163.com)
//
// Особенности:
//   • ТОЛЬКО HTTPS — HTTP блокируется Android 9+ cleartext policy
//   • POST /api/v1/search/get — v1 эндпоинт, более стабильный (обход ошибки -460)
//   • Эмуляция Linux-клиента (User-Agent + Cookie)
//   • Подмена X-Real-IP на случайный китайский IP для обхода блокировок
//   • yv=1 — принудительно запрашивает YRC (послоговой формат)
//   • Приоритет: YRC (syllable) > LRC (synced) > plain
//   • Текст скачивается только для правдоподобных песен из выдачи
//     (LyricsSearchRequest.relevance), не больше трёх на запрос
//   • Повтор — только на 429/503: песню без текста повторно не запрашиваем

import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../domain/lyrics_models.dart';
import '../lyrics_provider.dart';

class NetEaseProvider implements LyricsProvider {
  NetEaseProvider() {
    _dio = Dio(
      BaseOptions(
        baseUrl: 'https://music.163.com/api',
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          // Заголовки Linux-версии (обход -460)
          'User-Agent':
              'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/60.0.3112.90 Safari/537.36',
          'Referer': 'https://music.163.com/',
          'Origin': 'https://music.163.com',
          'Accept': 'application/json, text/plain, */*',
          'Accept-Language': 'en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7',
          // Куки для эмуляции Linux-клиента
          'Cookie': 'os=linux; appver=2.0.2; osver=Ubuntu; __remember_me=true',
        },
      ),
    );

    // Добавляем Interceptor для генерации случайного китайского IP при каждом запросе
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // Подсеть 211.161.244.0/24 (Часто используется в опенсорс плеерах для NetEase)
          final randomIp = '211.161.244.${Random().nextInt(254) + 1}';
          options.headers['X-Real-IP'] = randomIp;
          // Иногда NetEase также проверяет X-Forwarded-For
          options.headers['X-Forwarded-For'] = randomIp;

          return handler.next(options);
        },
      ),
    );
  }

  late final Dio _dio;

  // Сколько песен просить в выдаче и для скольких скачивать текст
  static const int _kSearchLimit = 8;
  static const int _kMaxLyricFetches = 3;

  // Ниже этого правдоподобия (LyricsMatcher.relevance) текст не скачиваем
  static const double _kMinRelevance = 0.45;

  // Retry при ошибках 429 / 503
  static const int _kMaxRetries = 2;
  static const int _kRetryDelayMs = 600;

  @override
  String get name => 'netease';

  @override
  Set<LyricsSearchMode> get modes => const {LyricsSearchMode.text};

  // ── Поиск ─────────────────────────────────────────────────────────────────

  @override
  Future<List<LyricsMetadata>> search(LyricsSearchRequest request) async {
    final query = request.query;
    if (request.mode != LyricsSearchMode.text || query.isEmpty) return [];
    try {
      debugPrint('[$name] Поиск: "$query"');

      // Используем v1 эндпоинт (более стабильный)
      final searchResp = await _dio.post(
        '/v1/search/get',
        data: {
          's': query,
          'type': 1, // 1 = треки
          'limit': _kSearchLimit,
          'offset': 0,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      final searchData = searchResp.data;
      if (searchData is! Map) {
        debugPrint('[$name] Неожиданный тип ответа: ${searchData.runtimeType}');
        return [];
      }

      final code = searchData['code'];
      if (code != 200) {
        debugPrint('[$name] API вернул код $code для "$query"');
        return [];
      }

      final songs = (searchData['result']?['songs'] as List?) ?? [];
      if (songs.isEmpty) {
        debugPrint('[$name] "$query" → 0 треков');
        return [];
      }

      // Текст тянем только для правдоподобных песен: раньше скачивались все
      // пять из выдачи, в том числе явно чужие.
      final relevance = request.relevance;
      final picked = <({dynamic song, double score})>[];
      for (final song in songs) {
        if (song is! Map) continue;
        final score = relevance == null
            ? 1.0
            : relevance(
                song['name'] as String? ?? '',
                _artistNames(song),
                song['duration'] as int?,
              );
        if (score >= _kMinRelevance) picked.add((song: song, score: score));
      }
      picked.sort((a, b) => b.score.compareTo(a.score));

      debugPrint('[$name] "$query" → ${songs.length} треков, '
          'правдоподобных ${picked.length}');

      final results = await Future.wait(
          picked.take(_kMaxLyricFetches).map((p) => _fetchLyricWithRetry(p.song)));
      return results.whereType<LyricsMetadata>().toList();
    } on DioException catch (e) {
      debugPrint('[$name] DioError при поиске "$query": ${e.message}');
      return [];
    } catch (e) {
      debugPrint('[$name] Ошибка при поиске "$query": $e');
      return [];
    }
  }

  /// Все артисты песни через запятую — у совместных треков первым может
  /// оказаться не тот, кто записан у нас.
  static String _artistNames(Map song) {
    final artists = song['artists'] as List?;
    if (artists == null) return '';
    return artists
        .map((a) => a is Map ? a['name'] as String? ?? '' : '')
        .where((n) => n.isNotEmpty)
        .join(', ');
  }

  // ── Получение текста с retry ───────────────────────────────────────────────

  Future<LyricsMetadata?> _fetchLyricWithRetry(dynamic song) async {
    for (var attempt = 0; attempt <= _kMaxRetries; attempt++) {
      if (attempt > 0) {
        final delay = _kRetryDelayMs * attempt;
        debugPrint('[$name] Retry #$attempt через ${delay}ms...');
        await Future.delayed(Duration(milliseconds: delay));
      }
      final result = await _fetchLyric(song);
      if (!result.retry) return result.lyric;
    }
    return null;
  }

  Future<({LyricsMetadata? lyric, bool retry})> _fetchLyric(dynamic song) async {
    try {
      final id = song['id']?.toString() ?? '';
      final trackName = song['name'] as String? ?? '';
      final durationMs = song['duration'] as int?;
      final artistName = song is Map ? _artistNames(song) : '';

      if (id.isEmpty) return (lyric: null, retry: false);

      debugPrint(
          '[$name] Запрашиваем текст: "$artistName — $trackName" (id=$id)');

      final lyricResp = await _dio.get(
        '/song/lyric',
        queryParameters: {
          'id': id,
          'lv': 1, // LRC построчный
          'tv': -1, // Перевод (отключаем)
          'kv': 1, // KRC (построчный, резервный)
          // ✅ КРИТИЧНО: yv=1 — запрашивает YRC (послоговой формат NetEase)
          'yv': 1,
        },
      );

      final data = lyricResp.data;
      if (data is! Map) return (lyric: null, retry: false);

      LyricsMetadata make(String content, LyricsType type) => LyricsMetadata(
            id: '${name}_$id',
            trackName: trackName,
            artistName: artistName,
            durationMs: durationMs,
            content: content,
            type: type,
            source: name,
          );

      // ── 1. YRC (послоговой) — наивысший приоритет ──────────────────────
      final yrcContent = data['yrc']?['lyric'] as String?;
      if (yrcContent != null && yrcContent.trim().isNotEmpty) {
        debugPrint('[$name] ★ YRC (СЛОГИ) найден для "$trackName"');
        return (lyric: make(yrcContent, LyricsType.syllable), retry: false);
      }

      // ── 2. Обычный LRC — фоллбэк ───────────────────────────────────────
      final lrcContent = data['lrc']?['lyric'] as String?;
      if (lrcContent != null && lrcContent.trim().isNotEmpty) {
        final isEnhanced =
            RegExp(r'<\d{1,2}:\d{2}\.\d{2,3}>').hasMatch(lrcContent);
        return (
          lyric: make(lrcContent,
              isEnhanced ? LyricsType.enhanced : LyricsType.synced),
          retry: false,
        );
      }

      // ── 3. KRC (если вдруг нет ни YRC ни LRC) ─────────────────────────
      final krcContent = data['krc']?['lyric'] as String?;
      if (krcContent != null && krcContent.trim().isNotEmpty) {
        return (lyric: make(krcContent, LyricsType.synced), retry: false);
      }

      debugPrint('[$name] Текст отсутствует для "$trackName" (id=$id)');
      return (lyric: null, retry: false);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      debugPrint(
          '[$name] DioError получения текста: HTTP $status ${e.message}');
      // 429 Too Many Requests / 503 — повторяем, остальное — нет
      return (lyric: null, retry: status == 429 || status == 503);
    } catch (e) {
      debugPrint('[$name] Ошибка получения текста: $e');
      return (lyric: null, retry: false);
    }
  }
}
