import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:protogenix/core/services/app_paths.dart';
import 'package:protogenix/features/library/data/library_database.dart';
import 'package:protogenix/features/library/domain/library_track.dart';
import 'package:protogenix/features/library/presentation/library_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// База и файлы — во временной папке, не в данных приложения
// (known-issues.md, «Тесты»).
void main() {
  late Directory tmp;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('protogenix_remove_');
    AppPaths.databasesDir = tmp.path;
  });

  test(
      'удаление пачкой: свои файлы и обложки удаляются, '
      'музыка с телефона остаётся', () async {
    File make(String name) =>
        File(p.join(tmp.path, name))..writeAsStringSync('data');
    File cover(String id) => File(p.join(tmp.path, '$id.jpg'));
    LibraryTrack track(String id, File file, String source) => LibraryTrack(
          id: id,
          title: id,
          artist: 'Artist',
          album: 'Album',
          filePath: file.path,
          coverPath: make('$id.jpg').path,
          durationMs: 0,
          source: source,
          addedAt: DateTime(2026, 9, 13),
        );

    final own = make('own.mp3');
    final phone = make('phone.mp3');
    final kept = make('kept.mp3');
    for (final t in [
      track('own', own, 'local'),
      track('phone', phone, 'device'),
      track('kept', kept, 'local'),
    ]) {
      await LibraryDatabase.instance.insertTrack(t);
    }

    final notifier = LibraryNotifier();
    await notifier.reload();
    await notifier.removeTracksWithFiles(
        notifier.state.where((t) => t.id != 'kept').toList());

    expect(notifier.state.map((t) => t.id), ['kept']);
    expect(await LibraryDatabase.instance.getTrackById('own'), isNull);
    expect(await LibraryDatabase.instance.getTrackById('phone'), isNull);
    expect(own.existsSync(), isFalse);
    expect(phone.existsSync(), isTrue, reason: 'файл пользователя не трогаем');
    expect(kept.existsSync(), isTrue);
    expect(cover('own').existsSync(), isFalse);
    expect(cover('phone').existsSync(), isFalse,
        reason: 'обложку сохраняло приложение');
    expect(cover('kept').existsSync(), isTrue);
  });
}
