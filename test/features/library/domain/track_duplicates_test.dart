import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/library/domain/library_track.dart';
import 'package:protogenix/features/library/domain/track_duplicates.dart';

// Дубль ищется по названию и исполнителю, **без альбома** — один и тот же трек
// приходит из сингла, из альбома и из плейлиста с разным полем «альбом»
// (track_duplicates.dart). Сравнение строгое: лишний вопрос человек закроет,
// а отрезанный молча вариант песни он не получит никак.

LibraryTrack track(
  String title,
  String artist, {
  String album = 'Album',
  String id = 'id',
}) =>
    LibraryTrack(
      id: id,
      title: title,
      artist: artist,
      album: album,
      filePath: 'x',
      durationMs: 1000,
      source: 'youtube',
      addedAt: DateTime(2026),
    );

void main() {
  final library = [
    track('Cheat Codes', 'Nitro Fun', id: 'a'),
    track('In The Jungle', 'WYR GEMI', id: 'b'),
    track('Way Down We Go', 'KALEO', album: 'A/B', id: 'c'),
  ];

  test('тот же трек находится, несмотря на другой альбом', () {
    final found = findDuplicate(library,
        title: 'Way Down We Go', artist: 'KALEO');
    expect(found?.id, 'c');
  });

  test('регистр, лишние пробелы и «ё» не мешают', () {
    final found = findDuplicate(
      [track('Ёлка', 'Море Внутри', id: 'd')],
      title: '  елка ',
      artist: 'море  внутри',
    );
    expect(found?.id, 'd');
  });

  test('другой исполнитель — это другой трек', () {
    expect(
      findDuplicate(library, title: 'Cheat Codes', artist: 'Someone Else'),
      isNull,
    );
  });

  test('другое название — это другой трек', () {
    expect(
      findDuplicate(library, title: 'Cheat Codes VIP', artist: 'Nitro Fun'),
      isNull,
      reason: 'VIP-версия — отдельный трек, молча её отрезать нельзя',
    );
  });

  test('неизвестный исполнитель с любой стороны — считаем совпадением', () {
    final noArtist = [track('pg_test', '', id: 'e')];
    expect(findDuplicate(noArtist, title: 'pg_test', artist: 'Кто-то')?.id, 'e');
    expect(
      findDuplicate(library, title: 'Cheat Codes', artist: '')?.id,
      'a',
      reason: 'свой файл без тегов не должен добавляться дважды',
    );
  });

  test('пустое название и пустая медиатека ничего не находят', () {
    expect(findDuplicate(library, title: '', artist: 'Nitro Fun'), isNull);
    expect(findDuplicate(const [], title: 'Cheat Codes', artist: 'Nitro Fun'),
        isNull);
  });
}
