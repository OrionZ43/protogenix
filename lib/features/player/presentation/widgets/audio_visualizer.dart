// lib/features/player/presentation/widgets/audio_visualizer.dart
//
// Визуализатор: показывается там, где раньше было пусто — когда у трека нет
// текста. Просили в отзывах («штука, которая двигается от звука»).
//
// Двигается по **настоящему спектру** трека (`domain/spectrogram.dart`):
// звук раскодирован заранее, разложен по 16 полосам от 40 Гц до 11 кГц
// 25 раз в секунду и лежит на диске. Ни микрофона, ни доступа к звуку
// в реальном времени для этого не нужно.
//
// Спектра нет (трек ещё считается, играет из сети или платформа без
// декодера) — берём огибающую громкости (`audio_envelope.dart`), а если и её
// нет, картинка просто ровно дышит: пустого места всё равно не будет.
//
// **Как это выглядит** (решение Orion 2026-09-27, после того как он забраковал
// «приборную» графику: «какие-то страшные они»). Основной вид — мягкие
// светящиеся пятна цвета обложки, как фон приложения, только живой: каждое
// пятно кормится своей полосой частот, все вместе дышат по низам и
// расходятся от центра на удар. Столбики остались вторым вариантом для тех,
// кому нужен обычный анализатор.
//
// По производительности (`performance.md`): пятна — это ровно та нагрузка,
// которая роняла телефон до 45 fps (крупные полупрозрачные области). Поэтому
// они рисуются тем же приёмом, что и фон приложения: в картинку вчетверо
// меньше экрана, которая пересобирается 30 раз в секунду и растягивается.
// Плюс один тикер на виджет, значения в общем списке, painter перерисовывается
// по счётчику кадров через `repaint`, всё внутри RepaintBoundary.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/audio_envelope.dart';
import '../../domain/spectrogram.dart';
import '../providers/envelope_provider.dart';
import '../providers/palette_provider.dart';
import '../providers/player_provider.dart';
import '../providers/spectrum_provider.dart';
import '../providers/visualizer_style_provider.dart';

/// Сколько значений считаем. Полос в спектре 16, между ними интерполируем:
/// столбикам нужна плавная линия, пятнам — усреднение по своему куску.
const _kBars = 48;

/// Во сколько раз уменьшается картинка с пятнами: смешивание идёт по 1/9
/// пикселей. У фона приложения множитель 4, но он на весь экран, а тут
/// область меньше, и на 4 пятна расплываются в кашу.
const _kGlowDownscale = 3.0;

/// Чаще 30 раз в секунду пятна не пересобираются: они мягкие, разницы не
/// видно, а работа экономится (`performance.md`).
const _kGlowInterval = 1 / 31;

class AudioVisualizer extends ConsumerStatefulWidget {
  const AudioVisualizer({super.key, this.compact = false});

  /// Компактный вид: предпросмотр в настройках.
  final bool compact;

  @override
  ConsumerState<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends ConsumerState<AudioVisualizer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  /// Счётчик кадров: по нему перерисовывается painter. Сами значения он
  /// читает из [_values] — новый список на кадр не создаётся.
  final _frame = ValueNotifier<int>(0);

  /// Уровни 0..1 по частотам, слева низы. Их читает painter.
  final _values = List<double>.filled(_kBars, 0);

  /// Полосы спектра в текущий момент — переиспользуемый буфер.
  List<double> _bands = const [];

  Spectrogram? _spectrum;
  AudioEnvelope? _envelope;
  Duration _position = Duration.zero;
  bool _playing = false;
  double _phase = 0;
  Duration? _lastTick;

  /// Позиция плеера приходит несколько раз в секунду, а кадров — под сотню.
  /// Между приходами ведём время сами, иначе удары «залипают».
  double _smoothMs = 0;

  /// Затухающий след от удара по низам: на нём картинка бьёт в такт.
  double _punch = 0;

  /// Своя фаза покачивания — нужна, когда спектра нет и картинка просто дышит.
  late final List<double> _phases;

  /// Пятна и их готовая картинка в уменьшенном размере.
  late final List<_GlowBlob> _blobs;
  int _glowTick = 0;
  double _sinceGlow = 0;
  ui.Image? _lowRes;
  int _lowResTick = -1;
  Size _lowResSize = Size.zero;
  Color _lowResAccent = const Color(0x00000000);

  @override
  void initState() {
    super.initState();
    final rng = math.Random(7);
    _phases = List.generate(_kBars, (_) => rng.nextDouble() * math.pi * 2);
    _blobs = _buildBlobs();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    _lowRes?.dispose();
    super.dispose();
  }

  /// Готовая картинка с пятнами. Пересобирается, только когда сменился такт
  /// (30 раз в секунду), размер или цвет обложки.
  ui.Image? lowResFor(Size size, Color accent) {
    if (size.isEmpty) return null;
    if (_lowRes != null &&
        _lowResTick == _glowTick &&
        _lowResSize == size &&
        _lowResAccent == accent) {
      return _lowRes;
    }

    final w = (size.width / _kGlowDownscale).round().clamp(1, 4096);
    final h = (size.height / _kGlowDownscale).round().clamp(1, 4096);
    final recorder = ui.PictureRecorder();
    _paintGlow(
      Canvas(recorder),
      Size(w.toDouble(), h.toDouble()),
      _blobs,
      _Accent(accent),
      _punch,
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(w, h);
    picture.dispose();

    _lowRes?.dispose();
    _lowRes = image;
    _lowResTick = _glowTick;
    _lowResSize = size;
    _lowResAccent = accent;
    return image;
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final dt = _lastTick == null
        ? 0.016
        : ((elapsed - _lastTick!).inMicroseconds / 1e6).clamp(0.001, 0.1);
    _lastTick = elapsed;
    _phase += dt;

    // Плеер сообщает позицию несколько раз в секунду, а кадр рисуется чаще.
    // Между сообщениями идём сами, иначе удар приходит рывком и мимо.
    final reported = _position.inMilliseconds.toDouble();
    if ((reported - _smoothMs).abs() > 400) {
      _smoothMs = reported; // перемотка или смена трека
    } else if (_playing) {
      _smoothMs += dt * 1000;
      _smoothMs += (reported - _smoothMs) * (dt * 3).clamp(0.0, 1.0);
    } else {
      _smoothMs = reported;
    }

    final ms = _smoothMs.round();
    final spectrum = _spectrum;
    final hasSpectrum = spectrum != null && !spectrum.isEmpty;

    if (hasSpectrum) {
      if (_bands.length != spectrum.bands) {
        _bands = List<double>.filled(spectrum.bands, 0);
      }
      spectrum.sampleInto(_bands, ms);
      final punch = spectrum.punchAt(ms);
      if (_playing && punch > _punch) _punch = punch;
    } else {
      final envelope = _envelope;
      if (envelope != null && !envelope.isEmpty && _playing) {
        final punch = envelope.punchAt(ms);
        if (punch > _punch) _punch = punch;
      }
    }
    // След от удара затухает за ~250 мс
    _punch = (_punch - dt * 4.0).clamp(0.0, 1.0);

    var changed = false;
    for (var i = 0; i < _kBars; i++) {
      double target;
      if (hasSpectrum) {
        target = _bandAt(_bands, i / (_kBars - 1));
        if (!_playing) target *= 0.55;
      } else {
        final envelope = _envelope;
        final level = envelope != null && !envelope.isEmpty
            ? envelope.at(ms)
            : 0.35 + 0.2 * math.sin(_phase * 1.5 + _phases[i]);
        // Без спектра частот нет: ровное дыхание с небольшим разбросом
        target = level *
                (0.75 + 0.25 * math.sin(_phase * 2.2 + _phases[i])) *
                (_playing ? 1.0 : 0.6) +
            _punch * 0.35;
      }
      target = target.clamp(0.0, 1.0);

      // Быстро вверх, плавно вниз — так удар читается глазом
      final current = _values[i];
      final speed = target > current ? 26.0 : 7.0;
      final next = current + (target - current) * (dt * speed).clamp(0.0, 1.0);
      if ((next - current).abs() > 0.0005) changed = true;
      _values[i] = next;
    }

    // Пятна живут своей, более ленивой жизнью: дрейф и сглаженный уровень
    for (final blob in _blobs) {
      blob.advance(dt, _phase, _values);
    }
    _sinceGlow += dt;
    if (_sinceGlow >= _kGlowInterval) {
      _sinceGlow = 0;
      _glowTick++;
      changed = true;
    }

    if (changed) _frame.value++;
  }

  @override
  Widget build(BuildContext context) {
    _spectrum = ref.watch(currentSpectrumProvider);
    _envelope = ref.watch(currentEnvelopeProvider);
    final player = ref.watch(playerProvider.select((s) => (
          position: s.position,
          isPlaying: s.isPlaying,
        )));
    _position = player.position;
    _playing = player.isPlaying;

    // Нужен только основной цвет обложки: тёмный `secondary` из палитры
    // для рисования не годится, см. `_Accent`
    final accent = ref.watch(paletteProvider.select((p) => p.primary));
    final style = ref.watch(visualizerStyleProvider);

    return RepaintBoundary(
      child: Padding(
        // Вплотную к краям панели картинка выглядит обрезанной
        padding: widget.compact
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
            : const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        child: CustomPaint(
          painter: switch (style) {
            VisualizerStyle.glow => _GlowPainter(
                frame: _frame,
                state: this,
                accent: accent,
              ),
            VisualizerStyle.bars => _BarsPainter(
                frame: _frame,
                values: _values,
                primary: accent,
                compact: widget.compact,
              ),
          },
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// Значение полосы в доле [t] (0 — самые низы, 1 — самые верха), между
/// полосами линейно.
double _bandAt(List<double> bands, double t) {
  if (bands.isEmpty) return 0;
  if (bands.length == 1) return bands.first;
  final exact = t.clamp(0.0, 1.0) * (bands.length - 1);
  final i = exact.floor();
  final next = math.min(i + 1, bands.length - 1);
  return bands[i] + (bands[next] - bands[i]) * (exact - i);
}

/// Средний уровень на куске частот [from]..[to] (доли от низов к верхам).
double _bandRange(List<double> values, double from, double to) {
  if (values.isEmpty) return 0;
  final a = (from * (values.length - 1)).round().clamp(0, values.length - 1);
  final b = (to * (values.length - 1)).round().clamp(0, values.length - 1);
  final lo = math.min(a, b);
  final hi = math.max(a, b);
  var sum = 0.0;
  for (var i = lo; i <= hi; i++) {
    sum += values[i];
  }
  return sum / (hi - lo + 1);
}

/// Средний уровень — по нему «дышит» картинка целиком.
double _average(List<double> values) {
  if (values.isEmpty) return 0;
  var sum = 0.0;
  for (final v in values) {
    sum += v;
  }
  return sum / values.length;
}

// ── Цвета ───────────────────────────────────────────────────────────────────

/// Цвета визуализатора из палитры обложки.
///
/// **`secondary` здесь не годится.** В палитре он намеренно тёмный (яркость
/// зажата до 0.05–0.5, `palette_provider.dart`) — он для фонов. Пока столбики
/// красились градиентом primary → secondary, правая половина анализатора
/// уходила в почти-чёрный, и вся картинка выглядела мёртвой.
///
/// Берём только `primary` и делаем из него оттенки. Заодно подстраховываемся
/// от серых обложек: у них palette_generator отдаёт блёклый цвет, а серое
/// пятно на чёрном — это не украшение.
class _Accent {
  _Accent(Color primary)
      : this._(HSLColor.fromColor(primary)
            .withSaturation(
                math.max(0.45, HSLColor.fromColor(primary).saturation))
            .withLightness(
                HSLColor.fromColor(primary).lightness.clamp(0.52, 0.72)));

  _Accent._(this._base);

  final HSLColor _base;

  /// Основной цвет.
  Color get main => _base.toColor();

  /// Светлый оттенок — верхушки столбиков и блики.
  Color get light => _base
      .withLightness((_base.lightness + 0.22).clamp(0.0, 0.92))
      .withSaturation((_base.saturation * 0.85).clamp(0.0, 1.0))
      .toColor();

  /// Тёмный оттенок того же цвета — для глубины, но не чёрный.
  Color get deep =>
      _base.withLightness((_base.lightness - 0.18).clamp(0.12, 1.0)).toColor();

  /// Соседний оттенок: сдвиг по кругу цветов на [degrees]. Нужен, чтобы
  /// пятна не были одноцветной кашей.
  Color shifted(double degrees, {double lightness = 0}) {
    final hue = (_base.hue + degrees) % 360;
    return _base
        .withHue(hue < 0 ? hue + 360 : hue)
        // Насыщенность держим высокой: `BlendMode.screen` сам по себе тянет
        // наложения к белому, и на блёклых цветах получается серая дымка
        .withSaturation((_base.saturation * 1.15).clamp(0.55, 1.0))
        .withLightness((_base.lightness + lightness).clamp(0.0, 0.92))
        .toColor();
  }
}

/// Плавная кривая через точки (Catmull-Rom в кубические Безье) — линия по
/// верхушкам столбиков не должна иметь углов.
Path _smoothThrough(List<Offset> points) {
  final path = Path();
  final n = points.length;
  if (n == 0) return path;
  if (n < 3) {
    path.moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return path;
  }

  Offset at(int i) => points[i.clamp(0, n - 1)];

  path.moveTo(points.first.dx, points.first.dy);
  for (var i = 0; i < n - 1; i++) {
    final p0 = at(i - 1);
    final p1 = at(i);
    final p2 = at(i + 1);
    final p3 = at(i + 2);
    path.cubicTo(
      p1.dx + (p2.dx - p0.dx) / 6,
      p1.dy + (p2.dy - p0.dy) / 6,
      p2.dx - (p3.dx - p1.dx) / 6,
      p2.dy - (p3.dy - p1.dy) / 6,
      p2.dx,
      p2.dy,
    );
  }
  return path;
}

// ── Мягкие пятна ────────────────────────────────────────────────────────────

/// Одно пятно: висит на своём месте, кормится своим куском частот.
class _GlowBlob {
  _GlowBlob({
    required this.bandFrom,
    required this.bandTo,
    required this.homeX,
    required this.homeY,
    required this.sizeRatio,
    required this.hueShift,
    required this.driftPhase,
    required this.driftSpeed,
    required this.driftRadius,
  });

  /// Какой кусок спектра его кормит (0 — низы, 1 — верха).
  final double bandFrom;
  final double bandTo;

  /// Место в долях от размера, вокруг которого оно гуляет.
  final double homeX;
  final double homeY;

  final double sizeRatio;
  final double hueShift;
  final double driftPhase;
  final double driftSpeed;
  final double driftRadius;

  /// Сглаженный уровень: пятну резкость ни к чему, оно мягкое.
  double level = 0;

  double _dx = 0;
  double _dy = 0;

  double get offsetX => _dx;
  double get offsetY => _dy;

  void advance(double dt, double phase, List<double> values) {
    final target = _bandRange(values, bandFrom, bandTo);
    // Вверх быстрее, вниз медленнее — но мягче, чем у столбиков
    final speed = target > level ? 9.0 : 3.5;
    level += (target - level) * (dt * speed).clamp(0.0, 1.0);

    final t = phase * driftSpeed + driftPhase;
    _dx = math.cos(t) * driftRadius;
    _dy = math.sin(t * 1.3) * driftRadius * 0.8;
  }
}

/// Шесть пятен: низы в середине и крупные, верха по краям и мелкие — так же,
/// как звук и ощущается.
List<_GlowBlob> _buildBlobs() => [
      _GlowBlob(
        bandFrom: 0.0,
        bandTo: 0.16,
        homeX: 0.50,
        homeY: 0.54,
        sizeRatio: 1.00,
        hueShift: 0,
        driftPhase: 0.0,
        driftSpeed: 0.35,
        driftRadius: 0.035,
      ),
      _GlowBlob(
        bandFrom: 0.14,
        bandTo: 0.34,
        homeX: 0.27,
        homeY: 0.40,
        sizeRatio: 0.80,
        hueShift: -8,
        driftPhase: 1.7,
        driftSpeed: 0.47,
        driftRadius: 0.045,
      ),
      _GlowBlob(
        bandFrom: 0.30,
        bandTo: 0.50,
        homeX: 0.73,
        homeY: 0.38,
        sizeRatio: 0.74,
        hueShift: 7,
        driftPhase: 3.1,
        driftSpeed: 0.41,
        driftRadius: 0.045,
      ),
      _GlowBlob(
        bandFrom: 0.46,
        bandTo: 0.68,
        homeX: 0.33,
        homeY: 0.70,
        sizeRatio: 0.62,
        hueShift: 12,
        driftPhase: 4.4,
        driftSpeed: 0.55,
        driftRadius: 0.05,
      ),
      _GlowBlob(
        bandFrom: 0.64,
        bandTo: 0.86,
        homeX: 0.70,
        homeY: 0.71,
        sizeRatio: 0.56,
        hueShift: -13,
        driftPhase: 5.6,
        driftSpeed: 0.62,
        driftRadius: 0.05,
      ),
      _GlowBlob(
        bandFrom: 0.82,
        bandTo: 1.0,
        homeX: 0.50,
        homeY: 0.26,
        sizeRatio: 0.46,
        hueShift: 17,
        driftPhase: 2.3,
        driftSpeed: 0.7,
        driftRadius: 0.055,
      ),
    ];

/// Пятна на прозрачном. `BlendMode.screen` смешивает их между собой — там,
/// где они накладываются, свет складывается, как у фона приложения.
void _paintGlow(
  Canvas canvas,
  Size size,
  List<_GlowBlob> blobs,
  _Accent accent,
  double punch,
) {
  final minSide = math.min(size.width, size.height);
  for (final blob in blobs) {
    // На удар пятна расходятся от середины и вспыхивают
    final push = 1.0 + punch * 0.16;
    final cx = (0.5 + (blob.homeX - 0.5) * push + blob.offsetX) * size.width;
    final cy = (0.5 + (blob.homeY - 0.5) * push + blob.offsetY) * size.height;

    final radius = minSide *
        0.36 *
        blob.sizeRatio *
        (0.42 + blob.level * 0.95 + punch * 0.14);
    if (radius <= 0.5) continue;

    final centre = Offset(cx, cy);
    final colour = accent.shifted(blob.hueShift, lightness: blob.level * 0.14);
    final alpha = (0.14 + blob.level * 0.62 + punch * 0.12).clamp(0.0, 0.95);

    // Резкий спад от ядра к краю: с пологим получается туман, а не пятна
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            colour.withValues(alpha: alpha),
            colour.withValues(alpha: alpha * 0.45),
            colour.withValues(alpha: alpha * 0.10),
            colour.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.28, 0.62, 1.0],
        ).createShader(Rect.fromCircle(center: centre, radius: radius))
        ..blendMode = BlendMode.screen,
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter({
    required this.frame,
    required this.state,
    required this.accent,
  }) : super(repaint: frame);

  final ValueListenable<int> frame;
  final _AudioVisualizerState state;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final image = state.lowResFor(size, accent);
    if (image == null) return;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.state != state || old.accent != accent;
}

// ── Столбики ────────────────────────────────────────────────────────────────

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.frame,
    required this.values,
    required this.primary,
    required this.compact,
  }) : super(repaint: frame);

  final ValueListenable<int> frame;
  final List<double> values;
  final Color primary;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.isEmpty) return;

    final accent = _Accent(primary);
    final gap = compact ? 2.5 : 4.0;
    final barWidth = (size.width - gap * (values.length - 1)) / values.length;
    if (barWidth <= 0) return;

    final baseline = size.height * 0.66;
    final maxHeight = size.height * 0.54;
    final energy = _average(values);

    // Мягкое пятно света под столбиками — глубина без размытия
    final ambient = Rect.fromCenter(
      center: Offset(size.width / 2, baseline),
      width: size.width,
      height: size.height * 1.4,
    );
    canvas.drawRect(
      ambient,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.main.withValues(alpha: 0.10 + energy * 0.14),
            accent.main.withValues(alpha: 0.0),
          ],
        ).createShader(ambient),
    );

    // Все столбики — одной фигурой: заливка идёт одним градиентом сверху вниз,
    // поэтому высокий столбик светится верхушкой, а низкий остаётся
    // приглушённым. Это и даёт объём вместо плоских палок.
    final bars = Path();
    final mirror = Path();
    final tops = <Offset>[];

    for (var i = 0; i < values.length; i++) {
      final height = (values[i] * maxHeight).clamp(barWidth * 0.55, maxHeight);
      final x = i * (barWidth + gap);
      final radius = Radius.circular(barWidth / 2);

      bars.addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(x, baseline - height, barWidth, height),
        radius,
      ));
      mirror.addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(x, baseline + gap * 1.6, barWidth, height * 0.45),
        radius,
      ));
      tops.add(Offset(x + barWidth / 2, baseline - height));
    }

    final barsArea =
        Rect.fromLTWH(0, baseline - maxHeight, size.width, maxHeight);
    canvas.drawPath(
      bars,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.light,
            accent.main,
            accent.deep.withValues(alpha: 0.55),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(barsArea),
    );

    // Отражение: не копия в 18% прозрачности, а плавное угасание вниз
    final mirrorArea = Rect.fromLTWH(
      0,
      baseline,
      size.width,
      maxHeight * 0.45 + gap * 1.6,
    );
    canvas.drawPath(
      mirror,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.main.withValues(alpha: 0.26),
            accent.main.withValues(alpha: 0.0),
          ],
        ).createShader(mirrorArea),
    );

    // Светящаяся линия по верхушкам — один мазок с размытием. Именно она
    // даёт «неон», а размывать всю заливку было бы дорого (performance.md)
    final crest = _smoothThrough(tops);
    canvas.drawPath(
      crest,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = compact ? 2.0 : 2.6
        ..strokeCap = StrokeCap.round
        ..color = accent.light.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, compact ? 5 : 9),
    );
    canvas.drawPath(
      crest,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = compact ? 1.0 : 1.4
        ..strokeCap = StrokeCap.round
        ..color = accent.light.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.primary != primary || old.compact != compact || old.values != values;
}
