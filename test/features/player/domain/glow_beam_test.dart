import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/player/domain/glow_beam.dart';

// Ореол караоке едет вместе с голосом, а не висит на всём спетом тексте:
// иначе каждый спетый слог рисуется ещё раз с размытием и съедает половину
// кадра (замеры — в `glow_beam.dart` и `performance.md`).

void main() {
  test('пока слог поётся — луч в полную силу', () {
    expect(beamAt(1000, 1000, 1400), 1.0);
    expect(beamAt(1200, 1000, 1400), 1.0);
    expect(beamAt(1400, 1000, 1400), 1.0);
  });

  test('далеко до слога и давно после — луча нет', () {
    expect(beamAt(0, 1000, 1400), 0.0);
    expect(beamAt(1400 + kBeamTailMs, 1000, 1400), 0.0);
    expect(beamAt(10000, 1000, 1400), 0.0);
  });

  test('разгорается перед слогом и гаснет после — без скачка', () {
    // На границах значение сходится к тому же, что и внутри отрезка
    expect(beamAt(1000 - kBeamLeadMs / 2, 1000, 1400), closeTo(0.5, 1e-9));
    expect(beamAt(1400 + kBeamTailMs / 2, 1000, 1400), closeTo(0.5, 1e-9));

    // Перед началом растёт
    var prev = 0.0;
    for (var ms = 1000 - kBeamLeadMs; ms <= 1000; ms += 10) {
      final v = beamAt(ms, 1000, 1400);
      expect(v, greaterThanOrEqualTo(prev));
      prev = v;
    }

    // После конца падает
    prev = 1.0;
    for (var ms = 1400.0; ms <= 1400 + kBeamTailMs; ms += 10) {
      final v = beamAt(ms, 1400, 1400);
      expect(v, lessThanOrEqualTo(prev));
      prev = v;
    }
  });

  test('хвост длиннее разгорания: ореол уходит мягче, чем приходит', () {
    expect(kBeamTailMs, greaterThan(kBeamLeadMs));
  });

  test('слог нулевой длины (бывает в кривых LRC) не ломает расчёт', () {
    expect(beamAt(500, 500, 500), 1.0);
    expect(beamAt(500 + kBeamTailMs + 1, 500, 500), 0.0);
    expect(beamAt(0, 500, 500), 0.0);
  });

  test('значение всегда в пределах 0..1', () {
    for (var ms = -5000.0; ms < 5000; ms += 37) {
      final v = beamAt(ms, 1000, 1400);
      expect(v, inInclusiveRange(0.0, 1.0));
    }
  });
}
