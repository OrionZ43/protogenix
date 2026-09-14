import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/importer/data/device_music.dart';

// Записи в том виде, что отдаёт MainActivity.queryAudio (MediaStore).
void main() {
  test('обычная запись', () {
    final track = DeviceTrack.fromMap({
      'path': '/storage/emulated/0/Music/Кино - Группа крови.mp3',
      'title': 'Группа крови',
      'artist': 'Кино',
      'album': 'Группа крови',
      'durationMs': 285000,
    })!;
    expect(track.path, '/storage/emulated/0/Music/Кино - Группа крови.mp3');
    expect(track.title, 'Группа крови');
    expect(track.artist, 'Кино');
    expect(track.durationMs, 285000);
  });

  test('«<unknown>» и пустые поля — как нет значения', () {
    final track = DeviceTrack.fromMap({
      'path': '/storage/emulated/0/Download/track.mp3',
      'title': '  ',
      'artist': '<unknown>',
      'album': null,
      'durationMs': 0,
    })!;
    expect(track.title, isNull);
    expect(track.artist, isNull);
    expect(track.album, isNull);
    expect(track.durationMs, isNull);
  });

  test('без пути — пропускается', () {
    expect(DeviceTrack.fromMap({'title': 'Без пути'}), isNull);
    expect(DeviceTrack.fromMap({'path': ''}), isNull);
  });
}
