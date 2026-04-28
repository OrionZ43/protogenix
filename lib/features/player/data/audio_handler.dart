import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

late AudioHandler audioHandler;

Future<void> initAudioService() async {
  audioHandler = await AudioService.init(
    builder: () => ProtogenixAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.protogenix.audio',
      androidNotificationChannelName: 'Protogenix Player',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
}

class ProtogenixAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AndroidEqualizer? _equalizer =
      Platform.isAndroid ? AndroidEqualizer() : null;
  late final AudioPlayer _player;

  ProtogenixAudioHandler() {
    _player = AudioPlayer(
      audioPipeline: AudioPipeline(
          androidAudioEffects: [if (_equalizer != null) _equalizer]),
    );
    _init();
  }

  void _init() {
    _player.playbackEventStream.listen(_broadcastState);
    _player.currentIndexStream.listen((index) {
      if (index != null && index < queue.value.length) {
        mediaItem.add(queue.value[index]);
      }
    });
  }

  AudioPlayer get player => _player;
  AndroidEqualizer? get equalizer => _equalizer; // Геттер, который требовал код

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  Future<void> loadPlaylist({
    required List<MediaItem> items,
    required List<AudioSource> sources,
    int initialIndex = 0,
  }) async {
    queue.add(items);
    final playlist = ConcatenatingAudioSource(children: sources);
    await _player.setAudioSource(playlist, initialIndex: initialIndex);
  }

  void _broadcastState(PlaybackEvent event) {
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
    ));
  }
}
