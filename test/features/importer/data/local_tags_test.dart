import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:protogenix/features/importer/data/local_tags.dart';

// Файлы в test/fixtures/audio — секунда тона с тегами на кириллице и
// обложкой 16×16, сделаны ffmpeg (-metadata, -disposition:v attached_pic).
void main() {
  const fixtures = 'test/fixtures/audio';

  test('MP3: теги ID3v2 на кириллице и обложка', () async {
    final tags = await readLocalTags(p.join(fixtures, 'tagged.mp3'));
    expect(tags.title, 'Группа крови');
    expect(tags.artist, 'Кино');
    expect(tags.album, 'Группа крови');
    expect(tags.cover, isNotEmpty);
  });

  test('M4A: теги iTunes, длительность и обложка', () async {
    final tags = await readLocalTags(p.join(fixtures, 'tagged.m4a'));
    expect(tags.title, 'Группа крови');
    expect(tags.artist, 'Кино');
    expect(tags.album, 'Группа крови');
    expect(tags.cover, isNotEmpty);
    expect(tags.duration!.inMilliseconds, closeTo(1000, 250));
  });

  test('не аудио — пустые теги, без исключения', () async {
    final tmp = await Directory.systemTemp.createTemp('protogenix_tags_');
    addTearDown(() => tmp.delete(recursive: true));
    final junk = File(p.join(tmp.path, 'junk.mp3'))
      ..writeAsBytesSync(List.generate(4096, (i) => i * 7 % 256));

    final tags = await readLocalTags(junk.path);
    expect(tags.title, isNull);
    expect(tags.artist, isNull);
    expect(tags.cover, isNull);
  });

  group('splitArtistTitle', () {
    test('«Артист - Название»', () {
      expect(splitArtistTitle('Кино - Группа крови'), ('Кино', 'Группа крови'));
    });
    test('без разделителя — только название', () {
      expect(splitArtistTitle('Группа крови'), (null, 'Группа крови'));
    });
    test('номер трека — не артист', () {
      expect(splitArtistTitle('01 - Intro'), (null, '01 - Intro'));
    });
  });

  test('id по содержимому: тот же файл в другой папке — тот же id', () async {
    final tmp = await Directory.systemTemp.createTemp('protogenix_local_');
    addTearDown(() => tmp.delete(recursive: true));
    File write(String rel, int shift) =>
        File(p.join(tmp.path, rel))
          ..createSync(recursive: true)
          ..writeAsBytesSync(List.generate(100000, (i) => (i + shift) % 256));

    final a = write('a/Песня.mp3', 0);
    final sameContent = write('b/Другое имя.mp3', 0);
    final otherContent = write('a/Песня 2.mp3', 1);

    expect(await localTrackId(a), startsWith('local_'));
    expect(await localTrackId(a), await localTrackId(sameContent));
    expect(await localTrackId(a), isNot(await localTrackId(otherContent)));
  });
}
