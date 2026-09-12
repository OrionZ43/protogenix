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
import 'package:flutter/painting.dart' show ImageProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../../../../core/services/app_visibility.dart';
import '../../data/audio_handler.dart';
import '../../data/eq_settings_store.dart';
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
    // Цвета обложки свёрнутому приложению не нужны — считаем по возвращении
    _ref.listen<bool>(appVisibleProvider, (_, visible) {
      final track = _paletteDeferred;
      if (visible && track != null) _updatePalette(track);
    });

    _player.positionStream.listen((pos) {
      if (mounted) state = state.copyWith(position: pos);
    });

    // bufferedPositionStream не слушаем: state.buffered никто не читает, а
    // событие приходило до двух раз в секунду и будило всех слушателей.

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

  // Обложка, для которой цвета уже посчитаны (или считаются)
  ImageProvider? _paletteImage;
  // Трек, чьи цвета ждут возвращения приложения на экран
  TrackModel? _paletteDeferred;

  void _updatePalette(TrackModel track) {
    if (!_ref.read(appVisibleProvider)) {
      _paletteDeferred = track;
      return;
    }
    _paletteDeferred = null;
    // Смена трека зовёт это дважды (loadPlaylist и currentIndexStream), а у
    // треков одного альбома обложка одна — цвета те же, считать незачем.
    if (track.coverImage == _paletteImage) return;
    _paletteImage = track.coverImage;
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
      unawaited(_restoreEq());
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
  //
  // AndroidEqualizer из just_audio стоит в конвейере ProtogenixAudioHandler
  // (только Android). Полосы — частоты и диапазон дБ — платформа отдаёт, когда
  // у плеера появляется источник. Поэтому сохранённые настройки применяются
  // после первой загрузки очереди (_restoreEq), а шторка ждёт полосы через
  // loadEq. Состояние (eqEnabled, eqBandGains) всегда берётся у самого
  // эквалайзера, а не хранится отдельно.

  AndroidEqualizer? get _equalizer => _handler.equalizer;
  late final _eqStore = EqSettingsStore();
  Timer? _eqSaveTimer;
  bool _eqRestored = false;

  /// Есть ли эквалайзер на этой платформе.
  bool get eqSupported => _equalizer != null;

  /// Полосы эквалайзера (заодно обновляет состояние). null — эквалайзера нет
  /// на этой платформе или плеер ещё не загрузил ни одного трека.
  Future<AndroidEqualizerParameters?> loadEq({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final eq = _equalizer;
    if (eq == null) return null;
    try {
      final params = await eq.parameters.timeout(timeout);
      _syncEqState(eq, params);
      return params;
    } catch (e) {
      debugPrint('[EQ] Полосы недоступны: $e');
      return null;
    }
  }

  /// Включает или выключает эквалайзер.
  Future<void> setEqEnabled(bool enabled) async {
    final eq = _equalizer;
    if (eq == null) return;
    try {
      await eq.setEnabled(enabled);
      if (mounted) state = state.copyWith(eqEnabled: enabled);
      _scheduleEqSave();
    } catch (e) {
      debugPrint('EQ setEnabled error: $e');
    }
  }

  /// Устанавливает усиление полосы в дБ.
  Future<void> setEqBandGain(int bandIndex, double gain) async {
    final params = await loadEq();
    if (params == null || bandIndex < 0 || bandIndex >= params.bands.length) {
      return;
    }
    try {
      await params.bands[bandIndex].setGain(
          gain.clamp(params.minDecibels, params.maxDecibels).toDouble());
      _syncEqState(_equalizer!, params);
      _scheduleEqSave();
    } catch (e) {
      debugPrint('EQ setGain error (band=$bandIndex): $e');
    }
  }

  /// Все полосы в ноль.
  Future<void> resetEq() async {
    final params = await loadEq();
    if (params == null) return;
    try {
      for (final band in params.bands) {
        await band.setGain(0);
      }
      _syncEqState(_equalizer!, params);
      _scheduleEqSave();
    } catch (e) {
      debugPrint('EQ reset error: $e');
    }
  }

  void _syncEqState(AndroidEqualizer eq, AndroidEqualizerParameters params) {
    if (!mounted) return;
    state = state.copyWith(
      eqEnabled: eq.enabled,
      eqBandGains: [for (final band in params.bands) band.gain],
    );
  }

  /// Применяет сохранённые настройки, как только у плеера появились полосы.
  Future<void> _restoreEq() async {
    final eq = _equalizer;
    if (eq == null || _eqRestored) return;
    _eqRestored = true;
    final params = await loadEq(timeout: const Duration(seconds: 15));
    if (params == null) {
      _eqRestored = false; // попробуем при следующей загрузке очереди
      return;
    }
    try {
      final saved = await _eqStore.load();
      if (saved != null && saved.gains.length == params.bands.length) {
        for (var i = 0; i < params.bands.length; i++) {
          await params.bands[i].setGain(saved.gains[i]
              .clamp(params.minDecibels, params.maxDecibels)
              .toDouble());
        }
        await eq.setEnabled(saved.enabled);
      }
    } catch (e) {
      debugPrint('[EQ] Не удалось применить сохранённые настройки: $e');
    }
    _syncEqState(eq, params);
  }

  /// Сохраняет настройки через полсекунды после последнего изменения:
  /// слайдер при перетаскивании меняет усиление десятки раз в секунду.
  void _scheduleEqSave() {
    _eqSaveTimer?.cancel();
    _eqSaveTimer = Timer(const Duration(milliseconds: 500), () {
      final eq = _equalizer;
      if (eq == null) return;
      unawaited(_eqStore.save(
          EqSettings(enabled: eq.enabled, gains: List.of(state.eqBandGains))));
    });
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
    _eqSaveTimer?.cancel();
    super.dispose();
  }
}

final playerProvider =
    StateNotifierProvider<PlayerNotifier, ProtogenixPlayerState>((ref) {
  return PlayerNotifier(ref);
});
