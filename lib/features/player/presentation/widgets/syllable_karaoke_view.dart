// lib/features/player/presentation/widgets/syllable_karaoke_view.dart
//
// v2: добавлена микро-реакция активной строки на бас:
//   • bass > 0.8 → лёгкий "толчок" вперёд через пружину translateX
//   • Ambient-фон теперь тоже получает текущий bass из visualizerEngineProvider

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'dart:ui';

import '../../domain/glow_beam.dart';
import '../../domain/lyric_spline.dart';
import '../../domain/spring.dart';
import 'glow_letter.dart';
import '../../domain/advanced_lrc_parser.dart';
import '../../domain/visualizer_engine.dart';
import '../providers/karaoke_provider.dart';
import '../providers/palette_provider.dart';
import '../providers/player_provider.dart';

const _kDistanceToMaxBlur = 4;
const _kBlurScale = 1.25;

/// Пауза перед возвратом к активной строке после ручной прокрутки — как
/// в beautiful_lyrics_view.dart, там же и почему.
const _kUserScrollResume = Duration(seconds: 6);

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

  /// Отсчёт до возврата к активной строке после ручной прокрутки.
  Timer? _resumeTimer;

  late final Ticker _ambientTicker;
  /// Пульс фона и бас уходят прямо в painter: раньше каждый кадр вызывался
  /// setState, и весь вид караоке перестраивался по 60–120 раз в секунду
  /// (`performance.md`, правило 3).
  final _ambientPulse = ValueNotifier<double>(0);
  final _bass = ValueNotifier<double>(0);

  StreamSubscription<VisualizerSnapshot>? _visSub;

  @override
  void initState() {
    super.initState();
    _ambientTicker = createTicker(_onAmbientTick)..start();
    // Подписываемся на визуализатор для ambient-реакции фона
    _visSub = ref.read(visualizerEngineProvider).stream.listen((s) {
      if (mounted) _bass.value = s.bass;
    });
  }

  void _onAmbientTick(Duration elapsed) {
    if (!mounted) return;
    final phase = elapsed.inMilliseconds / 2400.0 * 2 * math.pi;
    _ambientPulse.value = 0.78 + 0.22 * (math.sin(phase) * 0.5 + 0.5);
  }

  @override
  void dispose() {
    _visSub?.cancel();
    _resumeTimer?.cancel();
    _ambientTicker.dispose();
    _ambientPulse.dispose();
    _bass.dispose();
    super.dispose();
  }

  void _beginUserScroll() {
    _resumeTimer?.cancel();
    if (!_userScrolling) setState(() => _userScrolling = true);
  }

  void _scheduleResume() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(_kUserScrollResume, _returnToCurrentLine);
  }

  void _returnToCurrentLine() {
    _resumeTimer?.cancel();
    if (!mounted) return;
    setState(() => _userScrolling = false);
    _scrollTo(ref.read(karaokeProvider).currentIndex, force: true);
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
            // Автопрокрутку за ручную не считаем
            if (_autoScrolling) return false;
            if (n is UserScrollNotification &&
                n.direction != ScrollDirection.idle) {
              _beginUserScroll();
            } else if (n is ScrollEndNotification && _userScrolling) {
              _scheduleResume();
            }
            return false;
          },
          child: ScrollablePositionedList.builder(
            itemScrollController: _scroll,
            itemPositionsListener: _positions,
            // Открыли плеер посреди песни — сразу на текущей строке
            initialScrollIndex: activeIndex <= 0
                ? 0
                : activeIndex.clamp(0, widget.lines.length - 1),
            initialAlignment: 0.5,
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
              onTap: _returnToCurrentLine,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.white.withAlpha(20),
                  border: Border.all(color: Colors.white.withAlpha(45)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.my_location_rounded,
                        color: Colors.white70, size: 14),
                    SizedBox(width: 6),
                    Text('К текущей строке',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
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
                Colors.transparent
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

  /// Значения пружин каждого слога: их читает GlowLetter при отрисовке, так
  /// что строка на каждый кадр не пересобирается (`glow_letter.dart`).
  final Map<LyricSyllable, ValueNotifier<GlowValues>> _values = {};

  /// У слогов с акцентом своя буква — свой набор значений.
  final Map<LyricSyllable, List<ValueNotifier<GlowValues>>> _letterValues = {};

  /// Горизонтальный толчок от баса: тоже без setState.
  final ValueNotifier<double> _resonance = ValueNotifier(0.0);

  // ── Бас-резонанс: горизонтальный «толчок» активной строки ─────────────────
  final LyricSpring _resonanceSpr = LyricSpring(
    initial: 0.0,
    dampingRatio: 0.35,
    frequency: 5.0,
  );
  double _prevBass = 0.0;

  StreamSubscription<VisualizerSnapshot>? _visSub;
  double _bass = 0.0;

  @override
  void initState() {
    super.initState();

    _springs = {
      for (final syl in widget.line.allSyllables) syl: SyllableSprings(),
    };
    for (final syl in widget.line.allSyllables) {
      _values[syl] = ValueNotifier(GlowValues.idle);
      if (syl.isEmphasized) {
        _letterValues[syl] = [
          for (var i = 0; i < syl.text.characters.length; i++)
            ValueNotifier(GlowValues.idle),
        ];
      }
    }

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
    final dt =
        _lastTime == null ? 0.0 : (now - _lastTime!).inMicroseconds / 1e6;
    _lastTime = now;

    final currentMs = widget.currentMs;
    final lineStart = widget.line.startMs.toDouble();
    final lineDur = widget.line.durationMs.toDouble();
    final lineTimeScale = ((currentMs - lineStart) / lineDur).clamp(0.0, 1.0);

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
        syllableTimeScale =
            ((lineTimeScale - sylStart) / sylDur).clamp(0.0, 1.0);
      }

      // Ореол едет с голосом, а не висит на всём спетом (`glow_beam.dart`)
      final beam = beamAt(
        currentMs,
        syl.startMs.toDouble(),
        syl.endMs.toDouble(),
      );

      springs.setAll(
        kScaleSpline.at(syllableTimeScale),
        kYOffsetSpline.at(syllableTimeScale),
        kGlowSpline.at(syllableTimeScale),
      );

      if (dt > 0) {
        final (s, y, g) = springs.step(dt.clamp(0.0, 0.1));
        _values[syl]!.value =
            GlowValues(scale: s, yOffset: y, glow: g, beam: beam * g);
      } else {
        final g = springs.glow.position;
        _values[syl]!.value = GlowValues(
          scale: springs.scale.position,
          yOffset: springs.yOffset.position,
          glow: g,
          beam: beam * g,
        );
      }

      // Слог с акцентом: у каждой буквы свой сдвинутый отрезок времени —
      // тот самый «перекат» по буквам
      final letters = _letterValues[syl];
      if (letters != null && letters.isNotEmpty) {
        final sylStart = (syl.startMs - lineStart) / lineDur;
        final sylEnd = (syl.endMs - lineStart) / lineDur;
        final rawSylTs =
            ((lineTimeScale - sylStart) / (sylEnd - sylStart)).clamp(0.0, 1.0);
        final timeAlpha = math.sin(rawSylTs * math.pi / 2);
        final step = 1.0 / letters.length;
        for (var li = 0; li < letters.length; li++) {
          final lStart = li * step;
          final lEnd = (li + 1) * step;
          final letterTs =
              ((timeAlpha - lStart) / (lEnd - lStart)).clamp(0.0, 1.0);
          final glowTs =
              ((timeAlpha - lStart) / (1.0 - lStart)).clamp(0.0, 1.0);
          final letterGlow = kGlowSpline.at(glowTs);
          letters[li].value = GlowValues(
            scale: kScaleSpline.at(letterTs),
            yOffset: kYOffsetSpline.at(letterTs) * 2,
            glow: letterGlow,
            beam: beam * letterGlow,
          );
        }
      }
    }

    // Обновляем resonance-пружину
    // Цель = небольшое смещение пропорционально текущему bass (ambient)
    _resonanceSpr.goal = _bass * 2.0; // max 2px смещение при bass=1
    _resonance.value = _resonanceSpr.update(dt.clamp(0.0, 0.1));
    // setState не нужен: значения читают GlowLetter и ValueListenableBuilder
  }

  @override
  void dispose() {
    _visSub?.cancel();
    _ticker.dispose();
    _resonance.dispose();
    for (final v in _values.values) {
      v.dispose();
    }
    for (final list in _letterValues.values) {
      for (final v in list) {
        v.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double fontSize = 32.0;

    // Строка собирается один раз: дальше её слоги перекрашиваются сами
    final line = Wrap(
      spacing: 6,
      runSpacing: 4,
      children: widget.line.words.map((word) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: word.syllables.map((syl) {
            final letters = _letterValues[syl];
            if (letters != null && letters.isNotEmpty) {
              final chars = syl.text.characters.toList();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < chars.length && i < letters.length; i++)
                    _SyllableWidget(
                      text: chars[i],
                      values: letters[i],
                      fontSize: fontSize,
                      palette: widget.palette,
                    ),
                ],
              );
            }
            return _SyllableWidget(
              text: syl.text,
              values: _values[syl]!,
              fontSize: fontSize,
              palette: widget.palette,
            );
          }).toList(),
        );
      }).toList(),
    );

    // ← горизонтальный толчок от баса: перерисовывается только обёртка,
    // сама строка не пересобирается (child проносится сквозь builder)
    return ValueListenableBuilder<double>(
      valueListenable: _resonance,
      child: line,
      builder: (context, dx, child) => Transform.translate(
        offset: Offset(dx, 0),
        child: child,
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
  final ValueListenable<GlowValues> values;
  final double fontSize;
  final PaletteState palette;

  /// Тот же вид, что был у Text с тенями, только рисуется без перестроения
  /// дерева на каждый кадр (`glow_letter.dart`).
  static const _style = GlowStyle(
    colorFrom: Color(0x6EFFFFFF), // белый 110
    shadowScale: 0.35,
    shadowThreshold: 5,
    blurBase: 4.0,
    blurSlope: 2.0,
    minScale: 0.5,
    maxScale: 1.5,
  );

  @override
  Widget build(BuildContext context) {
    return GlowLetter(
      text: text,
      values: values,
      fontSize: fontSize,
      glowColor: palette.primary,
      textScaler: MediaQuery.textScalerOf(context),
      style: _style,
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
  /// [pulse] и [bass] приходят значениями, а не полями виджета: перерисовка
  /// идёт по ним, без setState и перестроения дерева (`performance.md`).
  _AmbientPainter({
    required this.c1,
    required this.c2,
    required this.pulse,
    required this.bass,
  }) : super(repaint: Listenable.merge([pulse, bass]));

  final Color c1, c2;
  final ValueListenable<double> pulse;
  final ValueListenable<double> bass;

  @override
  void paint(Canvas canvas, Size size) {
    final pulse = this.pulse.value;
    final bass = this.bass.value;
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
      center:
          Offset(size.width * 0.88, size.height * (0.72 + 0.08 * (1 - pulse))),
      radius: r2,
      color: c2.withAlpha((40 + bass * 30).round().clamp(0, 255)),
    );
  }

  void _blob(Canvas c,
      {required Offset center, required double radius, required Color color}) {
    c.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(colors: [color, Colors.transparent])
            .createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_AmbientPainter o) => o.c1 != c1 || o.c2 != c2;
}
