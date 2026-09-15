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
}
