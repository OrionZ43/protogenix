// Убрали импорты just_audio — они здесь не нужны

enum RepeatMode { none, one, all }

class ProtogenixPlayerState {
  final dynamic currentTrack;
  final List<dynamic> queue;
  final int currentIndex;

  final bool isPlaying;
  final bool isLoading;
  final bool isBuffering;

  final Duration position;
  final Duration buffered;
  final Duration total;

  final double volume;
  final double speed;

  final RepeatMode repeatMode;
  final bool isShuffle;

  final bool eqEnabled;
  final List<double> eqBandGains;

  final bool sleepTimerActive;
  final bool stopAfterTrack;

  const ProtogenixPlayerState({
    this.currentTrack,
    this.queue = const [],
    this.currentIndex = 0,
    this.isPlaying = false,
    this.isLoading = false,
    this.isBuffering = false,
    this.position = Duration.zero,
    this.buffered = Duration.zero,
    this.total = Duration.zero,
    this.volume = 1.0,
    this.speed = 1.0,
    this.repeatMode = RepeatMode.none,
    this.isShuffle = false,
    this.eqEnabled = false,
    this.eqBandGains = const [],
    this.sleepTimerActive = false,
    this.stopAfterTrack = false,
  });

  double get progress {
    if (total.inMilliseconds == 0) return 0.0;
    return (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  bool get hasNext =>
      repeatMode != RepeatMode.none || currentIndex < queue.length - 1;
  bool get hasPrevious => repeatMode != RepeatMode.none || currentIndex > 0;

  ProtogenixPlayerState copyWith({
    dynamic currentTrack,
    List<dynamic>? queue,
    int? currentIndex,
    bool? isPlaying,
    bool? isLoading,
    bool? isBuffering,
    Duration? position,
    Duration? buffered,
    Duration? total,
    double? volume,
    double? speed,
    RepeatMode? repeatMode,
    bool? isShuffle,
    bool? eqEnabled,
    List<double>? eqBandGains,
    bool? sleepTimerActive,
    bool? stopAfterTrack,
  }) {
    return ProtogenixPlayerState(
      currentTrack: currentTrack ?? this.currentTrack,
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      isBuffering: isBuffering ?? this.isBuffering,
      position: position ?? this.position,
      buffered: buffered ?? this.buffered,
      total: total ?? this.total,
      volume: volume ?? this.volume,
      speed: speed ?? this.speed,
      repeatMode: repeatMode ?? this.repeatMode,
      isShuffle: isShuffle ?? this.isShuffle,
      eqEnabled: eqEnabled ?? this.eqEnabled,
      eqBandGains: eqBandGains ?? this.eqBandGains,
      sleepTimerActive: sleepTimerActive ?? this.sleepTimerActive,
      stopAfterTrack: stopAfterTrack ?? this.stopAfterTrack,
    );
  }
}
