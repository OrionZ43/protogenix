import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/player/data/pcm_decoder.dart';

// WAV от mpv читается кусками (readWavChunks): двухчасовой сборник целиком в
// памяти — это около гигабайта. Здесь проверяется, что кусками получается
// ровно то, что было в файле.

/// WAV 16 бит: [frames] кадров по [channels] каналов, значение кадра i в
/// канале c — (i * 7 + c * 1000) % 30000 - 15000.
Uint8List wavBytes({
  required int frames,
  int channels = 1,
  int rate = 22050,
  bool sizeWritten = true,
}) {
  final dataSize = frames * channels * 2;
  final bytes = ByteData(44 + dataSize);
  void tag(int at, String text) {
    for (var i = 0; i < 4; i++) {
      bytes.setUint8(at + i, text.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  bytes.setUint32(4, sizeWritten ? 36 + dataSize : 0, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, channels, Endian.little);
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * channels * 2, Endian.little);
  bytes.setUint16(32, channels * 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  // mpv дописывает размер, только когда закрывает файл
  bytes.setUint32(40, sizeWritten ? dataSize : 0, Endian.little);
  for (var i = 0; i < frames; i++) {
    for (var c = 0; c < channels; c++) {
      bytes.setInt16(44 + (i * channels + c) * 2,
          (i * 7 + c * 1000) % 30000 - 15000, Endian.little);
    }
  }
  return bytes.buffer.asUint8List();
}

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('pg_wav'));
  tearDown(() async => dir.delete(recursive: true));

  Future<(List<double>, int, int)> read(Uint8List bytes) async {
    final file = File('${dir.path}/t.wav');
    await file.writeAsBytes(bytes);
    final samples = <double>[];
    var chunks = 0;
    var rate = 0;
    final ok = readWavChunks(file, (chunk, sampleRate) {
      samples.addAll(chunk);
      rate = sampleRate;
      chunks++;
    });
    expect(ok, isTrue);
    return (samples, rate, chunks);
  }

  test('моно: все отсчёты на месте, файл больше одного блока', () async {
    const frames = 100000; // 200 КБ — несколько блоков по 64 КБ
    final (samples, rate, chunks) = await read(wavBytes(frames: frames));
    expect(rate, 22050);
    expect(chunks, greaterThan(1), reason: 'читается кусками');
    expect(samples.length, frames);
    for (final i in [0, 1, 32767, 32768, 65536, frames - 1]) {
      expect(samples[i], closeTo(((i * 7) % 30000 - 15000) / 32768.0, 1e-6),
          reason: 'кадр $i');
    }
  });

  test('стерео сводится в моно', () async {
    final (samples, _, _) = await read(wavBytes(frames: 50000, channels: 2));
    expect(samples.length, 50000);
    for (final i in [0, 40000, 49999]) {
      final left = (i * 7) % 30000 - 15000;
      final right = (i * 7 + 1000) % 30000 - 15000;
      expect(samples[i], closeTo((left + right) / 2 / 32768.0, 1e-6));
    }
  });

  test('размер в заголовке не дописан — читается остаток файла', () async {
    final (samples, _, _) =
        await read(wavBytes(frames: 70000, sizeWritten: false));
    expect(samples.length, 70000);
  });

  test('не WAV — false, без исключения', () async {
    final file = File('${dir.path}/junk.wav');
    await file.writeAsBytes(List.filled(100, 7));
    expect(readWavChunks(file, (_, __) {}), isFalse);
  });
}
