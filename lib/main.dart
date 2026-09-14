import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:window_manager/window_manager.dart';
// lib/main.dart
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'app/demo_mode.dart';
import 'core/services/app_paths.dart';
import 'features/importer/data/local_tags_migration.dart';
import 'features/listen/presentation/listen_links.dart';
import 'features/player/data/audio_handler.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Windows: ссылка «Слушать в Protogenix» приходит аргументом запуска
  setLaunchArguments(args);

  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Куда складывать базы и файлы; на десктопе — ещё и перенос баз со старого
  // места. Должно отработать до первого обращения к базам.
  await AppPaths.init();

  // Один раз после обновления: теги своих файлов, добавленных до 1.1.
  // До загрузки плеера — чтобы очередь сразу получила новые названия.
  await LocalTagsMigration.runOnce();

  if (Platform.isAndroid || Platform.isIOS) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        // Иначе под тремя кнопками навигации Android рисует светлую подложку:
        // тёмный интерфейс перечёркивала серая полоса
        systemNavigationBarContrastEnforced: false,
      ),
    );
  }

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      // Запись демо (demo_mode.dart) — окно под пропорции картинки на сайте
      size: kIsDemo ? Size(1280, 853) : Size(1000, 700),
      minimumSize: Size(1000, 700),
      maximumSize: Size(2560, 1440),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setMinimumSize(const Size(1000, 700));
      await windowManager.setMaximumSize(const Size(2560, 1440));
    });
  }

  // For Windows/Linux desktop audio we must initialize media_kit for just_audio
  if (Platform.isWindows || Platform.isLinux) {
    JustAudioMediaKit.ensureInitialized();
  }

  // Инициализируем фоновое воспроизведение ПЕРЕД runApp
  await initAudioService();

  runApp(
    const ProviderScope(
      child: ProtogenixApp(),
    ),
  );
}
