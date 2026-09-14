// lib/features/importer/data/device_music.dart
//
// Музыка на телефоне (Android) — «как в других плеерах», просили в отзывах.
// Список берётся из MediaStore через свой канал в MainActivity.kt:
// on_audio_query в архиве и на AGP 8 не собирается, а свой запрос — это
// один метод. Файлы не копируются: трек играет с места (source 'device'),
// и удаление трека в приложении сам файл не трогает (library_provider.dart).

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class DeviceTrack {
  const DeviceTrack({
    required this.path,
    this.title,
    this.artist,
    this.album,
    this.durationMs,
  });

  final String path;
  final String? title;
  final String? artist;
  final String? album;
  final int? durationMs;

  /// null — запись без пути. «<unknown>» (так MediaStore пишет пустого
  /// исполнителя) — как нет значения.
  static DeviceTrack? fromMap(Map<Object?, Object?> map) {
    final path = map['path'];
    if (path is! String || path.isEmpty) return null;
    final duration = map['durationMs'];
    return DeviceTrack(
      path: path,
      title: _text(map['title']),
      artist: _text(map['artist']),
      album: _text(map['album']),
      durationMs: duration is num && duration > 0 ? duration.toInt() : null,
    );
  }

  static String? _text(Object? value) {
    final text =
        value?.toString().replaceAll(RegExp(r'[\x00-\x1F\x7F-\x9F]'), '').trim();
    return text == null || text.isEmpty || text == '<unknown>' ? null : text;
  }
}

class DeviceMusic {
  DeviceMusic._();

  static const _channel = MethodChannel('z43.studios.protogenix/media');

  /// Доступ к аудио: READ_MEDIA_AUDIO на Android 13+, READ_EXTERNAL_STORAGE
  /// ниже (оба объявлены в AndroidManifest.xml).
  static Future<PermissionStatus> requestPermission() async {
    final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    return (sdk >= 33 ? Permission.audio : Permission.storage).request();
  }

  /// Музыка не короче 30 секунд, новые сверху (фильтр — в MainActivity.kt).
  static Future<List<DeviceTrack>> query() async {
    final raw = await _channel
            .invokeListMethod<Map<Object?, Object?>>('queryAudio') ??
        const [];
    return [
      for (final map in raw)
        if (DeviceTrack.fromMap(map) case final track?) track,
    ];
  }
}
