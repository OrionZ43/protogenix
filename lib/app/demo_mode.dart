// lib/app/demo_mode.dart
//
// Режим записи демо для сайта (tool/record_demo.ps1). Приложение само
// включает трек с нужного места, открывает развёрнутый плеер поверх всех окон
// и пишет в %TEMP%\protogenix_demo_sync.csv пары «время на часах — позиция
// трека». По ним звук из файла трека сводится с записью экрана точно в такт
// тому, что показывает караоке.
//
// Включается только сборкой с флагами. В обычной сборке константы пустые, и
// компилятор этот код выбрасывает:
//   flutter build windows --release
//     --dart-define=PROTOGENIX_DEMO_TRACK=<id трека в медиатеке>
//     --dart-define=PROTOGENIX_DEMO_START_MS=<позиция старта в мс>

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../features/library/data/library_database.dart';
import '../features/player/data/audio_handler.dart';
import '../features/player/presentation/providers/player_provider.dart';

const kDemoTrackId = String.fromEnvironment('PROTOGENIX_DEMO_TRACK');
const kDemoStartMs = int.fromEnvironment('PROTOGENIX_DEMO_START_MS');
const kIsDemo = kDemoTrackId != '';

/// Включает демо-трек. false — такого трека нет в медиатеке.
Future<bool> startDemo(WidgetRef ref) async {
  // При запуске плеер сам грузит всю медиатеку — ждём, иначе она перетрёт
  // очередь демо.
  for (var i = 0; i < 100; i++) {
    final s = ref.read(playerProvider);
    if (s.queue.isNotEmpty && !s.isLoading) break;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  final tracks = await LibraryDatabase.instance.getAllTracks();
  final match = tracks.where((t) => t.id == kDemoTrackId).toList();
  if (match.isEmpty) {
    debugPrint('[Demo] Трека $kDemoTrackId нет в медиатеке');
    return false;
  }
  final notifier = ref.read(playerProvider.notifier);
  await notifier.loadPlaylist([match.first.toTrackModel()]);
  await notifier.seekTo(const Duration(milliseconds: kDemoStartMs));
  _writeSyncLog();
  await notifier.play();
  return true;
}

/// Две минуты пар «микросекунды на часах, позиция трека в микросекундах»,
/// только пока трек играет.
void _writeSyncLog() {
  final file =
      File(p.join(Directory.systemTemp.path, 'protogenix_demo_sync.csv'));
  final sink = file.openWrite();
  final player = (audioHandler as ProtogenixAudioHandler).player;
  final sub = player.positionStream.listen((pos) {
    if (!player.playing) return;
    sink.writeln(
        '${DateTime.now().microsecondsSinceEpoch},${pos.inMicroseconds}');
  });
  Timer(const Duration(minutes: 2), () async {
    await sub.cancel();
    await sink.close();
  });
}
