// lib/features/updater/updater_service.dart
//
// Сервис проверки обновлений через GitHub Releases API.
// Сравнивает текущую версию приложения с последним релизом на GitHub.

import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.releaseNotes,
    required this.releaseUrl,
    required this.publishedAt,
    this.downloadUrl,
    this.downloadSize,
  });

  final String version; // "v1.0.1"
  final String releaseNotes; // markdown из поля body
  final String releaseUrl; // ссылка на страницу релиза
  final DateTime publishedAt;
  final String? downloadUrl;
  final int? downloadSize;
}

class UpdaterService {
  static const _owner = 'OrionZ43';
  static const _repo = 'protogenix';
  static const _apiUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  /// Проверить наличие обновлений.
  /// Возвращает [UpdateInfo] если доступна новая версия, иначе null.
  /// Никогда не бросает исключений — при ошибке тихо возвращает null.
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // "1.0.0"

      final response = await http.get(
        Uri.parse(_apiUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final tagName = data['tag_name'] as String? ?? '';
      final releaseNotes = data['body'] as String? ?? '';
      final htmlUrl = data['html_url'] as String? ?? '';
      final publishedAtStr = data['published_at'] as String? ?? '';

      // Убираем "v" префикс из тега для сравнения
      final latestVersion =
          tagName.startsWith('v') ? tagName.substring(1) : tagName;

      if (latestVersion.isEmpty || htmlUrl.isEmpty) return null;

      // Сравниваем версии
      if (!_isNewer(latestVersion, currentVersion)) return null;

      debugPrint(
        '[Updater] Найдена новая версия: $latestVersion (текущая: $currentVersion)',
      );

      // Определяем нужный asset для текущей платформы
      String? downloadUrl;
      int? downloadSize;

      // Соглашение об именах assets в GitHub Release:
      //   protogenix-android.apk
      //   protogenix-windows.zip
      //   protogenix-linux.tar.gz
      // Содержимое ZIP и tar.gz: файлы приложения в корне архива (без вложенной папки).
      final assets = data['assets'] as List<dynamic>? ?? [];
      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        final browserUrl = asset['browser_download_url'] as String? ?? '';
        final size = asset['size'] as int? ?? 0;

        bool matches = false;
        if (Platform.isAndroid && name.endsWith('.apk')) matches = true;
        if (Platform.isWindows && name.contains('windows') && name.endsWith('.zip')) matches = true;
        if (Platform.isLinux && name.contains('linux') && name.endsWith('.tar.gz')) matches = true;

        if (matches && browserUrl.isNotEmpty) {
          downloadUrl = browserUrl;
          downloadSize = size;
          break;
        }
      }

      return UpdateInfo(
        version: tagName,
        releaseNotes: releaseNotes,
        releaseUrl: htmlUrl,
        publishedAt: publishedAtStr.isNotEmpty
            ? DateTime.tryParse(publishedAtStr) ?? DateTime.now()
            : DateTime.now(),
        downloadUrl: downloadUrl,
        downloadSize: downloadSize,
      );
    } catch (e) {
      // Тихая ошибка — не прерываем запуск приложения
      debugPrint('[Updater] Ошибка проверки обновлений: $e');
      return null;
    }
  }

  /// Сравнение семантических версий.
  /// Возвращает true если [latest] новее чем [current].
  static bool _isNewer(String latest, String current) {
    try {
      final latestParts = latest.split('.').map(int.parse).toList();
      final currentParts = current.split('.').map(int.parse).toList();

      // Выравниваем длину до 3 частей
      while (latestParts.length < 3) {
        latestParts.add(0);
      }
      while (currentParts.length < 3) {
        currentParts.add(0);
      }

      for (int i = 0; i < 3; i++) {
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }
      return false; // версии равны
    } catch (_) {
      return false;
    }
  }
}
