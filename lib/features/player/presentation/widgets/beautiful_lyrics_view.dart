// lib/features/player/presentation/widgets/beautiful_lyrics_view.dart
//
// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  GOAL-BASED SPRING PHYSICS  (v3 — полностью переписан)                 ║
// ╠══════════════════════════════════════════════════════════════════════════╣
// ║  Ключевое отличие от предыдущих версий:                                 ║
// ║  Мы НЕ ведём пружину по сплайну каждый кадр (это убивает инерцию).     ║
// ║  Вместо этого — конечный автомат из трёх состояний:                     ║
// ║                                                                          ║
// ║   WAITING  → цель: scale=1.0 / yOffset= 0.0 / glow=0.0                 ║
// ║   SINGING  → цель: scale=1.15 / yOffset=-0.5 / glow=1.0                ║
// ║   PASSED   → цель: scale=1.0 / yOffset= 0.0 / glow=1.0 (остаётся бел.) ║
// ║                                                                          ║
// ║  Цель меняется ТОЛЬКО при смене состояния. Пружина сама разгоняется     ║
// ║  и делает overshoot — это и есть живая анимация.                         ║
// ║                                                                          ║
// ║  _EmphasizedSyllable: каждая буква получает свой слот времени,          ║
// ║  собственные пружины и ту же машину состояний → stagger-прыжок.         ║
// ╚══════════════════════════════════════════════════════════════════════════╝
//
// CHANGELOG v3.1:
//   FIX   Убран Wrap(spacing) + вложенные Row-по-словам. Вместо этого
//         используется плоский Wrap по allSyllables. Последний слог каждого
//         слова (!syl.isPartOfWord) получает Padding(right: 10) — это
//         сохраняет идеальный baseline и убирает визуальный мусор.
//   FEAT  Interactive Lyrics Seeking: при _userScrolling текст разблюривается,
//         каждая строка оборачивается в GestureDetector — тап перематывает
//         воспроизведение к этой строке.
//
// CHANGELOG v3.2 — Whisper Effect (бэк-вокал / ад-либы):
//   FEAT  LyricSyllable.isBackground → _LetterWidget рендерит фоновые слоги
//         меньшим шрифтом (22px), курсивом, базовой непрозрачностью 0.4.
//   FEAT  SyllableSprings для фоновых слогов создаются с уменьшенным
//         overshoot: dampingRatio=0.85, frequency=0.55 — плавное проявление
//         без перетягивания внимания.
//   FEAT  _InactiveLine отображает фоновые слова меньшим шрифтом + opacity.

import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../domain/advanced_lrc_parser.dart';
import '../../domain/spring.dart';
import '../providers/karaoke_provider.dart';
import '../providers/palette_provider.dart';
import '../providers/player_provider.dart';

// ── Глобальные константы UI ────────────────────────────────────────────────
const _kDistanceToMaxBlur = 4;
const _kBlurScale = 1.25;
const _kUserScrollStopMs = 750;
const _kFontSize = 32.0;

/// Размер шрифта для бэк-вокала / ад-либов
const _kBgFontSize = 22.0;

/// Базовая непрозрачность фоновых слогов в состоянии WAITING
const _kBgBaseOpacity = 0.4;

// ── Цели пружин для каждого состояния ─────────────────────────────────────
const _kWaitingScale = 1.00;
const _kWaitingYOffset = 0.00;
const _kWaitingGlow = 0.00;

const _kSingingScale = 1.15;
const _kSingingYOffset = -0.50;
const _kSingingGlow = 1.00;

const _kPassedScale = 1.00;
const _kPassedYOffset = 0.00;
const _kPassedGlow = 1.00;

// Emphasized-слоги прыгают чуть выше — усиленный акцент
const _kSingingScaleEmph = 1.20;
const _kSingingYOffsetEmph = -0.65;

// Фоновые слоги — сниженный overshoot, плавное проявление
const _kBgSingingScale = 1.06;
const _kBgSingingYOffset = -0.20;
const _kBgSingingGlow = 0.75;

// ── Машина состояний слога ─────────────────────────────────────────────────
enum _SylState { waiting, singing, passed }

_SylState _stateFor(double currentMs, double startMs, double endMs) {
  if (currentMs < startMs) return _SylState.waiting;
  if (currentMs < endMs) return _SylState.singing;
  return _SylState.passed;
}

/// Создаёт SyllableSprings с параметрами, зависящими от isBackground.
/// Фоновые слоги: высокий damping + низкая frequency → мягкое проявление.
SyllableSprings _makeSprings({required bool isBackground}) {
  if (!isBackground) {
    return SyllableSprings();
  }
  // Пружины для бэк-вокала: почти критически затухшие, медленнее
  return SyllableSprings.withParams(
    scaleDamping: 0.85,
    scaleFrequency: 0.55,
    yOffsetDamping: 0.80,
    yOffsetFrequency: 0.80,
    glowDamping: 0.70,
    glowFrequency: 0.65,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// BEAUTIFUL LYRICS VIEW
// ═══════════════════════════════════════════════════════════════════════════

class BeautifulLyricsView extends ConsumerStatefulWidget {
  const BeautifulLyricsView({super.key});

  @override
  ConsumerState<BeautifulLyricsView> createState() =>
      _BeautifulLyricsViewState();
}

class _BeautifulLyricsViewState extends ConsumerState<BeautifulLyricsView>
    with SingleTickerProviderStateMixin {
  final ItemScrollController _scroll = ItemScrollController();
  final ItemPositionsListener _positions = ItemPositionsListener.create();

  bool _userScrolling = false;
  bool _autoScrolling = false;

  late final Ticker _ambientTicker;
  double _ambientPulse = 0.78;

  @override
  void initState() {
    super.initState();
    _ambientTicker = createTicker(_onAmbientTick)..start();
  }

  void _onAmbientTick(Duration elapsed) {
    if (!mounted) return;
    final phase = elapsed.inMilliseconds / 2400.0 * 2 * math.pi;
    setState(() {
      _ambientPulse = 0.78 + 0.22 * (math.sin(phase) * 0.5 + 0.5);
    });
  }

  @override
  void dispose() {
    _ambientTicker.dispose();
    super.dispose();
  }

  Future<void> _scrollTo(int index, {bool force = false}) async {
    if (_userScrolling && !force) return;
    if (index < 0) return;
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
    Future.delayed(
      const Duration(milliseconds: 120),
          () => _autoScrolling = false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final karaoke = ref.watch(karaokeProvider);
    final palette = ref.watch(paletteProvider);

    ref.listen(karaokeProvider.select((s) => s.currentIndex), (prev, next) {
      if (prev != next && next >= 0 && !_userScrolling) _scrollTo(next);
    });

    if (!karaoke.isLoaded) {
      return Center(
        child:
        CircularProgressIndicator(color: palette.primary, strokeWidth: 2),
      );
    }

    if (karaoke.lines.isEmpty) return _EmptyState(palette: palette);

    if (karaoke.format == LyricsFormat.plain) {
      return _PlainLyricsView(lines: karaoke.lines, palette: palette);
    }

    final activeIndex = karaoke.currentIndex;

    return RepaintBoundary(
      child: Stack(
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: _AmbientPainter(
                c1: palette.primary,
                c2: palette.secondary,
                pulse: _ambientPulse,
              ),
              child: const SizedBox.expand(),
            ),
          ),

          NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is UserScrollNotification) {
                if (n.direction != ScrollDirection.idle) {
                  if (!_autoScrolling && !_userScrolling) {
                    setState(() => _userScrolling = true);
                  }
                } else if (_userScrolling) {
                  Future.delayed(
                      const Duration(milliseconds: _kUserScrollStopMs), () {
                    if (mounted) {
                      setState(() => _userScrolling = false);
                      _scrollTo(activeIndex, force: true);
                    }
                  });
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
              itemCount: karaoke.lines.length,
              itemBuilder: (context, index) {
                final isCurrent = index == activeIndex;
                final distance = (index - activeIndex).abs();

                final blurAmount = _userScrolling
                    ? 0.0
                    : isCurrent
                    ? 0.0
                    : (distance / _kDistanceToMaxBlur).clamp(0.0, 1.0) *
                    _kBlurScale *
                    8.0;

                return _LineItem(
                  key: ValueKey('line_$index'),
                  line: karaoke.lines[index],
                  isCurrent: isCurrent,
                  distance: distance,
                  blurAmount: blurAmount,
                  palette: palette,
                  userScrolling: _userScrolling,
                );
              },
            ),
          ),

          const _Fade(top: true),
          const _Fade(top: false),

          Positioned(
            top: 18,
            left: 24,
            child: Text(
              'LYRICS',
              style: TextStyle(
                color: Colors.white.withAlpha(45),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 4,
              ),
            ),
          ),

          AnimatedPositioned(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            bottom: _userScrolling ? 28 : -64,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: () {
                  setState(() => _userScrolling = false);
                  _scrollTo(activeIndex, force: true);
                },
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    color: Colors.white.withAlpha(18),
                    border: Border.all(color: Colors.white.withAlpha(45)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withAlpha(100), blurRadius: 16),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.my_location_rounded,
                          color: Colors.white70, size: 14),
                      SizedBox(width: 7),
                      Text('К текущей строке',
                          style:
                          TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LINE ITEM
// ═══════════════════════════════════════════════════════════════════════════

class _LineItem extends ConsumerWidget {
  const _LineItem({
    super.key,
    required this.line,
    required this.isCurrent,
    required this.distance,
    required this.blurAmount,
    required this.palette,
    required this.userScrolling,
  });

  final LyricLine line;
  final bool isCurrent;
  final int distance;
  final double blurAmount;
  final PaletteState palette;
  final bool userScrolling;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget content;

    // ── КРИТИЧНО: держим _SpringLineWidget живым при distance <= 1 ──────
    // Это предотвращает резкое "исчезновение" анимации последнего слова
    // при переходе на новую строку. Для только что прошедшей строки
    // (distance == 1, line.endMs < posMs) все слоги окажутся в состоянии
    // PASSED и пружины плавно осядут. Для следующей строки — WAITING.
    if (isCurrent || distance == 1) {
      final posMs = ref.watch(
        playerProvider.select((s) => s.position.inMilliseconds.toDouble()),
      );
      content = TweenAnimationBuilder<double>(
        tween: Tween(begin: posMs, end: posMs),
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
        builder: (_, smoothMs, __) => _SpringLineWidget(
          line: line,
          currentMs: smoothMs,
          palette: palette,
        ),
      );
    } else {
      content = _InactiveLine(line: line, distance: distance);
    }

    if (blurAmount > 0) {
      content = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
        child: content,
      );
    }

    if (userScrolling) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(playerProvider.notifier).seekTo(
          Duration(milliseconds: line.startMs),
        ),
        child: content,
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: isCurrent ? 32 : 20),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 400),
        opacity: userScrolling
            ? (isCurrent ? 1.0 : 0.65)
            : isCurrent
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
// SPRING LINE WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class _SpringLineWidget extends StatefulWidget {
  const _SpringLineWidget({
    required this.line,
    required this.currentMs,
    required this.palette,
  });

  final LyricLine line;
  final double currentMs;
  final PaletteState palette;

  @override
  State<_SpringLineWidget> createState() => _SpringLineWidgetState();
}

class _SpringLineWidgetState extends State<_SpringLineWidget>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration? _lastElapsed;

  late final List<LyricSyllable> _allSyls;

  late final Map<LyricSyllable, SyllableSprings> _springs;
  final Map<LyricSyllable, _SylState> _states = {};

  final Map<LyricSyllable, ({double scale, double yOffset, double glow})>
  _vals = {};

  @override
  void initState() {
    super.initState();
    _allSyls = widget.line.allSyllables;

    _springs = {
      for (final syl in _allSyls)
        syl: _makeSprings(isBackground: syl.isBackground)
          ..setAllImmediate(_kWaitingScale, _kWaitingYOffset, _kWaitingGlow),
    };

    for (final syl in _allSyls) {
      _states[syl] = _SylState.waiting;
      _vals[syl] = (
      scale: _kWaitingScale,
      yOffset: _kWaitingYOffset,
      glow: _kWaitingGlow,
      );
    }

    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;

    final dt = _lastElapsed == null
        ? 0.0
        : (elapsed - _lastElapsed!).inMicroseconds / 1e6;
    _lastElapsed = elapsed;

    final ms = widget.currentMs;
    var anyActive = false;

    for (final syl in _allSyls) {
      final springs = _springs[syl]!;
      final newState =
      _stateFor(ms, syl.startMs.toDouble(), syl.endMs.toDouble());
      final oldState = _states[syl];

      if (newState != oldState) {
        _states[syl] = newState;
        switch (newState) {
          case _SylState.waiting:
            springs.setAll(_kWaitingScale, _kWaitingYOffset, _kWaitingGlow);
          case _SylState.singing:
          // Фоновые слоги — меньший «прыжок»
            if (syl.isBackground) {
              springs.setAll(
                  _kBgSingingScale, _kBgSingingYOffset, _kBgSingingGlow);
            } else {
              springs.setAll(_kSingingScale, _kSingingYOffset, _kSingingGlow);
            }
          case _SylState.passed:
            springs.setAll(_kPassedScale, _kPassedYOffset, _kPassedGlow);
        }
      }

      if (dt > 0) {
        final (s, y, g) = springs.step(dt.clamp(0.0, 0.1));
        _vals[syl] = (scale: s, yOffset: y, glow: g);
        if (!springs.isSleeping) anyActive = true;
      } else {
        _vals[syl] = (
        scale: springs.scale.position,
        yOffset: springs.yOffset.position,
        glow: springs.glow.position,
        );
      }
    }

    if (anyActive || dt == 0) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      runSpacing: 8,
      // Выравниваем по нижнему краю (аппроксимация baseline для разных размеров
      // шрифта: основной 32px + фоновый 22px). Transform.scale с alignment =
      // Alignment.bottomCenter масштабирует вверх → нижние края совпадают.
      crossAxisAlignment: WrapCrossAlignment.end,
      children: _allSyls.map((syl) {
        Widget child;

        if (syl.isEmphasized && !syl.isBackground) {
          // Emphasized только для основного вокала — бэк-вокал не акцентируем
          child = _EmphasizedSyllable(
            key: ValueKey('emph_${syl.startMs}'),
            syllable: syl,
            currentMs: widget.currentMs,
            palette: widget.palette,
          );
        } else {
          final vals = _vals[syl] ??
              (
              scale: _kWaitingScale,
              yOffset: _kWaitingYOffset,
              glow: _kWaitingGlow
              );

          child = _LetterWidget(
            text: syl.text,
            scale: vals.scale,
            yOffset: vals.yOffset,
            glow: vals.glow,
            isBackground: syl.isBackground,
            palette: widget.palette,
          );
        }

        if (!syl.isPartOfWord) {
          return Padding(
            padding: const EdgeInsets.only(right: 10.0),
            child: child,
          );
        }

        return child;
      }).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EMPHASIZED SYLLABLE
// ═══════════════════════════════════════════════════════════════════════════

class _LetterSlot {
  _LetterSlot({
    required this.char,
    required this.startMs,
    required this.endMs,
  })  : springs = SyllableSprings()
    ..setAllImmediate(_kWaitingScale, _kWaitingYOffset, _kWaitingGlow),
        state = _SylState.waiting,
        scale = _kWaitingScale,
        yOffset = _kWaitingYOffset,
        glow = _kWaitingGlow;

  final String char;
  final double startMs;
  final double endMs;
  final SyllableSprings springs;

  _SylState state;
  double scale;
  double yOffset;
  double glow;
}

class _EmphasizedSyllable extends StatefulWidget {
  const _EmphasizedSyllable({
    super.key,
    required this.syllable,
    required this.currentMs,
    required this.palette,
  });

  final LyricSyllable syllable;
  final double currentMs;
  final PaletteState palette;

  @override
  State<_EmphasizedSyllable> createState() => _EmphasizedSyllableState();
}

class _EmphasizedSyllableState extends State<_EmphasizedSyllable>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration? _lastElapsed;
  late final List<_LetterSlot> _slots;

  @override
  void initState() {
    super.initState();

    final chars = widget.syllable.text.characters.toList();
    final sylStart = widget.syllable.startMs.toDouble();
    final sylEnd = widget.syllable.endMs.toDouble();
    final slotDur = (sylEnd - sylStart) / chars.length.clamp(1, 999);

    _slots = List.generate(chars.length, (i) {
      return _LetterSlot(
        char: chars[i],
        startMs: sylStart + i * slotDur,
        endMs: sylStart + (i + 1) * slotDur,
      );
    });

    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;

    final dt = _lastElapsed == null
        ? 0.0
        : (elapsed - _lastElapsed!).inMicroseconds / 1e6;
    _lastElapsed = elapsed;

    final ms = widget.currentMs;
    var anyActive = false;

    for (final slot in _slots) {
      final newState = _stateFor(ms, slot.startMs, slot.endMs);

      if (newState != slot.state) {
        slot.state = newState;
        switch (newState) {
          case _SylState.waiting:
            slot.springs
                .setAll(_kWaitingScale, _kWaitingYOffset, _kWaitingGlow);
          case _SylState.singing:
            slot.springs.setAll(
              _kSingingScaleEmph,
              _kSingingYOffsetEmph,
              _kSingingGlow,
            );
          case _SylState.passed:
            slot.springs.setAll(_kPassedScale, _kPassedYOffset, _kPassedGlow);
        }
      }

      if (dt > 0) {
        final (s, y, g) = slot.springs.step(dt.clamp(0.0, 0.1));
        slot.scale = s;
        slot.yOffset = y;
        slot.glow = g;
        if (!slot.springs.isSleeping) anyActive = true;
      } else {
        slot.scale = slot.springs.scale.position;
        slot.yOffset = slot.springs.yOffset.position;
        slot.glow = slot.springs.glow.position;
      }
    }

    if (anyActive || dt == 0) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_slots.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: _slots.map((slot) {
        return _LetterWidget(
          text: slot.char,
          scale: slot.scale,
          yOffset: slot.yOffset,
          glow: slot.glow,
          isBackground: false,
          palette: widget.palette,
        );
      }).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LETTER WIDGET — одна буква / слог
//
// Whisper Effect:
//   isBackground = true →
//     • fontSize уменьшен до _kBgFontSize (22px)
//     • базовая непрозрачность _kBgBaseOpacity (0.4) в состоянии WAITING
//     • FontStyle.italic для визуального отделения
//     • Свечение при пении слабее (glow умножается на 0.6)
// ═══════════════════════════════════════════════════════════════════════════

class _LetterWidget extends StatelessWidget {
  const _LetterWidget({
    required this.text,
    required this.scale,
    required this.yOffset,
    required this.glow,
    required this.isBackground,
    required this.palette,
  });

  final String text;
  final double scale;
  final double yOffset;
  final double glow;
  final bool isBackground;
  final PaletteState palette;

  @override
  Widget build(BuildContext context) {
    final fontSize = isBackground ? _kBgFontSize : _kFontSize;

    // Для бэк-вокала приглушаем glow и базовую белизну
    final effectiveGlow = isBackground ? glow * 0.6 : glow;
    final g = effectiveGlow.clamp(0.0, 1.0);

    // WAITING-состояние: у фоновых слогов непрозрачность 0.4, у основных 75/255
    final waitingAlpha = isBackground ? (255 * _kBgBaseOpacity).round() : 75;
    final color = Color.lerp(
      Colors.white.withAlpha(waitingAlpha),
      Colors.white,
      g,
    )!;

    // Свечение для фона слабее
    final shadowAlpha = isBackground
        ? (g * 0.25 * 255).round()
        : (g * 0.45 * 255).round();
    final blurRadius = isBackground
        ? 2.0 + 4.0 * g
        : 4.0 + 6.0 * g;

    return Transform.translate(
      offset: Offset(0, fontSize * yOffset),
      child: Transform.scale(
        scale: scale.clamp(0.8, 1.8),
        alignment: Alignment.bottomCenter,
        // Baseline гарантирует, что при разных fontSize алфавитная базовая линия
        // выровнена относительно родителя (Wrap с WrapCrossAlignment.end).
        // baseline ≈ 0.8 * fontSize — типичное положение alphabetic baseline.
        child: Baseline(
          baseline: fontSize * 0.82,
          baselineType: TextBaseline.alphabetic,
          child: Text(
            text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBackground ? FontWeight.w500 : FontWeight.w800,
              fontStyle: isBackground ? FontStyle.italic : FontStyle.normal,
              color: color,
              height: 1.25,
              shadows: shadowAlpha > 8
                  ? [
                Shadow(
                  color: Colors.white.withAlpha(shadowAlpha),
                  blurRadius: blurRadius,
                ),
                Shadow(
                  color: palette.primary.withAlpha(shadowAlpha ~/ 2),
                  blurRadius: blurRadius * 2.0,
                ),
              ]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// INACTIVE LINE
// ═══════════════════════════════════════════════════════════════════════════

class _InactiveLine extends StatelessWidget {
  const _InactiveLine({required this.line, required this.distance});

  final LyricLine line;
  final int distance;

  @override
  Widget build(BuildContext context) {
    final baseFontSize = distance == 1
        ? 25.0
        : distance == 2
        ? 22.0
        : 19.0;

    // Если вся строка — бэк-вокал, показываем её меньше и курсивом
    if (line.isBackgroundLine) {
      return AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        style: TextStyle(
          fontSize: (baseFontSize * 0.75).clamp(13.0, 20.0),
          fontWeight: FontWeight.w400,
          fontStyle: FontStyle.italic,
          color: Colors.white.withOpacity(_kBgBaseOpacity),
          height: 1.35,
        ),
        child: Text(line.plainText, softWrap: true),
      );
    }

    // Смешанная строка (часть слов фоновая) — строим RichText
    final hasAnyBackground = line.words.any((w) => w.isBackground);
    if (hasAnyBackground) {
      return _MixedInactiveLine(line: line, baseFontSize: baseFontSize);
    }

    // Обычная строка
    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      style: TextStyle(
        fontSize: baseFontSize,
        fontWeight: FontWeight.w500,
        color: Colors.white,
        height: 1.35,
      ),
      child: Text(line.plainText, softWrap: true),
    );
  }
}

/// Неактивная строка со смешанным содержимым (часть слов — бэк-вокал).
class _MixedInactiveLine extends StatelessWidget {
  const _MixedInactiveLine({
    required this.line,
    required this.baseFontSize,
  });

  final LyricLine line;
  final double baseFontSize;

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];

    for (var i = 0; i < line.words.length; i++) {
      final word = line.words[i];
      if (i > 0) spans.add(const TextSpan(text: ' '));

      if (word.isBackground) {
        spans.add(TextSpan(
          text: word.text,
          style: TextStyle(
            fontSize: (baseFontSize * 0.75).clamp(13.0, 20.0),
            fontWeight: FontWeight.w400,
            fontStyle: FontStyle.italic,
            color: Colors.white.withOpacity(_kBgBaseOpacity),
          ),
        ));
      } else {
        spans.add(TextSpan(
          text: word.text,
          style: TextStyle(
            fontSize: baseFontSize,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ));
      }
    }

    return Text.rich(
      TextSpan(children: spans),
      softWrap: true,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PLAIN LYRICS VIEW
// ═══════════════════════════════════════════════════════════════════════════

class _PlainLyricsView extends StatelessWidget {
  const _PlainLyricsView({required this.lines, required this.palette});

  final List<LyricLine> lines;
  final PaletteState palette;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CustomPaint(
          painter: _AmbientPainter(
            c1: palette.primary,
            c2: palette.secondary,
            pulse: 0.9,
          ),
          child: const SizedBox.expand(),
        ),
        ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 60),
          itemCount: lines.length,
          itemBuilder: (context, i) {
            final line = lines[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: _PlainLineWidget(line: line),
            );
          },
        ),
        const _Fade(top: true),
        const _Fade(top: false),
      ],
    );
  }
}

/// Рендерит одну строку plain-текста.
///
/// • Вся строка фоновая → маленький курсив, приглушённый цвет.
/// • Смешанная строка (часть слов bg) → RichText с двумя стилями.
/// • Обычная строка → Text.
class _PlainLineWidget extends StatelessWidget {
  const _PlainLineWidget({super.key, required this.line});
  final LyricLine line;

  static const _mainStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    fontStyle: FontStyle.normal,
    color: Color(0xFFB4B4B4), // white @ 180 alpha
    height: 1.6,
  );

  static const _bgStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    fontStyle: FontStyle.italic,
    color: Color(0x5AFFFFFF), // white @ 90 alpha
    height: 1.6,
  );

  @override
  Widget build(BuildContext context) {
    // Вся строка фоновая
    if (line.isBackgroundLine) {
      return Text(
        line.plainText,
        textAlign: TextAlign.center,
        style: _bgStyle,
      );
    }

    // Проверяем наличие хотя бы одного bg-слова (mixed строка)
    final hasMixed = line.words.any((w) => w.isBackground);
    if (!hasMixed) {
      return Text(
        line.plainText,
        textAlign: TextAlign.center,
        style: _mainStyle,
      );
    }

    // Mixed: собираем RichText с inline-переключением стиля
    final spans = <InlineSpan>[];
    for (var i = 0; i < line.words.length; i++) {
      if (i > 0) {
        // пробел наследует стиль предыдущего слова — визуально нейтрально
        spans.add(const TextSpan(text: ' '));
      }
      final word = line.words[i];
      spans.add(TextSpan(
        text: word.text,
        style: word.isBackground ? _bgStyle : _mainStyle,
      ));
    }

    return Text.rich(
      TextSpan(children: spans),
      textAlign: TextAlign.center,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EMPTY STATE
// ═══════════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.palette});
  final PaletteState palette;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lyrics_rounded,
            size: 52, color: Colors.white.withAlpha(30)),
        const SizedBox(height: 14),
        Text(
          'Текст не найден',
          style: TextStyle(
            color: Colors.white.withAlpha(45),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// AMBIENT PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _AmbientPainter extends CustomPainter {
  const _AmbientPainter(
      {required this.c1, required this.c2, required this.pulse});

  final Color c1, c2;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    _blob(
      canvas,
      center: Offset(size.width * 0.18, size.height * 0.22 * pulse),
      radius: size.width * 0.72,
      color: c1.withAlpha(50),
    );
    _blob(
      canvas,
      center: Offset(
        size.width * 0.88,
        size.height * (0.72 + 0.08 * (1 - pulse)),
      ),
      radius: size.width * 0.58,
      color: c2.withAlpha(40),
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
        ..shader = RadialGradient(colors: [color, Colors.transparent])
            .createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_AmbientPainter o) =>
      o.pulse != pulse || o.c1 != c1 || o.c2 != c2;
}

// ═══════════════════════════════════════════════════════════════════════════
// FADE OVERLAY
// ═══════════════════════════════════════════════════════════════════════════

class _Fade extends StatelessWidget {
  const _Fade({required this.top});
  final bool top;

  @override
  Widget build(BuildContext context) => Positioned(
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