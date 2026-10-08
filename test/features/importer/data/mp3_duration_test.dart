import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/importer/data/mp3_duration.dart';

// Отзыв 2026-10-08: сборники на два часа показывались как 43 минуты. Без
// VBR-заголовка длину MP3 считали по битрейту первого кадра. Здесь MP3
// собираются из настоящих заголовков кадров (MPEG-1 Layer III, 44,1 кГц,
// стерео) с нулями внутри — длина известна точно: кадров × 1152 / 44100.

const _rate = 44100;

/// Индексы битрейта MPEG-1 Layer III.
const _kbpsIndex = {32: 1, 64: 5, 128: 9, 320: 14};

int frameLength(int kbps) => 144 * kbps * 1000 ~/ _rate;

Uint8List frame(int kbps, {Uint8List? payload}) {
  final bytes = Uint8List(frameLength(kbps));
  bytes[0] = 0xFF;
  bytes[1] = 0xFB; // MPEG 1, Layer III, без CRC
  bytes[2] = _kbpsIndex[kbps]! << 4; // 44,1 кГц, без добивки
  bytes[3] = 0x00; // стерео
  if (payload != null) bytes.setAll(4, payload);
  return bytes;
}

/// Первый кадр с заголовком Xing: число кадров и размер звука в байтах.
Uint8List xingFrame(int frames, int audioBytes) {
  final xing = ByteData(16)
    ..setUint8(0, 0x58) // X
    ..setUint8(1, 0x69) // i
    ..setUint8(2, 0x6E) // n
    ..setUint8(3, 0x67) // g
    ..setUint32(4, 0x3) // есть число кадров и размер
    ..setUint32(8, frames)
    ..setUint32(12, audioBytes);
  final payload = Uint8List(32 + 16)..setAll(32, xing.buffer.asUint8List());
  return frame(128, payload: payload);
}

/// ID3v2 нужной длины (без содержимого).
Uint8List id3(int size) {
  final bytes = Uint8List(10 + size);
  bytes.setAll(0, 'ID3'.codeUnits);
  bytes[3] = 3;
  bytes[6] = (size >> 21) & 0x7F;
  bytes[7] = (size >> 14) & 0x7F;
  bytes[8] = (size >> 7) & 0x7F;
  bytes[9] = size & 0x7F;
  return bytes;
}

Duration framesDuration(int frames) =>
    Duration(microseconds: (frames * 1152 * 1e6 / _rate).round());

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('pg_mp3'));
  tearDown(() async => dir.delete(recursive: true));

  Future<String> write(List<Uint8List> parts) async {
    final path = '${dir.path}/t${DateTime.now().microsecondsSinceEpoch}.mp3';
    final builder = BytesBuilder(copy: false);
    for (final part in parts) {
      builder.add(part);
    }
    await File(path).writeAsBytes(builder.takeBytes());
    return path;
  }

  void expectAbout(Duration? actual, Duration expected) {
    expect(actual, isNotNull);
    expect((actual! - expected).inMilliseconds.abs(), lessThan(5));
  }

  test('переменный битрейт без заголовка — длина по кадрам', () async {
    // Громкое начало, дальше тихо: оценка по первому кадру вышла бы в 5 раз
    // короче настоящей длины
    final path = await write([
      id3(500),
      for (var i = 0; i < 50; i++) frame(320),
      for (var i = 0; i < 2000; i++) frame(64),
    ]);
    expectAbout(exactMp3DurationIfNeeded(path), framesDuration(2050));
  });

  test('верный заголовок Xing — сканировать не нужно', () async {
    const frames = 300;
    final audio = frameLength(128) * (frames + 1);
    final path = await write([
      xingFrame(frames, audio),
      for (var i = 0; i < frames; i++) frame(128),
    ]);
    expect(exactMp3DurationIfNeeded(path), isNull,
        reason: 'длину верно даёт audio_metadata_reader');
  });

  test('склейка: заголовок от первого трека — длина по кадрам', () async {
    // Xing описывает только первые 100 кадров, а дальше приклеено ещё 3000
    final firstAudio = frameLength(128) * 101;
    final path = await write([
      xingFrame(100, firstAudio),
      for (var i = 0; i < 100; i++) frame(128),
      id3(300), // тег следующего трека посреди файла
      for (var i = 0; i < 3000; i++) frame(64),
    ]);
    expectAbout(exactMp3DurationIfNeeded(path), framesDuration(3101));
  });

  test('мусор и ID3 посреди файла не сбивают счёт', () async {
    final path = await write([
      for (var i = 0; i < 400; i++) frame(128),
      Uint8List(1234), // мусор
      id3(2048),
      for (var i = 0; i < 400; i++) frame(32),
    ]);
    expectAbout(scanMp3Duration(path), framesDuration(800));
  });

  test('не MP3 — null, без исключения', () async {
    final path = await write([Uint8List.fromList('просто текст'.codeUnits)]);
    expect(exactMp3DurationIfNeeded(path), isNull);
    expect(exactMp3DurationIfNeeded('${dir.path}/нет_такого.mp3'), isNull);
  });
}
