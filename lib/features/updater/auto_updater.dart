// lib/features/updater/auto_updater.dart
//
// Скачивает обновление с GitHub и устанавливает его платформо-зависимым способом.
//
// Android  — скачиваем APK → OpenFile.open() → системный установщик
// Windows  — скачиваем ZIP → пишем .ps1 → detached Process → exit(0)
// Linux    — скачиваем .tar.gz → пишем .sh → detached Process → exit(0)

import 'dart:convert' show utf8;
import 'dart:io' show exit, File, Platform, Process, ProcessStartMode;
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'updater_service.dart';

enum DownloadState { idle, downloading, installing, done, error }

class DownloadProgress {
  const DownloadProgress({
    required this.state,
    this.progress = 0.0,   // 0.0..1.0
    this.errorMsg,
  });

  final DownloadState state;
  final double progress;
  final String? errorMsg;
}

class AutoUpdater {
  /// Скачать и установить обновление.
  /// Вызывает [onProgress] при каждом изменении состояния.
  static Future<void> downloadAndInstall(
    UpdateInfo info,
    void Function(DownloadProgress) onProgress,
  ) async {
    if (info.downloadUrl == null) {
      onProgress(const DownloadProgress(
        state: DownloadState.error,
        errorMsg: 'Нет ссылки для скачивания',
      ));
      return;
    }

    try {
      // ── 1. Скачать ──────────────────────────────────────────────────────
      final tempDir = await getTemporaryDirectory();
      final fileName = info.downloadUrl!.split('/').last;
      final savePath = '${tempDir.path}${Platform.pathSeparator}$fileName';

      final dio = Dio();
      await dio.download(
        info.downloadUrl!,
        savePath,
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          onProgress(DownloadProgress(
            state: DownloadState.downloading,
            progress: received / total,
          ));
        },
      );

      // ── 2. Установить ───────────────────────────────────────────────────
      onProgress(const DownloadProgress(state: DownloadState.installing));

      if (Platform.isAndroid) {
        await _installAndroid(savePath);
      } else if (Platform.isWindows) {
        await _installWindows(savePath, tempDir.path);
      } else if (Platform.isLinux) {
        await _installLinux(savePath, tempDir.path);
      } else {
        // Неподдерживаемая платформа — фолбэк не нужен здесь,
        // баннер проверит downloadUrl перед вызовом
        onProgress(const DownloadProgress(
          state: DownloadState.error,
          errorMsg: 'Автообновление не поддерживается',
        ));
      }
    } catch (e) {
      debugPrint('[AutoUpdater] Ошибка: $e');
      onProgress(const DownloadProgress(
        state: DownloadState.error,
        errorMsg: 'Ошибка скачивания',
      ));
    }
  }

  static Future<void> _installAndroid(String apkPath) async {
    // Запрашиваем разрешение на установку из неизвестных источников
    final status = await Permission.requestInstallPackages.status;
    if (!status.isGranted) {
      await Permission.requestInstallPackages.request();
    }
    // Открываем APK — система показывает диалог установки
    await OpenFile.open(apkPath);
    // Не вызываем exit() — система сама перезапустит после установки
  }

  static Future<void> _installWindows(String zipPath, String tempDir) async {
    final exePath = Platform.resolvedExecutable; // C:\...\protogenix.exe
    final appDir = File(exePath).parent.path;
    final extractDir = '$tempDir${Platform.pathSeparator}update_extract';

    // PowerShell-скрипт: ждёт завершения старого процесса,
    // распаковывает ZIP во временную папку, копирует поверх, удаляет временные файлы и перезапускает.
    final ps1 = '''
\$ErrorActionPreference = 'Stop'
Start-Sleep -Seconds 3

# Распаковать ZIP во временную папку
if (Test-Path "$extractDir") { Remove-Item -Recurse -Force "$extractDir" }
Expand-Archive -Force -Path "$zipPath" -DestinationPath "$extractDir"

# Скопировать содержимое поверх директории приложения
Copy-Item -Recurse -Force "$extractDir\\*" "$appDir\\"

# Удалить временные файлы
Remove-Item -Recurse -Force "$extractDir"
Remove-Item -Force "$zipPath"

# Перезапустить приложение
Start-Process "$exePath"
''';

    final scriptPath = '$tempDir${Platform.pathSeparator}protogenix_update.ps1';
    await File(scriptPath).writeAsString(ps1, encoding: utf8);

    // Запускаем PS1 как полностью отсоединённый процесс
    await Process.start(
      'powershell.exe',
      ['-ExecutionPolicy', 'Bypass', '-NonInteractive', '-File', scriptPath],
      mode: ProcessStartMode.detached,
      runInShell: false,
    );

    // Закрываем приложение — теперь .exe не заблокирован
    exit(0);
  }

  static Future<void> _installLinux(String tarPath, String tempDir) async {
    final exePath = Platform.resolvedExecutable;
    final appDir = File(exePath).parent.path;
    final extractDir = '$tempDir/update_extract';

    final sh = '''
#!/bin/bash
set -e
sleep 3

# Распаковать архив во временную папку
rm -rf "$extractDir"
mkdir -p "$extractDir"
tar -xzf "$tarPath" -C "$extractDir"

# Скопировать содержимое поверх директории приложения
cp -rf "$extractDir"/. "$appDir/"

# Убедиться что бинарник исполняемый
chmod +x "$exePath"

# Удалить временные файлы
rm -rf "$extractDir"
rm -f "$tarPath"

# Перезапустить приложение
"$exePath" &
''';

    final scriptPath = '$tempDir/protogenix_update.sh';
    await File(scriptPath).writeAsString(sh);
    await Process.run('chmod', ['+x', scriptPath]);

    await Process.start(
      '/bin/bash',
      [scriptPath],
      mode: ProcessStartMode.detached,
    );

    exit(0);
  }
}
