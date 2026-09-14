import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/importer/data/yandex_music.dart';

// Ответы API — в том виде, что отдаёт api.music.yandex.net без токена
// (трек проверен с телефона Orion из Беларуси 2026-09-13). Только метаданные.
Map<String, Object?> _track({
  String title = 'Believer',
  String? version,
  bool available = true,
  List<String> artists = const ['Imagine Dragons'],
}) =>
    {
      'id': '33311009',
      'title': title,
      if (version != null) 'version': version,
      'available': available,
      'durationMs': 204330,
      'artists': [
        for (final name in artists) {'name': name},
      ],
      'albums': [
        {'id': 5568718, 'title': 'Evolve'},
      ],
      'coverUri': 'avatars.yandex.net/get-music-content/98892/a6be0789.a.5568718-1/%%',
    };

void main() {
  group('YandexLink.parse', () {
    YandexLink? parse(String url) => YandexLink.parse(url);

    test('трек из альбома — это трек, а не весь альбом', () {
      final link = parse('https://music.yandex.ru/album/5568718/track/33311009'
          '?utm_source=web&utm_medium=copy_link');
      expect(link?.kind, YandexLinkKind.track);
      expect(link?.id, '33311009');
    });

    test('короткая ссылка на трек и другие домены', () {
      expect(parse('https://music.yandex.by/track/33311009')?.kind,
          YandexLinkKind.track);
      expect(parse('https://music.yandex.com/album/5568718')?.kind,
          YandexLinkKind.album);
      expect(parse('https://music.yandex.kz/album/5568718')?.id, '5568718');
    });

    test('плейлист пользователя', () {
      final link =
          parse('https://music.yandex.ru/users/yamusic-top/playlists/1076');
      expect(link?.kind, YandexLinkKind.userPlaylist);
      expect(link?.owner, 'yamusic-top');
      expect(link?.id, '1076');
    });

    test('плейлист по uuid', () {
      final link = parse('https://music.yandex.ru/playlists/'
          'lk.0f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b');
      expect(link?.kind, YandexLinkKind.playlistUuid);
      expect(link?.id, 'lk.0f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b');
    });

    test('исполнитель, чужой домен и не Яндекс — null', () {
      expect(parse('https://music.yandex.ru/artist/675068'), isNull);
      expect(parse('https://music.yandex.ru.evil.com/album/1'), isNull);
      expect(parse('https://open.spotify.com/track/4vvLC50if1kVOemsm7gjcJ'),
          isNull);
    });
  });

  group('разбор ответов', () {
    test('трек: название, исполнители, длительность, обложка 400×400', () {
      final track = YandexMusicApi.parseTrack(
          _track(artists: ['Imagine Dragons', 'Lil Wayne']))!;
      expect(track.title, 'Believer');
      expect(track.artists, 'Imagine Dragons, Lil Wayne');
      expect(track.durationMs, 204330);
      expect(track.album, 'Evolve');
      expect(track.coverUrl,
          'https://avatars.yandex.net/get-music-content/98892/a6be0789.a.5568718-1/400x400');
    });

    test('версия трека идёт в название', () {
      expect(YandexMusicApi.parseTrack(_track(version: 'Remix'))!.title,
          'Believer (Remix)');
    });

    test('альбом: тома склеиваются, недоступные пропускаются', () {
      final album = YandexMusicApi.parseAlbum({
        'title': 'Evolve',
        'volumes': [
          [_track(title: 'Next To Me'), _track(title: 'Believer')],
          [_track(title: 'Hidden', available: false)],
        ],
      });
      expect(album.title, 'Evolve');
      expect(album.tracks.map((t) => t.title), ['Next To Me', 'Believer']);
      expect(album.unavailable, 1);
      expect(album.isSingleTrack, isFalse);
    });

    test('плейлист: треки в обёртке {id, track}', () {
      final playlist = YandexMusicApi.parsePlaylist({
        'title': 'Чарт',
        'tracks': [
          {'id': 1, 'track': _track(title: 'Первый')},
          {'id': 2, 'track': _track(title: 'Второй')},
        ],
      });
      expect(playlist.title, 'Чарт');
      expect(playlist.tracks.map((t) => t.title), ['Первый', 'Второй']);
    });
  });

  group('запросы к API', () {
    late HttpServer server;
    late int status;
    late Object? body;

    setUp(() async {
      status = 200;
      body = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response
          ..statusCode = status
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(body));
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    YandexMusicApi api() =>
        YandexMusicApi(baseUrl: 'http://127.0.0.1:${server.port}');

    test('ссылка на трек — один трек, альбом в названии', () async {
      body = {
        'result': [_track()],
      };
      final collection = await api()
          .fetch(const YandexLink(YandexLinkKind.track, '33311009'));
      expect(collection.isSingleTrack, isTrue);
      expect(collection.title, 'Evolve');
      expect(collection.tracks.single.title, 'Believer');
    });

    test('451 из-за страны или VPN — понятное сообщение', () async {
      status = 451;
      body = {
        'error': {'name': 'Unavailable For Legal Reasons'},
      };
      await expectLater(
        api().fetch(const YandexLink(YandexLinkKind.track, '33311009')),
        throwsA(isA<YandexMusicException>().having(
            (e) => e.message, 'message', YandexMusicApi.regionMessage)),
      );
    });
  });
}
