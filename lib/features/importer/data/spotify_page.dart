// lib/features/importer/data/spotify_page.dart
//
// Spotify без API и токена: что можно вытащить со страниц open.spotify.com.
//
// Трек (open.spotify.com/track/…) — из метатегов og:title, description
// и music:duration. Из-за трёх их особенностей импорт почти каждого трека
// заканчивался «нашлись только другие версии» (known-issues.md, 2026-09-14):
//   - в них HTML-сущности: Don&#x27;t, Rock &amp; Roll, Guns N&#x27; Roses;
//   - версию Spotify пишет через тире: «Song - Remastered 2011», «Song - Live
//     at Wembley», «Song - Kaskade Remix». Разбор названий (track_query.dart)
//     принимает такое тире за «Артист - Название», поэтому приписку
//     переносим в скобки — как у Яндекса;
//   - длительность на странице есть, и её надо передать в подбор ролика.
//
// Альбом и плейлист — со встраиваемой страницы open.spotify.com/embed/…:
// в ней есть <script id="__NEXT_DATA__"> со списком треков (название,
// исполнители, длительность). На обычной странице списка нет: она собирается
// в браузере.
//
// ⚠ Плейлист приходит обрезанным: Spotify отдаёт без входа только первые
// [kSpotifyEmbedTrackLimit] треков, сколько бы их ни было (проверено
// 2026-09-18 на плейлисте из 446 треков). Альбом приходит целиком. Остальное
// — только через официальный API со входом пользователя, а он нам закрыт
// (known-issues.md). Пользователю про это говорит подсказка под полем ссылки
// (importer_sheet.dart) и строка в итоге импорта.

import 'dart:convert';

import '../domain/import_collection.dart';

/// Сколько треков плейлиста отдаёт встраиваемая страница без входа.
const kSpotifyEmbedTrackLimit = 99;

class SpotifyTrack {
  const SpotifyTrack({
    required this.title,
    required this.artist,
    this.durationMs,
  });

  /// Название, как на Spotify: «Don't Stop Me Now - Remastered 2011».
  final String title;

  /// Исполнители через «, », как пишет Spotify; пусто — не нашли.
  final String artist;

  final int? durationMs;

  /// Название для подбора ролика и медиатеки.
  String get matchTitle => spotifyMatchTitle(title);
}

/// Приписка после тире — в скобки. В скобках разбор названий видит версию
/// (remix, live…) или отбрасывает приписку («Remastered 2011», «Love Theme
/// from …»).
String spotifyMatchTitle(String title) {
  final i = title.indexOf(' - ');
  if (i <= 0) return title;
  final song = title.substring(0, i).trim();
  final suffix = title.substring(i + 3).trim();
  if (song.isEmpty || suffix.isEmpty) return title;
  return '$song ($suffix)';
}

// ── Ссылка ────────────────────────────────────────────────────────────────────

enum SpotifyLinkKind { track, album, playlist }

class SpotifyLink {
  const SpotifyLink(this.kind, this.id);

  final SpotifyLinkKind kind;
  final String id;

  /// Альбом и плейлист качаются целиком, как коллекция из Яндекса.
  bool get isCollection => kind != SpotifyLinkKind.track;

  String get _path => switch (kind) {
        SpotifyLinkKind.track => 'track',
        SpotifyLinkKind.album => 'album',
        SpotifyLinkKind.playlist => 'playlist',
      };

  /// Обычная страница — метатеги (og:title, description, music:duration).
  String get pageUrl => 'https://open.spotify.com/$_path/$id';

  /// Встраиваемая страница — список треков в __NEXT_DATA__.
  String get embedUrl => 'https://open.spotify.com/embed/$_path/$id';
}

// Идентификатор Spotify — base62, обычно 22 символа. Проверка не только
// от мусора: id подставляется в адрес, который мы потом запрашиваем
// (security.md).
final _spotifyId = RegExp(r'^[A-Za-z0-9]{16,40}$');

/// Разбирает ссылку: open.spotify.com/intl-ru/album/<id>?si=…, embed-адреса
/// и ссылки с языком в пути. null — не ссылка Spotify на трек, альбом или
/// плейлист.
SpotifyLink? parseSpotifyLink(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  if (host != 'open.spotify.com' && host != 'play.spotify.com') return null;

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  for (var i = 0; i + 1 < segments.length; i++) {
    final kind = switch (segments[i].toLowerCase()) {
      'track' => SpotifyLinkKind.track,
      'album' => SpotifyLinkKind.album,
      'playlist' => SpotifyLinkKind.playlist,
      _ => null,
    };
    if (kind == null) continue;
    final id = segments[i + 1];
    return _spotifyId.hasMatch(id) ? SpotifyLink(kind, id) : null;
  }
  return null;
}

// ── Страница трека ────────────────────────────────────────────────────────────

final _ogTitle = RegExp(r'<meta property="og:title" content="([^"]+)"');
final _description = RegExp(r'<meta name="description" content="([^"]+)"');
final _duration = RegExp(r'<meta name="music:duration" content="(\d+)"');
final _year = RegExp(r'^\d{4}\.?$');

/// Слово перед первой «·» в описании — что это за страница.
const _trackKinds = {'song', 'track', 'песня', 'трек'};
const _collectionKinds = {
  'album', 'playlist', 'single', 'ep', 'compilation', 'artist', 'podcast',
  'episode', 'show', 'альбом', 'плейлист', 'сингл', 'исполнитель',
};

/// null — не страница трека (плейлист, альбом) или на ней нет метаданных.
SpotifyTrack? parseSpotifyTrackPage(String html) {
  final titleMatch = _ogTitle.firstMatch(html);
  final descMatch = _description.firstMatch(html);
  if (titleMatch == null || descMatch == null) return null;

  final title = decodeHtmlEntities(titleMatch.group(1)!).trim();
  // «Listen to … on Spotify. Song · Queen, David Bowie · 1981». Части берём
  // с конца: в самом названии тоже может встретиться «·».
  final parts = decodeHtmlEntities(descMatch.group(1)!)
      .split('·')
      .map((p) => p.trim())
      .toList();
  if (title.isEmpty || parts.length < 3) return null;

  final kindWords = parts[parts.length - 3].split(' ');
  final kind = kindWords.last.toLowerCase();
  final looksLikeTrack = _trackKinds.contains(kind) ||
      (!_collectionKinds.contains(kind) &&
          parts.length == 3 &&
          _year.hasMatch(parts.last));
  if (!looksLikeTrack) return null;

  final seconds = int.tryParse(_duration.firstMatch(html)?.group(1) ?? '');
  return SpotifyTrack(
    title: title,
    artist: parts[parts.length - 2],
    durationMs: seconds != null && seconds > 0 ? seconds * 1000 : null,
  );
}

// ── Встраиваемая страница альбома и плейлиста ─────────────────────────────────

final _nextData =
    RegExp(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', dotAll: true);

/// Список треков со встраиваемой страницы. null — не та страница, разметка
/// поменялась или список пуст.
ImportCollection? parseSpotifyEmbedCollection(String html) {
  final match = _nextData.firstMatch(html);
  if (match == null) return null;

  final Object? data;
  try {
    data = jsonDecode(match.group(1)!);
  } catch (_) {
    return null;
  }

  final entity =
      _dig(data, const ['props', 'pageProps', 'state', 'data', 'entity']);
  if (entity is! Map) return null;

  final rawList = entity['trackList'];
  if (rawList is! List) return null;

  final tracks = <ImportTrack>[];
  var unavailable = 0;
  for (final item in rawList) {
    if (item is! Map) continue;
    // В плейлист можно положить и выпуск подкаста — такое пропускаем.
    final uri = _text(item['uri']) ?? '';
    if (uri.isNotEmpty && !uri.contains(':track:')) continue;

    final title = _text(item['title']);
    if (title == null) continue;
    // Трека нет в самом Spotify: удалён или недоступен в этой стране.
    if (item['isPlayable'] == false) {
      unavailable++;
      continue;
    }
    final duration = item['duration'];
    tracks.add(ImportTrack(
      title: spotifyMatchTitle(title),
      artists: _text(item['subtitle']) ?? '',
      durationMs: duration is int && duration > 0 ? duration : null,
    ));
  }
  if (tracks.isEmpty) return null;

  return ImportCollection(
    title: _text(entity['name']) ?? _text(entity['title']) ?? 'Spotify',
    tracks: tracks,
    sourceName: 'Spotify',
    unavailable: unavailable,
  );
}

// «446 items», «17 songs», «446 треков». Слова перечислены целиком: \w
// и \b в Dart работают только по латинице.
final _itemCount = RegExp(
  r'(\d[\d\s,.]*)\s*(songs|song|items|item|треков|трека|трек|песен|песни)',
  caseSensitive: false,
);

/// Сколько треков в альбоме или плейлисте по описанию обычной страницы:
/// «Playlist · Ня · 446 items», «Album · Queen · 1981 · 17 songs».
/// null — в описании числа нет.
int? parseSpotifyCollectionSize(String html) {
  final desc = _description.firstMatch(html);
  if (desc == null) return null;
  final match = _itemCount.firstMatch(decodeHtmlEntities(desc.group(1)!));
  if (match == null) return null;
  final digits = match.group(1)!.replaceAll(RegExp(r'[^\d]'), '');
  final size = int.tryParse(digits);
  return size != null && size > 0 ? size : null;
}

Object? _dig(Object? data, List<String> path) {
  var current = data;
  for (final key in path) {
    if (current is! Map) return null;
    current = current[key];
  }
  return current;
}

/// Текст из JSON: без управляющих символов (security.md), пустой — null.
String? _text(Object? value) {
  if (value is! String) return null;
  final clean = decodeHtmlEntities(value)
      .replaceAll(RegExp(r'[\x00-\x1F\x7F-\x9F]'), ' ')
      .trim();
  return clean.isEmpty ? null : clean;
}

const _namedEntities = {
  'amp': '&',
  'quot': '"',
  'apos': "'",
  'lt': '<',
  'gt': '>',
  'nbsp': ' ',
};

/// HTML-сущности — в символы. Один проход, как в браузере: «&amp;amp;» даёт
/// «&amp;». Неизвестные сущности остаются как есть.
String decodeHtmlEntities(String text) => text.replaceAllMapped(
      RegExp(r'&(#[xX][0-9a-fA-F]{1,6}|#\d{1,7}|[a-zA-Z]+);'),
      (m) {
        final entity = m.group(1)!;
        if (!entity.startsWith('#')) return _namedEntities[entity] ?? m[0]!;
        final hex = entity.startsWith('#x') || entity.startsWith('#X');
        final code =
            int.tryParse(entity.substring(hex ? 2 : 1), radix: hex ? 16 : 10);
        final valid = code != null &&
            code > 0 &&
            code <= 0x10FFFF &&
            (code < 0xD800 || code > 0xDFFF);
        return valid ? String.fromCharCode(code) : m[0]!;
      },
    );
