import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/player/data/spectrum_store.dart';
import 'package:protogenix/features/player/domain/spectrogram.dart';

// Спектр лежит на диске своим маленьким форматом (spectrum_store.dart).
// Главное, чего здесь нельзя допустить, — прочитать чужой или старый файл как
// свой: полосы поедут, и визуализатор будет дёргаться непонятно почему.

Spectrogram sample({int bands = 4, int frames = 5}) {
  final values = Uint8List(bands * frames);
  for (var i = 0; i < values.length; i++) {
    values[i] = (i * 7) % 256;
  }
  return Spectrogram(values: values, bands: bands, frameMs: 40);
}

void main() {
  test('записали и прочитали — то же самое', () {
    final spectrum = sample();
    final back = unpackSpectrogram(packSpectrogram(spectrum))!;

    expect(back.bands, spectrum.bands);
    expect(back.frames, spectrum.frames);
    expect(back.frameMs, spectrum.frameMs);
    expect(back.values, spectrum.values);
  });

  test('настоящий размер: 16 полос по 25 кадров — байт на значение', () {
    final spectrum = sample(bands: kSpectrumBands, frames: 60 * kSpectrumFps);
    final packed = packSpectrogram(spectrum);
    // Минута трека — около 24 КБ, плюс крошечный заголовок
    expect(packed.length, closeTo(24000, 200));
  });

  test('чужой или битый файл — null, а не каша из полос', () {
    expect(unpackSpectrogram(Uint8List(0)), isNull);
    expect(unpackSpectrogram(Uint8List.fromList([1, 2, 3])), isNull);
    expect(
      unpackSpectrogram(Uint8List.fromList(List.filled(64, 9))),
      isNull,
      reason: 'без подписи PGS1 файл не наш',
    );

    // Подпись своя, а длина не сходится с заголовком: файл дописан не до конца
    final packed = packSpectrogram(sample());
    expect(unpackSpectrogram(packed.sublist(0, packed.length - 3)), isNull);
  });

  test('файл прошлой версии формата не читается как свой', () {
    // У первой версии была бы другая подпись — проверяем, что сверяется она,
    // а не просто длина
    final packed = packSpectrogram(sample());
    final older = Uint8List.fromList(packed)..[3] = 0x30; // PGS0
    expect(unpackSpectrogram(older), isNull);
  });

  test('пустой заголовок не проходит', () {
    final packed = packSpectrogram(sample());
    final broken = Uint8List.fromList(packed)..[4] = 0; // полос ноль
    expect(unpackSpectrogram(broken), isNull);
  });
}
