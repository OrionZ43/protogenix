// lib/features/player/domain/spring.dart
//
// Точный перенос LegacySpring.ts от Beautiful Lyrics
// Credits: https://github.com/Fraktality/spr/blob/master/spr.lua

import 'dart:math' as math;

const double _epsilon = 1e-4;
const double _tau = math.pi * 2;
const double _sleepEps = 0.1;

/// Затухающий гармонический осциллятор.
/// Используется для анимации scale, yOffset, glow каждого слога.
class LyricSpring {
  double _velocity = 0;
  final double _dampingRatio;
  final double _frequency;
  bool _sleeping = true;

  double position;
  double goal;

  LyricSpring({
    required double initial,
    required double dampingRatio,
    required double frequency,
  })  : position = initial,
        goal = initial,
        _dampingRatio = dampingRatio,
        _frequency = frequency {
    assert(dampingRatio * frequency >= 0,
        'Spring does not converge: dampingRatio=$dampingRatio frequency=$frequency');
  }

  /// Шаг симуляции на [dt] секунд. Возвращает новую позицию.
  double update(double dt) {
    final radialFreq = _frequency * _tau;
    final offset = position - goal;
    final d = _dampingRatio;
    final decay = math.exp(-d * radialFreq * dt);

    double newPos, newVel;

    if (d == 1.0) {
      newPos =
          ((offset * (1 + radialFreq * dt) + _velocity * dt) * decay) + goal;
      newVel = ((_velocity * (1 - radialFreq * dt) -
              offset * (radialFreq * radialFreq * dt)) *
          decay);
    } else if (d < 1.0) {
      final c = math.sqrt(1 - d * d);
      final i = math.cos(radialFreq * c * dt);
      final j = math.sin(radialFreq * c * dt);

      final double z;
      if (c > _epsilon) {
        z = j / c;
      } else {
        final a = dt * radialFreq;
        final cSquared = c * c;
        z = a +
            ((((a * a * cSquared * cSquared / 20) - cSquared) * (a * a * a)) /
                6);
      }

      final double y;
      final fc = radialFreq * c;
      if (fc > _epsilon) {
        y = j / fc;
      } else {
        final fcSq = fc * fc;
        y = dt + ((((dt * dt * fcSq * fcSq / 20) - fcSq) * (dt * dt * dt)) / 6);
      }

      newPos = (((offset * (i + d * z) + _velocity * y) * decay) + goal);
      newVel = ((_velocity * (i - z * d) - offset * (z * radialFreq)) * decay);
    } else {
      final c = math.sqrt(d * d - 1);
      final r1 = -radialFreq * (d - c);
      final r2 = -radialFreq * (d + c);
      final co2 = (_velocity - offset * r1) / (2 * radialFreq * c);
      final co1 = offset - co2;
      final e1 = co1 * math.exp(r1 * dt);
      final e2 = co2 * math.exp(r2 * dt);
      newPos = e1 + e2 + goal;
      newVel = e1 * r1 + e2 * r2;
    }

    position = newPos;
    _velocity = newVel;
    _sleeping = (newPos - goal).abs() <= _sleepEps;

    return newPos;
  }

  /// Мгновенно добавить импульс скорости (удар пружины).
  void kick({required double velocity}) {
    _velocity += velocity;
    _sleeping = false;
  }

  /// Моментально установить позицию и цель.
  void set(double value) {
    position = value;
    goal = value;
    _velocity = 0;
    _sleeping = true;
  }

  bool get isSleeping => _sleeping;
}

/// Набор пружин для одного слога (Scale + YOffset + Glow).
///
/// Стандартный конструктор создаёт пружины для основного вокала.
/// [SyllableSprings.withParams] позволяет задать произвольные параметры —
/// используется для бэк-вокала / ад-либов (меньший overshoot).
class SyllableSprings {
  late final LyricSpring scale;
  late final LyricSpring yOffset;
  late final LyricSpring glow;

  /// Стандартные пружины для основного вокала.
  SyllableSprings()
      : scale = LyricSpring(initial: 0, dampingRatio: 0.6, frequency: 0.7),
        yOffset = LyricSpring(initial: 0, dampingRatio: 0.4, frequency: 1.25),
        glow = LyricSpring(initial: 0, dampingRatio: 0.5, frequency: 1.0);

  /// Пружины с произвольными параметрами.
  ///
  /// Для бэк-вокала рекомендуется высокий dampingRatio (0.80–0.90) и
  /// низкая frequency (0.5–0.7) — плавное проявление без резкого «прыжка».
  SyllableSprings.withParams({
    required double scaleDamping,
    required double scaleFrequency,
    required double yOffsetDamping,
    required double yOffsetFrequency,
    required double glowDamping,
    required double glowFrequency,
  })  : scale = LyricSpring(
            initial: 0, dampingRatio: scaleDamping, frequency: scaleFrequency),
        yOffset = LyricSpring(
            initial: 0,
            dampingRatio: yOffsetDamping,
            frequency: yOffsetFrequency),
        glow = LyricSpring(
            initial: 0, dampingRatio: glowDamping, frequency: glowFrequency);

  bool get isSleeping =>
      scale.isSleeping && yOffset.isSleeping && glow.isSleeping;

  void setAll(double s, double y, double g) {
    scale.goal = s;
    yOffset.goal = y;
    glow.goal = g;
  }

  void setAllImmediate(double s, double y, double g) {
    scale.set(s);
    yOffset.set(y);
    glow.set(g);
  }

  (double, double, double) step(double dt) {
    return (scale.update(dt), yOffset.update(dt), glow.update(dt));
  }
}
