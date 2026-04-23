/// Кубический сплайн для интерполяции ScaleRange, YOffsetRange, GlowRange.
/// Перенос логики npm:cubic-spline используемого в Beautiful Lyrics.
class LyricSpline {
  final List<double> _xs;
  final List<double> _ys;
  final List<double> _ks; // вторые производные

  LyricSpline(List<({double time, double value})> points)
      : _xs = points.map((p) => p.time).toList(),
        _ys = points.map((p) => p.value).toList(),
        _ks = _computeNaturalSpline(
          points.map((p) => p.time).toList(),
          points.map((p) => p.value).toList(),
        );

  /// Значение сплайна в точке [t]
  double at(double t) {
    final n = _xs.length;
    if (t <= _xs.first) return _ys.first;
    if (t >= _xs.last) return _ys.last;

    // Бинарный поиск сегмента
    int lo = 0, hi = n - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_xs[mid] <= t) {
        lo = mid;
      } else {
        hi = mid;
      }
    }

    final h = _xs[hi] - _xs[lo];
    final tt = (t - _xs[lo]) / h;

    // Кубическая интерполяция Эрмита
    final a = _ks[lo] * h - (_ys[hi] - _ys[lo]);
    final b = -_ks[hi] * h + (_ys[hi] - _ys[lo]);

    return (1 - tt) * _ys[lo] +
        tt * _ys[hi] +
        tt * (1 - tt) * (a * (1 - tt) + b * tt);
  }

  static List<double> _computeNaturalSpline(
    List<double> xs,
    List<double> ys,
  ) {
    final n = xs.length;
    final ks = List<double>.filled(n, 0);
    if (n < 2) return ks;

    final ms = List<double>.filled(n - 1, 0);
    for (var i = 0; i < n - 1; i++) {
      ms[i] = (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]);
    }

    ks[0] = ms[0];
    for (var i = 1; i < n - 1; i++) {
      if (ms[i - 1] * ms[i] <= 0) {
        ks[i] = 0;
      } else {
        final w1 = 2 * (xs[i + 1] - xs[i]) + (xs[i] - xs[i - 1]);
        final w2 = (xs[i + 1] - xs[i]) + 2 * (xs[i] - xs[i - 1]);
        ks[i] = (w1 + w2) / (w1 / ms[i - 1] + w2 / ms[i]);
      }
    }
    ks[n - 1] = ms[n - 2];
    return ks;
  }
}

// ── Сплайны точно из SyllableVocals.ts ────────────────────────────────────

/// ScaleRange из оригинала
final kScaleSpline = LyricSpline([
  (time: 0.0, value: 0.95), // Lowest
  (time: 0.7, value: 1.025), // Highest
  (time: 1.0, value: 1.0), // Rest
]);

/// YOffsetRange — относительно font-size
final kYOffsetSpline = LyricSpline([
  (time: 0.0, value: 1 / 100), // Lowest
  (time: 0.9, value: -1 / 60), // Highest (вверх)
  (time: 1.0, value: 0.0), // Rest
]);

/// GlowRange — альфа свечения
final kGlowSpline = LyricSpline([
  (time: 0.0, value: 0.0), // Lowest
  (time: 0.15, value: 1.0), // Highest
  (time: 0.6, value: 1.0), // Sustain
  (time: 1.0, value: 0.0), // Rest
]);
