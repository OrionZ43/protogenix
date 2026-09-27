// lib/features/player/presentation/widgets/glow_letter.dart
//
// Буква (или слог, или целая строка) караоке, которая анимируется без
// перестроения дерева виджетов.
//
// Раньше каждая буква жила внутри `Transform.scale(Transform.translate(Text))`,
// а пружины дёргали `setState` у строки: каждый кадр заново собиралась и
// раскладывалась вся строка со всеми слогами. У каждой строки и у каждого
// слога при этом был свой `Ticker` — на экране их набиралось несколько
// десятков (`performance.md`).
//
// Здесь вместо этого один RenderBox:
//   • раскладывается один раз, размер берётся у TextPainter — ровно тот же,
//     что был у Text, поэтому Wrap, Row и Baseline расставляют слоги как
//     прежде, и перенос слов не меняется;
//   • на каждый кадр только красится: смещение и масштаб — это преобразования
//     канвы (как и был Transform, он тоже не влиял на раскладку), а свечение —
//     те же `Shadow` в стиле;
//   • перерисовку запускает [GlowLetter.values] — `markNeedsPaint`, без layout.
//
// Метрики текста при смене свечения не меняются (цвет и тени на размер не
// влияют), поэтому строка от анимации не прыгает.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Состояние пружин одной буквы: масштаб, подскок вверх и свечение.
@immutable
class GlowValues {
  const GlowValues({
    required this.scale,
    required this.yOffset,
    required this.glow,
  });

  static const idle = GlowValues(scale: 1.0, yOffset: 0.0, glow: 0.0);

  final double scale;
  final double yOffset;
  final double glow;

  @override
  bool operator ==(Object other) =>
      other is GlowValues &&
      other.scale == scale &&
      other.yOffset == yOffset &&
      other.glow == glow;

  @override
  int get hashCode => Object.hash(scale, yOffset, glow);
}

/// Как выглядит текст при свечении 0 и 1. Значения по умолчанию — вид
/// строк в `beautiful_lyrics_view.dart`; у караоке по слогам свой набор.
@immutable
class GlowStyle {
  const GlowStyle({
    this.colorFrom,
    this.colorTo,
    this.fontWeight = FontWeight.w800,
    this.italic = false,
    this.shadowScale = 0.45,
    this.shadowThreshold = 8,
    this.blurBase = 4.0,
    this.blurSlope = 6.0,
    this.paletteShadow = true,
    this.minScale = 0.8,
    this.maxScale = 1.8,
  });

  /// Цвет при свечении 0 и 1; null — белый 75 → белый.
  final Color? colorFrom;
  final Color? colorTo;

  final FontWeight fontWeight;
  final bool italic;

  /// Непрозрачность тени на пике свечения и порог, ниже которого тени нет.
  final double shadowScale;
  final int shadowThreshold;

  /// Радиус тени: [blurBase] + [blurSlope] × свечение.
  final double blurBase;
  final double blurSlope;

  /// Вторая, широкая тень цветом обложки.
  final bool paletteShadow;

  final double minScale;
  final double maxScale;

  @override
  bool operator ==(Object other) =>
      other is GlowStyle &&
      other.colorFrom == colorFrom &&
      other.colorTo == colorTo &&
      other.fontWeight == fontWeight &&
      other.italic == italic &&
      other.shadowScale == shadowScale &&
      other.shadowThreshold == shadowThreshold &&
      other.blurBase == blurBase &&
      other.blurSlope == blurSlope &&
      other.paletteShadow == paletteShadow &&
      other.minScale == minScale &&
      other.maxScale == maxScale;

  @override
  int get hashCode => Object.hash(colorFrom, colorTo, fontWeight, italic,
      shadowScale, shadowThreshold, blurBase, blurSlope, paletteShadow,
      minScale, maxScale);
}

class GlowLetter extends LeafRenderObjectWidget {
  const GlowLetter({
    super.key,
    required this.text,
    required this.values,
    required this.fontSize,
    required this.glowColor,
    required this.textScaler,
    this.baseFontSize,
    this.style = const GlowStyle(),
  });

  final String text;

  /// Пружины буквы: меняется значение — буква перекрашивается, дерево нет.
  final ValueListenable<GlowValues> values;

  /// Размер шрифта самой буквы.
  final double fontSize;

  /// От чего считается подскок: у слогов это размер шрифта строки.
  /// null — от собственного размера.
  final double? baseFontSize;

  /// Цвет обложки — вторая тень.
  final Color glowColor;

  final TextScaler textScaler;
  final GlowStyle style;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderGlowLetter(
        text: text,
        values: values,
        fontSize: fontSize,
        baseFontSize: baseFontSize ?? fontSize,
        glowColor: glowColor,
        textScaler: textScaler,
        style: style,
      );

  @override
  void updateRenderObject(BuildContext context, RenderGlowLetter renderObject) {
    renderObject
      ..text = text
      ..values = values
      ..fontSize = fontSize
      ..baseFontSize = baseFontSize ?? fontSize
      ..glowColor = glowColor
      ..textScaler = textScaler
      ..style = style;
  }
}

class RenderGlowLetter extends RenderBox {
  RenderGlowLetter({
    required String text,
    required ValueListenable<GlowValues> values,
    required double fontSize,
    required double baseFontSize,
    required Color glowColor,
    required TextScaler textScaler,
    required GlowStyle style,
  })  : _text = text,
        _values = values,
        _fontSize = fontSize,
        _baseFontSize = baseFontSize,
        _glowColor = glowColor,
        _textScaler = textScaler,
        _style = style;

  final TextPainter _painter = TextPainter(textDirection: TextDirection.ltr);

  /// Свечение, с которым текст разложен сейчас: пока оно то же, TextPainter
  /// трогать не нужно.
  double? _paintedGlow;

  /// Ширина, по которой разложен текст: длинная строка переносится так же,
  /// как переносил Text.
  double _maxWidth = double.infinity;

  String _text;
  set text(String value) {
    if (_text == value) return;
    _text = value;
    _paintedGlow = null;
    markNeedsLayout();
  }

  ValueListenable<GlowValues> _values;
  set values(ValueListenable<GlowValues> value) {
    if (identical(_values, value)) return;
    if (attached) _values.removeListener(markNeedsPaint);
    _values = value;
    if (attached) _values.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  double _fontSize;
  set fontSize(double value) {
    if (_fontSize == value) return;
    _fontSize = value;
    _paintedGlow = null;
    markNeedsLayout();
  }

  double _baseFontSize;
  set baseFontSize(double value) {
    if (_baseFontSize == value) return;
    _baseFontSize = value;
    markNeedsPaint();
  }

  Color _glowColor;
  set glowColor(Color value) {
    if (_glowColor == value) return;
    _glowColor = value;
    _paintedGlow = null;
    markNeedsPaint();
  }

  TextScaler _textScaler;
  set textScaler(TextScaler value) {
    if (_textScaler == value) return;
    _textScaler = value;
    _paintedGlow = null;
    markNeedsLayout();
  }

  GlowStyle _style;
  set style(GlowStyle value) {
    if (_style == value) return;
    final relayout = _style.fontWeight != value.fontWeight ||
        _style.italic != value.italic;
    _style = value;
    _paintedGlow = null;
    if (relayout) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _values.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _values.removeListener(markNeedsPaint);
    super.detach();
  }

  /// Цвет и тени зависят от свечения, размеры — нет, поэтому раскладка от
  /// анимации не меняется.
  TextStyle _styleFor(double glow) {
    final g = glow.clamp(0.0, 1.0);
    final shadowAlpha = (g * _style.shadowScale * 255).round();
    final blurRadius = _style.blurBase + _style.blurSlope * g;

    return TextStyle(
      fontSize: _fontSize,
      fontWeight: _style.fontWeight,
      fontStyle: _style.italic ? FontStyle.italic : FontStyle.normal,
      color: Color.lerp(
        _style.colorFrom ?? Colors.white.withAlpha(75),
        _style.colorTo ?? Colors.white,
        g,
      ),
      height: 1.25,
      shadows: shadowAlpha > _style.shadowThreshold
          ? [
              Shadow(
                color: Colors.white.withAlpha(shadowAlpha),
                blurRadius: blurRadius,
              ),
              if (_style.paletteShadow)
                Shadow(
                  color: _glowColor.withAlpha(shadowAlpha ~/ 2),
                  blurRadius: blurRadius * 2,
                ),
            ]
          : null,
    );
  }

  void _layoutText(double glow) {
    if (_paintedGlow == glow) return;
    _painter
      ..text = TextSpan(text: _text, style: _styleFor(glow))
      ..textScaler = _textScaler
      ..layout(maxWidth: _maxWidth);
    _paintedGlow = glow;
  }

  @override
  void performLayout() {
    // Размер считаем по «спокойному» стилю: тени и цвет на метрики не влияют,
    // а масштаб — преобразование при отрисовке, как и был Transform.scale
    _maxWidth = constraints.maxWidth;
    _paintedGlow = null;
    _layoutText(0.0);
    size = constraints.constrain(_painter.size);
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    _layoutText(0.0);
    return _painter.minIntrinsicWidth;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    _layoutText(0.0);
    return _painter.maxIntrinsicWidth;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    _layoutText(0.0);
    return _painter.height;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    _layoutText(0.0);
    return _painter.height;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    _layoutText(_paintedGlow ?? 0.0);
    return _painter.computeDistanceToActualBaseline(baseline);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final painter = TextPainter(
      text: TextSpan(text: _text, style: _styleFor(0.0)),
      textDirection: TextDirection.ltr,
      textScaler: _textScaler,
    )..layout(maxWidth: constraints.maxWidth);
    final result = constraints.constrain(painter.size);
    painter.dispose();
    return result;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final v = _values.value;
    _layoutText(v.glow.clamp(0.0, 1.0));

    final canvas = context.canvas;
    canvas.save();

    // То же самое, что делали Transform.translate и Transform.scale
    // с alignment: bottomCenter — обе операции только красят
    canvas.translate(offset.dx, offset.dy + _baseFontSize * v.yOffset);
    final scale = v.scale.clamp(_style.minScale, _style.maxScale);
    if (scale != 1.0) {
      final cx = size.width / 2;
      final cy = size.height;
      canvas
        ..translate(cx, cy)
        ..scale(scale)
        ..translate(-cx, -cy);
    }

    _painter.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }
}
