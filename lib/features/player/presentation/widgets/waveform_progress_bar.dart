// lib/features/player/presentation/widgets/waveform_progress_bar.dart
//
// WaveformProgressBar v3 — красивая волна по таймеру, без привязки к аудио.
// Убраны: bass, highs, volume — анимация полностью автономна.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../../../core/utils/haptic_patterns.dart';

typedef WaveformProgressBar = LiveWaveformProgressBar;

class LiveWaveformProgressBar extends StatefulWidget {
  const LiveWaveformProgressBar({
    super.key,
    required this.progress,
    required this.accentColor,
    required this.onSeek,
    this.position = Duration.zero,
    this.total = Duration.zero,
    this.height = 56.0,
    this.barCount = 80,
  });

  final double progress;
  final Color accentColor;
  final ValueChanged<double> onSeek;
  final Duration position;
  final Duration total;
  final double height;
  final int barCount;

  @override
  State<LiveWaveformProgressBar> createState() =>
      _LiveWaveformProgressBarState();
}

class _LiveWaveformProgressBarState extends State<LiveWaveformProgressBar>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  late List<double> _baseAmps;
  late List<double> _phaseOffsets;
  double _time = 0.0;
  double _lastTime = -1.0;
  final ValueNotifier<int> _tickNotifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _generateWaveform();
    _ticker = createTicker(_onTick)..start();
  }

  void _generateWaveform() {
    final n = widget.barCount;
    final rng = math.Random(widget.total.inSeconds ^ 0xDEADBEEF);

    _baseAmps = List.generate(n, (i) {
      final t = i / n;
      final envelope = math.sin(t * math.pi).clamp(0.3, 1.0);
      final w1 = math.sin(t * 22.3 + rng.nextDouble()) * 0.40;
      final w2 = math.sin(t * 7.1 + rng.nextDouble() * 2) * 0.30;
      final w3 = rng.nextDouble() * 0.18;
      return ((w1 + w2 + w3).abs() * envelope).clamp(0.06, 1.0);
    });

    _phaseOffsets = List.generate(n, (_) => rng.nextDouble() * math.pi * 2);
  }

  @override
  void didUpdateWidget(LiveWaveformProgressBar old) {
    super.didUpdateWidget(old);
    if (old.total != widget.total || old.barCount != widget.barCount) {
      _generateWaveform();
    }
  }

  DateTime? _lastHapticTime;

  void _onTick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    final dt = _lastTime < 0 ? 0.016 : (t - _lastTime).clamp(0.0, 0.1);
    _lastTime = t;
    _time = t;
    if (dt > 0 && mounted) _tickNotifier.value++;
  }

  void _triggerSeekHaptic() {
    final now = DateTime.now();
    // Rate limit to max 1 haptic feedback every 30ms to prevent overwhelming the device
    if (_lastHapticTime == null ||
        now.difference(_lastHapticTime!) > const Duration(milliseconds: 30)) {
      HapticPatterns.seek();
      _lastHapticTime = now;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _tickNotifier.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTapUp: (d) {
            final box = context.findRenderObject() as RenderBox?;
            if (box != null) {
              _triggerSeekHaptic();
              widget.onSeek(
                (d.localPosition.dx / box.size.width).clamp(0.0, 1.0),
              );
            }
          },
          onHorizontalDragUpdate: (d) {
            final box = context.findRenderObject() as RenderBox?;
            if (box != null) {
              _triggerSeekHaptic();
              widget.onSeek(
                (d.localPosition.dx / box.size.width).clamp(0.0, 1.0),
              );
            }
          },
          child: SizedBox(
            height: widget.height,
            child: ValueListenableBuilder<int>(
              valueListenable: _tickNotifier,
              builder: (context, _, __) {
                return CustomPaint(
                  painter: _LiveWavePainter(
                    progress: widget.progress,
                    baseAmps: _baseAmps,
                    phaseOffsets: _phaseOffsets,
                    time: _time,
                    accentColor: widget.accentColor,
                    barCount: widget.barCount,
                  ),
                  child: const SizedBox.expand(),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _fmt(widget.position),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              Text(
                _fmt(widget.total),
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── CustomPainter ─────────────────────────────────────────────────────────────

class _LiveWavePainter extends CustomPainter {
  const _LiveWavePainter({
    required this.progress,
    required this.baseAmps,
    required this.phaseOffsets,
    required this.time,
    required this.accentColor,
    required this.barCount,
  });

  final double progress;
  final List<double> baseAmps;
  final List<double> phaseOffsets;
  final double time;
  final Color accentColor;
  final int barCount;

  // Тихое «дыхание» волны — медленная синусоида по таймеру
  static const double _breathSpeed = 1.2;
  static const double _breathAmp = 0.08;

  @override
  void paint(Canvas canvas, Size size) {
    if (baseAmps.isEmpty) return;

    final w = size.width;
    final h = size.height;
    final centerY = h / 2;
    final n = barCount;
    final barW = (w / n) * 0.55;
    final gap = (w / n) * 0.45;
    final maxH = h * 0.82;
    final progressX = w * progress;

    for (int i = 0; i < n; i++) {
      final x = (i / n) * w + gap / 2;

      // Плавное дыхание волны по таймеру — никакого аудио
      final breath = math.sin(
            time * _breathSpeed + phaseOffsets[i],
          ) *
          _breathAmp;

      final liveAmp = (baseAmps[i] + breath).clamp(0.06, 1.0);
      final barH = liveAmp * maxH;
      final isPlayed = x < progressX;

      final Color barColor;
      if (isPlayed) {
        barColor = accentColor;
      } else {
        barColor = Colors.white.withAlpha(38 + (liveAmp * 20).round());
      }

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x + barW / 2, centerY),
            width: barW,
            height: barH,
          ),
          const Radius.circular(2),
        ),
        Paint()
          ..color = barColor
          ..style = PaintingStyle.fill,
      );
    }

    // Playhead
    canvas.drawLine(
      Offset(progressX, centerY - maxH / 2 - 4),
      Offset(progressX, centerY + maxH / 2 + 4),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_LiveWavePainter old) =>
      old.progress != progress || old.time != time;
}
