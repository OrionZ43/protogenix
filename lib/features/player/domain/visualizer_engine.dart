// lib/features/player/domain/visualizer_engine.dart
//
// VisualizerEngine v4 — НАСТОЯЩИЙ FFT-анализ через Platform Channels.
//
// ═══════════════════════════════════════════════════════════════════════════
// АРХИТЕКТУРА
// ═══════════════════════════════════════════════════════════════════════════
//
//  Android (нативный Visualizer):
//    MethodChannel "com.protogenix.visualizer/control"
//      startVisualizer(sessionId) → привязывает android.media.audiofx.Visualizer
//      stopVisualizer()           → освобождает Visualizer
//
//    EventChannel  "com.protogenix.visualizer/events"
//      ← List<double>[bass, highs, volume, beatDrop]  (~20 Hz, реальный FFT)
//
//  iOS / Desktop (нет Visualizer API):
//    Graceful fallback: Volume Envelope через positionStream.
//    Пульсация живая, но без частотного анализа.
//
// ═══════════════════════════════════════════════════════════════════════════
// FLOW
// ═══════════════════════════════════════════════════════════════════════════
//
//  PlayerNotifier._init()
//    └─► visualizerEngine.attachPlayer(player)
//          ├─ playerStateStream → при play: запрашивает sessionId у just_audio
//          │                               → вызывает startVisualizer(sessionId)
//          │                    при pause: stopVisualizer() + decay
//          └─ EventChannel.receiveBroadcastStream()
//               → _onNativeEvent([bass, highs, vol, drop]) → _emit()
//
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

// ── Public API ────────────────────────────────────────────────────────────────

class VisualizerSnapshot {
  final double bass;      // 0.0–1.0  низкие частоты
  final double highs;     // 0.0–1.0  высокие частоты
  final double volume;    // 0.0–1.0  общая энергия
  final bool   beatDrop;  // true — один тик при резком пике

  const VisualizerSnapshot({
    this.bass     = 0.0,
    this.highs    = 0.0,
    this.volume   = 0.0,
    this.beatDrop = false,
  });

  VisualizerSnapshot copyWith({
    double? bass, double? highs, double? volume, bool? beatDrop,
  }) => VisualizerSnapshot(
    bass:     bass     ?? this.bass,
    highs:    highs    ?? this.highs,
    volume:   volume   ?? this.volume,
    beatDrop: beatDrop ?? this.beatDrop,
  );
}

// ── Engine ────────────────────────────────────────────────────────────────────

class VisualizerEngine {

  // ── Platform channels ──────────────────────────────────────────────────────

  static const _kMethodChannel = 'z43.studios.protogenix/control';
  static const _kEventChannel  = 'z43.studios.protogenix/events';

  final _methodChannel = const MethodChannel(_kMethodChannel);
  final _eventChannel  = const EventChannel(_kEventChannel);

  // ── Public stream ──────────────────────────────────────────────────────────

  final _controller = StreamController<VisualizerSnapshot>.broadcast();
  Stream<VisualizerSnapshot> get stream => _controller.stream;

  VisualizerSnapshot _last = const VisualizerSnapshot();
  VisualizerSnapshot get current => _last;

  // ── Internal state ─────────────────────────────────────────────────────────

  AudioPlayer? _player;
  StreamSubscription<PlayerState>?  _stateSub;
  StreamSubscription<dynamic>?      _nativeSub;   // EventChannel subscription
  StreamSubscription<Duration>?     _fallbackSub; // iOS position-stream fallback

  bool _isPlaying      = false;
  bool _nativeActive   = false; // true когда EventChannel шлёт данные
  Timer? _decayTimer;

  // Fallback EMA (iOS / при недоступном Visualizer)
  Duration _prevPos        = Duration.zero;
  DateTime _prevWallTime   = DateTime.now();
  double   _bassEma        = 0.0;
  double   _highsEma       = 0.0;
  double   _volEma         = 0.0;
  double   _bassLongEma    = 0.0;
  bool     _dropSent       = false;

  // ── attachPlayer ───────────────────────────────────────────────────────────

  /// Вызывать из PlayerNotifier._init() после создания AudioPlayer.
  void attachPlayer(AudioPlayer player) {
    _detach();
    _player = player;

    _stateSub = player.playerStateStream.listen((state) async {
      final nowPlaying = state.playing &&
          state.processingState == ProcessingState.ready;

      if (nowPlaying == _isPlaying) return;
      _isPlaying = nowPlaying;

      if (nowPlaying) {
        _cancelDecay();
        await _startNative(player);
      } else {
        await _stopNative();
        _scheduleDecay();
      }
    });
  }

  // ── Native Visualizer (Android) ───────────────────────────────────────────

  Future<void> _startNative(AudioPlayer player) async {
    // Только Android — на iOS нет android.media.audiofx.Visualizer
    if (!Platform.isAndroid) {
      _startFallback(player);
      return;
    }

    // Подписываемся на EventChannel ДО вызова startVisualizer,
    // чтобы не пропустить первые события.
    _nativeSub?.cancel();
    _nativeSub = _eventChannel
        .receiveBroadcastStream()
        .listen(
      _onNativeEvent,
      onError: (Object e) {
        // Если нативная сторона вернула ошибку — уходим в fallback
        _nativeActive = false;
        _startFallback(player);
      },
    );

    // Получаем AudioSession ID от just_audio
    // just_audio 0.9.x: AndroidAudioEffects через AndroidEqualizer / AndroidLoudnessEnhancer.
    // AudioSession ID доступен через player.androidAudioSessionId (Stream<int?>).
    // Берём первое ненулевое значение.
    try {
      final sessionId = await _getSessionId(player);
      if (sessionId == null || sessionId == 0) {
        // Нет сессии — fallback
        _nativeSub?.cancel();
        _startFallback(player);
        return;
      }

      final started = await _methodChannel.invokeMethod<bool>(
        'startVisualizer',
        {'sessionId': sessionId},
      );

      if (started == true) {
        _nativeActive = true;
      } else {
        // Разрешение запрошено, ждём — нативная сторона пришлёт события
        // как только разрешение будет дано. На случай отказа запустим fallback
        // через 2 секунды, если события так и не придут.
        Future.delayed(const Duration(seconds: 2), () {
          if (!_nativeActive && _isPlaying) _startFallback(player);
        });
      }
    } on PlatformException catch (e) {
      // Канал не реализован (например, тест на desktop)
      _nativeSub?.cancel();
      _startFallback(player);
      assert(() {
        // ignore: avoid_print
        print('[VisualizerEngine] PlatformException: $e → fallback');
        return true;
      }());
    }
  }

  Future<void> _stopNative() async {
    _nativeSub?.cancel();
    _nativeSub    = null;
    _nativeActive = false;

    _fallbackSub?.cancel();
    _fallbackSub = null;

    if (Platform.isAndroid) {
      try {
        await _methodChannel.invokeMethod('stopVisualizer');
      } on PlatformException catch (_) {/* ignore */}
    }
  }

  /// Получить Android AudioSession ID из just_audio.
  /// just_audio предоставляет `player.androidAudioSessionId` — Stream<int?>.
  /// Берём первое ненулевое значение (таймаут 3 сек).
  Future<int?> _getSessionId(AudioPlayer player) async {
    try {
      // ИСПРАВЛЕНИЕ: just_audio 0.9.x отдаёт Stream<int?> или Stream<int>.
      // Мы приводим всё к Stream<int?>, фильтруем null и нули.
      final stream = player.androidAudioSessionId as Stream<int?>;

      return await stream
          .where((id) => id != null && id != 0)
          .first
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      return null;
    }
  }

  // ── Обработка нативных FFT-данных ─────────────────────────────────────────

  void _onNativeEvent(dynamic data) {
    if (data is! List || data.length < 4) return;
    _nativeActive = true;

    final bass     = (data[0] as num).toDouble().clamp(0.0, 1.0);
    final highs    = (data[1] as num).toDouble().clamp(0.0, 1.0);
    final volume   = (data[2] as num).toDouble().clamp(0.0, 1.0);
    final beatDrop = (data[3] as num).toDouble() >= 0.5;

    _emit(VisualizerSnapshot(
      bass:     bass,
      highs:    highs,
      volume:   volume,
      beatDrop: beatDrop,
    ));
  }

  // ── iOS / Desktop Fallback: Volume Envelope из positionStream ─────────────
  //
  // Не такой точный, как FFT, но лучше чем ничего.
  // Использует тот же RC-фильтр из v3, но честнее называет себя fallback.

  void _startFallback(AudioPlayer player) {
    _fallbackSub?.cancel();
    _prevPos      = player.position;
    _prevWallTime = DateTime.now();

    _fallbackSub = player.positionStream.listen(_onFallbackPosition);
  }

  void _onFallbackPosition(Duration pos) {
    if (!_isPlaying) return;

    final now    = DateTime.now();
    final wallDt = now.difference(_prevWallTime).inMicroseconds / 1e6;
    final audioDt = (pos.inMicroseconds - _prevPos.inMicroseconds) / 1e6;
    _prevPos      = pos;
    _prevWallTime = now;

    if (wallDt < 0.004 || wallDt > 0.3 || audioDt < 0.0) return;

    final energy = ((audioDt - wallDt).abs() / wallDt + 0.08).clamp(0.0, 1.0);

    final aB = (wallDt / 0.080).clamp(0.0, 1.0);
    final aH = (wallDt / 0.015).clamp(0.0, 1.0);
    final aV = (wallDt / 0.040).clamp(0.0, 1.0);
    final aL = (wallDt / 1.500).clamp(0.0, 1.0);

    _bassEma     += aB * (energy - _bassEma);
    _highsEma    += aH * (energy - _highsEma);
    _volEma      += aV * (energy - _volEma);
    _bassLongEma += aL * (_bassEma - _bassLongEma);

    final bass   = _softClip(_bassEma  * 2.5);
    final highs  = _softClip(_highsEma * 1.8);
    final volume = _softClip(_volEma   * 2.0);
    final drop   = _detectDrop(bass);

    _emit(VisualizerSnapshot(
      bass: bass, highs: highs, volume: volume, beatDrop: drop,
    ));
  }

  // ── Decay при паузе ───────────────────────────────────────────────────────

  void _scheduleDecay() {
    _cancelDecay();
    _decayTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      _bassEma  *= 0.88;
      _highsEma *= 0.75;
      _volEma   *= 0.85;

      final snap = VisualizerSnapshot(
        bass:   _softClip(_bassEma  * 2.5),
        highs:  _softClip(_highsEma * 1.8),
        volume: _softClip(_volEma   * 2.0),
      );
      _emit(snap);

      if (_bassEma < 0.001 && _highsEma < 0.001) {
        _cancelDecay();
        _emit(const VisualizerSnapshot());
      }
    });
  }

  void _cancelDecay() {
    _decayTimer?.cancel();
    _decayTimer = null;
  }

  // ── Утилиты ───────────────────────────────────────────────────────────────

  double _softClip(double x) {
    if (x >= 1.0) return 1.0;
    if (x <= 0.0) return 0.0;
    return x * (2.0 - x);
  }

  bool _detectDrop(double bass) {
    if (bass > _bassLongEma * 2.0 && bass > 0.50 && !_dropSent) {
      _dropSent = true;
      return true;
    }
    if (bass < _bassLongEma * 1.1) _dropSent = false;
    return false;
  }

  void _emit(VisualizerSnapshot snap) {
    _last = snap;
    if (!_controller.isClosed) _controller.add(snap);
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────

  void _detach() {
    _stateSub?.cancel();
    _nativeSub?.cancel();
    _fallbackSub?.cancel();
    _stateSub    = null;
    _nativeSub   = null;
    _fallbackSub = null;
    _player      = null;
    _nativeActive = false;
    _cancelDecay();

    if (Platform.isAndroid) {
      _methodChannel.invokeMethod('stopVisualizer').catchError((_) {});
    }
  }

  void dispose() {
    _detach();
    _controller.close();
  }
}

// ── Riverpod Providers ────────────────────────────────────────────────────────

final visualizerEngineProvider = Provider<VisualizerEngine>((ref) {
  final engine = VisualizerEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

final visualizerStreamProvider = StreamProvider<VisualizerSnapshot>((ref) {
  return ref.watch(visualizerEngineProvider).stream;
});