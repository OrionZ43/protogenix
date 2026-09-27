// lib/features/player/domain/audio_envelope.dart
//
// Огибающая громкости трека: сколько «энергии» в каждый момент песни.
// Нужна волне под прогрессом и визуализатору.
//
// Считается **без декодирования звука**, по размеру звуковых пакетов в файле.
// У Opus и AAC переменный битрейт: тишина и пауза — это десятки байт на кадр,
// плотный припев — сотни. Точного уровня в децибелах так не получить, но форма
// песни (вступление, куплет, припев, затухание) видна хорошо, а стоит это одно
// чтение файла без единого декодера, одинаково на телефоне и на ПК.
//
// Что разбираем:
//   • WebM/Opus (`.webm`) — так YouTube отдаёт звук, это 95% медиатеки:
//     идём по кластерам EBML и берём размеры SimpleBlock;
//   • MP4/AAC (`.m4a`, `.mp4`) — таблица размеров сэмплов `stsz` и их
//     длительностей `stts`;
//   • MP3 — заголовки кадров: битрейт кадра у VBR тоже следует за музыкой.
//
// Неизвестный формат — null, и волна рисуется как раньше, синтетическая.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Огибающая: [points] — значения 0..255 по времени трека.
class AudioEnvelope {
  const AudioEnvelope({required this.points, required this.durationMs});

  final Uint8List points;
  final int durationMs;

  bool get isEmpty => points.isEmpty;

  /// Сколько миллисекунд приходится на точку.
  double get msPerPoint =>
      points.isEmpty ? 0 : durationMs / points.length;

  /// Значение 0..1 в момент [ms].
  double at(int ms) {
    if (points.isEmpty || durationMs <= 0) return 0;
    final i = (ms / durationMs * points.length).floor().clamp(
          0,
          points.length - 1,
        );
    return points[i] / 255.0;
  }

  /// Насколько громкость подскочила к моменту [ms] по сравнению с тем, что
  /// было только что: по этому визуализатор «бьёт» в такт. 0 — ровное место,
  /// 1 — резкий удар.
  ///
  /// Сравниваем с усреднением за последние ~120 мс: ровный громкий кусок
  /// толчка не даёт, а удар на фоне тишины — даёт.
  double punchAt(int ms) {
    if (points.isEmpty || durationMs <= 0) return 0;
    final perPoint = msPerPoint;
    if (perPoint <= 0) return 0;
    final i = (ms / perPoint).floor().clamp(0, points.length - 1);
    final back = math.max(1, (120 / perPoint).round());
    final from = math.max(0, i - back);
    if (i <= from) return 0;

    var sum = 0;
    for (var j = from; j < i; j++) {
      sum += points[j];
    }
    final average = sum / (i - from);
    final rise = (points[i] - average) / 255.0;
    return (rise * 3.2).clamp(0.0, 1.0);
  }
}

/// Шаг огибающей по времени. 20 мс — это примерно один звуковой пакет Opus,
/// то есть мельче, чем удар: на таком шаге бочка и хлопок видны.
///
/// Сначала тут было 400 точек на весь трек — по точке на полсекунды. Волне
/// под прогрессом хватало, а визуализатор от такого «не попадал в биты»
/// (отзыв Orion), потому что удары просто усреднялись.
const kEnvelopeStepMs = 20;

/// Потолок на случай очень длинных записей: час музыки — это 180 000 точек,
/// больше не нужно никому.
const kEnvelopeMaxPoints = 180000;

/// Огибающая для файла. null — формат не разобрали.
Future<AudioEnvelope?> computeEnvelope(File file,
    {int stepMs = kEnvelopeStepMs}) async {
  if (!await file.exists()) return null;
  final Uint8List bytes;
  try {
    bytes = await file.readAsBytes();
  } catch (_) {
    return null;
  }
  return envelopeFromBytes(bytes, stepMs: stepMs);
}

/// То же, но по готовым байтам — так удобнее в тестах.
AudioEnvelope? envelopeFromBytes(Uint8List bytes,
    {int stepMs = kEnvelopeStepMs}) {
  if (bytes.length < 16) return null;
  final samples = _readWebm(bytes) ?? _readMp4(bytes) ?? _readMp3(bytes);
  if (samples == null || samples.isEmpty) return null;

  final durationMs = samples.last.timeMs;
  if (durationMs <= 0) return null;
  final points =
      (durationMs / math.max(1, stepMs)).round().clamp(8, kEnvelopeMaxPoints);

  final envelope = _bucket(samples, points);
  return envelope.isEmpty ? null : envelope;
}

/// Пакет звука: когда звучит и сколько весит.
class _Packet {
  const _Packet(this.timeMs, this.size);
  final int timeMs;
  final int size;
}

/// Пакеты → точки 0..255. Внутри точки берём среднее, потом нормируем по
/// верхушке (по 98-му проценту, чтобы одиночный всплеск не прижал всю песню).
AudioEnvelope _bucket(List<_Packet> packets, int points) {
  final durationMs = packets.last.timeMs;
  if (durationMs <= 0) {
    return AudioEnvelope(points: Uint8List(0), durationMs: 0);
  }

  final sums = List<double>.filled(points, 0);
  final counts = List<int>.filled(points, 0);
  for (final p in packets) {
    final i = (p.timeMs / durationMs * points).floor().clamp(0, points - 1);
    sums[i] += p.size.toDouble();
    counts[i]++;
  }

  final values = List<double>.generate(
    points,
    (i) => counts[i] == 0 ? double.nan : sums[i] / counts[i],
  );

  // Точка без пакетов — не тишина, а просто короткий трек при большом числе
  // точек. Берём ближайшее известное значение, иначе в волне появлялись бы
  // провалы на ровном месте.
  var lastKnown = double.nan;
  for (var i = 0; i < points; i++) {
    if (!values[i].isNaN) {
      lastKnown = values[i];
    } else if (!lastKnown.isNaN) {
      values[i] = lastKnown;
    }
  }
  for (var i = points - 1; i >= 0; i--) {
    if (!values[i].isNaN) {
      lastKnown = values[i];
    } else if (!lastKnown.isNaN) {
      values[i] = lastKnown;
    }
  }
  for (var i = 0; i < points; i++) {
    if (values[i].isNaN) values[i] = 0;
  }

  final sorted = [...values]..sort();
  final top = sorted[(points * 0.98).floor().clamp(0, points - 1)];
  final floor = sorted[(points * 0.05).floor().clamp(0, points - 1)];

  // Постоянный битрейт (обычный mp3): все кадры одного размера, и разброс
  // берётся только из байта выравнивания. Нормировать такое нельзя — получится
  // «пила» из шума, поэтому честнее сказать, что огибающей нет.
  if (top <= 0 || (top - floor) / top < 0.08) {
    return AudioEnvelope(points: Uint8List(0), durationMs: durationMs);
  }
  final span = top - floor;

  final out = Uint8List(points);
  for (var i = 0; i < points; i++) {
    final v = ((values[i] - floor) / span).clamp(0.0, 1.0);
    out[i] = (v * 255).round();
  }
  return AudioEnvelope(points: out, durationMs: durationMs);
}

// ── WebM (Matroska) ──────────────────────────────────────────────────────────

const _kEbmlHeader = 0x1A45DFA3;
const _kSegment = 0x18538067;
const _kInfo = 0x1549A966;
const _kTimecodeScale = 0x2AD7B1;
const _kCluster = 0x1F43B675;
const _kTimecode = 0xE7;
const _kSimpleBlock = 0xA3;
const _kBlockGroup = 0xA0;
const _kBlock = 0xA1;

List<_Packet>? _readWebm(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  if (bytes.length < 4 || data.getUint32(0) != _kEbmlHeader) return null;

  final packets = <_Packet>[];
  // Масштаб времени кластеров; по умолчанию миллисекунда
  var timecodeScaleNs = 1000000;
  var clusterTimeMs = 0;

  void walk(int start, int end, int depth) {
    var offset = start;
    while (offset < end && depth < 6) {
      final id = _readId(bytes, offset);
      if (id == null) return;
      offset = id.next;
      final size = _readVint(bytes, offset, keepMarker: false);
      if (size == null) return;
      offset = size.next;
      final contentEnd =
          size.value < 0 ? end : math.min(end, offset + size.value);

      switch (id.value) {
        case _kSegment:
        case _kInfo:
        case _kCluster:
        case _kBlockGroup:
          walk(offset, contentEnd, depth + 1);
        case _kTimecodeScale:
          timecodeScaleNs = _readUint(bytes, offset, contentEnd - offset);
        case _kTimecode:
          clusterTimeMs = _readUint(bytes, offset, contentEnd - offset) *
              timecodeScaleNs ~/
              1000000;
        case _kSimpleBlock:
        case _kBlock:
          final track = _readVint(bytes, offset, keepMarker: false);
          if (track != null && track.next + 2 < contentEnd) {
            final rel = data.getInt16(track.next);
            // Заголовок блока: номер дорожки, смещение времени, флаги
            final payload = contentEnd - (track.next + 3);
            if (payload > 0) {
              packets.add(_Packet(clusterTimeMs + rel, payload));
            }
          }
        default:
          break;
      }
      offset = contentEnd;
    }
  }

  walk(0, bytes.length, 0);
  if (packets.length < 8) return null;
  packets.sort((a, b) => a.timeMs.compareTo(b.timeMs));
  return packets;
}

/// Идентификатор элемента EBML: длина зашита в старшие биты первого байта.
({int value, int next})? _readId(Uint8List bytes, int offset) {
  if (offset >= bytes.length) return null;
  final first = bytes[offset];
  final length = first >= 0x80
      ? 1
      : first >= 0x40
          ? 2
          : first >= 0x20
              ? 3
              : first >= 0x10
                  ? 4
                  : 0;
  if (length == 0 || offset + length > bytes.length) return null;
  var value = 0;
  for (var i = 0; i < length; i++) {
    value = (value << 8) | bytes[offset + i];
  }
  return (value: value, next: offset + length);
}

/// Число переменной длины. [keepMarker] false — старший бит-маркер снимается.
({int value, int next})? _readVint(Uint8List bytes, int offset,
    {bool keepMarker = true}) {
  if (offset >= bytes.length) return null;
  final first = bytes[offset];
  if (first == 0) return null;
  var length = 1;
  var mask = 0x80;
  while (length <= 8 && (first & mask) == 0) {
    length++;
    mask >>= 1;
  }
  if (length > 8 || offset + length > bytes.length) return null;
  var value = keepMarker ? first : first & (mask - 1);
  for (var i = 1; i < length; i++) {
    value = (value << 8) | bytes[offset + i];
  }
  // Все единицы — размер неизвестен (потоковая запись)
  final unknown = !keepMarker && value == (1 << (7 * length)) - 1;
  return (value: unknown ? -1 : value, next: offset + length);
}

int _readUint(Uint8List bytes, int offset, int length) {
  var value = 0;
  for (var i = 0; i < length && offset + i < bytes.length; i++) {
    value = (value << 8) | bytes[offset + i];
  }
  return value;
}

// ── MP4 / M4A ────────────────────────────────────────────────────────────────

List<_Packet>? _readMp4(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  if (bytes.length < 12) return null;
  // Второй атом файла — ftyp
  if (String.fromCharCodes(bytes.sublist(4, 8)) != 'ftyp') return null;

  Uint8List? stsz;
  Uint8List? stts;
  var timescale = 0;

  void walk(int start, int end, int depth) {
    var offset = start;
    while (offset + 8 <= end && depth < 8) {
      var size = data.getUint32(offset);
      final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
      var header = 8;
      if (size == 1 && offset + 16 <= end) {
        size = data.getUint64(offset + 8);
        header = 16;
      }
      if (size < header || offset + size > end) return;

      switch (type) {
        case 'moov':
        case 'trak':
        case 'mdia':
        case 'minf':
        case 'stbl':
          walk(offset + header, offset + size, depth + 1);
        case 'mdhd':
          // version(1) flags(3) created(4) modified(4) timescale(4)
          if (offset + header + 20 <= end && timescale == 0) {
            timescale = data.getUint32(offset + header + 12);
          }
        case 'stsz':
          stsz = bytes.sublist(offset + header, offset + size);
        case 'stts':
          stts = bytes.sublist(offset + header, offset + size);
        default:
          break;
      }
      offset += size;
    }
  }

  walk(0, bytes.length, 0);
  final sizes = stsz;
  if (sizes == null || timescale <= 0) return null;

  final sizeData = ByteData.sublistView(sizes);
  if (sizes.length < 12) return null;
  final uniformSize = sizeData.getUint32(4);
  final count = sizeData.getUint32(8);
  if (count == 0) return null;

  // Длительность одного сэмпла: берём первую запись stts, у звука она одна
  var sampleDelta = 1024;
  final times = stts;
  if (times != null && times.length >= 16) {
    sampleDelta = ByteData.sublistView(times).getUint32(12);
  }
  final msPerSample = sampleDelta * 1000 / timescale;

  final packets = <_Packet>[];
  for (var i = 0; i < count; i++) {
    final size = uniformSize != 0
        ? uniformSize
        : (12 + i * 4 + 4 <= sizes.length
            ? sizeData.getUint32(12 + i * 4)
            : 0);
    if (size == 0) continue;
    packets.add(_Packet((i * msPerSample).round(), size));
  }
  return packets.length < 8 ? null : packets;
}

// ── MP3 ──────────────────────────────────────────────────────────────────────

const _kMp3Bitrates = [
  0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0 //
];
const _kMp3Rates = [44100, 48000, 32000, 0];

List<_Packet>? _readMp3(Uint8List bytes) {
  var offset = 0;
  // Пропускаем тег ID3, если он есть
  if (bytes.length > 10 &&
      bytes[0] == 0x49 &&
      bytes[1] == 0x44 &&
      bytes[2] == 0x33) {
    final size = ((bytes[6] & 0x7F) << 21) |
        ((bytes[7] & 0x7F) << 14) |
        ((bytes[8] & 0x7F) << 7) |
        (bytes[9] & 0x7F);
    offset = 10 + size;
  }

  final packets = <_Packet>[];
  var timeMs = 0.0;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] != 0xFF || (bytes[offset + 1] & 0xE0) != 0xE0) {
      offset++;
      continue;
    }
    final bitrateIndex = (bytes[offset + 2] >> 4) & 0x0F;
    final rateIndex = (bytes[offset + 2] >> 2) & 0x03;
    final padding = (bytes[offset + 2] >> 1) & 0x01;
    final bitrate = _kMp3Bitrates[bitrateIndex];
    final rate = _kMp3Rates[rateIndex];
    if (bitrate == 0 || rate == 0) {
      offset++;
      continue;
    }
    final frameLength = (144 * bitrate * 1000 ~/ rate) + padding;
    if (frameLength <= 4) break;
    packets.add(_Packet(timeMs.round(), frameLength));
    timeMs += 1152 * 1000 / rate;
    offset += frameLength;
  }
  return packets.length < 8 ? null : packets;
}
