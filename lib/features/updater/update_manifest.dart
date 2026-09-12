// lib/features/updater/update_manifest.dart
//
// Манифест релиза: что вышло и откуда качать. Публикуется в каждом GitHub
// Release внутри подписанной обёртки protogenix-update.json
// (см. update_envelope.dart).
//
// {
//   "version": "1.1.0",              // для показа пользователю
//   "build": 12,                     // сравнение версий — только по нему
//   "minSupportedBuild": 9,          // ниже этой сборки обновление обязательное
//   "publishedAt": "2026-10-01T12:00:00Z",
//   "notes": "Что нового…",
//   "message": null,                 // объявление для всех, необязательно
//   "releaseUrl": "https://github.com/OrionZ43/protogenix/releases/tag/v1.1.0",
//   "assets": {
//     "android-arm64-v8a": {"urls": ["https://…"], "size": 21000000, "sha256": "…"},
//     "android-universal": { … },
//     "windows-x64":       { … }
//   }
// }
//
// Файл без Flutter-импортов: его использует и tool/update_signing.dart.

import 'package:path/path.dart' as p;

class UpdateAsset {
  const UpdateAsset({
    required this.urls,
    required this.size,
    required this.sha256,
  });

  factory UpdateAsset.fromJson(Map<String, dynamic> json) {
    final rawUrls = json['urls'];
    if (rawUrls is! List || rawUrls.isEmpty) {
      throw const FormatException('У файла нет адресов');
    }
    final urls = <Uri>[];
    for (final raw in rawUrls) {
      final uri = raw is String ? Uri.tryParse(raw) : null;
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        throw FormatException('Адрес файла должен быть https: $raw');
      }
      urls.add(uri);
    }

    final size = json['size'];
    if (size is! int || size <= 0 || size > maxSize) {
      throw FormatException('Недопустимый размер файла: $size');
    }

    final hash = json['sha256'];
    if (hash is! String || !_sha256Pattern.hasMatch(hash)) {
      throw FormatException('Недопустимый SHA-256: $hash');
    }

    return UpdateAsset(urls: urls, size: size, sha256: hash.toLowerCase());
  }

  /// Верхняя граница размера — защита от забивания диска.
  static const maxSize = 1024 * 1024 * 1024;
  static final _sha256Pattern = RegExp(r'^[0-9a-fA-F]{64}$');

  /// Адреса в порядке попытки; при сбое берётся следующий.
  final List<Uri> urls;
  final int size;

  /// SHA-256 в нижнем регистре.
  final String sha256;

  /// Имя для сохранения на диск: последний сегмент первого адреса,
  /// очищенный по правилам security.md.
  String get fileName {
    final segments = urls.first.pathSegments;
    final raw = segments.isEmpty ? '' : p.basename(segments.last);
    final safe = raw.replaceAll(RegExp(r'[^a-zA-Z0-9\.\-\_]'), '_');
    if (safe.isEmpty || safe == '.' || safe == '..') {
      return 'protogenix-update.bin';
    }
    return safe;
  }
}

class UpdateManifest {
  const UpdateManifest({
    required this.version,
    required this.build,
    required this.minSupportedBuild,
    required this.notes,
    required this.assets,
    this.message,
    this.releaseUrl,
    this.publishedAt,
  });

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! String || version.trim().isEmpty) {
      throw const FormatException('В манифесте нет версии');
    }

    final build = json['build'];
    if (build is! int || build <= 0) {
      throw FormatException('Недопустимый номер сборки: $build');
    }

    final minSupported = json['minSupportedBuild'] ?? 0;
    if (minSupported is! int || minSupported < 0) {
      throw FormatException('Недопустимый minSupportedBuild: $minSupported');
    }

    final rawAssets = json['assets'];
    if (rawAssets is! Map) {
      throw const FormatException('В манифесте нет списка файлов');
    }
    final assets = <String, UpdateAsset>{};
    rawAssets.forEach((key, value) {
      if (key is! String || value is! Map<String, dynamic>) {
        throw FormatException('Некорректное описание файла: $key');
      }
      assets[key] = UpdateAsset.fromJson(value);
    });

    final notes = json['notes'];
    final message = json['message'];
    final releaseUrl = json['releaseUrl'] is String
        ? Uri.tryParse(json['releaseUrl'] as String)
        : null;
    final publishedAt = json['publishedAt'] is String
        ? DateTime.tryParse(json['publishedAt'] as String)
        : null;

    return UpdateManifest(
      version: version.trim(),
      build: build,
      minSupportedBuild: minSupported,
      notes: notes is String ? notes.trim() : '',
      message: message is String && message.trim().isNotEmpty
          ? message.trim()
          : null,
      releaseUrl:
          releaseUrl != null && releaseUrl.scheme == 'https' ? releaseUrl : null,
      publishedAt: publishedAt,
      assets: Map.unmodifiable(assets),
    );
  }

  final String version;
  final int build;
  final int minSupportedBuild;
  final String notes;
  final String? message;
  final Uri? releaseUrl;
  final DateTime? publishedAt;

  /// Ключ платформы (`android-arm64-v8a`, `windows-x64`…) → файл.
  final Map<String, UpdateAsset> assets;

  /// Первый файл из [preferredKeys], который есть в релизе.
  UpdateAsset? assetFor(List<String> preferredKeys) {
    for (final key in preferredKeys) {
      final asset = assets[key];
      if (asset != null) return asset;
    }
    return null;
  }
}
