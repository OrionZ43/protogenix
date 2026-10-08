// lib/core/widgets/sheet_cover.dart
//
// Полноэкранная шторка и то, что под ней.
//
// Шторка (`showModalBottomSheet`) — не непрозрачный маршрут, и Flutter рисует
// под ней всё. Кэша растеризации у Impeller нет, поэтому даже замершее
// содержимое под шторкой перерисовывается каждый кадр целиком, а стекло
// (`BackdropFilter`) каждый кадр заново размывает то, что под ним. На слабых
// телефонах это больше половины кадра: на Redmi Note 8 главная под плеером
// стоила 31 мс из 40 (`.claude/rules/performance.md`, «Слабые телефоны»).
//
// Пока шторка раскрыта до конца и её не тянут, закрытое ею можно не рисовать:
//   • [CoveringSheet] — шторка сообщает в [SheetCover], что раскрыта;
//   • [HiddenUnderSheet] — закрытое по этому флагу не рисуется;
//   • [FrozenGlass] — стекло шторки: раскрытой оно показывает один раз
//     размытый снимок того, что под ним, и только после этого прячет его.
// Стоит шторку потянуть — всё возвращается как было, в том же кадре.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// Закрыто ли сейчас содержимое шторкой целиком. Пишет шторка, читает
/// [HiddenUnderSheet].
class SheetCover extends ValueNotifier<bool> {
  SheetCover() : super(false);

  bool _disposed = false;

  /// Снять флаг, когда шторка разбирается.
  ///
  /// Прямо в `dispose` шторки этого делать нельзя: идёт разборка дерева, и
  /// перестроить закрытый экран в этот момент Flutter не даст. А снять надо
  /// обязательно — если шторку убрали без анимации закрытия, экран под ней
  /// иначе так и остался бы невидимым.
  void releaseLater() {
    if (!value) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) value = false;
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Открывающему шторку изнутри закрываемого экрана: куда сообщать, что
/// экран закрыт ([cover]), и откуда снять его картинку для стекла
/// ([boundary] — ключ `RepaintBoundary` вокруг экрана).
class SheetCoverScope extends InheritedWidget {
  const SheetCoverScope({
    super.key,
    required this.cover,
    required this.boundary,
    required super.child,
  });

  final SheetCover cover;
  final GlobalKey boundary;

  static SheetCoverScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SheetCoverScope>();

  @override
  bool updateShouldNotify(SheetCoverScope oldWidget) =>
      cover != oldWidget.cover || boundary != oldWidget.boundary;
}

/// Содержимое, которое не рисуется и не анимируется, пока его закрывает
/// шторка.
///
/// Размер и состояние сохраняются (`maintainSize`): раскладка не меняется, и
/// когда шторку потянут, всё уже на месте. Нажатия и озвучка под закрытым
/// экраном отключены — их и так не видно.
class HiddenUnderSheet extends StatelessWidget {
  const HiddenUnderSheet({
    super.key,
    required this.covered,
    required this.child,
  });

  final ValueListenable<bool> covered;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: covered,
      builder: (context, covered, child) => TickerMode(
        enabled: !covered,
        child: Visibility(
          visible: !covered,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: true,
          child: child!,
        ),
      ),
      child: child,
    );
  }
}

/// Следит за анимацией своего маршрута: раскрыт до конца — `completed`.
/// Пока шторку открывают, закрывают или тянут, статус другой.
mixin _RouteCoverage<T extends StatefulWidget> on State<T> {
  Animation<double>? _route;

  void onCoverageChanged(bool covers);

  bool get routeCovers => _route?.status == AnimationStatus.completed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context)?.animation;
    if (route == _route) return;
    _route?.removeStatusListener(_onStatus);
    _route = route?..addStatusListener(_onStatus);
    if (route == null) return;
    // Начальное состояние — после кадра: сейчас идёт построение, а флаг
    // перестраивает экран под шторкой, который не наш потомок
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && _route == route) _onStatus(route.status);
    });
  }

  void _onStatus(AnimationStatus status) =>
      onCoverageChanged(status == AnimationStatus.completed);

  @override
  void dispose() {
    _route?.removeStatusListener(_onStatus);
    super.dispose();
  }
}

/// Шторка, которая сообщает [cover], раскрыта ли она до конца.
class CoveringSheet extends StatefulWidget {
  const CoveringSheet({super.key, required this.cover, required this.child});

  final SheetCover cover;
  final Widget child;

  @override
  State<CoveringSheet> createState() => _CoveringSheetState();
}

class _CoveringSheetState extends State<CoveringSheet>
    with _RouteCoverage<CoveringSheet> {
  @override
  void onCoverageChanged(bool covers) => widget.cover.value = covers;

  @override
  void dispose() {
    widget.cover.releaseLater();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Стекло полноэкранной шторки, которое «замерзает», пока шторка раскрыта.
///
/// Пока шторка едет или её тянут — обычный `BackdropFilter`. Встала на место —
/// стекло один раз снимает экран под собой ([scope]), размывает снимок так же
/// и дальше рисует готовую картинку, а экран под шторкой прячет. На кадр
/// вместо полноэкранного размытия остаётся одна картинка.
///
/// Без [scope] стекло всегда живое — так оно ведёт себя, если шторку открыли
/// не из экрана, который умеет прятаться.
///
/// [refreshKey] — что под шторкой может смениться само (трек): когда он
/// меняется, снимок делается заново.
class FrozenGlass extends StatefulWidget {
  const FrozenGlass({
    super.key,
    required this.sigma,
    required this.scope,
    this.refreshKey,
    required this.child,
  });

  final double sigma;
  final SheetCoverScope? scope;
  final Object? refreshKey;
  final Widget child;

  @override
  State<FrozenGlass> createState() => _FrozenGlassState();
}

class _FrozenGlassState extends State<FrozenGlass>
    with _RouteCoverage<FrozenGlass> {
  /// Снимок делается мельче экрана: после размытия мелких деталей в нём
  /// не остаётся, а снимать и размывать вчетверо меньше пикселей.
  static const _scale = 0.5;

  /// После смены трека экран под шторкой ещё подтягивает обложку и цвета.
  static const _refreshDelay = Duration(milliseconds: 900);

  ui.Image? _frozen;

  /// Где снимок лежит относительно самой шторки.
  Rect _frozenRect = Rect.zero;

  /// Отменяет снимки, которые устарели, пока делались.
  int _generation = 0;
  Timer? _refresh;

  @override
  void onCoverageChanged(bool covers) {
    if (covers) {
      unawaited(_freeze());
    } else {
      _thaw();
    }
  }

  @override
  void didUpdateWidget(FrozenGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshKey != oldWidget.refreshKey && routeCovers) {
      // Под шторкой новый трек: показать экран, дать ему обновиться, снять
      // заново. Оттаивать — после кадра: сейчас идёт построение
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _thaw();
        _refresh = Timer(_refreshDelay, () {
          if (mounted && routeCovers) unawaited(_freeze());
        });
      });
    }
  }

  Future<void> _freeze() async {
    final scope = widget.scope;
    if (scope == null) return;
    final generation = ++_generation;

    // Снимать надо уже отрисованное: кадр, где шторка встала на место
    await SchedulerBinding.instance.endOfFrame;
    if (!mounted || generation != _generation) return;

    final boundary = scope.boundary.currentContext?.findRenderObject();
    final self = context.findRenderObject();
    if (boundary is! RenderRepaintBoundary ||
        self is! RenderBox ||
        !boundary.hasSize ||
        !self.hasSize) {
      return;
    }
    final barrier = ModalRoute.of(context)?.barrierColor;
    final origin =
        boundary.localToGlobal(Offset.zero) - self.localToGlobal(Offset.zero);
    final rect = origin & boundary.size;

    ui.Image? captured;
    ui.Image? blurred;
    try {
      captured = await boundary.toImage(pixelRatio: _scale);
      final width = captured.width;
      final height = captured.height;

      // То же размытие, что делал BackdropFilter, плюс затемнение маршрута
      // шторки поверх: размытие линейно, порядок не важен
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final sigma = widget.sigma * _scale;
      canvas.drawImage(
        captured,
        Offset.zero,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.clamp,
          ),
      );
      if (barrier != null) {
        canvas.drawRect(
          Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          Paint()..color = barrier,
        );
      }
      final picture = recorder.endRecording();
      // Не toImageSync: ленивая картинка внутри другой пересобиралась бы
      // каждый кадр (`performance.md`)
      blurred = await picture.toImage(width, height);
      picture.dispose();
    } catch (e) {
      debugPrint('[FrozenGlass] снимок не удался: $e');
      blurred?.dispose();
      return;
    } finally {
      captured?.dispose();
    }

    if (!mounted || generation != _generation) {
      blurred.dispose();
      return;
    }
    setState(() {
      _frozen?.dispose();
      _frozen = blurred;
      _frozenRect = rect;
    });
    // Прятать экран только теперь, когда картинка уже готова
    scope.cover.value = true;
  }

  void _thaw() {
    _generation++;
    _refresh?.cancel();
    widget.scope?.cover.value = false;
    if (_frozen != null) {
      setState(() {
        _frozen!.dispose();
        _frozen = null;
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    _refresh?.cancel();
    widget.scope?.cover.releaseLater();
    _frozen?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frozen = _frozen;
    // Устройство дерева одно и то же в обоих состояниях: иначе содержимое
    // шторки (текст песни с прокруткой) пересоздавалось бы при каждой смене
    return BackdropFilter(
      enabled: frozen == null,
      filter: ui.ImageFilter.blur(sigmaX: widget.sigma, sigmaY: widget.sigma),
      child: CustomPaint(
        painter: frozen == null ? null : _FrozenPainter(frozen, _frozenRect),
        child: widget.child,
      ),
    );
  }
}

class _FrozenPainter extends CustomPainter {
  _FrozenPainter(this.image, this.rect);

  final ui.Image image;
  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_FrozenPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.rect != rect;
}
