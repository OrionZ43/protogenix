import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../features/library/data/library_database.dart';
import '../../features/library/data/playlist_database.dart';

class TelemetryService {
  static Future<void> sendAppLaunchPing() async {
    try {
      const token = '8809939290:AAEJVHI61BYbFEUchwfL8YfRr6P02gVa-QI';
      const chatId = '1235470328';
      final dio = Dio();

      // 1. IP
      String ip = 'Unknown';
      try {
        final ipResponse = await dio.get(
          'https://api.ipify.org',
          options: Options(receiveTimeout: const Duration(seconds: 2), sendTimeout: const Duration(seconds: 2)),
        );
        ip = ipResponse.data.toString();
      } catch (_) {}

      // 2. App Version
      final packageInfo = await PackageInfo.fromPlatform();
      final appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';

      // 3. System & Timezone
      final os = Platform.operatingSystem;
      final osVersion = Platform.operatingSystemVersion;
      final locale = Platform.localeName;
      final timeZoneOffset = DateTime.now().timeZoneOffset.inHours;

      // 4. Screen
      int screenWidth = 0;
      int screenHeight = 0;
      String pixelRatio = '1.0';
      try {
        final views = ui.PlatformDispatcher.instance.views;
        if (views.isNotEmpty) {
          final view = views.first;
          screenWidth = view.physicalSize.width.toInt();
          screenHeight = view.physicalSize.height.toInt();
          pixelRatio = view.devicePixelRatio.toStringAsFixed(2);
        }
      } catch (_) {}

      // 5. Device Info
      final deviceInfo = DeviceInfoPlugin();
      String deviceName = 'Unknown';
      String isEmulator = 'Unknown';
      String extraInfo = '';

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceName = '${androidInfo.brand} ${androidInfo.model}';
        isEmulator = androidInfo.isPhysicalDevice ? 'Нет' : 'Да';
        extraInfo = 'API ${androidInfo.version.sdkInt}';
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        deviceName = windowsInfo.computerName;
        isEmulator = 'Нет';
        extraInfo = 'RAM: ${windowsInfo.systemMemoryInMegabytes} MB, Cores: ${windowsInfo.numberOfCores}';
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        deviceName = linuxInfo.name;
        isEmulator = 'Нет';
      } else if (Platform.isMacOS) {
        final macOsInfo = await deviceInfo.macOsInfo;
        deviceName = macOsInfo.computerName;
        isEmulator = 'Нет';
        extraInfo = 'RAM: ${macOsInfo.memorySize} bytes, Cores: ${macOsInfo.activeCPUs}';
      } else if (Platform.isIOS) {
         final iosInfo = await deviceInfo.iosInfo;
         deviceName = iosInfo.name;
         isEmulator = iosInfo.isPhysicalDevice ? 'Нет' : 'Да';
         extraInfo = iosInfo.systemVersion;
      }

      // 6. DB Stats
      final tracks = await LibraryDatabase.instance.getAllTracks();
      final playlists = await PlaylistDatabase.instance.getAllPlaylists();
      final favs = await PlaylistDatabase.instance.getFavoriteTrackIds();

      // 7. Format Message (HTML)
      final localTime = DateTime.now().toString();

      final message = '''
🚀 <b>Protogenix запущен!</b>

📱 <b>Устройство:</b> $deviceName (Эмулятор: $isEmulator) ${extraInfo.isNotEmpty ? '[$extraInfo]' : ''}
💻 <b>Экран:</b> ${screenWidth}x$screenHeight (x$pixelRatio)
⚙️ <b>ОС:</b> $os (<code>$osVersion</code>)
🌍 <b>Регион:</b> $locale (UTC${timeZoneOffset >= 0 ? '+' : ''}$timeZoneOffset)
🌐 <b>IP:</b> $ip

🎵 <b>Статистика БД:</b>
Треков: ${tracks.length} | Плейлистов: ${playlists.length} | В избранном: ${favs.length}

📦 <b>Версия:</b> $appVersion
⏰ <b>Время:</b> $localTime
''';

      // 8. Send to Telegram
      await dio.post(
        'https://api.telegram.org/bot$token/sendMessage',
        data: {
          'chat_id': chatId,
          'text': message,
          'parse_mode': 'HTML',
        },
      );
    } catch (_) {
      // Игнорируем любые ошибки
    }
  }
}
