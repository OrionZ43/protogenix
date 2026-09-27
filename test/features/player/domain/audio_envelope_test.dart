import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/player/domain/audio_envelope.dart';

// Огибающая считается по размерам звуковых пакетов, без декодирования
// (audio_envelope.dart). Здесь собираем поток mp3-кадров руками: у кадра
// размер задаётся битрейтом в заголовке, так что «тихо» и «громко»
// моделируются прямо.

const _bitrates = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224];

/// Поток mp3 из кадров с битрейтами [perFrame] (индексы таблицы).
Uint8List mp3(List<int> perFrame) {
  final out = BytesBuilder();
  for (final index in perFrame) {
    final length = 144 * _bitrates[index] * 1000 ~/ 44100;
    final frame = Uint8List(length);
    frame[0] = 0xFF;
    frame[1] = 0xFB; // MPEG1 Layer3, без CRC
    frame[2] = (index << 4); // битрейт, частота 44100 (индекс 0), без padding
    frame[3] = 0;
    out.add(frame);
  }
  return out.toBytes();
}

void main() {
  test('тихое начало и громкий конец видны в огибающей', () {
    final bytes = mp3([
      for (var i = 0; i < 100; i++) 5, // 64 кбит/с — «тихо»
      for (var i = 0; i < 100; i++) 12, // 224 кбит/с — «громко»
    ]);

    final envelope = envelopeFromBytes(bytes, stepMs: 260)!;
    expect(envelope.points.length, greaterThan(15));
    expect(envelope.durationMs, greaterThan(4000));

    final half = envelope.points.length ~/ 2;
    final firstHalf =
        envelope.points.take(half).reduce((a, b) => a + b) / half;
    final secondHalf = envelope.points.skip(half).reduce((a, b) => a + b) /
        (envelope.points.length - half);
    expect(secondHalf, greaterThan(firstHalf * 3),
        reason: 'вторая половина громче первой');
    expect(envelope.at(0), lessThan(0.3));
    expect(envelope.at(envelope.durationMs - 1), greaterThan(0.7));
  });

  test('постоянный битрейт — огибающей нет, а не «пила» из шума', () {
    // Обычный mp3 с постоянным битрейтом: все кадры одного размера, и разброс
    // взялся бы только из выравнивания — по такому судить о громкости нельзя
    final bytes = mp3([for (var i = 0; i < 200; i++) 9]);
    expect(envelopeFromBytes(bytes), isNull);
  });

  test('мусор вместо файла — null, а не исключение', () {
    expect(envelopeFromBytes(Uint8List(0)), isNull);
    expect(envelopeFromBytes(Uint8List.fromList(List.filled(64, 7))), isNull);
    expect(
      envelopeFromBytes(Uint8List.fromList([0x1A, 0x45, 0xDF, 0xA3, 1, 2, 3])),
      isNull,
      reason: 'заголовок WebM есть, а содержимого нет',
    );
  });

  test('значение в момент времени не выходит за границы', () {
    // Блоками по 8 кадров: на шаге 20 мс это разные точки огибающей,
    // а не усреднённая каша
    final bytes = mp3([
      for (var i = 0; i < 120; i++) (i ~/ 8).isEven ? 5 : 12,
    ]);
    final envelope = envelopeFromBytes(bytes)!;
    for (final ms in [
      -100,
      0,
      envelope.durationMs ~/ 2,
      envelope.durationMs * 5,
    ]) {
      expect(envelope.at(ms), inInclusiveRange(0.0, 1.0));
      expect(envelope.punchAt(ms), inInclusiveRange(0.0, 1.0));
    }
  });

  test('удар после тишины виден как толчок, ровное место — нет', () {
    // Тихо, потом резко громко: на границе должен быть толчок
    final bytes = mp3([
      for (var i = 0; i < 120; i++) 5,
      for (var i = 0; i < 120; i++) 12,
    ]);
    final envelope = envelopeFromBytes(bytes)!;
    final edgeMs = envelope.durationMs ~/ 2;

    expect(envelope.punchAt(edgeMs + 30), greaterThan(0.3),
        reason: 'на переходе тихо→громко толчок есть');
    expect(envelope.punchAt(envelope.durationMs - 200), lessThan(0.15),
        reason: 'внутри ровного громкого куска толчка нет');
  });
}
