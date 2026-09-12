// lib/core/services/youtube_clients.dart
//
// Клиенты YouTube, которыми youtube_explode_dart запрашивает аудио-потоки.
//
// YouTube по-разному защищает свои приложения. С августа 2026 у androidVr и
// ios он требует PO-токен (issues youtube_explode_dart #386, #389): манифест
// приходит, а поток — 403 или «Sign in to confirm you're not a bot». У android
// поток приходит пустым (#379). Клиент Apple Vision Pro (visionOS) на
// 2026-09-12 отдаёт ссылки без токена и без JS-задачек; описание взято из
// неслитых PR #390/#391.
//
// Это обход: YouTube может закрыть и visionOS. Тогда смотреть свежие issues и
// PR библиотеки и .claude/rules/known-issues.md. Проверять на реальных треках,
// а не на одном популярном видео — оно может проходить и через старые клиенты.

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

const kVisionOsClient = YoutubeApiClient({
  'context': {
    'client': {
      'clientName': 'VISIONOS',
      'clientVersion': '1.02',
      'deviceMake': 'Apple',
      'deviceModel': 'RealityDevice17,1',
      'osName': 'visionOS',
      'osVersion': '26.5.23O471',
      'userAgent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
      'hl': 'en',
      'timeZone': 'UTC',
      'utcOffsetMinutes': 0,
    },
  },
}, 'https://www.youtube.com/youtubei/v1/player?prettyPrint=false');

/// Порядок клиентов при скачивании: первым — visionOS, дальше прежние
/// (на части видео они ещё отвечают).
final List<YoutubeApiClient> kYoutubeClientFallbackOrder = [
  kVisionOsClient,
  YoutubeApiClient.androidVr,
  YoutubeApiClient.ios,
  YoutubeApiClient.android,
  YoutubeApiClient.mweb,
];

/// Имя клиента для логов: `VISIONOS`, `ANDROID_VR`, … — вместо
/// «Instance of 'YoutubeApiClient'».
String youtubeClientName(YoutubeApiClient client) {
  final context = client.payload['context'];
  if (context is Map && context['client'] is Map) {
    final name = (context['client'] as Map)['clientName'];
    if (name is String) return name;
  }
  return client.apiUrl;
}
