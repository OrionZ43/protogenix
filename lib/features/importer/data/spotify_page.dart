// lib/features/importer/data/spotify_page.dart
//
// Трек Spotify по его странице (open.spotify.com/track/…): без API и токена
// берём метатеги og:title, description и music:duration.
//
// Из-за трёх особенностей этих метатегов импорт почти каждого трека
// заканчивался «нашлись только другие версии» (known-issues.md, 2026-09-14):
//   - в них HTML-сущности: Don&#x27;t, Rock &amp; Roll, Guns N&#x27; Roses;
//   - версию Spotify пишет через тире: «Song - Remastered 2011», «Song - Live
//     at Wembley», «Song - Kaskade Remix». Разбор названий (track_query.dart)
//     принимает такое тире за «Артист - Название», поэтому приписку
//     переносим в скобки — как у Яндекса;
//   - длительность на странице есть, и её надо передать в подбор ролика.

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

  /// Название для подбора ролика и медиатеки: приписка после тире — в
  /// скобках. В скобках разбор названий видит версию (remix, live…) или
  /// отбрасывает приписку («Remastered 2011», «Love Theme from …»).
  String get matchTitle {
    final i = title.indexOf(' - ');
    if (i <= 0) return title;
    final song = title.substring(0, i).trim();
    final suffix = title.substring(i + 3).trim();
    if (song.isEmpty || suffix.isEmpty) return title;
    return '$song ($suffix)';
  }
}

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
