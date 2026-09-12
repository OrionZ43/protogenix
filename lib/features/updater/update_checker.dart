// lib/features/updater/update_checker.dart
//
// Проверка обновлений: скачивает подписанный манифест, проверяет подпись,
// сравнивает номер сборки и выбирает файл под это устройство.

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'update_envelope.dart';
import 'update_keys.dart';
import 'update_manifest.dart';

/// Найденное обновление.
class AvailableUpdate {
  const AvailableUpdate({
    required this.manifest,
    required this.asset,
    required this.isMandatory,
  });

  final UpdateManifest manifest;

  /// Файл для этого устройства; null — в релизе его нет, остаётся
  /// страница релиза.
  final UpdateAsset? asset;

  /// Текущая сборка ниже minSupportedBuild — баннер нельзя скрыть.
  final bool isMandatory;
}

/// Чем кончилась проверка обновлений.
enum UpdateCheckOutcome {
  /// Есть сборка новее.
  available,

  /// Опубликованная сборка не новее текущей.
  upToDate,

  /// Ни один адрес не ответил или подпись не сошлась: неизвестно, есть ли
  /// обновление.
  failed,

  /// Ключей подписи нет — проверка выключена.
  disabled,
}

class UpdateCheckResult {
  const UpdateCheckResult(this.outcome, [this.update]);

  final UpdateCheckOutcome outcome;

  /// Только при [UpdateCheckOutcome.available].
  final AvailableUpdate? update;
}

class UpdateChecker {
  UpdateChecker({
    Dio? dio,
    List<Uri>? manifestUrls,
    Map<String, List<int>>? trustedKeys,
  })  : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            )),
        _manifestUrls = manifestUrls ?? defaultManifestUrls,
        _trustedKeys = trustedKeys ?? decodeUpdateSigningKeys();

  /// Где искать манифест. Сейчас только GitHub Releases (решение Orion,
  /// release.md); зеркало добавляется ещё одним адресом. Это обычная
  /// загрузка файла, а не API, поэтому лимита 60 запросов в час нет.
  static final defaultManifestUrls = [
    Uri.parse(
      'https://github.com/OrionZ43/protogenix/releases/latest/download/'
      '${UpdateEnvelope.fileName}',
    ),
  ];

  final Dio _dio;
  final List<Uri> _manifestUrls;
  final Map<String, List<int>> _trustedKeys;

  /// Обновление или null: новее нет, сети нет, подпись не сошлась.
  /// Ошибки наружу не бросает — только пишет в лог. Чем именно кончилась
  /// проверка, говорит [checkDetailed].
  Future<AvailableUpdate?> check({
    required int currentBuild,
    required List<String> assetKeys,
  }) async =>
      (await checkDetailed(currentBuild: currentBuild, assetKeys: assetKeys))
          .update;

  /// То же, что [check], но отличает «новее нет» от «проверить не удалось»:
  /// странице «Инфо» нельзя писать «последняя версия», когда нет сети.
  /// Берётся первый ответивший адрес; ошибки только пишутся в лог.
  Future<UpdateCheckResult> checkDetailed({
    required int currentBuild,
    required List<String> assetKeys,
  }) async {
    if (_trustedKeys.isEmpty) {
      debugPrint('[Updater] Ключ подписи не задан (update_keys.dart) — '
          'проверка обновлений выключена');
      return const UpdateCheckResult(UpdateCheckOutcome.disabled);
    }

    for (final url in _manifestUrls) {
      try {
        final response = await _dio.getUri<String>(
          url,
          options: Options(responseType: ResponseType.plain),
        );
        final manifest = await UpdateEnvelope.verifyAndParse(
          response.data ?? '',
          _trustedKeys,
        );
        if (manifest.build <= currentBuild) {
          return const UpdateCheckResult(UpdateCheckOutcome.upToDate);
        }
        return UpdateCheckResult(
          UpdateCheckOutcome.available,
          AvailableUpdate(
            manifest: manifest,
            asset: manifest.assetFor(assetKeys),
            isMandatory: currentBuild < manifest.minSupportedBuild,
          ),
        );
      } catch (e) {
        debugPrint('[Updater] Не удалось проверить обновления ($url): $e');
      }
    }
    return const UpdateCheckResult(UpdateCheckOutcome.failed);
  }
}

/// Ключи файлов для Android в порядке предпочтения: сначала архитектуры
/// устройства, потом универсальный APK.
List<String> androidAssetKeys(List<String> supportedAbis) => [
      for (final abi in supportedAbis) 'android-$abi',
      'android-universal',
    ];

/// Ключи файлов для текущего устройства.
Future<List<String>> currentAssetKeys() async {
  if (Platform.isAndroid) {
    final info = await DeviceInfoPlugin().androidInfo;
    return androidAssetKeys(info.supportedAbis);
  }
  if (Platform.isWindows) return const ['windows-x64'];
  return const [];
}

/// Номер сборки (`+N` из pubspec). На Windows package_info_plus берёт его
/// из ProductVersion exe.
Future<int> currentBuildNumber() async {
  final info = await PackageInfo.fromPlatform();
  return int.tryParse(info.buildNumber) ?? 0;
}
