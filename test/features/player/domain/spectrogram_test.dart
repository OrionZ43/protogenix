import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/player/domain/spectrogram.dart';

// Спектр считается по настоящему звуку (spectrogram.dart), поэтому и проверять
// его надо звуком: синус известной частоты должен попадать в свою полосу.
//
// Важно: звук в тестах обязан **меняться по громкости**. Каждая полоса
// нормируется по своему размаху, и ровный синус — вырожденный случай:
// у него размаха нет, и полоса встаёт в потолок с первого кадра. Настоящая
// музыка так себя не ведёт, поэтому тоны здесь пульсируют.

const _rate = 22050;

/// Синус [hz] длиной [seconds], громкость плавно гуляет с периодом [pulseS]
/// от почти тишины до максимума.
Float32List tone(
  double hz,
  double seconds, {
  double amplitude = 0.5,
  double pulseS = 0.8,
}) {
  final samples = Float32List((_rate * seconds).round());
  for (var i = 0; i < samples.length; i++) {
    final t = i / _rate;
    final swell = 0.5 - 0.5 * math.cos(2 * math.pi * t / pulseS);
    samples[i] =
        amplitude * (0.02 + 0.98 * swell) * math.sin(2 * math.pi * hz * t);
  }
  return samples;
}

/// Полосы в момент [ms].
List<double> bandsAt(Spectrogram spectrum, int ms) {
  final out = List<double>.filled(spectrum.bands, 0);
  spectrum.sampleInto(out, ms);
  return out;
}

/// Номер самой громкой полосы.
int loudest(List<double> bands) {
  var best = 0;
  for (var i = 1; i < bands.length; i++) {
    if (bands[i] > bands[best]) best = i;
  }
  return best;
}

/// Самое громкое значение полосы [band] за весь трек.
double peakOf(Spectrogram spectrum, int band) {
  var best = 0.0;
  for (var f = 0; f < spectrum.frames; f++) {
    final v = spectrum.values[f * spectrum.bands + band] / 255.0;
    if (v > best) best = v;
  }
  return best;
}

void main() {
  test('низкий звук попадает в нижние полосы, высокий — в верхние', () {
    final low = analyzeSpectrum(tone(80, 4), sampleRate: _rate);
    final high = analyzeSpectrum(tone(6000, 4), sampleRate: _rate);

    // Смотрим на пике пульсации: период 0,8 с, значит громче всего в 0,4 с
    expect(loudest(bandsAt(low, 400)), lessThan(4), reason: '80 Гц — это низы');
    expect(loudest(bandsAt(high, 400)), greaterThan(11),
        reason: '6 кГц — это верха');

    // И наоборот: чужих частот в треке нет вовсе
    expect(peakOf(low, 15), lessThan(0.05),
        reason: 'у низкого тона верхних частот нет');
    expect(peakOf(high, 0), lessThan(0.05),
        reason: 'у высокого тона низов нет');
  });

  test('полосы не путаются: два тона видны отдельно, а не размазаны', () {
    final samples = tone(80, 4, pulseS: 0.8);
    final highs = tone(6000, 4, pulseS: 1.7);
    for (var i = 0; i < samples.length; i++) {
      samples[i] += highs[i];
    }
    final spectrum = analyzeSpectrum(samples, sampleRate: _rate);

    // Низы и полоса с 6 кГц (14-я: 5,4–7,7 кГц) звучат, между ними пусто
    expect(peakOf(spectrum, 0), greaterThan(0.8));
    expect(peakOf(spectrum, 14), greaterThan(0.8));
    expect(peakOf(spectrum, 8), lessThan(0.35),
        reason: 'между двумя тонами ничего нет');
    expect(peakOf(spectrum, 15), lessThan(0.35),
        reason: 'выше 7,7 кГц ничего нет — значит полосы узкие');
  });

  test('полоса живёт своей громкостью: от тишины до потолка', () {
    final spectrum = analyzeSpectrum(tone(80, 6), sampleRate: _rate);
    final band = <double>[];
    for (var f = 0; f < spectrum.frames; f++) {
      band.add(spectrum.values[f * spectrum.bands] / 255.0);
    }
    band.sort();
    expect(band.last, greaterThan(0.9), reason: 'на пике столбик вверху');
    expect(band[band.length ~/ 10], lessThan(0.3),
        reason: 'в тихие моменты столбик внизу');
  });

  test('длительность и число кадров совпадают со звуком', () {
    final spectrum = analyzeSpectrum(tone(440, 4), sampleRate: _rate);
    expect(spectrum.frameMs, closeTo(1000 / kSpectrumFps, 1.0));
    expect(spectrum.bands, kSpectrumBands);
    expect(spectrum.durationMs, closeTo(4000, 120));
    expect(spectrum.frames, closeTo(4 * kSpectrumFps, 3));
  });

  test('значения не выходят за границы и не падают на краях', () {
    final spectrum = analyzeSpectrum(tone(440, 3), sampleRate: _rate);
    for (final ms in [-500, 0, 1000, spectrum.durationMs, 99999]) {
      for (final value in bandsAt(spectrum, ms)) {
        expect(value, inInclusiveRange(0.0, 1.0));
      }
      expect(spectrum.punchAt(ms), inInclusiveRange(0.0, 1.0));
    }
  });

  test('удар по низам виден как толчок, ровное место — нет', () {
    // Секунда тишины, потом низкий тон, который держится ровно
    final samples = Float32List(_rate * 3);
    final hit = tone(60, 2, amplitude: 0.9, pulseS: 1000);
    for (var i = 0; i < hit.length; i++) {
      samples[_rate + i] = hit[i];
    }
    final spectrum = analyzeSpectrum(samples, sampleRate: _rate);

    expect(spectrum.punchAt(1060), greaterThan(0.3),
        reason: 'на входе низов есть толчок');
    expect(spectrum.punchAt(2600), lessThan(0.15),
        reason: 'внутри ровного тона толчка нет');
  });

  test('тишина и мусор не ломают разбор', () {
    expect(analyzeSpectrum(Float32List(0), sampleRate: _rate).isEmpty, isTrue);
    expect(analyzeSpectrum(tone(440, 1), sampleRate: 0).isEmpty, isTrue);

    final silence = analyzeSpectrum(Float32List(_rate), sampleRate: _rate);
    expect(silence.isEmpty, isFalse);
    for (final value in bandsAt(silence, 500)) {
      expect(value, 0.0, reason: 'из тишины визуализатор ничего не выдумывает');
    }
  });
}
