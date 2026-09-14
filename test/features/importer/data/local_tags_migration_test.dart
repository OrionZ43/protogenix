import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/importer/data/local_tags.dart';
import 'package:protogenix/features/importer/data/local_tags_migration.dart';
import 'package:protogenix/features/library/domain/library_track.dart';

/// Трек, каким его записывал импорт своих файлов до 1.1: название — имя
/// файла, копия — под «очищенным» именем.
LibraryTrack _old(
  String title, {
  String artist = 'Unknown Artist',
  String album = 'Local Import',
  String source = 'local',
  String? file,
}) =>
    LibraryTrack(
      id: 'old',
      title: title,
      artist: artist,
      album: album,
      filePath: file ??
          '/data/music/${title.replaceAll(RegExp(r'[^a-zA-Z0-9\.\-\_]'), '_')}.mp3',
      durationMs: 0,
      source: source,
      addedAt: DateTime(2026, 9, 1),
    );

void main() {
  group('needsReread', () {
    test('трек старого импорта', () {
      expect(LocalTagsMigration.needsReread(_old('Кино - Группа крови')),
          isTrue);
    });

    test('исполнителя правили руками — не трогаем', () {
      expect(
          LocalTagsMigration.needsReread(
              _old('Кино - Группа крови', artist: 'Кино')),
          isFalse);
    });

    test('название правили руками — не трогаем', () {
      expect(
          LocalTagsMigration.needsReread(
              _old('Группа крови', file: '/data/music/track_01.mp3')),
          isFalse);
    });

    test('не свой файл — не трогаем', () {
      expect(LocalTagsMigration.needsReread(_old('abc', source: 'youtube')),
          isFalse);
    });
  });

  group('retag', () {
    test('теги есть — всё из тегов', () {
      final track = LocalTagsMigration.retag(
        _old('track_01'),
        const LocalTags(
          title: 'Группа крови',
          artist: 'Кино',
          album: 'Группа крови',
          duration: Duration(seconds: 285),
        ),
        coverPath: '/data/covers/old.jpg',
      )!;
      expect(track.title, 'Группа крови');
      expect(track.artist, 'Кино');
      expect(track.album, 'Группа крови');
      expect(track.durationMs, 285000);
      expect(track.coverPath, '/data/covers/old.jpg');
    });

    test('тегов нет — «Артист - Название» из имени файла', () {
      final track = LocalTagsMigration.retag(
          _old('Кино - Группа крови'), LocalTags.empty)!;
      expect(track.artist, 'Кино');
      expect(track.title, 'Группа крови');
      expect(track.album, 'Local Import');
    });

    test('ничего нового — null', () {
      expect(LocalTagsMigration.retag(_old('track_01'), LocalTags.empty),
          isNull);
    });
  });
}
