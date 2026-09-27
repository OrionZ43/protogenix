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
// CHANGELOG v3.2:
//   FIX   _HighlightedLineWidget: plainText склеивал main + bg в одну строку.
//         Теперь main и bg рендерятся раздельно через Column, аналогично
//         _InactiveLine и _SpringLineWidget.

import 'dart:async';
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
import 'audio_visualizer.dart';
import 'glow_letter.dart';
import '../../../../core/utils/haptic_patterns.dart';
import '../providers/karaoke_provider.dart';
import '../providers/lyrics_display_provider.dart';
import '../providers/palette_provider.dart';
import '../providers/player_provider.dart';

// ── Глобальные константы UI ────────────────────────────────────────────────
const _kDistanceToMaxBlur = 4;
const _kBlurScale = 1.25;

/// Сколько текст стоит неподвижно после того, как пользователь пролистал, —
/// и только потом караоке снова начинает вести его за строкой.
///
/// Раньше здесь было 750 мс, причём отсчёт шёл от момента, когда палец
/// оторвался от экрана: список ещё доезжал по инерции, а его уже насильно
/// возвращало к активной строке. Отзыв Orion: «текст очень сложно листать».
/// Теперь отсчёт начинается, когда список полностью остановился, и до
/// возврата есть время прочитать. Вернуться сразу — кнопка «К текущей строке».
const _kUserScrollResume = Duration(seconds: 6);

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
const _kBgSingingGlow = 0.85; // чуть приглушённее

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

  /// Отсчёт до возврата к активной строке после ручной прокрутки.
  Timer? _resumeTimer;

  /// Позиция плеера — обновляется каждый кадр через SchedulerBinding.
  /// Только ValueNotifier.value меняется → нет setState → нет rebuild дерева.
  final ValueNotifier<double> _positionMs = ValueNotifier(0.0);

  /// Общий такт для пружин: номер кадра. Раньше у каждой строки и каждого
  /// слога был свой `Ticker` — на экране их набиралось несколько десятков
  /// (`performance.md`). Значение меняется каждый кадр, даже когда позиция
  /// стоит: пружинам надо доехать и на паузе.
  final ValueNotifier<int> _frame = ValueNotifier(0);
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
    _frame.value++;
    _scheduleFrame();
  }

  @override
  void dispose() {
    _frameCallbackScheduled = false;
    _resumeTimer?.cancel();
    _positionMs.dispose();
    _frame.dispose();
    super.dispose();
  }

  /// Пользователь взялся листать: караоке перестаёт вести текст за строкой.
  void _beginUserScroll() {
    _resumeTimer?.cancel();
    if (!_userScrolling) setState(() => _userScrolling = true);
  }

  /// Список остановился — с этого момента отсчитываем паузу до возврата.
  void _scheduleResume() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(_kUserScrollResume, _returnToCurrentLine);
  }

  void _returnToCurrentLine() {
    _resumeTimer?.cancel();
    if (!mounted) return;
    setState(() => _userScrolling = false);
    // Индекс читаем сейчас, а не тот, что был при подписке: пока листали,
    // строка уже сменилась
    _scrollTo(ref.read(karaokeProvider).currentIndex, force: true);
  }

  Future<void> _scrollTo(int index, {bool force = false}) async {
    if (_userScrolling && !force) return;
    if (index < 0) return;
    if (!_scroll.isAttached) return;
    _autoScrolling = true;
    try {
      await _scroll.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        alignment: 0.45,
      );
    } catch (_) {}
    Future.delayed(
      const Duration(milliseconds: 140),
      () => _autoScrolling = false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. СНАЧАЛА ВСЕ ПРОВАЙДЕРЫ И СЛУШАТЕЛИ
    final karaoke = ref.watch(karaokeProvider);
    final palette = ref.watch(paletteProvider);
    final linesOnly = ref.watch(lyricsLinesOnlyProvider);

    ref.listen(karaokeProvider.select((s) => s.currentIndex), (prev, next) {
      if (prev != next && next >= 0) {
        if (!_userScrolling) _scrollTo(next);
        // Вид текста остаётся в дереве и со свёрнутым приложением, если перед
        // этим был открыт, — вибрируем, только пока приложение на экране.
        if (WidgetsBinding.instance.lifecycleState ==
            AppLifecycleState.resumed) {
          HapticPatterns.lyricsLine();
        }
      }
    });

    // 2. ЗАТЕМ ЛОКАЛЬНАЯ ЛОГИКА И МАСШТАБ
    final referenceWidth = MediaQuery.sizeOf(context).width;
    final scale = (referenceWidth / 1200).clamp(0.85, 1.3);
    final baseFontSize = 32.0 * scale;
    // bgFontSize is automatically passed via baseFontSize logic in child widgets

    if (!karaoke.isLoaded) {
      return Center(
        child:
            CircularProgressIndicator(color: palette.primary, strokeWidth: 2),
      );
    }

    if (karaoke.lines.isEmpty) return _EmptyState(palette: palette);

    if (karaoke.format == LyricsFormat.plain) {
      return _PlainLyricsView(lines: karaoke.lines, palette: palette, baseFontSize: baseFontSize);
    }

    final activeIndex = karaoke.currentIndex;
    // Тайминги по словам и слогам можно показать и просто строками — так
    // легче слабому телефону (lyrics_display_provider.dart)
    final canWordSync = karaoke.format == LyricsFormat.yrc ||
        karaoke.format == LyricsFormat.enhancedLrc;
    final hasWordSync = canWordSync && !linesOnly;

    return RepaintBoundary(
      child: Stack(
        children: [
          _AmbientBackground(palette: palette),
          NotificationListener<ScrollNotification>(
            onNotification: (n) {
              // Автопрокрутка тоже шлёт уведомления — её не считаем за ручную
              if (_autoScrolling) return false;
              if (n is UserScrollNotification &&
                  n.direction != ScrollDirection.idle) {
                _beginUserScroll();
              } else if (n is ScrollEndNotification && _userScrolling) {
                // Список доехал и встал — отсюда и отсчитываем паузу
                _scheduleResume();
              }
              return false;
            },
            child: ShaderMask(
              shaderCallback: (Rect bounds) {
                return const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black, Colors.transparent, Colors.transparent, Colors.black],
                  stops: [0.0, 0.1, 0.9, 1.0],
                ).createShader(bounds);
              },
              blendMode: BlendMode.dstOut,
              child: ScrollablePositionedList.builder(
                itemScrollController: _scroll,
                itemPositionsListener: _positions,
                // Открыли плеер посреди песни — текст сразу стоит на текущей
                // строке. Раньше список начинался с первой и прыгал к нужной
                // только со следующей строкой (отзыв Orion)
                initialScrollIndex:
                    activeIndex <= 0 ? 0 : activeIndex.clamp(0, karaoke.lines.length - 1),
                initialAlignment: 0.45,
                padding: EdgeInsets.symmetric(
                  vertical: MediaQuery.of(context).size.height * 0.42,
                  horizontal: 24.0,
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
                      positionMs: _positionMs,
                      frame: _frame,
                      hasWordSync: hasWordSync,
                      baseFontSize: baseFontSize,
                    ),
                  );
                },
              ),
            ),
          ),
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
          if (canWordSync)
            const Positioned(
              top: 8,
              right: 12,
              child: _LyricsModeToggle(),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            bottom: _userScrolling ? 28 : -64,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _returnToCurrentLine,
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

/// «Слоги / Строки» — как показывать текст с таймингами по словам. Кнопка
/// видна, только когда такие тайминги есть.
class _LyricsModeToggle extends ConsumerWidget {
  const _LyricsModeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linesOnly = ref.watch(lyricsLinesOnlyProvider);
    return Tooltip(
      message: linesOnly ? 'Показать по слогам' : 'Показать по строкам',
      child: GestureDetector(
        onTap: () => ref.read(lyricsLinesOnlyProvider.notifier).toggle(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.black.withAlpha(90),
            border: Border.all(color: Colors.white.withAlpha(35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                linesOnly ? Icons.segment_rounded : Icons.graphic_eq_rounded,
                color: Colors.white70,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                linesOnly ? 'Строки' : 'Слоги',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    required this.frame,
    required this.hasWordSync,
    required this.baseFontSize,
  });

  final LyricLine line;
  final bool isCurrent;
  final int distance;
  final double blurAmount;
  final PaletteState palette;
  final bool userScrolling;
  final ValueNotifier<double> positionMs;

  /// Общий такт пружин — один на весь вид текста
  final Listenable frame;
  final bool hasWordSync;
  final double baseFontSize;

  @override
  Widget build(BuildContext context) {
    final bool useSpring = isCurrent || distance <= 1;

    Widget activeContent;
    if (useSpring) {
      if (hasWordSync) {
        activeContent = _SpringLineWidget(
          key: ValueKey('spring_${line.startMs}'),
          line: line,
          positionMs: positionMs,
          frame: frame,
          palette: palette,
          baseFontSize: baseFontSize,
        );
      } else {
        activeContent = _HighlightedLineWidget(
          key: ValueKey('highlight_${line.startMs}'),
          line: line,
          positionMs: positionMs,
          frame: frame,
          palette: palette,
          baseFontSize: baseFontSize,
        );
      }
    } else {
      activeContent = _InactiveLine(
        key: ValueKey('inactive_${line.startMs}'),
        line: line,
        distance: distance,
        baseFontSize: baseFontSize,
      );
    }

    Widget content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
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
// ═══════════════════════════════════════════════════════════════════════════

class _SpringLineWidget extends StatefulWidget {
  const _SpringLineWidget({
    super.key,
    required this.line,
    required this.positionMs,
    required this.frame,
    required this.palette,
    required this.baseFontSize,
  });

  final LyricLine line;
  final ValueListenable<double> positionMs;

  /// Общий такт: шагаем пружины на нём, своего `Ticker` у строки больше нет.
  final Listenable frame;
  final PaletteState palette;
  final double baseFontSize;

  @override
  State<_SpringLineWidget> createState() => _SpringLineWidgetState();
}

class _SpringLineWidgetState extends State<_SpringLineWidget> {
  Duration? _lastElapsed;

  late final List<LyricSyllable> _allSyls;
  late final List<LyricSyllable> _mainSyls;
  late final List<LyricSyllable> _bgSyls;

  late final Map<LyricSyllable, SyllableSprings> _springs;
  final Map<LyricSyllable, _SylState> _states = {};

  /// Значения пружин каждого слога. Меняются каждый кадр, но перекрашивают
  /// только сам слог — дерево не перестраивается (`glow_letter.dart`).
  final Map<LyricSyllable, ValueNotifier<GlowValues>> _vals = {};

  @override
  void initState() {
    super.initState();
    _allSyls = widget.line.allSyllables;
    _mainSyls = _allSyls.where((s) => !s.isBackground).toList();
    _bgSyls = _allSyls.where((s) => s.isBackground).toList();

    _springs = {
      for (final syl in _allSyls)
        syl: SyllableSprings()
          ..setAllImmediate(_kWaitingScale, _kWaitingYOffset, _kWaitingGlow),
    };

    for (final syl in _allSyls) {
      _states[syl] = _SylState.waiting;
      _vals[syl] = ValueNotifier(const GlowValues(
        scale: _kWaitingScale,
        yOffset: _kWaitingYOffset,
        glow: _kWaitingGlow,
      ));
    }

    widget.frame.addListener(_onTick);
  }

  void _onTick() {
    if (!mounted) return;

    final elapsed = SchedulerBinding.instance.currentFrameTimeStamp;
    final dt = _lastElapsed == null
        ? 0.0
        : (elapsed - _lastElapsed!).inMicroseconds / 1e6;
    _lastElapsed = elapsed;

    final ms = widget.positionMs.value;

    for (final syl in _allSyls) {
      final springs = _springs[syl]!;
      final newState =
          _stateFor(ms, syl.startMs.toDouble(), syl.endMs.toDouble());
      final oldState = _states[syl];

      if (newState != oldState) {
        _states[syl] = newState;
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
        _vals[syl]!.value = GlowValues(scale: s, yOffset: y, glow: g);
      } else {
        _vals[syl]!.value = GlowValues(
          scale: springs.scale.position,
          yOffset: springs.yOffset.position,
          glow: springs.glow.position,
        );
      }
    }

    // setState больше не нужен: каждый слог перекрашивается сам по своему
    // ValueNotifier, а раскладка строки при этом не трогается
  }

  @override
  void dispose() {
    widget.frame.removeListener(_onTick);
    for (final notifier in _vals.values) {
      notifier.dispose();
    }
    super.dispose();
  }

  Widget _buildWrap(List<LyricSyllable> syls) {
    return Wrap(
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: syls.map((syl) {
        Widget child;

        if (syl.isEmphasized && !syl.isBackground) {
          child = _EmphasizedSyllable(
            frame: widget.frame,
            key: ValueKey('emph_${syl.startMs}'),
            syllable: syl,
            positionMs: widget.positionMs,
            palette: widget.palette,
            baseFontSize: widget.baseFontSize,
          );
        } else {
          child = _LetterWidget(
            text: syl.text,
            values: _vals[syl]!,
            isBackground: syl.isBackground,
            palette: widget.palette,
            baseFontSize: widget.baseFontSize,
          );
        }

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
}

// ═══════════════════════════════════════════════════════════════════════════
// HIGHLIGHTED LINE WIDGET
// Для syncedLrc — подсветка строки целиком без буквенной анимации.
//
// FIX v3.2: plainText склеивал main + bg в одну строку.
// Теперь main и bg рендерятся раздельно через Column — аналогично
// _InactiveLine и _SpringLineWidget. _mainText/_bgText кешируются
// в initState — нет аллокаций в build().
// ═══════════════════════════════════════════════════════════════════════════

class _HighlightedLineWidget extends StatefulWidget {
  const _HighlightedLineWidget({
    super.key,
    required this.line,
    required this.positionMs,
    required this.frame,
    required this.palette,
    required this.baseFontSize,
  });

  final LyricLine line;
  final ValueListenable<double> positionMs;

  /// Общий такт пружин
  final Listenable frame;
  final PaletteState palette;
  final double baseFontSize;

  @override
  State<_HighlightedLineWidget> createState() => _HighlightedLineWidgetState();
}

class _HighlightedLineWidgetState extends State<_HighlightedLineWidget> {
  late final SyllableSprings _spring;
  _SylState _state = _SylState.waiting;

  /// Свечение строки: читается при отрисовке, дерево не перестраивается.
  final _values = ValueNotifier<GlowValues>(
    const GlowValues(scale: 1.0, yOffset: 0.0, glow: 0.0),
  );

  // FIX: кешируем разбивку main/bg один раз — нет аллокаций в build()
  late final String _mainText;
  late final String _bgText;

  @override
  void initState() {
    super.initState();

    // FIX: разделяем слова на main и bg здесь, а не через plainText
    _mainText = widget.line.words
        .where((w) => !w.isBackground)
        .map((w) => w.text)
        .join(' ');
    _bgText = widget.line.words
        .where((w) => w.isBackground)
        .map((w) => w.text)
        .join(' ');

    _spring = SyllableSprings()
      ..setAllImmediate(_kWaitingScale, _kWaitingYOffset, _kWaitingGlow);
    widget.frame.addListener(_onTick);
  }

  void _onTick() {
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
    final g = stepResult.$3;
    if (_values.value.glow != g) {
      _values.value = GlowValues(scale: 1.0, yOffset: 0.0, glow: g);
    }
  }

  @override
  void dispose() {
    widget.frame.removeListener(_onTick);
    _values.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);

    // Цвета и тени те же, что были в стиле Text: теперь их по свечению
    // считает GlowLetter при отрисовке, а строка на каждый кадр не
    // пересобирается (`glow_letter.dart`)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_mainText.isNotEmpty)
          GlowLetter(
            text: _mainText,
            values: _values,
            fontSize: widget.baseFontSize,
            baseFontSize: widget.baseFontSize,
            glowColor: widget.palette.primary,
            textScaler: textScaler,
          ),
        if (_bgText.isNotEmpty) ...[
          const SizedBox(height: 5),
          GlowLetter(
            text: _bgText,
            values: _values,
            fontSize: widget.baseFontSize * 0.62,
            baseFontSize: widget.baseFontSize,
            glowColor: widget.palette.primary,
            textScaler: textScaler,
            // Бэк-вокал тусклее основного текста и без цветной тени
            style: GlowStyle(
              fontWeight: FontWeight.w500,
              italic: true,
              shadowScale: 0.22,
              paletteShadow: false,
              colorFrom: Colors.white.withAlpha(45),
              colorTo: Colors.white.withAlpha(160),
            ),
          ),
        ],
      ],
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
        values = ValueNotifier(const GlowValues(
          scale: _kWaitingScale,
          yOffset: _kWaitingYOffset,
          glow: _kWaitingGlow,
        ));

  final String char;
  final double startMs;
  final double endMs;
  final SyllableSprings springs;

  /// Значения пружин буквы: их читает GlowLetter при отрисовке.
  final ValueNotifier<GlowValues> values;

  _SylState state;
}

class _EmphasizedSyllable extends StatefulWidget {
  const _EmphasizedSyllable({
    super.key,
    required this.syllable,
    required this.positionMs,
    required this.frame,
    required this.palette,
    required this.baseFontSize,
  });

  final LyricSyllable syllable;
  final ValueListenable<double> positionMs;

  /// Общий такт пружин — свой Ticker у слога больше не нужен
  final Listenable frame;
  final PaletteState palette;
  final double baseFontSize;

  @override
  State<_EmphasizedSyllable> createState() => _EmphasizedSyllableState();
}

class _EmphasizedSyllableState extends State<_EmphasizedSyllable> {
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

    widget.frame.addListener(_onTick);
  }

  void _onTick() {
    if (!mounted) return;

    final elapsed = SchedulerBinding.instance.currentFrameTimeStamp;
    final dt = _lastElapsed == null
        ? 0.0
        : (elapsed - _lastElapsed!).inMicroseconds / 1e6;
    _lastElapsed = elapsed;

    final ms = widget.positionMs.value;

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
        slot.values.value = GlowValues(scale: s, yOffset: y, glow: g);
      } else {
        slot.values.value = GlowValues(
          scale: slot.springs.scale.position,
          yOffset: slot.springs.yOffset.position,
          glow: slot.springs.glow.position,
        );
      }
    }
    // Каждая буква перекрашивается по своему ValueNotifier — setState нет
  }

  @override
  void dispose() {
    widget.frame.removeListener(_onTick);
    for (final slot in _slots) {
      slot.values.dispose();
    }
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
          values: slot.values,
          palette: widget.palette,
          baseFontSize: widget.baseFontSize,
        );
      }).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LETTER WIDGET — одна буква / слог
// ═══════════════════════════════════════════════════════════════════════════

/// Буква или слог: раскладка та же, что была у `Text` внутри `Baseline`,
/// а подскок, масштаб и свечение рисует `GlowLetter` — без перестроения
/// дерева на каждый кадр (`glow_letter.dart`).
class _LetterWidget extends StatelessWidget {
  const _LetterWidget({
    required this.text,
    required this.values,
    required this.palette,
    required this.baseFontSize,
    this.isBackground = false,
  });

  final String text;
  final ValueListenable<GlowValues> values;
  final PaletteState palette;
  final double baseFontSize;
  final bool isBackground;

  @override
  Widget build(BuildContext context) {
    final fontSize = isBackground ? baseFontSize * 0.62 : baseFontSize;

    return Baseline(
      baseline: fontSize * 0.82,
      baselineType: TextBaseline.alphabetic,
      child: GlowLetter(
        text: text,
        values: values,
        fontSize: fontSize,
        baseFontSize: baseFontSize,
        glowColor: palette.primary,
        textScaler: MediaQuery.textScalerOf(context),
        style: isBackground
            ? const GlowStyle(
                fontWeight: FontWeight.w500,
                italic: true,
                shadowScale: 0.22,
              )
            : const GlowStyle(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// INACTIVE LINE
// ═══════════════════════════════════════════════════════════════════════════

class _InactiveLine extends StatelessWidget {
  const _InactiveLine({super.key, required this.line, required this.distance, required this.baseFontSize});

  final LyricLine line;
  final int distance;
  final double baseFontSize;

  static double _scaleFor(int d) => switch (d) {
        1 => 0.78,
        2 => 0.69,
        _ => 0.59,
      };

  @override
  Widget build(BuildContext context) {
    final scale = _scaleFor(distance);

    final mainText =
        line.words.where((w) => !w.isBackground).map((w) => w.text).join(' ');
    final bgText =
        line.words.where((w) => w.isBackground).map((w) => w.text).join(' ');

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
              style: TextStyle(
                fontSize: baseFontSize,
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
                fontSize: baseFontSize * 0.62,
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
  const _PlainLyricsView({required this.lines, required this.palette, required this.baseFontSize});

  final List<LyricLine> lines;
  final PaletteState palette;
  final double baseFontSize;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CustomPaint(
          painter: _AmbientPainter.fixed(
            c1: palette.primary,
            c2: palette.secondary,
            pulse: 0.9,
          ),
          child: const SizedBox.expand(),
        ),
        ShaderMask(
          shaderCallback: (Rect bounds) {
            return const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black, Colors.transparent, Colors.transparent, Colors.black],
              stops: [0.0, 0.1, 0.9, 1.0],
            ).createShader(bounds);
          },
          blendMode: BlendMode.dstOut,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 60),
            itemCount: lines.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                lines[i].plainText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: baseFontSize * 0.6,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withAlpha(180),
                  height: 1.6,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EMPTY STATE
// ═══════════════════════════════════════════════════════════════════════════

/// Текста у трека нет. Раньше здесь была только надпись, и на ПК оставалось
/// большое пустое место (отзыв Кесса) — теперь его занимает визуализатор,
/// который двигается по настоящему спектру трека. Стиль — в настройках.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.palette});
  final PaletteState palette;

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          const Positioned.fill(child: AudioVisualizer()),
          Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: Center(
              child: Text(
                'Текст не найден',
                style: TextStyle(
                  color: Colors.white.withAlpha(45),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// AMBIENT BACKGROUND
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

  /// Пульс уходит прямо в painter: у него нет setState, значит нет и
  /// перестроения дерева каждый кадр (правило 3, `performance.md`).
  final _pulse = ValueNotifier<double>(0.78);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final phase = elapsed.inMilliseconds / 2400.0 * 2 * math.pi;
    final newPulse = 0.78 + 0.22 * (math.sin(phase) * 0.5 + 0.5);
    if ((newPulse - _pulse.value).abs() > 0.002) _pulse.value = newPulse;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _pulse.dispose();
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
  /// Пульс живёт в [pulse]: перерисовка идёт по нему, минуя build и layout.
  _AmbientPainter({required this.c1, required this.c2, required this.pulse})
      : _fixed = null,
        super(repaint: pulse);

  /// Неподвижный фон (простой текст без караоке) — без тикера вообще.
  _AmbientPainter.fixed({required this.c1, required this.c2, required double pulse})
      : _fixed = pulse,
        pulse = null;

  final Color c1, c2;
  final ValueListenable<double>? pulse;
  final double? _fixed;

  @override
  void paint(Canvas canvas, Size size) {
    final pulse = _fixed ?? this.pulse!.value;
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
      o.c1 != c1 || o.c2 != c2 || o._fixed != _fixed;
}

