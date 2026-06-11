// lib/features/player/presentation/providers/player_provider.dart
//
// Объединенная версия:
// 1. Оптимизация загрузки больших плейлистов (от Bolt: Future.microtask + Iterable)
// 2. Плавная пауза (Smooth Fade Out)
// 3. Эквалайзер (EQ)
// 4. Таймер сна (Sleep Timer / Stop after track)

import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../../data/audio_handler.dart';
import '../../domain/player_state.dart';
import '../../domain/track_model.dart';
import 'palette_provider.dart';
import '../../../library/data/library_database.dart';

class PlayerNotifier extends StateNotifier<ProtogenixPlayerState> {
  PlayerNotifier(this._ref) : super(const ProtogenixPlayerState()) {
    _init();
  }

  final Ref _ref;

  ProtogenixAudioHandler get _handler => audioHandler as ProtogenixAudioHandler;

  AudioPlayer get _player => _handler.player;

  // ── Таймер сна ───────────────────────────────────────────────────────────
  Timer? _sleepTimer;

  /// Индекс трека, после которого нужно остановиться.
  /// null = флаг не установлен.
  int? _stopAfterTrackIndex;

  // ── Инициализация ─────────────────────────────────────────────────────────

  Future<void> _init() async {
    _player.positionStream.listen((pos) {
      if (mounted) state = state.copyWith(position: pos);
    });

    _player.bufferedPositionStream.listen((pos) {
      if (mounted) state = state.copyWith(buffered: pos);
    });

    _player.durationStream.listen((dur) {
      if (mounted && dur != null) state = state.copyWith(total: dur);
    });

    _player.playerStateStream.listen((playerState) {
      if (mounted) {
        state = state.copyWith(
          isPlaying: playerState.playing,
          isLoading: playerState.processingState == ProcessingState.loading,
          isBuffering: playerState.processingState == ProcessingState.buffering,
        );
      }
    });

    _player.currentIndexStream.listen((index) async {
      if (!mounted || index == null || index >= state.queue.length) return;

      final track = state.queue[index] as TrackModel;
      state = state.copyWith(currentIndex: index, currentTrack: track);
      _updatePalette(track);

      // Stop After Track: остановить по окончании трека
      if (_stopAfterTrackIndex != null && index != _stopAfterTrackIndex) {
        _stopAfterTrackIndex = null;
        if (mounted) {
          state = state
              .copyWith(
                stopAfterTrack: false,
                sleepTimerActive: false,
                isPlaying: false,
              )
              .clearSleepTimerRemaining();
        }
        await _handler.pause();
        // Перематываем начало нового трека, чтобы он был готов к resume play
        await _handler.seek(Duration.zero);
        if (mounted && state.isPlaying) {
          state = state.copyWith(isPlaying: false);
        }
      }
    });

    await _loadLibrary();
  }

  Future<void> reloadFromLibrary() async => _loadLibrary();

  Future<void> _loadLibrary() async {
    try {
      final libraryTracks = await LibraryDatabase.instance.getAllTracks();
      if (libraryTracks.isEmpty) {
        state = state.copyWith(queue: [], currentTrack: null, isLoading: false);
        return;
      }
      // Передаем ленивый Iterable. loadPlaylist сам вызовет toList() в микротаске.
      await loadPlaylist(libraryTracks.map((t) => t.toTrackModel()));
    } catch (e) {
      debugPrint('Error loading library into player: $e');
    }
  }

  void _updatePalette(TrackModel track) {
    try {
      _ref.read(paletteProvider.notifier).extractFromImage(track.coverImage);
    } catch (e) {
      debugPrint('Palette update skipped: $e');
    }
  }

  // ── Очередь (Play Next / Add to queue) ────────────────────────────────────

  /// Вставить трек следующим в очереди и сразу начать воспроизведение.
  Future<void> playNext(TrackModel track) async {
    final newQueue = List<TrackModel>.from(state.queue.cast<TrackModel>());

    if (newQueue.isEmpty) {
      newQueue.add(track);
      await loadPlaylist(newQueue, initialIndex: 0);
      return;
    }

    final insertIndex = state.currentIndex + 1;
    newQueue.insert(insertIndex, track);
    await loadPlaylist(newQueue, initialIndex: insertIndex);
  }

  /// Добавить трек в конец очереди без прерывания воспроизведения.
  Future<void> addToQueue(TrackModel track) async {
    final newQueue = List<TrackModel>.from(state.queue.cast<TrackModel>());

    if (newQueue.isEmpty) {
      newQueue.add(track);
      await loadPlaylist(newQueue, initialIndex: 0);
      return;
    }

    newQueue.add(track);
    final currentIdx = state.currentIndex;
    final currentPos = state.position;
    await loadPlaylist(newQueue, initialIndex: currentIdx);
    await seekTo(currentPos);
  }

  // ── Загрузка плейлиста (Оптимизировано Bolt) ──────────────────────────────

  Future<void> loadPlaylist(Iterable<TrackModel> tracks,
      {int initialIndex = 0}) async {
    state = state.copyWith(isLoading: true);

    // Уступаем поток UI для предотвращения джанка (Jank)
    await Future.microtask(() {});

    // Ленивое преобразование в список
    final tracksList = tracks is List<TrackModel> ? tracks : tracks.toList();

    state = state.copyWith(
      queue: tracksList,
      currentIndex: initialIndex,
      currentTrack: tracksList.isNotEmpty ? tracksList[initialIndex] : null,
    );

    if (tracksList.isEmpty) {
      state = state.copyWith(isLoading: false);
      return;
    }

    final mediaItems = tracksList
        .map((t) => MediaItem(
              id: t.id,
              title: t.title,
              artist: t.artist,
              album: t.album,
              duration: t.duration,
            ))
        .toList();

    final audioSources = await Future.wait(tracksList.map((t) => t.toAudioSource()));

    try {
      await _handler.loadPlaylist(
        items: mediaItems,
        sources: audioSources,
        initialIndex: initialIndex,
      );
      if (tracksList.isNotEmpty) {
        _updatePalette(tracksList[initialIndex]);
      }
    } catch (e) {
      debugPrint('loadPlaylist error: $e');
    }

    if (mounted) state = state.copyWith(isLoading: false);
  }

  // ── Плавное изменение громкости (Fade) ────────────────────────────────────

  Future<void> _fadeVolume({
    required double from,
    required double to,
    int steps = 10,
    int intervalMs = 30,
  }) async {
    for (int i = 1; i <= steps; i++) {
      final vol = (from + (to - from) * i / steps).clamp(0.0, 1.0);
      await _player.setVolume(vol);
      await Future.delayed(Duration(milliseconds: intervalMs));
    }
  }

  // ── Управление воспроизведением ───────────────────────────────────────────

  Future<void> playPause() async {
    if (_player.playing) {
      await pause();
    } else {
      await _handler.play();
    }
  }

  Future<void> play() async => _handler.play();

  /// Плавная пауза (Fade Out 300 мс).
  Future<void> pause() async {
    final userVolume = state.volume;
    await _fadeVolume(from: userVolume, to: 0.0);
    await _handler.pause();
    // Восстанавливаем громкость (без звука — трек уже на паузе)
    await _player.setVolume(userVolume);
  }

  Future<void> next() async {
    if (state.hasNext) await _handler.skipToNext();
  }

  Future<void> previous() async {
    if (state.position.inSeconds > 3) {
      await seekTo(Duration.zero);
    } else if (state.hasPrevious) {
      await _handler.skipToPrevious();
    }
  }

  Future<void> seekTo(Duration position) async => _handler.seek(position);

  Future<void> seekToProgress(double progress) async {
    final target = Duration(
      milliseconds: (state.total.inMilliseconds * progress).round(),
    );
    await seekTo(target);
  }

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
    if (mounted) state = state.copyWith(volume: volume);
  }

  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    if (mounted) state = state.copyWith(speed: speed);
  }

  void toggleShuffle() {
    final newShuffle = !state.isShuffle;
    _handler.setShuffleMode(
      newShuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    );
    if (mounted) state = state.copyWith(isShuffle: newShuffle);
  }

  void toggleRepeat() {
    final next = switch (state.repeatMode) {
      RepeatMode.none => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.none,
    };
    _handler.setRepeatMode(switch (next) {
      RepeatMode.none => AudioServiceRepeatMode.none,
      RepeatMode.all => AudioServiceRepeatMode.all,
      RepeatMode.one => AudioServiceRepeatMode.one,
    });
    if (mounted) state = state.copyWith(repeatMode: next);
  }

  // ── Эквалайзер ─────────────────────────────────────────────────────────────

  /// Включает или выключает Android DSP эквалайзер.
  Future<void> setEqEnabled(bool enabled) async {
    try {
      // Not implemented for now in the custom AudioHandler
      if (mounted) state = state.copyWith(eqEnabled: enabled);
    } catch (e) {
      debugPrint('EQ setEnabled error: $e');
    }
  }

  /// Устанавливает gain указанной полосы в dB.
  Future<void> setEqBandGain(int bandIndex, double gain) async {
    try {
      // Not implemented for now in the custom AudioHandler
      final newGains = List<double>.from(state.eqBandGains);
      if (bandIndex >= 0 && bandIndex < newGains.length) {
        newGains[bandIndex] = gain;
        if (mounted) state = state.copyWith(eqBandGains: newGains);
      }
    } catch (e) {
      debugPrint('EQ setGain error (band=$bandIndex): $e');
    }
  }

  // ── Таймер сна ─────────────────────────────────────────────────────────────

  /// Запустить таймер: через [duration] вызывает плавную паузу (Fade Out).
  void startSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _stopAfterTrackIndex = null;

    if (mounted) {
      state = state.copyWith(
        sleepTimerActive: true,
        stopAfterTrack: false,
        sleepTimerRemaining: duration,
      );
    }

    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final remaining = state.sleepTimerRemaining;
      if (remaining != null && remaining.inSeconds > 0) {
        state = state.copyWith(
            sleepTimerRemaining: remaining - const Duration(seconds: 1));
      } else {
        timer.cancel();
        await pause(); // Fade Out 300 мс + pause
        if (mounted) {
          state = state
              .copyWith(sleepTimerActive: false, stopAfterTrack: false)
              .clearSleepTimerRemaining();
        }
      }
    });
  }

  /// Включить режим «остановить по окончании текущего трека».
  void setStopAfterTrack() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _stopAfterTrackIndex = state.currentIndex;

    if (mounted) {
      state = state
          .copyWith(sleepTimerActive: true, stopAfterTrack: true)
          .clearSleepTimerRemaining();
    }
  }

  /// Отменить любой активный таймер сна.
  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _stopAfterTrackIndex = null;
    if (mounted) {
      state = state
          .copyWith(sleepTimerActive: false, stopAfterTrack: false)
          .clearSleepTimerRemaining();
    }
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _sleepTimer?.cancel();
    super.dispose();
  }
}

final playerProvider =
    StateNotifierProvider<PlayerNotifier, ProtogenixPlayerState>((ref) {
  return PlayerNotifier(ref);
});
