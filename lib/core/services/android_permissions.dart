// lib/core/services/android_permissions.dart
//
// Разрешения Android — без пакета permission_handler.
//
// permission_handler тянет на Windows свою реализацию, а
// permission_handler_windows 0.2.1 при каждом запуске подписывается на
// Geolocator.PositionChanged: Windows включает отслеживание местоположения,
// новым пользователям показывает «Разрешить доступ к местоположению?» и
// записывает Protogenix в журнал местоположения (координаты при этом никто
// не читает). Разрешения нам нужны только на Android, поэтому зависим
// напрямую от Android-реализации и общего интерфейса — на Windows плагина нет
// вовсе (known-issues.md).

import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

export 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart'
    show Permission, PermissionStatus, PermissionStatusGetters;

PermissionHandlerPlatform get _platform => PermissionHandlerPlatform.instance;

/// Текущее состояние разрешения.
Future<PermissionStatus> androidPermissionStatus(Permission permission) =>
    _platform.checkPermissionStatus(permission);

/// Запросить разрешение — системный диалог показывает Android.
Future<PermissionStatus> requestAndroidPermission(Permission permission) async {
  final result = await _platform.requestPermissions([permission]);
  return result[permission] ?? PermissionStatus.denied;
}

/// Открыть настройки приложения (разрешение отклонено навсегда).
Future<bool> openAndroidAppSettings() => _platform.openAppSettings();
