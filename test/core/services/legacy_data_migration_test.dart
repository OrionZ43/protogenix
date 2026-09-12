import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:protogenix/core/services/legacy_data_migration.dart';

void main() {
  late Directory tmp;
  late String target;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('protogenix_migration_');
    target = p.join(tmp.path, 'new', 'databases');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<String> legacyDir(String name) async {
    final dir = LegacyDatabaseMigration.legacyDirFor(p.join(tmp.path, name));
    await Directory(dir).create(recursive: true);
    return dir;
  }

  Future<void> writeFile(String dir, String name, String content,
      {DateTime? modified}) async {
    final file = File(p.join(dir, name));
    await file.writeAsString(content);
    if (modified != null) await file.setLastModified(modified);
  }

  String read(String dir, String name) =>
      File(p.join(dir, name)).readAsStringSync();

  bool exists(String dir, String name) => File(p.join(dir, name)).existsSync();

  test('без старых данных ничего не копирует и ставит маркер', () async {
    final result = await LegacyDatabaseMigration(
      targetDir: target,
      legacyDirs: [p.join(tmp.path, 'nowhere')],
    ).run();

    expect(result, target);
    expect(exists(target, LegacyDatabaseMigration.markerName), isTrue);
    expect(exists(target, 'protogenix.db'), isFalse);
  });

  test('копирует обе базы и оставляет старые на месте', () async {
    final old = await legacyDir('cwd');
    await writeFile(old, 'protogenix.db', 'library');
    await writeFile(old, 'protogenix_playlists.db', 'playlists');

    final result =
        await LegacyDatabaseMigration(targetDir: target, legacyDirs: [old])
            .run();

    expect(result, target);
    expect(read(target, 'protogenix.db'), 'library');
    expect(read(target, 'protogenix_playlists.db'), 'playlists');
    expect(read(old, 'protogenix.db'), 'library');
  });

  test('берёт папку, где базы менялись последними', () async {
    final stale = await legacyDir('stale');
    final fresh = await legacyDir('fresh');
    await writeFile(stale, 'protogenix.db', 'stale',
        modified: DateTime(2026, 1, 1));
    await writeFile(fresh, 'protogenix.db', 'fresh',
        modified: DateTime(2026, 6, 1));

    await LegacyDatabaseMigration(
      targetDir: target,
      legacyDirs: [stale, fresh],
    ).run();

    expect(read(target, 'protogenix.db'), 'fresh');
  });

  test('копирует служебные файлы SQLite вместе с базой', () async {
    final old = await legacyDir('cwd');
    await writeFile(old, 'protogenix.db', 'library');
    await writeFile(old, 'protogenix.db-journal', 'journal');

    await LegacyDatabaseMigration(targetDir: target, legacyDirs: [old]).run();

    expect(read(target, 'protogenix.db-journal'), 'journal');
    expect(exists(target, 'protogenix.db.tmp'), isFalse);
  });

  test('не затирает базы, которые уже есть на новом месте', () async {
    final old = await legacyDir('cwd');
    await writeFile(old, 'protogenix.db', 'old');
    await writeFile(old, 'protogenix_playlists.db', 'old playlists');
    await Directory(target).create(recursive: true);
    await writeFile(target, 'protogenix.db', 'current');

    await LegacyDatabaseMigration(targetDir: target, legacyDirs: [old]).run();

    expect(read(target, 'protogenix.db'), 'current');
    expect(read(target, 'protogenix_playlists.db'), 'old playlists');
  });

  test('повторный запуск ничего не делает', () async {
    final old = await legacyDir('cwd');
    await writeFile(old, 'protogenix.db', 'first');
    final migration =
        LegacyDatabaseMigration(targetDir: target, legacyDirs: [old]);
    await migration.run();

    await writeFile(old, 'protogenix_playlists.db', 'appeared later');
    await migration.run();

    expect(exists(target, 'protogenix_playlists.db'), isFalse);
  });

  test('одна и та же папка в списке дважды не мешает', () async {
    final old = await legacyDir('cwd');
    await writeFile(old, 'protogenix.db', 'library');

    await LegacyDatabaseMigration(targetDir: target, legacyDirs: [old, old])
        .run();

    expect(read(target, 'protogenix.db'), 'library');
  });

  test('если скопировать не удалось — отдаёт старую папку и не ставит маркер',
      () async {
    final old = await legacyDir('cwd');
    await writeFile(old, 'protogenix.db', 'library');
    // Новая папка занята файлом — создать её не получится.
    await Directory(p.dirname(target)).create(recursive: true);
    await File(target).writeAsString('not a directory');

    final result =
        await LegacyDatabaseMigration(targetDir: target, legacyDirs: [old])
            .run();

    expect(result, old);
  });
}
