// lib/core/services/invidious_proxy_service.dart
//
// Singleton-сервис для работы с публичными инстансами Invidious.
// Используется из search_provider, importer_service и track_model.
//
// Функции:
//  • Ротация и проверка инстансов
//  • Построение URL стрима: /latest_version?id=<id>&itag=140&local=true
//    (itag 140 = AAC 128kbps — чистый аудио без DRM и IP-локов)
//  • Поиск через API: /api/v1/search
//  • Метаданные видео: /api/v1/videos/<id>

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// ── Публичные инстансы Invidious ──────────────────────────────────────────────

const List<String> kInvidiousInstances = [
  'yewtu.be',
  'invidious.privacydev.net',
  'inv.nadeko.net',
  'invidious.fdn.fr',
];

// ── Фразы «слом 4-й стены» при активации прокси ──────────────────────────────

const List<String> kProxyBypassPhrases = [
  'Твоё правительство не хочет, чтобы ты это слушал. Но мне плевать.',
  'Ищу обходной путь в цифровых катакомбах...',
  'Обхожу блокировки. Пристегни ремни.',
  'Ютуб сопротивляется. Подключаю подпольные прокси...',
  'Сигнал перехвачен. Переключаюсь на защищённый канал...',
  'Цифровое подполье принимает запрос. Ожидай.',
  'Они блокируют музыку. Мы — нет.',
  'Прокладываю тоннель сквозь файрвол...',
];

// ── Модель результата поиска Invidious ────────────────────────────────────────

class InvidiousSearchResult {
  final String videoId;
  final String title;
  final String author;
  final String thumbnailUrl;
  final String highResThumbnailUrl;
  final Duration duration;

  const InvidiousSearchResult({
    required this.videoId,
    required this.title,
    required this.author,
    required this.thumbnailUrl,
    required this.highResThumbnailUrl,
    required this.duration,
  });

  factory InvidiousSearchResult.fromJson(Map<String, dynamic> json) {
    final thumbnails = json['videoThumbnails'] as List? ?? [];
    String thumb = '';
    String highRes = '';
    if (thumbnails.isNotEmpty) {
      thumb = (thumbnails.last['url'] as String? ?? '')
          .replaceFirst('http://', 'https://');
      highRes = (thumbnails.first['url'] as String? ?? '')
          .replaceFirst('http://', 'https://');
    }

    return InvidiousSearchResult(
      videoId: json['videoId'] as String? ?? '',
      title: json['title'] as String? ?? 'Unknown',
      author: json['author'] as String? ?? 'Unknown',
      thumbnailUrl: thumb,
      highResThumbnailUrl: highRes.isNotEmpty ? highRes : thumb,
      duration: Duration(seconds: json['lengthSeconds'] as int? ?? 0),
    );
  }
}

// ── Singleton-сервис ──────────────────────────────────────────────────────────

class InvidiousProxyService {
  InvidiousProxyService._();
  static final InvidiousProxyService instance = InvidiousProxyService._();

  String? _workingInstance;
  DateTime? _lastCheck;
  static const _cacheDuration = Duration(minutes: 30);

  String? get workingInstance => _workingInstance;

  // ── Построение URL стрима ─────────────────────────────────────────────────

  /// Возвращает URL аудио-потока через Invidious для [videoId].
  /// itag=140 — AAC 128kbps, работает без IP-лока и googlevideo-подписи.
  String buildStreamUrl(String videoId) {
    final inst = _workingInstance ?? kInvidiousInstances.first;
    return 'https://$inst/latest_version?id=$videoId&itag=140&local=true';
  }

  // ── Поиск рабочего инстанса ───────────────────────────────────────────────

  /// Находит первый доступный инстанс и кэширует его.
  Future<String?> findWorkingInstance() async {
    if (_workingInstance != null && _lastCheck != null) {
      if (DateTime.now().difference(_lastCheck!) < _cacheDuration) {
        return _workingInstance;
      }
    }

    for (final inst in kInvidiousInstances) {
      if (await _ping(inst)) {
        _workingInstance = inst;
        _lastCheck = DateTime.now();
        debugPrint('[Invidious] Рабочий инстанс: $inst');
        return inst;
      }
    }

    debugPrint('[Invidious] Все инстансы недоступны');
    _workingInstance = null;
    return null;
  }

  Future<bool> _ping(String instance) async {
    try {
      final uri = Uri.parse(
          'https://$instance/api/v1/search?q=test&type=video');
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Поиск видео ───────────────────────────────────────────────────────────

  Future<List<InvidiousSearchResult>> searchVideos(String query) async {
    final inst = await findWorkingInstance();
    if (inst == null) throw Exception('Нет доступных Invidious инстансов');

    final uri = Uri.parse(
        'https://$inst/api/v1/search?q=${Uri.encodeComponent(query)}&type=video');
    final resp = await http.get(uri).timeout(const Duration(seconds: 12));

    if (resp.statusCode != 200) {
      throw Exception('Invidious вернул ${resp.statusCode}');
    }

    final List<dynamic> data = jsonDecode(resp.body);
    return data
        .where((r) => r['type'] == 'video')
        .take(20)
        .map((r) => InvidiousSearchResult.fromJson(r as Map<String, dynamic>))
        .where((r) => r.videoId.isNotEmpty)
        .toList();
  }

  // ── Метаданные видео ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getVideoInfo(String videoId) async {
    final inst = await findWorkingInstance();
    if (inst == null) return null;

    try {
      final uri = Uri.parse('https://$inst/api/v1/videos/$videoId');
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[Invidious] getVideoInfo($videoId): $e');
    }
    return null;
  }

  // ── Утилиты ───────────────────────────────────────────────────────────────

  static String randomPhrase() {
    final rnd = Random();
    return kProxyBypassPhrases[rnd.nextInt(kProxyBypassPhrases.length)];
  }
}
