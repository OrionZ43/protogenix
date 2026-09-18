import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/importer/data/imported_tracks_index.dart';
import 'package:protogenix/features/importer/domain/import_collection.dart';
import 'package:protogenix/features/library/domain/library_track.dart';

// Трек в медиатеке — так, как его сохраняет импорт коллекции
// (_importCollection → _downloadYouTubeVideo): название с версией,
// все исполнители, альбом трека.
LibraryTrack stored(String id, String title, String artist, String album,
        {DateTime? addedAt}) =>
    LibraryTrack(
      id: id,
      title: title,
      artist: artist,
      album: album,
      filePath: '$id.m4a',
      durationMs: 0,
      source: 'youtube',
      addedAt: addedAt ?? DateTime(2026, 9, 13),
    );

void main() {
  const believer = ImportTrack(
    title: 'Believer',
    artists: 'Imagine Dragons',
    album: 'Evolve',
  );

  test('узнаёт скачанный трек по названию, исполнителям и альбому', () {
    final index = ImportedTracksIndex([
      stored('vid1', 'Believer', 'Imagine Dragons', 'Evolve'),
    ]);
    expect(index.find(believer, album: 'Evolve'), 'vid1');
  });

  test('регистр и лишние пробелы не мешают', () {
    final index = ImportedTracksIndex([
      stored('vid1', ' believer ', 'Imagine  Dragons', 'EVOLVE'),
    ]);
    expect(index.find(believer, album: 'Evolve'), 'vid1');
  });

  test('другая версия, альбом или исполнитель — другой трек', () {
    final index = ImportedTracksIndex([
      stored('vid1', 'Believer (Kaskade Remix)', 'Imagine Dragons', 'Evolve'),
      stored('vid2', 'Believer', 'Imagine Dragons', 'Believer (Single)'),
      stored('vid3', 'Believer', 'Other Band', 'Evolve'),
    ]);
    expect(index.find(believer, album: 'Evolve'), isNull);
  });

  test('без исполнителей не угадывает: в медиатеке тогда имя канала', () {
    final index = ImportedTracksIndex([
      stored('vid1', 'Believer', '', 'Evolve'),
    ]);
    const noArtists =
        ImportTrack(title: 'Believer', artists: '', album: 'Evolve');
    expect(index.find(noArtists, album: 'Evolve'), isNull);
  });

  test('из двух копий — свежая, скачанная новым подбором записи', () {
    final older = stored('old', 'Believer', 'Imagine Dragons', 'Evolve',
        addedAt: DateTime(2026, 9, 13, 9));
    final newer = stored('new', 'Believer', 'Imagine Dragons', 'Evolve',
        addedAt: DateTime(2026, 9, 13, 12));
    for (final library in [
      [older, newer],
      [newer, older],
    ]) {
      expect(ImportedTracksIndex(library).find(believer, album: 'Evolve'),
          'new');
    }
  });

  test('скачанный в этом же импорте дальше находится без поиска', () {
    final index = ImportedTracksIndex(const []);
    expect(index.find(believer, album: 'Evolve'), isNull);
    index.add(believer, album: 'Evolve', id: 'vid1');
    expect(index.find(believer, album: 'Evolve'), 'vid1');
  });
}
