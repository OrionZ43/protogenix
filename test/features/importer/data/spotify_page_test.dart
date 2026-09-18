import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/importer/data/spotify_page.dart';
import 'package:protogenix/features/importer/data/youtube_match.dart';

/// Страница трека в том виде, в каком её отдаёт Spotify (метатеги сняты с
/// настоящих страниц 2026-09-14).
String page(String title, String description, {int? duration}) => '''
<html><head>
<meta property="og:title" content="$title"/>
<meta name="description" content="$description"/>
${duration == null ? '' : '<meta name="music:duration" content="$duration"/>'}
</head></html>''';

void main() {
  test('сущности раскодированы, длительность в миллисекундах', () {
    final track = parseSpotifyTrackPage(page(
      'Don&#x27;t Stop Me Now - Remastered 2011',
      'Listen to Don&#x27;t Stop Me Now - Remastered 2011 on Spotify. '
          'Song · Queen · 1978',
      duration: 209,
    ))!;
    expect(track.title, "Don't Stop Me Now - Remastered 2011");
    expect(track.artist, 'Queen');
    expect(track.durationMs, 209000);
    expect(track.matchTitle, "Don't Stop Me Now (Remastered 2011)");
  });

  test('кавычки, апостроф в исполнителе, несколько исполнителей', () {
    final titanic = parseSpotifyTrackPage(page(
      'My Heart Will Go On - Love Theme from &quot;Titanic&quot;',
      'Listen to My Heart Will Go On on Spotify. Song · Céline Dion · 1997',
    ))!;
    expect(titanic.matchTitle, 'My Heart Will Go On (Love Theme from "Titanic")');

    final guns = parseSpotifyTrackPage(page(
      'Sweet Child O&#x27; Mine',
      'Listen to Sweet Child O&#x27; Mine on Spotify. '
          'Song · Guns N&#x27; Roses · 1987',
    ))!;
    expect(guns.artist, "Guns N' Roses");
    expect(guns.matchTitle, "Sweet Child O' Mine");

    final pressure = parseSpotifyTrackPage(page(
      'Under Pressure - Remastered 2011',
      'Listen to Under Pressure on Spotify. Song · Queen, David Bowie · 1981',
    ))!;
    expect(pressure.artist, 'Queen, David Bowie');
  });

  test('локализованная страница трека', () {
    final track = parseSpotifyTrackPage(page(
      'Кукла',
      'Слушай «Кукла» на Spotify. Песня · Кино · 1988',
    ))!;
    expect(track.artist, 'Кино');
  });

  test('плейлист и альбом — не трек', () {
    expect(
        parseSpotifyTrackPage(page('Top 50',
            'Listen to Top 50 on Spotify. Playlist · Spotify · 50 items · 1.2M saves')),
        isNull);
    expect(
        parseSpotifyTrackPage(page('Divide',
            'Listen to Divide on Spotify. Ed Sheeran · Album · 2017 · 16 songs.')),
        isNull);
    expect(parseSpotifyTrackPage('<html></html>'), isNull);
  });

  test('HTML-сущности', () {
    expect(decodeHtmlEntities('Rock &amp; Roll'), 'Rock & Roll');
    expect(decodeHtmlEntities('&amp;amp;'), '&amp;');
    expect(decodeHtmlEntities('It&#39;s &#1082;'), "It's к");
    expect(decodeHtmlEntities('&unknown; &#xD800;'), '&unknown; &#xD800;');
  });

  test('со Spotify подбор берёт студийную запись, а не концерт', () {
    final track = parseSpotifyTrackPage(page(
      'Don&#x27;t Stop Me Now - Remastered 2011',
      'Listen to Don&#x27;t Stop Me Now on Spotify. Song · Queen · 1978',
      duration: 209,
    ))!;
    final matcher = YoutubeTrackMatcher(
        title: track.matchTitle,
        artist: track.artist,
        durationMs: track.durationMs);
    final picked = matcher.pick(const [
      YoutubeCandidate(
          id: 'live',
          title: "Don't Stop Me Now (Live at Montreal 1981)",
          author: 'Queen Official',
          durationMs: 212000),
      YoutubeCandidate(
          id: 'studio',
          title: "Don't Stop Me Now - Remastered 2011",
          author: 'Queen - Topic',
          durationMs: 209000),
    ]);
    expect(picked?.id, 'studio');
  });

  test('ремикс со Spotify ищет ремикс, а не оригинал', () {
    final track = parseSpotifyTrackPage(page(
      'Believer - Kaskade Remix',
      'Listen to Believer - Kaskade Remix on Spotify. '
          'Song · Imagine Dragons, Kaskade · 2017',
      duration: 220,
    ))!;
    final matcher = YoutubeTrackMatcher(
        title: track.matchTitle,
        artist: track.artist,
        durationMs: track.durationMs);
    final picked = matcher.pick(const [
      YoutubeCandidate(
          id: 'original',
          title: 'Imagine Dragons - Believer (Official Music Video)',
          author: 'ImagineDragonsVEVO',
          durationMs: 204000),
      YoutubeCandidate(
          id: 'remix',
          title: 'Believer (Kaskade Remix)',
          author: 'Imagine Dragons - Topic',
          durationMs: 220000),
    ]);
    expect(picked?.id, 'remix');
  });

  // ── Ссылка ────────────────────────────────────────────────────────────────

  test('ссылка: трек, альбом, плейлист, язык в пути, хвост si=', () {
    final track = parseSpotifyLink(
        'https://open.spotify.com/track/4u7EnebtmKWzUH433cf5Qv?si=abc')!;
    expect(track.kind, SpotifyLinkKind.track);
    expect(track.id, '4u7EnebtmKWzUH433cf5Qv');
    expect(track.isCollection, isFalse);
    expect(track.pageUrl,
        'https://open.spotify.com/track/4u7EnebtmKWzUH433cf5Qv');

    final playlist = parseSpotifyLink(
        'https://open.spotify.com/playlist/3qDD9XgaWAKwMaQ89uzcIc')!;
    expect(playlist.kind, SpotifyLinkKind.playlist);
    expect(playlist.isCollection, isTrue);
    expect(playlist.embedUrl,
        'https://open.spotify.com/embed/playlist/3qDD9XgaWAKwMaQ89uzcIc');

    final album = parseSpotifyLink(
        'https://open.spotify.com/intl-ru/album/3T4tUhGYeRNVUGevb0wThu')!;
    expect(album.kind, SpotifyLinkKind.album);
    expect(album.id, '3T4tUhGYeRNVUGevb0wThu');
  });

  test('ссылка: чужой адрес, исполнитель и мусорный id — не импортируем', () {
    expect(parseSpotifyLink('https://music.yandex.ru/album/123'), isNull);
    expect(
        parseSpotifyLink(
            'https://open.spotify.com/artist/1dfeR4HaWDbWqFHLkxsg1d'),
        isNull);
    expect(parseSpotifyLink('https://open.spotify.com/playlist/../secret'),
        isNull);
    expect(parseSpotifyLink('https://open.spotify.com/'), isNull);
  });

  // ── Встраиваемая страница ─────────────────────────────────────────────────

  /// Встраиваемая страница в том виде, в каком её отдаёт Spotify: разметка
  /// и __NEXT_DATA__ сняты с настоящей страницы 2026-09-18.
  String embed(Map<String, Object?> entity) {
    final data = jsonEncode({
      'props': {
        'pageProps': {
          'state': {
            'data': {'entity': entity}
          }
        }
      }
    });
    return '<html><body><div id="__next"></div>'
        '<script id="__NEXT_DATA__" type="application/json">$data</script>'
        '</body></html>';
  }

  Map<String, Object?> spotifyItem(
    String id,
    String title,
    String subtitle,
    int duration, {
    bool playable = true,
  }) =>
      {
        'uri': 'spotify:track:$id',
        'title': title,
        'subtitle': subtitle,
        'duration': duration,
        'isPlayable': playable,
      };

  test('плейлист: название, треки, версия в скобках', () {
    final collection = parseSpotifyEmbedCollection(embed({
      'type': 'playlist',
      'name': 'Ня',
      'title': 'Ня',
      'trackList': [
        spotifyItem('a1', 'Under Pressure - Remastered 2011',
            'Queen, David Bowie', 248000),
        spotifyItem('a2', 'Кукла', 'Кино', 205000),
      ],
    }))!;

    expect(collection.title, 'Ня');
    expect(collection.sourceName, 'Spotify');
    expect(collection.tracks.length, 2);
    expect(collection.tracks.first.title, 'Under Pressure (Remastered 2011)');
    expect(collection.tracks.first.artists, 'Queen, David Bowie');
    expect(collection.tracks.first.durationMs, 248000);
    expect(collection.tracks.last.artists, 'Кино');
    expect(collection.unavailable, 0);
  });

  test('недоступные треки считаются, подкасты пропускаются', () {
    final collection = parseSpotifyEmbedCollection(embed({
      'type': 'playlist',
      'name': 'Смесь',
      'trackList': [
        spotifyItem('a1', 'Believer', 'Imagine Dragons', 204000),
        spotifyItem('a2', 'Удалённый трек', 'Кто-то', 200000, playable: false),
        {
          'uri': 'spotify:episode:e1',
          'title': 'Выпуск подкаста',
          'subtitle': 'Подкаст',
          'duration': 3600000,
          'isPlayable': true,
        },
      ],
    }))!;

    expect(collection.tracks.length, 1);
    expect(collection.tracks.single.title, 'Believer');
    expect(collection.unavailable, 1);
  });

  test('не та страница или пустой список — null', () {
    expect(parseSpotifyEmbedCollection('<html></html>'), isNull);
    expect(
        parseSpotifyEmbedCollection(
            '<script id="__NEXT_DATA__">не json</script>'),
        isNull);
    expect(
        parseSpotifyEmbedCollection(
            embed({'type': 'playlist', 'name': 'Пусто', 'trackList': []})),
        isNull);
  });

  test('сколько треков в коллекции — из описания обычной страницы', () {
    expect(
        parseSpotifyCollectionSize(page(
            'Ня', 'Listen to Ня on Spotify. Playlist · Ня · 446 items')),
        446);
    expect(
        parseSpotifyCollectionSize(page('Divide',
            'Listen to Divide on Spotify. Ed Sheeran · Album · 2017 · 16 songs.')),
        16);
    expect(
        parseSpotifyCollectionSize(page('Большой',
            'Listen on Spotify. Playlist · Spotify · 1,234 items')),
        1234);
    expect(
        parseSpotifyCollectionSize(
            page('Кукла', 'Слушай «Кукла» на Spotify. Песня · Кино · 1988')),
        isNull);
  });
}
