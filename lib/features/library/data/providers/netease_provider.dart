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
//   • Retry с exponential backoff при 429/503

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

  // Максимальное количество треков для параллельного запроса текстов
  static const int _kMaxSongs = 5;

  // Retry при ошибках 429 / 503
  static const int _kMaxRetries = 2;
  static const int _kRetryDelayMs = 600;

  @override
  String get name => 'netease';

  // ── Поиск ─────────────────────────────────────────────────────────────────

  @override
  Future<List<LyricsMetadata>> search(String query) async {
    try {
      debugPrint('[$name] Поиск: "$query"');

      // Используем v1 эндпоинт (более стабильный)
      final searchResp = await _dio.post(
        '/v1/search/get',
        data: {
          's': query,
          'type': 1, // 1 = треки
          'limit': _kMaxSongs,
          'offset': 0,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
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

      debugPrint(
        '[$name] "$query" → ${songs.length} треков, запрашиваем тексты...',
      );

      // Параллельные запросы текстов
      final futures = songs
          .take(_kMaxSongs)
          .map((song) => _fetchLyricWithRetry(song))
          .toList();

      final results = await Future.wait(futures);
      final valid = results.whereType<LyricsMetadata>().toList();

      debugPrint('[$name] Успешно получено текстов: ${valid.length}');
      return valid;
    } on DioException catch (e) {
      debugPrint('[$name] DioError при поиске "$query": ${e.message}');
      return [];
    } catch (e) {
      debugPrint('[$name] Ошибка при поиске "$query": $e');
      return [];
    }
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
      if (result != null) return result;
    }
    return null;
  }

  Future<LyricsMetadata?> _fetchLyric(dynamic song) async {
    try {
      final id = song['id']?.toString() ?? '';
      final trackName = song['name'] as String? ?? '';
      final durationMs = song['duration'] as int?;

      final artists = song['artists'] as List?;
      final artistName =
          (artists?.isNotEmpty == true
              ? artists!.first['name'] as String?
              : null) ??
          '';

      if (id.isEmpty) return null;

      debugPrint(
        '[$name] Запрашиваем текст: "$artistName — $trackName" (id=$id)',
      );

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
      if (data is! Map) return null;

      // ── 1. YRC (послоговой) — наивысший приоритет ──────────────────────
      final yrcContent = data['yrc']?['lyric'] as String?;
      if (yrcContent != null && yrcContent.trim().isNotEmpty) {
        debugPrint(
          '[$name] ★ YRC (СЛОГИ) найден для "$trackName" '
          '(${yrcContent.length} байт)',
        );
        return LyricsMetadata(
          id: '${name}_$id',
          trackName: trackName,
          artistName: artistName,
          durationMs: durationMs,
          content: yrcContent,
          type: LyricsType.syllable,
          source: name,
        );
      }

      // ── 2. Обычный LRC — фоллбэк ───────────────────────────────────────
      final lrcContent = data['lrc']?['lyric'] as String?;
      if (lrcContent != null && lrcContent.trim().isNotEmpty) {
        final isEnhanced = RegExp(
          r'<\d{1,2}:\d{2}\.\d{2,3}>',
        ).hasMatch(lrcContent);

        final type = isEnhanced ? LyricsType.enhanced : LyricsType.synced;
        debugPrint(
          '[$name] ${isEnhanced ? "Enhanced" : "Synced"} LRC '
          'для "$trackName"',
        );

        return LyricsMetadata(
          id: '${name}_$id',
          trackName: trackName,
          artistName: artistName,
          durationMs: durationMs,
          content: lrcContent,
          type: type,
          source: name,
        );
      }

      // ── 3. KRC (если вдруг нет ни YRC ни LRC) ─────────────────────────
      final krcContent = data['krc']?['lyric'] as String?;
      if (krcContent != null && krcContent.trim().isNotEmpty) {
        debugPrint('[$name] KRC найден для "$trackName"');
        return LyricsMetadata(
          id: '${name}_$id',
          trackName: trackName,
          artistName: artistName,
          durationMs: durationMs,
          content: krcContent,
          type: LyricsType.synced,
          source: name,
        );
      }

      debugPrint('[$name] Текст отсутствует для "$trackName" (id=$id)');
      return null;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      debugPrint(
        '[$name] DioError получения текста: HTTP $status ${e.message}',
      );
      // 429 Too Many Requests — сигнал для retry
      if (status == 429 || status == 503) return null;
      return null;
    } catch (e) {
      debugPrint('[$name] Ошибка получения текста: $e');
      return null;
    }
  }
}
