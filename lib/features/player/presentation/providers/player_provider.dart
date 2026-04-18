// lib/features/player/presentation/providers/player_provider.dart
//
// v4 — чистый провайдер без VisualizerEngine.
// Убраны: импорт visualizer_engine, вызов visualizer.attachPlayer().

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

  ProtogenixAudioHandler get _handler =>
      audioHandler as ProtogenixAudioHandler;

  AudioPlayer get _player => _handler.player;

  Future<void> _init() async {
    // ── Стандартные подписки ─────────────────────────────────────────────────
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
          isPlaying:   playerState.playing,
          isLoading:   playerState.processingState == ProcessingState.loading,
          isBuffering: playerState.processingState == ProcessingState.buffering,
        );
      }
    });

    _player.currentIndexStream.listen((index) {
      if (mounted && index != null && index < state.queue.length) {
        final track = state.queue[index] as TrackModel;
        state = state.copyWith(
          currentIndex: index,
          currentTrack: track,
        );
        _updatePalette(track);
      }
    });

    await _loadLibrary();
  }

  Future<void> reloadFromLibrary() async {
    await _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    try {
      final libraryTracks = await LibraryDatabase.instance.getAllTracks();

      if (libraryTracks.isEmpty) {
        state = state.copyWith(
          queue:        [],
          currentTrack: null,
          isLoading:    false,
        );
        return;
      }

      final trackModels = libraryTracks.map((t) => t.toTrackModel()).toList();
      await loadPlaylist(trackModels);
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

  Future<void> loadPlaylist(List<TrackModel> tracks,
      {int initialIndex = 0}) async {
    state = state.copyWith(
      queue:        tracks,
      currentIndex: initialIndex,
      currentTrack: tracks.isNotEmpty ? tracks[initialIndex] : null,
      isLoading:    true,
    );

    if (tracks.isEmpty) {
      state = state.copyWith(isLoading: false);
      return;
    }

    final mediaItems = tracks.map((t) => MediaItem(
      id:       t.id,
      title:    t.title,
      artist:   t.artist,
      album:    t.album,
      duration: t.duration,
    )).toList();

    final audioSources = tracks.map((t) => t.toAudioSource()).toList();

    try {
      await _handler.loadPlaylist(
        items:        mediaItems,
        sources:      audioSources,
        initialIndex: initialIndex,
      );
      if (tracks.isNotEmpty) {
        _updatePalette(tracks[initialIndex]);
      }
    } catch (e) {
      debugPrint('loadPlaylist error: $e');
    }

    if (mounted) state = state.copyWith(isLoading: false);
  }

  Future<void> playPause() async {
    if (_player.playing) {
      await _handler.pause();
    } else {
      await _handler.play();
    }
  }

  Future<void> play()  async => _handler.play();
  Future<void> pause() async => _handler.pause();

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

  Future<void> seekTo(Duration position) async {
    await _handler.seek(position);
  }

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
      newShuffle
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
    );
    if (mounted) state = state.copyWith(isShuffle: newShuffle);
  }

  void toggleRepeat() {
    final next = switch (state.repeatMode) {
      RepeatMode.none => RepeatMode.all,
      RepeatMode.all  => RepeatMode.one,
      RepeatMode.one  => RepeatMode.none,
    };
    _handler.setRepeatMode(switch (next) {
      RepeatMode.none => AudioServiceRepeatMode.none,
      RepeatMode.all  => AudioServiceRepeatMode.all,
      RepeatMode.one  => AudioServiceRepeatMode.one,
    });
    if (mounted) state = state.copyWith(repeatMode: next);
  }
}

final playerProvider =
    StateNotifierProvider<PlayerNotifier, ProtogenixPlayerState>((ref) {
  return PlayerNotifier(ref);
});
