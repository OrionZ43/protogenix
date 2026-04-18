// lib/features/player/presentation/widgets/animated_background.dart
//
// AnimatedBackground v3 — автономный фон без привязки к аудио.
//   • Блобы медленно «дышат» по таймеру (синусоидальный скейл)
//   • Скорость орбиты и размер блобов постоянны
//   • Vignette статична, нет никаких пульсаций от звука
//   • Убраны: visualizer, bass, highs, beatDrop, spring-реакции

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class AnimatedBackground extends StatefulWidget {
  const AnimatedBackground({
    super.key,
    required this.primaryColor,
    required this.secondaryColor,
    required this.tertiaryColor,
    required this.child,
  });

  final Color  primaryColor;
  final Color  secondaryColor;
  final Color  tertiaryColor;
  final Widget child;

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with SingleTickerProviderStateMixin {

  late Ticker _ticker;
  double _lastTime = -1.0;
  double _time     = 0.0;

  late final List<_BlobState> _blobs;

  @override
  void initState() {
    super.initState();
    _initBlobs();
    _ticker = createTicker(_onTick)..start();
  }

  void _initBlobs() {
    final rng = math.Random(42);
    _blobs = List.generate(4, (i) {
      final angleBase = (i / 4.0) * math.pi * 2;
      return _BlobState(
        initialAngle: angleBase + rng.nextDouble() * 0.5,
        orbitRadius:  0.25 + rng.nextDouble() * 0.20,
        speed:        0.06 + rng.nextDouble() * 0.04, // медленнее
        sizeRatio:    0.55 + rng.nextDouble() * 0.35,
        phaseOffset:  rng.nextDouble() * math.pi * 2,
        breathPeriod: 3.0 + rng.nextDouble() * 4.0,   // период «дыхания» 3–7 с
        breathAmp:    0.04 + rng.nextDouble() * 0.06,  // амплитуда дыхания ±4–10%
      );
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final t  = elapsed.inMicroseconds / 1e6;
    final dt = _lastTime < 0 ? 0.016 : (t - _lastTime).clamp(0.001, 0.05);
    _lastTime = t;
    _time     = t;

    for (final blob in _blobs) {
      blob.tick(dt, _time);
    }

    if (mounted) setState(() {});
  }

  Color get _baseBg =>
      Color.lerp(widget.tertiaryColor, Colors.black, 0.55)!;

  List<Color> get _blobColors => [
    widget.primaryColor.withValues(alpha: 0.55),
    widget.secondaryColor.withValues(alpha: 0.45),
    widget.primaryColor.withValues(alpha: 0.30),
    widget.tertiaryColor.withValues(alpha: 0.40),
  ];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return ColoredBox(
      color: _baseBg,
      child: Stack(
        children: [
          // Blobs
          RepaintBoundary(
            child: CustomPaint(
              size: size,
              painter: _BlobPainter(
                blobs:  _blobs,
                colors: _blobColors,
              ),
            ),
          ),

          // Статичная vignette
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end:   Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.15),
                    Colors.black.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
          ),

          widget.child,
        ],
      ),
    );
  }
}

// ── Blob State ────────────────────────────────────────────────────────────────

class _BlobState {
  _BlobState({
    required this.initialAngle,
    required this.orbitRadius,
    required this.speed,
    required this.sizeRatio,
    required this.phaseOffset,
    required this.breathPeriod,
    required this.breathAmp,
  });

  final double initialAngle;
  final double orbitRadius;
  final double speed;
  final double sizeRatio;
  final double phaseOffset;
  final double breathPeriod; // период автономного «дыхания»
  final double breathAmp;    // амплитуда дыхания

  double nx    = 0.5;
  double ny    = 0.5;
  double scale = 1.0;

  void tick(double dt, double t) {
    // Медленная орбита — скорость постоянна
    final angle = initialAngle + (t + phaseOffset) * speed;
    nx = 0.5 + math.cos(angle) * orbitRadius;
    ny = 0.5 + math.sin(angle * 0.7 + phaseOffset) * orbitRadius;

    // Автономное «дыхание» — синусоида без привязки к аудио
    scale = 1.0 + math.sin(t * (math.pi * 2 / breathPeriod) + phaseOffset)
        * breathAmp;
  }
}

// ── CustomPainter ─────────────────────────────────────────────────────────────

class _BlobPainter extends CustomPainter {
  const _BlobPainter({
    required this.blobs,
    required this.colors,
  });

  final List<_BlobState> blobs;
  final List<Color>      colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());

    for (int i = 0; i < blobs.length; i++) {
      final b      = blobs[i];
      final cx     = b.nx * size.width;
      final cy     = b.ny * size.height;
      final radius = (math.min(size.width, size.height) * 0.42 *
          b.sizeRatio * b.scale)
          .clamp(80.0, 500.0);

      final color = colors[i % colors.length];

      canvas.drawCircle(
        Offset(cx, cy),
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0.0)],
            stops:  const [0.0, 1.0],
          ).createShader(
            Rect.fromCircle(center: Offset(cx, cy), radius: radius),
          )
          ..blendMode = BlendMode.screen,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_BlobPainter old) => true;
}
