// lib/features/player/presentation/widgets/syllable_karaoke_view.dart
//
// v2: добавлена микро-реакция активной строки на бас:
//   • bass > 0.8 → лёгкий "толчок" вперёд через пружину translateX
//   • Ambient-фон теперь тоже получает текущий bass из visualizerEngineProvider

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'dart:ui';

import '../../domain/lyric_spline.dart';
import '../../domain/spring.dart';
import '../../domain/advanced_lrc_parser.dart';
import '../../domain/visualizer_engine.dart';
import '../providers/karaoke_provider.dart';
import '../providers/palette_provider.dart';
import '../providers/player_provider.dart';

const _kDistanceToMaxBlur = 4;
const _kBlurScale = 1.25;
const _kUserScrollStopSec = 0.75;

// ═══════════════════════════════════════════════════════════════════════════
// SYLLABLE KARAOKE VIEW
// ═══════════════════════════════════════════════════════════════════════════

class SyllableKaraokeView extends ConsumerStatefulWidget {
  const SyllableKaraokeView({super.key, required this.lines});
  final List<LyricLine> lines;

  @override
  ConsumerState<SyllableKaraokeView> createState() =>
      _SyllableKaraokeViewState();
}

class _SyllableKaraokeViewState extends ConsumerState<SyllableKaraokeView>
    with SingleTickerProviderStateMixin {
  final ItemScrollController _scroll = ItemScrollController();
  final ItemPositionsListener _positions = ItemPositionsListener.create();

  bool _userScrolling = false;
  bool _autoScrolling = false;

  late final Ticker _ambientTicker;
  double _ambientPulse = 0;
  double _ambientPhase = 0;
  double _bass = 0.0;

  StreamSubscription<VisualizerSnapshot>? _visSub;

  @override
  void initState() {
    super.initState();
    _ambientTicker = createTicker(_onAmbientTick)..start();
    // Подписываемся на визуализатор для ambient-реакции фона
    _visSub = ref.read(visualizerEngineProvider).stream.listen((s) {
      if (mounted) setState(() => _bass = s.bass);
    });
  }

  void _onAmbientTick(Duration elapsed) {
    if (!mounted) return;
    setState(() {
      _ambientPhase = elapsed.inMilliseconds / 2400.0 * 2 * math.pi;
      _ambientPulse = 0.78 + 0.22 * (math.sin(_ambientPhase) * 0.5 + 0.5);
    });
  }

  @override
  void dispose() {
    _visSub?.cancel();
    _ambientTicker.dispose();
    super.dispose();
  }

  Future<void> _scrollTo(int index, {bool force = false}) async {
    if (_userScrolling && !force) return;
    if (!_scroll.isAttached) return;
    _autoScrolling = true;
    try {
      await _scroll.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeInOutCubic,
        alignment: 0.5,
      );
    } catch (_) {}
    Future.delayed(const Duration(milliseconds: 100), () {
      _autoScrolling = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(paletteProvider);

    ref.listen(karaokeProvider, (prev, next) {
      if (prev?.currentIndex != next.currentIndex &&
          next.currentIndex >= 0 &&
          !_userScrolling) {
        _scrollTo(next.currentIndex);
      }
    });

    final activeIndex = ref.watch(
      karaokeProvider.select((s) => s.currentIndex),
    );

    return Stack(
      children: [
        // Ambient-фон — реагирует на bass
        RepaintBoundary(
          child: CustomPaint(
            painter: _AmbientPainter(
              c1: palette.primary,
              c2: palette.secondary,
              pulse: _ambientPulse,
              bass: _bass,
            ),
            child: const SizedBox.expand(),
          ),
        ),

        // Список строк
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is UserScrollNotification) {
              if (n.direction != ScrollDirection.idle) {
                if (!_autoScrolling && !_userScrolling) {
                  setState(() => _userScrolling = true);
                }
              } else if (_userScrolling) {
                Future.delayed(
                  Duration(milliseconds: (_kUserScrollStopSec * 1000).toInt()),
                  () {
                    if (mounted) {
                      setState(() => _userScrolling = false);
                      _scrollTo(activeIndex, force: true);
                    }
                  },
                );
              }
            }
            return false;
          },
          child: ScrollablePositionedList.builder(
            itemScrollController: _scroll,
            itemPositionsListener: _positions,
            padding: EdgeInsets.symmetric(
              vertical: MediaQuery.of(context).size.height * 0.42,
              horizontal: 24,
            ),
            itemCount: widget.lines.length,
            itemBuilder: (context, index) {
              final distance = (index - activeIndex).abs();
              final isCurrent = index == activeIndex;
              final blurAmount = isCurrent
                  ? 0.0
                  : (distance / _kDistanceToMaxBlur).clamp(0.0, 1.0) *
                        _kBlurScale *
                        8.0;

              return _LineWidget(
                key: ValueKey(index),
                line: widget.lines[index],
                isCurrent: isCurrent,
                distance: distance,
                blurAmount: blurAmount,
                palette: palette,
              );
            },
          ),
        ),

        _buildFade(top: true),
        _buildFade(top: false),

        // Кнопка возврата к текущей строке
        AnimatedPositioned(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          bottom: _userScrolling ? 28 : -60,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: () {
                setState(() => _userScrolling = false);
                _scrollTo(activeIndex, force: true);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.white.withAlpha(20),
                  border: Border.all(color: Colors.white.withAlpha(45)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.my_location_rounded,
                      color: Colors.white70,
                      size: 14,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'К текущей строке',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFade({required bool top}) {
    return Positioned(
      top: top ? 0 : null,
      bottom: top ? null : 0,
      left: 0,
      right: 0,
      height: 110,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [
                Colors.black,
                Colors.black.withAlpha(190),
                Colors.transparent,
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LINE WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class _LineWidget extends ConsumerWidget {
  const _LineWidget({
    super.key,
    required this.line,
    required this.isCurrent,
    required this.distance,
    required this.blurAmount,
    required this.palette,
  });

  final LyricLine line;
  final bool isCurrent;
  final int distance;
  final double blurAmount;
  final PaletteState palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(playerProvider.select((s) => s.position));

    Widget content;

    if (isCurrent) {
      content = TweenAnimationBuilder<double>(
        tween: Tween(
          begin: position.inMilliseconds.toDouble(),
          end: position.inMilliseconds.toDouble(),
        ),
        duration: const Duration(milliseconds: 250),
        curve: Curves.linear,
        builder: (context, smoothMs, _) {
          return _ActiveLineWidget(
            line: line,
            currentMs: smoothMs,
            palette: palette,
          );
        },
      );
    } else {
      content = _InactiveLineWidget(line: line, distance: distance);
    }

    if (blurAmount > 0) {
      content = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
        child: content,
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: isCurrent ? 32 : 20),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 400),
        opacity: isCurrent
            ? 1.0
            : distance == 1
            ? 0.48
            : distance == 2
            ? 0.28
            : 0.14,
        child: content,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ACTIVE LINE WIDGET — с микро-реакцией на бас
// ═══════════════════════════════════════════════════════════════════════════

class _ActiveLineWidget extends ConsumerStatefulWidget {
  const _ActiveLineWidget({
    required this.line,
    required this.currentMs,
    required this.palette,
  });

  final LyricLine line;
  final double currentMs;
  final PaletteState palette;

  @override
  ConsumerState<_ActiveLineWidget> createState() => _ActiveLineWidgetState();
}

class _ActiveLineWidgetState extends ConsumerState<_ActiveLineWidget>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration? _lastTime;

  late final Map<LyricSyllable, SyllableSprings> _springs;
  final Map<LyricSyllable, ({double scale, double yOffset, double glow})>
  _values = {};

  // ── Бас-резонанс: горизонтальный «толчок» активной строки ─────────────────
  final LyricSpring _resonanceSpr = LyricSpring(
    initial: 0.0,
    dampingRatio: 0.35,
    frequency: 5.0,
  );
  double _resonanceX = 0.0;
  double _prevBass = 0.0;

  StreamSubscription<VisualizerSnapshot>? _visSub;
  double _bass = 0.0;

  @override
  void initState() {
    super.initState();

    _springs = {
      for (final syl in widget.line.allSyllables) syl: SyllableSprings(),
    };

    // Подписываемся на visualizer напрямую для минимальной задержки
    _visSub = ref.read(visualizerEngineProvider).stream.listen((snap) {
      if (!mounted) return;
      _bass = snap.bass;
      // bass > 0.8 → микро-толчок вперёд
      if (snap.bass > 0.8 && _prevBass <= 0.8) {
        final intensity = (snap.bass - 0.8) / 0.2; // 0..1
        _resonanceSpr.kick(velocity: intensity * 6.0);
      }
      _prevBass = snap.bass;
    });

    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;

    final now = elapsed;
    final dt = _lastTime == null
        ? 0.0
        : (now - _lastTime!).inMicroseconds / 1e6;
    _lastTime = now;

    final currentMs = widget.currentMs;
    final lineStart = widget.line.startMs.toDouble();
    final lineDur = widget.line.durationMs.toDouble();
    final lineTimeScale = ((currentMs - lineStart) / lineDur).clamp(0.0, 1.0);

    bool anyChanged = false;

    for (final entry in _springs.entries) {
      final syl = entry.key;
      final springs = entry.value;

      final sylStart = (syl.startMs - lineStart) / lineDur;
      final sylEnd = (syl.endMs - lineStart) / lineDur;
      final sylDur = sylEnd - sylStart;

      final double syllableTimeScale;
      if (sylDur <= 0) {
        syllableTimeScale = lineTimeScale >= sylStart ? 1.0 : 0.0;
      } else {
        syllableTimeScale = ((lineTimeScale - sylStart) / sylDur).clamp(
          0.0,
          1.0,
        );
      }

      springs.setAll(
        kScaleSpline.at(syllableTimeScale),
        kYOffsetSpline.at(syllableTimeScale),
        kGlowSpline.at(syllableTimeScale),
      );

      if (dt > 0) {
        final (s, y, g) = springs.step(dt.clamp(0.0, 0.1));
        _values[syl] = (scale: s, yOffset: y, glow: g);
        if (!springs.isSleeping) anyChanged = true;
      } else {
        _values[syl] = (
          scale: springs.scale.position,
          yOffset: springs.yOffset.position,
          glow: springs.glow.position,
        );
      }
    }

    // Обновляем resonance-пружину
    // Цель = небольшое смещение пропорционально текущему bass (ambient)
    _resonanceSpr.goal = _bass * 2.0; // max 2px смещение при bass=1
    final newRX = _resonanceSpr.update(dt.clamp(0.0, 0.1));
    if ((newRX - _resonanceX).abs() > 0.01) anyChanged = true;
    _resonanceX = newRX;

    if (anyChanged || dt == 0) setState(() {});
  }

  @override
  void dispose() {
    _visSub?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double fontSize = 32.0;

    return Transform.translate(
      offset: Offset(_resonanceX, 0), // ← горизонтальный толчок от баса
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: widget.line.words.map((word) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: word.syllables.map((syl) {
              final vals =
                  _values[syl] ?? (scale: 1.0, yOffset: 0.0, glow: 0.0);

              if (syl.isEmphasized) {
                return _EmphasizedSyllable(
                  syllable: syl,
                  values: vals,
                  fontSize: fontSize,
                  palette: widget.palette,
                  lineStartMs: widget.line.startMs.toDouble(),
                  lineDurMs: widget.line.durationMs.toDouble(),
                  currentMs: widget.currentMs,
                );
              } else {
                return _SyllableWidget(
                  text: syl.text,
                  values: vals,
                  fontSize: fontSize,
                  palette: widget.palette,
                );
              }
            }).toList(),
          );
        }).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SYLLABLE WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class _SyllableWidget extends StatelessWidget {
  const _SyllableWidget({
    required this.text,
    required this.values,
    required this.fontSize,
    required this.palette,
  });

  final String text;
  final ({double scale, double yOffset, double glow}) values;
  final double fontSize;
  final PaletteState palette;

  @override
  Widget build(BuildContext context) {
    final glowAlpha = values.glow.clamp(0.0, 1.0);
    final color = Color.lerp(
      Colors.white.withAlpha(110),
      Colors.white,
      glowAlpha,
    )!;
    final blurRadius = 4.0 + 2.0 * glowAlpha;
    final shadowAlpha = (glowAlpha * 0.35 * 255).round();

    return Transform(
      transform: Matrix4.translationValues(0, fontSize * values.yOffset, 0),
      alignment: Alignment.center,
      child: Transform.scale(
        scale: values.scale.clamp(0.5, 1.5),
        alignment: Alignment.bottomCenter,
        child: Text(
          text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            color: color,
            height: 1.25,
            shadows: shadowAlpha > 5
                ? [
                    Shadow(
                      color: Colors.white.withAlpha(shadowAlpha),
                      blurRadius: blurRadius,
                    ),
                    Shadow(
                      color: palette.primary.withAlpha(shadowAlpha ~/ 2),
                      blurRadius: blurRadius * 2,
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EMPHASIZED SYLLABLE
// ═══════════════════════════════════════════════════════════════════════════

class _EmphasizedSyllable extends StatelessWidget {
  const _EmphasizedSyllable({
    required this.syllable,
    required this.values,
    required this.fontSize,
    required this.palette,
    required this.lineStartMs,
    required this.lineDurMs,
    required this.currentMs,
  });

  final LyricSyllable syllable;
  final ({double scale, double yOffset, double glow}) values;
  final double fontSize;
  final PaletteState palette;
  final double lineStartMs;
  final double lineDurMs;
  final double currentMs;

  @override
  Widget build(BuildContext context) {
    final letters = syllable.text.characters.toList();
    if (letters.isEmpty) return const SizedBox.shrink();

    final sylStart = (syllable.startMs - lineStartMs) / lineDurMs;
    final sylEnd = (syllable.endMs - lineStartMs) / lineDurMs;
    final lineTs = ((currentMs - lineStartMs) / lineDurMs).clamp(0.0, 1.0);
    final rawSylTs = ((lineTs - sylStart) / (sylEnd - sylStart)).clamp(
      0.0,
      1.0,
    );
    final timeAlpha = math.sin(rawSylTs * math.pi / 2);
    final step = 1.0 / letters.length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(letters.length, (li) {
        final lStart = li * step;
        final lEnd = (li + 1) * step;
        final letterTs = ((timeAlpha - lStart) / (lEnd - lStart)).clamp(
          0.0,
          1.0,
        );
        final glowTs = ((timeAlpha - lStart) / (1.0 - lStart)).clamp(0.0, 1.0);

        return _SyllableWidget(
          text: letters[li],
          values: (
            scale: kScaleSpline.at(letterTs),
            yOffset: kYOffsetSpline.at(letterTs) * 2,
            glow: kGlowSpline.at(glowTs),
          ),
          fontSize: fontSize,
          palette: palette,
        );
      }),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// INACTIVE LINE
// ═══════════════════════════════════════════════════════════════════════════

class _InactiveLineWidget extends StatelessWidget {
  const _InactiveLineWidget({required this.line, required this.distance});
  final LyricLine line;
  final int distance;

  @override
  Widget build(BuildContext context) {
    final fontSize = distance == 1
        ? 25.0
        : distance == 2
        ? 22.0
        : 19.0;
    final text = line.words.map((w) => w.text).join(' ');

    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        color: Colors.white,
        height: 1.35,
      ),
      child: Text(text),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AMBIENT PAINTER — реагирует на bass
// ═══════════════════════════════════════════════════════════════════════════

class _AmbientPainter extends CustomPainter {
  const _AmbientPainter({
    required this.c1,
    required this.c2,
    required this.pulse,
    required this.bass,
  });
  final Color c1, c2;
  final double pulse;
  final double bass;

  @override
  void paint(Canvas canvas, Size size) {
    // Радиус blob-а растёт с bass
    final r1 = size.width * (0.72 + bass * 0.18);
    final r2 = size.width * (0.58 + bass * 0.14);

    _blob(
      canvas,
      center: Offset(size.width * 0.18, size.height * 0.22 * pulse),
      radius: r1,
      color: c1.withAlpha((50 + bass * 40).round().clamp(0, 255)),
    );
    _blob(
      canvas,
      center: Offset(
        size.width * 0.88,
        size.height * (0.72 + 0.08 * (1 - pulse)),
      ),
      radius: r2,
      color: c2.withAlpha((40 + bass * 30).round().clamp(0, 255)),
    );
  }

  void _blob(
    Canvas c, {
    required Offset center,
    required double radius,
    required Color color,
  }) {
    c.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [color, Colors.transparent],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_AmbientPainter o) =>
      o.pulse != pulse || o.c1 != c1 || o.c2 != c2 || o.bass != bass;
}
