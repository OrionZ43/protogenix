// lib/features/player/presentation/widgets/animated_background.dart
//
// AnimatedBackground v3.1 — автономный фон с элитной оптимизацией.
//
// ── Elite Optimization ──────────────────────────────────────────────────────
// Отрисовка блобов происходит ТОЛЬКО в фазе Paint через repaint: _blobTick.
// Это полностью исключает build/layout тики (0ms build time во время анимации).
// widget.child (интерфейс плеера) не перерисовывается от тиков фона.

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Блобы перерисовываются не чаще 30 раз в секунду (`performance.md`).
const _kMinFrameInterval = 1 / 31;

/// Во сколько раз фон рисуется мельче экрана. Смешивание полупрозрачных
/// блобов — самая дорогая часть кадра, и здесь оно идёт вчетверо меньше
/// пикселей, а на экран кладётся одна непрозрачная картинка.
///
/// Вид от этого не страдает: «страшным» фон делал не размер картинки, а
/// подкраска готовой текстуры через  — она задирала яркость
/// примерно в 1,8 раза. Текстуру убрали, градиенты рисуются как раньше.
const _kDownscale = 4.0;

class AnimatedBackground extends StatefulWidget {
  const AnimatedBackground({
    super.key,
    required this.primaryColor,
    required this.secondaryColor,
    required this.tertiaryColor,
    required this.child,
  });

  final Color primaryColor;
  final Color secondaryColor;
  final Color tertiaryColor;
  final Widget child;

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  double _lastTime = -1.0;
  double _time = 0.0;

  late final List<_BlobState> _blobs;
  List<_BlobState> get blobs => _blobs;

  /// Уведомляем ТОЛЬКО слой отрисовки (Paint), а не дерево виджетов.
  final _blobTick = ValueNotifier<int>(0);

  /// Готовый фон, нарисованный в уменьшенном размере: смешивание идёт по
  /// 1/16 пикселей, а на экран кладётся одной непрозрачной картинкой.
  ui.Image? _lowRes;
  int _lowResTick = -1;
  Size _lowResSize = Size.zero;

  /// Картинка с одними блобами, прозрачная между ними. Это ровно тот слой,
  /// который раньше рисовался поверх заливки: `BlendMode.screen` смешивает
  /// блобы между собой, а на экран слой кладётся обычным наложением.
  ///
  /// Заливка и виньетка рисуются уже на экране: это две заливки
  /// прямоугольника, они дешёвые, а вот `saveLayer` внутри записываемой
  /// картинки на Impeller оказался дорогим (37 fps против 58, `performance.md`).
  ui.Image? lowResFor(Size size, List<Color> colors, Color baseColor) {
    if (size.isEmpty) return null;
    if (_lowRes != null &&
        _lowResTick == _blobTick.value &&
        _lowResSize == size) {
      return _lowRes;
    }

    final w = (size.width / _kDownscale).round().clamp(1, 4096);
    final h = (size.height / _kDownscale).round().clamp(1, 4096);
    final small = Size(w.toDouble(), h.toDouble());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // В картинке только блобы, на прозрачном: это ровно тот слой, что раньше
    // лежал поверх заливки, и на экран он ложится обычным наложением.
    // Запекать в неё ещё заливку с виньеткой пробовал — средний FPS тот же,
    // но заметно больше тяжёлых кадров (`performance.md`).
    _paintBlobs(canvas, small, _blobs, colors);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(w, h);
    picture.dispose();

    _lowRes?.dispose();
    _lowRes = image;
    _lowResTick = _blobTick.value;
    _lowResSize = size;
    return image;
  }

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
        orbitRadius: 0.25 + rng.nextDouble() * 0.20,
        speed: 0.06 + rng.nextDouble() * 0.04,
        sizeRatio: 0.55 + rng.nextDouble() * 0.35,
        phaseOffset: rng.nextDouble() * math.pi * 2,
        breathPeriod: 3.0 + rng.nextDouble() * 4.0,
        breathAmp: 0.04 + rng.nextDouble() * 0.06,
      );
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _blobTick.dispose();
    _lowRes?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    // Фон — самое дорогое место на экране (замер на Pixel 7: с ним 45 fps на
    // тексте песни, без него 58). Блобы ползают медленно, и 30 кадров в
    // секунду для них глазом не отличить от 90, а перерисовок втрое меньше.
    if (_lastTime >= 0 && t - _lastTime < _kMinFrameInterval) return;

    final dt = _lastTime < 0 ? 0.016 : (t - _lastTime).clamp(0.001, 0.1);
    _lastTime = t;
    _time = t;

    for (final blob in _blobs) {
      blob.tick(dt, _time);
    }

    // Уведомляем Painter о необходимости перерисоваться. build() НЕ вызывается.
    if (mounted) _blobTick.value++;
  }

  Color get _baseBg => Color.lerp(widget.tertiaryColor, Colors.black, 0.55)!;

  List<Color> get _blobColors => [
        widget.primaryColor.withValues(alpha: 0.55),
        widget.secondaryColor.withValues(alpha: 0.45),
        widget.primaryColor.withValues(alpha: 0.30),
        widget.tertiaryColor.withValues(alpha: 0.40),
      ];

  @override
  Widget build(BuildContext context) {
    // Фон, блобы и виньетка — в одном непрозрачном слое.
    //
    // Раньше это были три полноэкранных слоя друг над другом (заливка,
    // полупрозрачные блобы в своём RepaintBoundary, полупрозрачный градиент),
    // и систему каждый кадр заставляли их смешивать. На Pixel 7 это стоило
    // трети кадрового бюджета: без блобов средний FPS поднимался с 45 до 58
    // на экране с текстом песни (`performance.md`).
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _BlobPainter(
                state: this,
                colors: _blobColors,
                baseColor: _baseBg,
                repaint: _blobTick,
              ),
            ),
          ),
        ),

        // ── Дочерний UI ──────────────────────────────────────────────────
        widget.child,
      ],
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
  final double breathPeriod;
  final double breathAmp;

  double nx = 0.5;
  double ny = 0.5;
  double scale = 1.0;

  void tick(double dt, double t) {
    final angle = initialAngle + (t + phaseOffset) * speed;
    nx = 0.5 + math.cos(angle) * orbitRadius;
    ny = 0.5 + math.sin(angle * 0.7 + phaseOffset) * orbitRadius;

    scale = 1.0 +
        math.sin(t * (math.pi * 2 / breathPeriod) + phaseOffset) * breathAmp;
  }
}

// ── Отрисовка фона ────────────────────────────────────────────────────────────

/// Только блобы, на прозрачном. `BlendMode.screen` смешивает их между собой —
/// ровно как раньше внутри отдельного слоя.
void _paintBlobs(
  Canvas canvas,
  Size size,
  List<_BlobState> blobs,
  List<Color> colors,
) {
  for (int i = 0; i < blobs.length; i++) {
    final b = blobs[i];
    final cx = b.nx * size.width;
    final cy = b.ny * size.height;
    final radius =
        (math.min(size.width, size.height) * 0.42 * b.sizeRatio * b.scale)
            .clamp(80.0 / _kDownscale, 500.0);
    final color = colors[i % colors.length];
    final target = Rect.fromCircle(center: Offset(cx, cy), radius: radius);

    // Тот же градиент, что и был. Готовая текстура с подкраской через
    // `BlendMode.modulate` не годится: цветовые каналы фильтра не
    // домножаются на прозрачность, и блобы становятся ярче примерно
    // в 1,8 раза («фон какой-то мега страшный»), а скорости это не давало.
    canvas.drawCircle(
      Offset(cx, cy),
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0.0)],
          stops: const [0.0, 1.0],
        ).createShader(target)
        ..blendMode = BlendMode.screen,
    );
  }
}

/// Виньетка поверх блобов — как была.
void _paintVignette(Canvas canvas, Rect rect) {
  canvas.drawRect(
    rect,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black.withValues(alpha: 0.15),
          Colors.black.withValues(alpha: 0.55),
        ],
      ).createShader(rect),
  );
}

// ── CustomPainter ─────────────────────────────────────────────────────────────

class _BlobPainter extends CustomPainter {
  _BlobPainter({
    required this.state,
    required this.colors,
    required this.baseColor,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final _AnimatedBackgroundState state;
  final List<Color> colors;
  final Color baseColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = baseColor);

    // Блобы — готовой картинкой в уменьшенном размере (`lowResFor`)
    final image = state.lowResFor(size, colors, baseColor);
    if (image != null) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        rect,
        Paint()..filterQuality = FilterQuality.medium,
      );
    } else {
      canvas.saveLayer(rect, Paint());
      _paintBlobs(canvas, size, state.blobs, colors);
      canvas.restore();
    }

    _paintVignette(canvas, rect);
  }

  @override
  bool shouldRepaint(_BlobPainter old) =>
      old.state != state ||
      old.colors != colors ||
      old.baseColor != baseColor;
}
