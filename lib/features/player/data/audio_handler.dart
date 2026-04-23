// lib/features/player/data/audio_handler.dart
//
// Фоновое воспроизведение через audio_service.
// Плеер работает при свёрнутом приложении, управляется с экрана блокировки
// и шторки уведомлений (Android) / Control Center (iOS).
//
// Установка:
//   flutter pub add audio_service
//
// pubspec.yaml:
//   audio_service: ^0.18.13
//
// AndroidManifest.xml → добавить внутрь <application>:
//   <service android:name="com.ryanheise.audioservice.AudioServiceFragmentationShimService"
//             android:foregroundServiceType="mediaPlayback"
//             android:exported="false" />
//
// Info.plist (iOS):
//   <key>UIBackgroundModes</key>
//   <array><string>audio</string></array>

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// Глобальный экземпляр — инициализируется в main()
late AudioHandler audioHandler;

/// Инициализирует audio_service. Вызывать ОДИН РАЗ в main() до runApp().
Future<void> initAudioService() async {
  audioHandler = await AudioService.init(
    builder: () => ProtogenixAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.protogenix.audio',
      androidNotificationChannelName: 'Protogenix Player',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      notificationColor: null,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// AUDIO HANDLER
// ─────────────────────────────────────────────────────────────────────────────

class ProtogenixAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  ProtogenixAudioHandler() {
    _init();
  }

  // ── Инициализация стримов ──────────────────────────────────────────────────

  void _init() {
    // Транслируем состояние just_audio → audio_service
    _player.playbackEventStream.listen(_broadcastState);

    _player.currentIndexStream.listen((index) {
      if (index != null && index < queue.value.length) {
        mediaItem.add(queue.value[index]);
      }
    });

    _player.durationStream.listen((duration) {
      final item = mediaItem.valueOrNull;
      if (item != null && duration != null) {
        mediaItem.add(item.copyWith(duration: duration));
      }
    });
  }

  // ── Загрузка плейлиста ─────────────────────────────────────────────────────

  Future<void> loadPlaylist({
    required List<MediaItem> items,
    required List<AudioSource> sources,
    int initialIndex = 0,
  }) async {
    queue.add(items);
    if (items.isNotEmpty) {
      mediaItem.add(items[initialIndex]);
    }

    final playlist = ConcatenatingAudioSource(children: sources);
    await _player.setAudioSource(
      playlist,
      initialIndex: initialIndex,
      preload: false,
    );
  }

  // ── Базовые команды (экран блокировки, шторка уведомлений) ────────────────

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    await _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
    } else {
      await _player.seekToPrevious();
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await _player.seek(Duration.zero, index: index);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode != AudioServiceShuffleMode.none;
    await _player.setShuffleModeEnabled(enabled);
    await super.setShuffleMode(shuffleMode);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final loopMode = switch (repeatMode) {
      AudioServiceRepeatMode.none => LoopMode.off,
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all => LoopMode.all,
      AudioServiceRepeatMode.group => LoopMode.all,
    };
    await _player.setLoopMode(loopMode);
    await super.setRepeatMode(repeatMode);
  }

  // ── Публичный доступ к плееру ──────────────────────────────────────────────

  AudioPlayer get player => _player;

  // ── Трансляция состояния ───────────────────────────────────────────────────

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    ));
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }
}
