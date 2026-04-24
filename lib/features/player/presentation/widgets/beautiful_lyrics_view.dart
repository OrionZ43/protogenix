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

// ── Цели пружин для каждого состояния ─────────────────────────────────────
// Изменяй здесь — правки мгновенно отразятся на всей анимации.
const _kWaitingScale = 1.00;
const _kWaitingYOffset = 0.00;
const _kWaitingGlow = 0.00;

const _kSingingScale =
    1.15; // +15% — пружина перелетит ещё выше за счёт overshoot
const _kSingingYOffset = -0.50; // вверх на 50% размера шрифта
const _kSingingGlow = 1.00;

const _kPassedScale = 1.00;
const _kPassedYOffset = 0.00;
const _kPassedGlow = 1.00; // спетые буквы остаются белыми (karaoke UX)

// Emphasized-слоги прыгают чуть выше — усиленный акцент
const _kSingingScaleEmph = 1.20;
const _kSingingYOffsetEmph = -0.65;

// ── Машина состояний слога ─────────────────────────────────────────────────
enum _SylState { waiting, singing, passed }

_SylState _stateFor(double currentMs, double startMs, double endMs) {
  if (currentMs < startMs) return _SylState.waiting;
  if (currentMs < endMs) return _SylState.singing;
  return _SylState.passed;
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
        child: CircularProgressIndicator(
          color: palette.primary,
          strokeWidth: 2,
        ),
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
          // Ambient фон
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
                    const Duration(milliseconds: _kUserScrollStopMs),
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
              itemCount: karaoke.lines.length,
              itemBuilder: (context, index) {
                final isCurrent = index == activeIndex;
                final distance = (index - activeIndex).abs();

                // FEAT Interactive Seeking: снимаем блюр со всех строк,
                // пока пользователь скроллит — текст становится читаемым.
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    color: Colors.white.withAlpha(18),
                    border: Border.all(color: Colors.white.withAlpha(45)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(100),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.my_location_rounded,
                        color: Colors.white70,
                        size: 14,
                      ),
                      SizedBox(width: 7),
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

    if (isCurrent) {
      final posMs = ref.watch(
        playerProvider.select((s) => s.position.inMilliseconds.toDouble()),
      );
      // TweenAnimationBuilder сглаживает дискретные прыжки позиции плеера.
      // Длительность 100мс — достаточно плавно, не «глотает» быстрые слоги.
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

    // FEAT Interactive Seeking: когда пользователь скроллит, строки
    // становятся кликабельными — тап перематывает трек к этой строке.
    if (userScrolling) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref
            .read(playerProvider.notifier)
            .seekTo(Duration(milliseconds: line.startMs)),
        child: content,
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: isCurrent ? 32 : 20),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 400),
        // При пользовательском скролле все строки становятся более заметными
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
// Активная строка с goal-based физикой.
//
// Принцип работы:
//   _onTick вычисляет _SylState для каждого слога.
//   При смене состояния → пружина получает новую ЦЕЛЬ через setAll().
//   После этого мы ТОЛЬКО шагаем: springs.step(dt).
//   Пружина сама разгоняется, перелетает (overshoot) и затухает.
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

  // Пружины и текущие состояния per-слог
  late final Map<LyricSyllable, SyllableSprings> _springs;
  final Map<LyricSyllable, _SylState> _states = {};

  // Визуальные значения, читаемые в build()
  final Map<LyricSyllable, ({double scale, double yOffset, double glow})>
  _vals = {};

  @override
  void initState() {
    super.initState();
    _allSyls = widget.line.allSyllables;

    _springs = {
      for (final syl in _allSyls)
        syl: SyllableSprings()
          // Все слоги стартуют в состоянии WAITING без анимации
          ..setAllImmediate(_kWaitingScale, _kWaitingYOffset, _kWaitingGlow),
    };

    // Заполняем начальные значения, чтобы build() не получил пустую map
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
      final newState = _stateFor(
        ms,
        syl.startMs.toDouble(),
        syl.endMs.toDouble(),
      );
      final oldState = _states[syl];

      // Обновляем цель пружины ТОЛЬКО при смене состояния.
      // Это сохраняет накопленную скорость (кинетическую энергию).
      if (newState != oldState) {
        _states[syl] = newState;
        switch (newState) {
          case _SylState.waiting:
            springs.setAll(_kWaitingScale, _kWaitingYOffset, _kWaitingGlow);
          case _SylState.singing:
            springs.setAll(_kSingingScale, _kSingingYOffset, _kSingingGlow);
          case _SylState.passed:
            springs.setAll(_kPassedScale, _kPassedYOffset, _kPassedGlow);
        }
      }

      // Шагаем пружину каждый кадр независимо от смены состояния
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
    // FIX: Плоский Wrap по allSyllables вместо Wrap(spacing) + Row-по-словам.
    // Расстояние между словами задаётся через Padding(right: 10) на последнем
    // слоге каждого слова (!syl.isPartOfWord). Это сохраняет идеальный baseline
    // шрифта и убирает визуальный мусор, который давал SizedBox/Wrap.spacing.
    return Wrap(
      runSpacing: 8,
      children: _allSyls.map((syl) {
        Widget child;

        // Emphasized: длинный слог (≥800ms) с несколькими символами
        if (syl.isEmphasized) {
          child = _EmphasizedSyllable(
            key: ValueKey('emph_${syl.startMs}'),
            syllable: syl,
            currentMs: widget.currentMs,
            palette: widget.palette,
          );
        } else {
          final vals =
              _vals[syl] ??
              (
                scale: _kWaitingScale,
                yOffset: _kWaitingYOffset,
                glow: _kWaitingGlow,
              );

          child = _LetterWidget(
            text: syl.text,
            scale: vals.scale,
            yOffset: vals.yOffset,
            glow: vals.glow,
            palette: widget.palette,
          );
        }

        // Конец слова: добавляем правый отступ вместо SizedBox/Wrap.spacing.
        // !isPartOfWord == последний слог в слове (см. _groupSyllablesIntoWords).
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
// Длинный слог → каждая буква получает равный временной слот и собственные
// пружины. Буквы прыгают по очереди — stagger-эффект Apple Music.
// ═══════════════════════════════════════════════════════════════════════════

/// Данные одной буквы в emphasized-слоге
class _LetterSlot {
  _LetterSlot({required this.char, required this.startMs, required this.endMs})
    : springs = SyllableSprings()
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

    // Строим равномерную временну́ю сетку по буквам
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
            slot.springs.setAll(
              _kWaitingScale,
              _kWaitingYOffset,
              _kWaitingGlow,
            );
          case _SylState.singing:
            // Emphasized прыгает сильнее обычного слога
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
          palette: widget.palette,
        );
      }).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LETTER WIDGET — одна буква / слог
// ═══════════════════════════════════════════════════════════════════════════

class _LetterWidget extends StatelessWidget {
  const _LetterWidget({
    required this.text,
    required this.scale,
    required this.yOffset,
    required this.glow,
    required this.palette,
  });

  final String text;
  final double scale;
  final double yOffset;
  final double glow;
  final PaletteState palette;

  @override
  Widget build(BuildContext context) {
    // glow [0..1]: 0 = тусклая непрочитанная, 1 = ярко-белая спетая
    final g = glow.clamp(0.0, 1.0);
    final color = Color.lerp(
      Colors.white.withAlpha(75), // waiting: приглушённый белый
      Colors.white, // singing / passed: чистый белый
      g,
    )!;

    final shadowAlpha = (g * 0.45 * 255).round();
    final blurRadius = 4.0 + 6.0 * g;

    return Transform.translate(
      offset: Offset(0, _kFontSize * yOffset),
      child: Transform.scale(
        scale: scale.clamp(0.8, 1.8),
        alignment: Alignment.bottomCenter,
        child: Text(
          text,
          style: TextStyle(
            fontSize: _kFontSize,
            fontWeight: FontWeight.w800,
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
    final fontSize = distance == 1
        ? 25.0
        : distance == 2
        ? 22.0
        : 19.0;

    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        color: Colors.white,
        height: 1.35,
      ),
      child: Text(line.plainText, softWrap: true),
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
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text(
              lines[i].plainText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.white.withAlpha(180),
                height: 1.6,
              ),
            ),
          ),
        ),
        const _Fade(top: true),
        const _Fade(top: false),
      ],
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
        Icon(Icons.lyrics_rounded, size: 52, color: Colors.white.withAlpha(30)),
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
  const _AmbientPainter({
    required this.c1,
    required this.c2,
    required this.pulse,
  });

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
        ..shader = RadialGradient(
          colors: [color, Colors.transparent],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
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
