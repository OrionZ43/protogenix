// lib/core/services/legacy_data_migration.dart
//
// Перенос баз данных десктопной версии со старого места.
//
// До сентября 2026 на Windows/Linux базы лежали там, куда их по умолчанию
// кладёт sqflite_common_ffi: `<рабочая папка процесса>/.dart_tool/
// sqflite_common_ffi/databases`. Путь зависел от того, откуда запустили
// приложение, а установщик или обновление могли снести его вместе с папкой
// программы.
//
// Правила переноса:
//   • файлы КОПИРУЮТСЯ — старые остаются резервной копией;
//   • база, которая уже есть на новом месте, никогда не перезаписывается;
//   • перенос выполняется один раз (файл-маркер в новой папке);
//   • музыку, обложки и тексты не трогаем: пути к ним в базе абсолютные
//     и продолжают работать.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class LegacyDatabaseMigration {
  LegacyDatabaseMigration({
    required this.targetDir,
    required this.legacyDirs,
  });

  /// Новая папка для баз.
  final String targetDir;

  /// Где базы могли лежать раньше.
  final List<String> legacyDirs;

  static const databaseNames = ['protogenix.db', 'protogenix_playlists.db'];

  /// Служебные файлы SQLite. Копируются вместе с базой, чтобы не потерять
  /// незавершённую транзакцию.
  static const _sidecarSuffixes = ['-journal', '-wal', '-shm'];

  static const markerName = '.legacy_migration_done';

  /// Папка, которую sqflite_common_ffi использовал по умолчанию, если
  /// процесс был запущен из [baseDir].
  static String legacyDirFor(String baseDir) =>
      p.join(baseDir, '.dart_tool', 'sqflite_common_ffi', 'databases');

  /// Выполняет перенос и возвращает папку, из которой читать базы в этой
  /// сессии.
  ///
  /// Обычно это [targetDir]. Если скопировать не удалось, возвращается
  /// старая папка — чтобы пользователь не увидел пустую библиотеку; маркер
  /// тогда не ставится, и перенос повторится при следующем запуске.
  Future<String> run() async {
    if (await File(p.join(targetDir, markerName)).exists()) return targetDir;

    final source = await _pickSourceDir();
    try {
      await Directory(targetDir).create(recursive: true);
      if (source != null) {
        for (final name in databaseNames) {
          await _copyDatabase(p.join(source, name), p.join(targetDir, name));
        }
        debugPrint('[Migration] Базы скопированы из $source в $targetDir');
      }
      await File(p.join(targetDir, markerName))
          .writeAsString(DateTime.now().toIso8601String());
      return targetDir;
    } catch (e) {
      debugPrint('[Migration] Не удалось перенести базы: $e');
      return source ?? targetDir;
    }
  }

  /// Старая папка, где базы менялись последними.
  Future<String?> _pickSourceDir() async {
    final target = p.canonicalize(targetDir);
    final seen = <String>{};
    String? best;
    DateTime? bestTime;

    for (final dir in legacyDirs) {
      final key = p.canonicalize(dir);
      if (key == target || !seen.add(key)) continue;

      for (final name in databaseNames) {
        final file = File(p.join(dir, name));
        if (!await file.exists()) continue;
        final modified = await file.lastModified();
        if (bestTime == null || modified.isAfter(bestTime)) {
          best = dir;
          bestTime = modified;
        }
      }
    }
    return best;
  }

  Future<void> _copyDatabase(String sourcePath, String targetPath) async {
    final source = File(sourcePath);
    if (!await source.exists()) return;
    if (await File(targetPath).exists()) return;

    // Служебные файлы идут первыми, сама база — последней: раз база есть
    // на новом месте, значит копирование завершено.
    for (final suffix in _sidecarSuffixes) {
      final sidecar = File('$sourcePath$suffix');
      if (await sidecar.exists()) {
        await _atomicCopy(sidecar, '$targetPath$suffix');
      }
    }
    await _atomicCopy(source, targetPath);
  }

  /// Копирует через временный файл: оборванное копирование не оставит
  /// на новом месте недописанный файл.
  Future<void> _atomicCopy(File source, String targetPath) async {
    // Сюда доходят только служебные файлы от прерванной попытки —
    // существующую базу _copyDatabase не трогает.
    final target = File(targetPath);
    if (await target.exists()) await target.delete();

    final tmp = await source.copy('$targetPath.tmp');
    await tmp.rename(targetPath);
  }
}
