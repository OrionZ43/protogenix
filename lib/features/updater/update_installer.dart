// lib/features/updater/update_installer.dart
//
// Установка скачанного и проверенного файла.
//   Android — системный установщик APK. Разрешение «установка неизвестных
//             приложений» запрашивается один раз; подтверждает пользователь.
//   Windows — тихий запуск установщика Inno Setup и выход из приложения:
//             установщик дождётся закрытия, заменит файлы (при сбое
//             откатится) и запустит новую версию (release.md).
//   Остальные платформы — не поддерживаются, баннер ведёт на страницу релиза.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;

import '../../core/services/android_permissions.dart';

class UpdateInstallException implements Exception {
  const UpdateInstallException(this.message);

  /// Текст для пользователя.
  final String message;

  @override
  String toString() => 'UpdateInstallException: $message';
}

class UpdateInstaller {
  UpdateInstaller._();

  static bool get isSupported => Platform.isAndroid || Platform.isWindows;

  static Future<void> install(File file) async {
    if (Platform.isAndroid) return _installAndroid(file);
    if (Platform.isWindows) return _installWindows(file);
    throw const UpdateInstallException(
        'На этой платформе обновление ставится вручную');
  }

  static Future<void> _installAndroid(File apk) async {
    var status = await androidPermissionStatus(Permission.requestInstallPackages);
    if (!status.isGranted) {
      status = await requestAndroidPermission(Permission.requestInstallPackages);
    }
    if (!status.isGranted) {
      throw const UpdateInstallException(
          'Разреши Protogenix устанавливать приложения — '
          'без этого обновление не поставить');
    }

    final result = await OpenFile.open(
      apk.path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      debugPrint('[Updater] OpenFile: ${result.type} ${result.message}');
      throw const UpdateInstallException('Не удалось открыть установщик');
    }
  }

  static Future<void> _installWindows(File setup) async {
    final log = p.join(Directory.systemTemp.path, 'protogenix-update.log');
    await Process.start(
      setup.path,
      windowsInstallerArguments(log),
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  /// Ключи Inno Setup: без окон и вопросов, без перезагрузки системы;
  /// `/update=1` — после замены файлов установщик снова запускает
  /// приложение.
  @visibleForTesting
  static List<String> windowsInstallerArguments(String logPath) => [
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/update=1',
        '/LOG=$logPath',
      ];
}
