// lib/features/importer/data/yandex_music.dart
//
// Импорт из Яндекс Музыки: разбор ссылки и список треков через публичный API
// (api.music.yandex.net, без токена). Сами треки потом ищутся и качаются
// с YouTube (importer_service.dart).
//
// Проверено 2026-09-13: адреса сайта music.yandex.ru/handlers/*.jsx, через
// которые импорт работал раньше, Яндекс убрал — 404 «This page is no longer
// available». API без токена отвечает только из «своих» стран: из Беларуси
// без VPN трек отдаётся, через VPN с выходом в Германии — 451 Unavailable For
// Legal Reasons. Со страниц сайта данные не вытащить: он на Next.js,
// и в серверном HTML нет ничего, кроме общего заголовка.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

enum YandexLinkKind { track, album, userPlaylist, playlistUuid }

class YandexLink {
  const YandexLink(this.kind, this.id, {this.owner});

  final YandexLinkKind kind;

  /// id трека или альбома, номер (kind) плейлиста или его uuid.
  final String id;

  /// Логин владельца — для ссылок `users/<логин>/playlists/<номер>`.
  final String? owner;

  static final _host = RegExp(r'^music\.yandex\.[a-z]{2,3}$');
  static final _number = RegExp(r'^\d+$');
  static final _uuid = RegExp(r'^[A-Za-z0-9.\-]+$');

  /// Любой домен Яндекс Музыки: .ru, .by, .kz, .com и другие.
  static bool isYandexMusicHost(String host) =>
      _host.hasMatch(host.toLowerCase());

  /// null — не ссылка Яндекс Музыки или вид, который импорт не понимает
  /// (исполнитель, подкаст, радио).
  static YandexLink? parse(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !isYandexMusicHost(uri.host)) return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    String? after(String name) {
      final i = segments.indexOf(name);
      return i >= 0 && i + 1 < segments.length ? segments[i + 1] : null;
    }

    // album/<a>/track/<t> — ссылка на трек, а не на альбом: раньше импорт
    // принимал её за альбом и качал его целиком
    final track = after('track');
    if (track != null && _number.hasMatch(track)) {
      return YandexLink(YandexLinkKind.track, track);
    }
    final album = after('album');
    if (album != null && _number.hasMatch(album)) {
      return YandexLink(YandexLinkKind.album, album);
    }
    final playlist = after('playlists');
    final owner = after('users');
    if (playlist != null && owner != null && _number.hasMatch(playlist)) {
      return YandexLink(YandexLinkKind.userPlaylist, playlist, owner: owner);
    }
    if (playlist != null && _uuid.hasMatch(playlist)) {
      return YandexLink(YandexLinkKind.playlistUuid, playlist);
    }
    return null;
  }
}

class YandexTrack {
  const YandexTrack({
    required this.title,
    required this.artists,
    this.durationMs,
    this.coverUrl,
    this.album,
  });

  /// Название вместе с версией: «Believer (Remix)».
  final String title;

  /// Все исполнители через запятую; пусто, если Яндекс их не отдал.
  final String artists;
  final int? durationMs;
  final String? coverUrl;
  final String? album;
}

class YandexCollection {
  const YandexCollection({
    required this.title,
    required this.tracks,
    this.isSingleTrack = false,
    this.unavailable = 0,
  });

  final String title;
  final List<YandexTrack> tracks;
  final bool isSingleTrack;

  /// Сколько треков пропущено: в самом Яндексе они недоступны.
  final int unavailable;
}

/// [message] — готовый текст для пользователя; подробности — в логе.
class YandexMusicException implements Exception {
  const YandexMusicException(this.message);
  final String message;

  @override
  String toString() => 'YandexMusicException: $message';
}

class YandexMusicApi {
  YandexMusicApi({Dio? dio, String baseUrl = 'https://api.music.yandex.net'})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
            )),
        _base = baseUrl;

  final Dio _dio;
  final String _base;

  // Двухшагового импорта (список → «Скачать») нет — решение Orion 2026-09-13:
  // достаточно попросить выключить VPN
  static const regionMessage =
      'Яндекс Музыка не открывается через VPN. Выключи VPN на время импорта '
      'и вставь ссылку ещё раз.';

  Future<YandexCollection> fetch(YandexLink link) async {
    switch (link.kind) {
      case YandexLinkKind.track:
        final result = await _get('/tracks/${link.id}');
        final parsed = parseTracks(result is List ? result : const []);
        if (parsed.tracks.isEmpty) {
          throw const YandexMusicException(
              'Этот трек недоступен в Яндекс Музыке');
        }
        final track = parsed.tracks.first;
        return YandexCollection(
          title: track.album ?? track.title,
          tracks: [track],
          isSingleTrack: true,
        );
      case YandexLinkKind.album:
        return parseAlbum(await _get('/albums/${link.id}/with-tracks'));
      case YandexLinkKind.userPlaylist:
        return parsePlaylist(await _get(
            '/users/${Uri.encodeComponent(link.owner!)}/playlists/${link.id}'));
      case YandexLinkKind.playlistUuid:
        return parsePlaylist(
            await _get('/playlist/${Uri.encodeComponent(link.id)}'));
    }
  }

  Future<Object?> _get(String path) async {
    try {
      final response = await _dio.get<Object?>(
        '$_base$path',
        options: Options(
          headers: {'Accept': 'application/json'},
          responseType: ResponseType.json,
        ),
      );
      final data = response.data;
      if (data is Map && data.containsKey('result')) return data['result'];
      debugPrint('[Yandex] $path: ответ без result');
      throw const YandexMusicException(
          'Яндекс Музыка ответила непонятно — попробуй позже');
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      debugPrint('[Yandex] $path: HTTP $code ${e.type.name}');
      throw YandexMusicException(switch (code) {
        451 => regionMessage,
        404 => 'Не нашёл это в Яндекс Музыке — проверь ссылку',
        401 || 403 => 'Этот плейлист закрыт: Яндекс отдаёт его только '
            'владельцу. Сделай его публичным и попробуй ещё раз',
        _ => 'Яндекс Музыка не ответила — проверь интернет или попробуй позже',
      });
    }
  }

  // ── Разбор ответов API (без сети, покрыт тестами) ─────────────────────────

  static YandexCollection parseAlbum(Object? result) {
    if (result is! Map) {
      throw const YandexMusicException('Не удалось прочитать альбом');
    }
    final volumes = result['volumes'];
    final items = <Object?>[
      if (volumes is List)
        for (final volume in volumes)
          if (volume is List) ...volume,
    ];
    final parsed = parseTracks(items);
    return YandexCollection(
      title: _text(result['title']) ?? 'Альбом Яндекс Музыки',
      tracks: parsed.tracks,
      unavailable: parsed.unavailable,
    );
  }

  static YandexCollection parsePlaylist(Object? result) {
    // Старый вид ответа заворачивал плейлист в {"playlist": {…}}
    final playlist =
        result is Map && result['playlist'] is Map ? result['playlist'] : result;
    if (playlist is! Map) {
      throw const YandexMusicException('Не удалось прочитать плейлист');
    }
    final tracks = playlist['tracks'];
    final parsed = parseTracks(tracks is List ? tracks : const []);
    return YandexCollection(
      title: _text(playlist['title']) ?? 'Плейлист Яндекс Музыки',
      tracks: parsed.tracks,
      unavailable: parsed.unavailable,
    );
  }

  /// Элемент списка — сам трек или обёртка `{id, track: {…}}` (в плейлистах).
  static ({List<YandexTrack> tracks, int unavailable}) parseTracks(
      Iterable<Object?> items) {
    final tracks = <YandexTrack>[];
    var unavailable = 0;
    for (final item in items) {
      if (item is! Map) continue;
      final json = item['track'] is Map ? item['track'] as Map : item;
      if (json['available'] == false) {
        unavailable++;
        continue;
      }
      final track = parseTrack(json);
      if (track != null) tracks.add(track);
    }
    return (tracks: tracks, unavailable: unavailable);
  }

  static YandexTrack? parseTrack(Map json) {
    final title = _text(json['title']);
    if (title == null) return null;
    final version = _text(json['version']);
    final artists = json['artists'];
    final albums = json['albums'];
    final firstAlbum =
        albums is List && albums.isNotEmpty && albums.first is Map
            ? albums.first as Map
            : null;
    final duration = json['durationMs'];
    return YandexTrack(
      title: version == null ? title : '$title ($version)',
      artists: [
        if (artists is List)
          for (final artist in artists)
            if (artist is Map && _text(artist['name']) != null)
              _text(artist['name'])!,
      ].join(', '),
      durationMs: duration is num ? duration.toInt() : null,
      coverUrl: coverUrlFromUri(
          _text(json['coverUri']) ?? _text(firstAlbum?['coverUri'])),
      album: _text(firstAlbum?['title']),
    );
  }

  /// `coverUri` вида `avatars.yandex.net/get-music-content/…/%%` → адрес
  /// картинки 400×400.
  static String? coverUrlFromUri(String? uri) {
    if (uri == null) return null;
    final sized = uri.replaceAll('%%', '400x400');
    return sized.startsWith('http') ? sized : 'https://$sized';
  }

  /// Управляющие символы убираются, как во всём пользовательском тексте
  /// (security.md п. 4): названия уходят в базу и на экран.
  static String? _text(Object? value) {
    final text =
        value?.toString().replaceAll(RegExp(r'[\x00-\x1F\x7F-\x9F]'), '').trim();
    return text == null || text.isEmpty ? null : text;
  }
}
