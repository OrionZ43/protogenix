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
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../domain/advanced_lrc_parser.dart';
import '../../domain/spring.dart';
import '../../../../core/utils/haptic_patterns.dart';
import '../providers/karaoke_provider.dart';
import '../providers/palette_provider.dart';
import '../providers/player_provider.dart';

// ── Глобальные константы UI ────────────────────────────────────────────────
const _kDistanceToMaxBlur = 4;
const _kBlurScale = 1.25;
const _kUserScrollStopMs = 750;
const _kFontSize = 32.0;
const _kBgFontSize = _kFontSize * 0.62; // бэк-вокал: 62% от основного

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

// Бэк-вокал: мягче и тише — не отвлекает от основной строки
const _kBgSingingScale = 1.07;
const _kBgSingingYOffset = -0.22; // почти не прыгает
const _kBgSingingGlow = 0.85;    // чуть приглушённее

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

class _BeautifulLyricsViewState extends ConsumerState<BeautifulLyricsView> {
  final ItemScrollController _scroll = ItemScrollController();
  final ItemPositionsListener _positions = ItemPositionsListener.create();

  bool _userScrolling = false;
  bool _autoScrolling = false;

  /// Позиция плеера — обновляется каждый кадр через SchedulerBinding.
  /// Только ValueNotifier.value меняется → нет setState → нет rebuild дерева.
  final ValueNotifier<double> _positionMs = ValueNotifier(0.0);
  bool _frameCallbackScheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleFrame();
  }

  void _scheduleFrame() {
    if (_frameCallbackScheduled) return;
    _frameCallbackScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
  }

  void _onFrame(Duration _) {
    _frameCallbackScheduled = false;
    if (!mounted) return;
    _positionMs.value =
        ref.read(playerProvider).position.inMilliseconds.toDouble();
    _scheduleFrame();
  }

  @override
  void dispose() {
    _frameCallbackScheduled = false;
    _positionMs.dispose();
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
        // Плавный easeOutCubic — предсказуем, без переботка spring
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        alignment: 0.45, // чуть выше центра — текущая строка читается лучше
      );
    } catch (_) {}
    Future.delayed(
      const Duration(milliseconds: 140),
          () => _autoScrolling = false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final karaoke = ref.watch(karaokeProvider);
    final palette = ref.watch(paletteProvider);

    ref.listen(karaokeProvider.select((s) => s.currentIndex), (prev, next) {
      if (prev != next && next >= 0) {
        if (!_userScrolling) _scrollTo(next);
        // Тактильный тик при каждой смене строки
        HapticPatterns.lyricsLine();
      }
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
    // Для line-synced форматов (syncedLrc) не рисуем буквенную анимацию —
    // только подсветка всей строки. YRC / enhancedLrc — полная анимация.
    final hasWordSync = karaoke.format == LyricsFormat.yrc ||
        karaoke.format == LyricsFormat.enhancedLrc;

    return RepaintBoundary(
      child: Stack(
        children: [
          // Фон со своим тикером — не трогает rebuild списка строк
          _AmbientBackground(palette: palette),

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

                return RepaintBoundary(
                  child: _LineItem(
                    key: ValueKey('line_$index'),
                    line: karaoke.lines[index],
                    isCurrent: isCurrent,
                    distance: distance,
                    blurAmount: blurAmount,
                    palette: palette,
                    userScrolling: _userScrolling,
                    positionMs: _positionMs,    // ← ValueNotifier, без Riverpod
                    hasWordSync: hasWordSync,    // ← тип анимации
                  ),
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

class _LineItem extends StatelessWidget {
  const _LineItem({
    super.key,
    required this.line,
    required this.isCurrent,
    required this.distance,
    required this.blurAmount,
    required this.palette,
    required this.userScrolling,
    required this.positionMs,
    required this.hasWordSync,
  });

  final LyricLine line;
  final bool isCurrent;
  final int distance;
  final double blurAmount;
  final PaletteState palette;
  final bool userScrolling;
  /// Позиция плеера — ValueNotifier обновляется каждый кадр через ticker.
  /// Нет Riverpod-watch здесь → нет rebuild-каскада при смене позиции.
  final ValueNotifier<double> positionMs;
  /// true = YRC/Enhanced → буквенная пружинная анимация
  /// false = syncedLrc → подсветка всей строки целиком
  final bool hasWordSync;

  @override
  Widget build(BuildContext context) {
    // Ключ для AnimatedSwitcher: меняется при переходе между режимами
    final bool useSpring = isCurrent || distance <= 1;

    Widget activeContent;
    if (useSpring) {
      if (hasWordSync) {
        activeContent = _SpringLineWidget(
          key: ValueKey('spring_${line.startMs}'),
          line: line,
          positionMs: positionMs,
          palette: palette,
        );
      } else {
        activeContent = _HighlightedLineWidget(
          key: ValueKey('highlight_${line.startMs}'),
          line: line,
          positionMs: positionMs,
          palette: palette,
        );
      }
    } else {
      activeContent = _InactiveLine(
        key: ValueKey('inactive_${line.startMs}'),
        line: line,
        distance: distance,
      );
    }

    // AnimatedSwitcher даёт плавный crossfade при переходе
    // _SpringLineWidget (all-passed) → _InactiveLine.
    // FadeTransition — минимальные аллокации, нет layout-pass во время fade.
    Widget content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      // По умолчанию Stack внутри AnimatedSwitcher использует Alignment.center —
      // это центрирует уходящий виджет внутри бокса входящего. Фиксируем topLeft.
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topLeft,
        children: [
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      child: activeContent,
    );

    if (blurAmount > 0) {
      content = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
        child: content,
      );
    }

    if (userScrolling) {
      content = Consumer(
        builder: (context, ref, child) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ref.read(playerProvider.notifier).seekTo(
            Duration(milliseconds: line.startMs),
          ),
          child: child,
        ),
        child: content,
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: isCurrent ? 32 : 20),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        opacity: userScrolling
            ? (isCurrent ? 1.0 : 0.65)
            : isCurrent
            ? 1.0
            : distance == 1
            ? 0.45
            : distance == 2
            ? 0.25
            : 0.12,
        child: content,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SPRING LINE WIDGET
// Активная строка с goal-based физикой.
//
// КЛЮЧЕВОЕ ИЗМЕНЕНИЕ v3.2:
//   Принимает ValueListenable<double> вместо double currentMs.
//   Ticker читает positionMs.value НАПРЯМУЮ без rebuild родителя.
//   → Только _SpringLineWidget.setState() вызывается на каждый кадр,
//     а не вся цепочка Riverpod → _LineItem → TweenAnimationBuilder → виджет.
// ═══════════════════════════════════════════════════════════════════════════

class _SpringLineWidget extends StatefulWidget {
  const _SpringLineWidget({
    super.key,
    required this.line,
    required this.positionMs,
    required this.palette,
  });

  final LyricLine line;
  final ValueListenable<double> positionMs;
  final PaletteState palette;

  @override
  State<_SpringLineWidget> createState() => _SpringLineWidgetState();
}

class _SpringLineWidgetState extends State<_SpringLineWidget>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration? _lastElapsed;

  late final List<LyricSyllable> _allSyls;
  // Кешируем разбивку — _allSyls не меняется за время жизни виджета
  late final List<LyricSyllable> _mainSyls;
  late final List<LyricSyllable> _bgSyls;

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
    // Один раз делим на main/bg — в build() только читаем
    _mainSyls = _allSyls.where((s) => !s.isBackground).toList();
    _bgSyls   = _allSyls.where((s) => s.isBackground).toList();

    _springs = {
      for (final syl in _allSyls)
        syl: SyllableSprings()
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

    final ms = widget.positionMs.value;
    var anyActive = false;

    for (final syl in _allSyls) {
      final springs = _springs[syl]!;
      final newState =
      _stateFor(ms, syl.startMs.toDouble(), syl.endMs.toDouble());
      final oldState = _states[syl];

      if (newState != oldState) {
        _states[syl] = newState;
        // Бэк-вокал получает более мягкие цели пружин
        final isBg = syl.isBackground;
        switch (newState) {
          case _SylState.waiting:
            springs.setAll(_kWaitingScale, _kWaitingYOffset, _kWaitingGlow);
          case _SylState.singing:
            springs.setAll(
              isBg ? _kBgSingingScale : _kSingingScale,
              isBg ? _kBgSingingYOffset : _kSingingYOffset,
              isBg ? _kBgSingingGlow : _kSingingGlow,
            );
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

  /// Собирает Wrap из слогов. [syls] — уже отфильтрованный список.
  Widget _buildWrap(List<LyricSyllable> syls) {
    return Wrap(
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: syls.map((syl) {
        Widget child;

        if (syl.isEmphasized && !syl.isBackground) {
          child = _EmphasizedSyllable(
            key: ValueKey('emph_${syl.startMs}'),
            syllable: syl,
            positionMs: widget.positionMs,
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

        // Пробел между словами через правый padding на последнем слоге слова
        if (!syl.isPartOfWord) {
          return Padding(
            padding: EdgeInsets.only(
              right: syl.isBackground ? 6.0 : 10.0,
            ),
            child: child,
          );
        }

        return child;
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // _mainSyls и _bgSyls закешированы в initState — нет аллокаций в build()
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_mainSyls.isNotEmpty) _buildWrap(_mainSyls),
        if (_bgSyls.isNotEmpty) ...[
          const SizedBox(height: 5),
          _buildWrap(_bgSyls),
        ],
      ],
    );
  }
} // end _SpringLineWidgetState

// ═══════════════════════════════════════════════════════════════════════════
// HIGHLIGHTED LINE WIDGET (Task 3)
// Для синхронизированных, но не пословных форматов (syncedLrc).
// Вся строка подсвечивается целиком — никакой "фейковой" буквенной анимации.
// ═══════════════════════════════════════════════════════════════════════════

class _HighlightedLineWidget extends StatefulWidget {
  const _HighlightedLineWidget({
    super.key,
    required this.line,
    required this.positionMs,
    required this.palette,
  });

  final LyricLine line;
  final ValueListenable<double> positionMs;
  final PaletteState palette;

  @override
  State<_HighlightedLineWidget> createState() => _HighlightedLineWidgetState();
}

class _HighlightedLineWidgetState extends State<_HighlightedLineWidget>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  // Пружина для glow текущей строки
  late final SyllableSprings _spring;
  _SylState _state = _SylState.waiting;
  double _glow = 0.0;

  @override
  void initState() {
    super.initState();
    _spring = SyllableSprings()
      ..setAllImmediate(_kWaitingScale, _kWaitingYOffset, _kWaitingGlow);
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final ms = widget.positionMs.value;
    final newState = _stateFor(
      ms,
      widget.line.startMs.toDouble(),
      widget.line.endMs.toDouble(),
    );

    if (newState != _state) {
      _state = newState;
      switch (newState) {
        case _SylState.waiting:
          _spring.setAll(_kWaitingScale, _kWaitingYOffset, _kWaitingGlow);
        case _SylState.singing:
          _spring.setAll(_kSingingScale, _kSingingYOffset, _kSingingGlow);
        case _SylState.passed:
          _spring.setAll(_kPassedScale, _kPassedYOffset, _kPassedGlow);
      }
    }

    final stepResult = _spring.step(1 / 60.0);
    final g = stepResult.$3; // только glow; scale и yOffset для строки не нужны
    if (_glow != g) {
      _glow = g;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = _glow.clamp(0.0, 1.0);
    final color = Color.lerp(Colors.white.withAlpha(75), Colors.white, g)!;
    final shadowAlpha = (g * 0.45 * 255).round();
    final blurR = 4.0 + 6.0 * g;

    return Text(
      widget.line.plainText,
      style: TextStyle(
        fontSize: _kFontSize,
        fontWeight: FontWeight.w800,
        color: color,
        height: 1.25,
        shadows: shadowAlpha > 8
            ? [
          Shadow(
            color: Colors.white.withAlpha(shadowAlpha),
            blurRadius: blurR,
          ),
          Shadow(
            color: widget.palette.primary.withAlpha(shadowAlpha ~/ 2),
            blurRadius: blurR * 2,
          ),
        ]
            : null,
      ),
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
    required this.positionMs,
    required this.palette,
  });

  final LyricSyllable syllable;
  final ValueListenable<double> positionMs;
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

    final ms = widget.positionMs.value;
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
    this.isBackground = false,
  });

  final String text;
  final double scale;
  final double yOffset;
  final double glow;
  final PaletteState palette;
  final bool isBackground;

  @override
  Widget build(BuildContext context) {
    final g = glow.clamp(0.0, 1.0);
    final color = Color.lerp(
      Colors.white.withAlpha(75),
      Colors.white,
      g,
    )!;

    final fontSize = isBackground ? _kBgFontSize : _kFontSize;
    final shadowAlpha =
    isBackground ? (g * 0.22 * 255).round() : (g * 0.45 * 255).round();
    final blurRadius = 4.0 + 6.0 * g;

    return Transform.translate(
      offset: Offset(0, _kFontSize * yOffset),
      child: Transform.scale(
        scale: scale.clamp(0.8, 1.8),
        alignment: Alignment.bottomCenter,
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
                  color:
                  palette.primary.withAlpha(shadowAlpha ~/ 2),
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
// Все строки рендерятся при _kFontSize (32px) → перенос слов одинаков всегда.
// Визуальное уменьшение — Transform.scale, который НЕ влияет на layout.
// Нет рефлоу при приближении строки = нет прыжков высоты.
// ═══════════════════════════════════════════════════════════════════════════

class _InactiveLine extends StatelessWidget {
  const _InactiveLine({super.key, required this.line, required this.distance});

  final LyricLine line;
  final int distance;

  // Масштаб соответствует старым fontSize: 25/32, 22/32, 19/32
  static double _scaleFor(int d) => switch (d) {
    1 => 0.78,
    2 => 0.69,
    _ => 0.59,
  };

  @override
  Widget build(BuildContext context) {
    final scale = _scaleFor(distance);

    final mainText = line.words
        .where((w) => !w.isBackground)
        .map((w) => w.text)
        .join(' ');
    final bgText = line.words
        .where((w) => w.isBackground)
        .map((w) => w.text)
        .join(' ');

    // Базовый стиль всегда на _kFontSize — layout одинаков на любой distance.
    // AnimatedScale даёт плавное визуальное уменьшение без layout-пересчёта.
    return AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mainText.isNotEmpty)
            Text(
              mainText,
              softWrap: true,
              style: const TextStyle(
                fontSize: _kFontSize,
                fontWeight: FontWeight.w500,
                color: Colors.white,
                height: 1.35,
              ),
            ),
          if (bgText.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              bgText,
              softWrap: true,
              style: TextStyle(
                fontSize: _kBgFontSize,
                fontWeight: FontWeight.w400,
                fontStyle: FontStyle.italic,
                color: Colors.white.withAlpha(140),
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
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
// AMBIENT BACKGROUND
// Изолированный виджет с собственным тикером для пульсации фона.
// setState здесь не затрагивает список строк — только перерисовывает себя.
// ═══════════════════════════════════════════════════════════════════════════

class _AmbientBackground extends StatefulWidget {
  const _AmbientBackground({required this.palette});
  final PaletteState palette;

  @override
  State<_AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<_AmbientBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _pulse = 0.78;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final phase = elapsed.inMilliseconds / 2400.0 * 2 * math.pi;
    final newPulse = 0.78 + 0.22 * (math.sin(phase) * 0.5 + 0.5);
    // Обновляем только если разница заметна — снижаем количество repaint
    if ((newPulse - _pulse).abs() > 0.002) {
      setState(() => _pulse = newPulse);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _AmbientPainter(
          c1: widget.palette.primary,
          c2: widget.palette.secondary,
          pulse: _pulse,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
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