// lib/core/services/app_paths.dart
//
// Единое место, где решается, куда приложение складывает данные.
//
// Android / iOS / macOS — как раньше: базы в getDatabasesPath(), файлы в папке
// документов приложения (на мобильных она приватная).
//
// Windows / Linux — постоянная папка, не зависящая от рабочей папки процесса:
//   Windows: %LOCALAPPDATA%\Z43 Studios\Protogenix
//   Linux:   getApplicationSupportDirectory() (~/.local/share/<id приложения>)
// Внутри: databases/, music/, covers/, lyrics/, audio_cache/.
// При первом запуске базы переносятся со старого места (LegacyDatabaseMigration).
//
// init() обязан отработать в main() до первого обращения к базам и файлам.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'legacy_data_migration.dart';

class AppPaths {
  AppPaths._();

  /// Папка с файлами баз данных.
  static late String databasesDir;

  /// Корень для скачанной музыки, обложек, текстов и кэша.
  static late String dataDir;

  static String get musicDir => p.join(dataDir, 'music');
  static String get coversDir => p.join(dataDir, 'covers');
  static String get lyricsDir => p.join(dataDir, 'lyrics');
  static String get audioCacheDir => p.join(dataDir, 'audio_cache');

  static Future<void> init() async {
    if (!Platform.isWindows && !Platform.isLinux) {
      databasesDir = await getDatabasesPath();
      dataDir = (await getApplicationDocumentsDirectory()).path;
      return;
    }

    dataDir = await _desktopDataDir();
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    databasesDir = await LegacyDatabaseMigration(
      targetDir: p.join(dataDir, 'databases'),
      legacyDirs: [
        LegacyDatabaseMigration.legacyDirFor(Directory.current.path),
        LegacyDatabaseMigration.legacyDirFor(exeDir),
      ],
    ).run();
  }

  /// На Windows путь задан явно, а не через getApplicationSupportDirectory():
  /// тот строит путь из CompanyName/ProductName в Runner.rc, и правка
  /// метаданных exe молча увела бы данные в новую пустую папку.
  static Future<String> _desktopDataDir() async {
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        return p.join(localAppData, 'Z43 Studios', 'Protogenix');
      }
    }
    return (await getApplicationSupportDirectory()).path;
  }
}
