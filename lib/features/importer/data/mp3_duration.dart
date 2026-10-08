// lib/features/importer/data/mp3_duration.dart
//
// Точная длина MP3 — по заголовкам кадров.
//
// Зачем. Длину MP3 обычно берут из VBR-заголовка (Xing, Info или VBRI) в
// первом кадре: там записано число кадров. Если его нет, `audio_metadata_reader`
// считает длину по битрейту **первого** кадра — и на файле с переменным
// битрейтом ошибается в разы. Так же ошибаются ffprobe, ExoPlayer и MediaStore
// на Pixel (на Samsung MediaStore считает верно). Отзыв 2026-10-08: сборники на
// два часа показывались как 43 минуты. Такие файлы чаще всего склеены из
// треков с разным битрейтом — и общего заголовка у них нет, или он остался от
// первого трека склейки и описывает только его.
//
// Здесь — проход по заголовкам кадров: на кадр читается 4 байта, остальное
// пропускается, длина — сумма отсчётов кадров, делённая на частоту.
// Двухчасовой файл на 28 МБ — доли секунды. Нормальные MP3 с верным
// заголовком не сканируются вовсе.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Точная длина MP3, если обычному способу верить нельзя: VBR-заголовка нет
/// или он от другого, более короткого файла (склейка). null — заголовок в
/// порядке (длину верно даёт `audio_metadata_reader`), это не MP3 или файл
/// не разобрался. Исключений не бросает.
Duration? exactMp3DurationIfNeeded(String path) {
  RandomAccessFile? file;
  try {
    file = File(path).openSync();
    final reader = _Reader(file);
    final first = _findFirstFrame(reader, _skipId3v2(reader));
    if (first == null) return null;
    if (_vbrHeaderIsTrustworthy(reader, first)) return null;
    return _scan(reader, first.offset);
  } catch (_) {
    return null;
  } finally {
    file?.closeSync();
  }
}

/// Длина по всем кадрам файла, без оглядки на заголовки. Для тестов.
Duration? scanMp3Duration(String path) {
  RandomAccessFile? file;
  try {
    file = File(path).openSync();
    final reader = _Reader(file);
    final first = _findFirstFrame(reader, _skipId3v2(reader));
    return first == null ? null : _scan(reader, first.offset);
  } catch (_) {
    return null;
  } finally {
    file?.closeSync();
  }
}

/// Заголовок кадра MPEG-аудио.
class _Frame {
  const _Frame({
    required this.offset,
    required this.length,
    required this.samples,
    required this.sampleRate,
    required this.mpeg1,
    required this.mono,
  });

  final int offset;
  final int length;
  final int samples;
  final int sampleRate;
  final bool mpeg1;
  final bool mono;
}

const _bitratesV1 = [
  [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448], // I
  [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384], // II
  [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320], // III
];
const _bitratesV2 = [
  [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256], // I
  [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160], // II, III
];
const _sampleRates = {
  3: [44100, 48000, 32000], // MPEG 1
  2: [22050, 24000, 16000], // MPEG 2
  0: [11025, 12000, 8000], // MPEG 2.5
};

/// Разбор 4 байт заголовка кадра на [offset]; null — не заголовок.
_Frame? _parseHeader(int b0, int b1, int b2, int b3, int offset) {
  if (b0 != 0xFF || (b1 & 0xE0) != 0xE0) return null;
  final version = (b1 >> 3) & 0x3; // 3 — MPEG 1, 2 — MPEG 2, 0 — MPEG 2.5
  final layerBits = (b1 >> 1) & 0x3; // 3 — I, 2 — II, 1 — III
  if (version == 1 || layerBits == 0) return null;
  final bitrateIndex = (b2 >> 4) & 0xF;
  final rateIndex = (b2 >> 2) & 0x3;
  // Свободный битрейт (0) длину кадра не даёт — такой файл не считаем
  if (bitrateIndex == 0 || bitrateIndex == 15 || rateIndex == 3) return null;

  final layer = 4 - layerBits; // 1, 2, 3
  final mpeg1 = version == 3;
  final kbps = mpeg1
      ? _bitratesV1[layer - 1][bitrateIndex]
      : _bitratesV2[layer == 1 ? 0 : 1][bitrateIndex];
  final sampleRate = _sampleRates[version]![rateIndex];
  final padding = (b2 >> 1) & 0x1;
  final mono = ((b3 >> 6) & 0x3) == 3;

  final int length;
  final int samples;
  if (layer == 1) {
    length = (12 * kbps * 1000 ~/ sampleRate + padding) * 4;
    samples = 384;
  } else if (layer == 2 || mpeg1) {
    length = 144 * kbps * 1000 ~/ sampleRate + padding;
    samples = 1152;
  } else {
    length = 72 * kbps * 1000 ~/ sampleRate + padding;
    samples = 576;
  }
  if (length < 4) return null;
  return _Frame(
    offset: offset,
    length: length,
    samples: samples,
    sampleRate: sampleRate,
    mpeg1: mpeg1,
    mono: mono,
  );
}

/// Кадр на [offset], если там действительно кадр.
_Frame? _frameAt(_Reader reader, int offset) {
  if (!reader.ensure(offset, 4)) return null;
  return _parseHeader(reader.byte(offset), reader.byte(offset + 1),
      reader.byte(offset + 2), reader.byte(offset + 3), offset);
}

/// Кадр, за которым сразу следует ещё один, — так случайные 0xFF в данных
/// не принимаются за начало кадра. Последний кадр файла тоже годится.
_Frame? _confirmedFrameAt(_Reader reader, int offset) {
  final frame = _frameAt(reader, offset);
  if (frame == null) return null;
  final next = offset + frame.length;
  if (next >= reader.length - 4) return frame;
  return _frameAt(reader, next) == null ? null : frame;
}

/// Начало звука после ID3v2 в начале файла.
int _skipId3v2(_Reader reader) {
  var offset = 0;
  // Бывает несколько тегов подряд
  while (reader.ensure(offset, 10) &&
      reader.byte(offset) == 0x49 && // I
      reader.byte(offset + 1) == 0x44 && // D
      reader.byte(offset + 2) == 0x33) {
    // 3
    final size = (reader.byte(offset + 6) & 0x7F) << 21 |
        (reader.byte(offset + 7) & 0x7F) << 14 |
        (reader.byte(offset + 8) & 0x7F) << 7 |
        (reader.byte(offset + 9) & 0x7F);
    final footer = (reader.byte(offset + 5) & 0x10) != 0 ? 10 : 0;
    offset += 10 + size + footer;
  }
  return offset;
}

/// Первый настоящий кадр — ищем не дальше 1 МБ от [from].
_Frame? _findFirstFrame(_Reader reader, int from) {
  final limit = math.min(reader.length - 4, from + (1 << 20));
  for (var offset = from; offset < limit; offset++) {
    if (!reader.ensure(offset, 4)) return null;
    if (reader.byte(offset) != 0xFF) continue;
    final frame = _confirmedFrameAt(reader, offset);
    if (frame != null) return frame;
  }
  return null;
}

/// Можно ли верить VBR-заголовку первого кадра.
///
/// Нет заголовка — нельзя. Есть, и в нём записан размер звука — сверяем с
/// настоящим: у склейки заголовок остаётся от первого трека и описывает
/// только его. Размера в заголовке нет — верим (LAME его пишет всегда).
bool _vbrHeaderIsTrustworthy(_Reader reader, _Frame first) {
  if (!reader.ensure(first.offset, first.length)) return false;
  final audioBytes = reader.length - first.offset - _id3v1Size(reader);

  // Xing / Info — после побочной информации кадра
  final side = first.mpeg1 ? (first.mono ? 17 : 32) : (first.mono ? 9 : 17);
  final xing = first.offset + 4 + side;
  if (_tagAt(reader, xing, 'Xing') || _tagAt(reader, xing, 'Info')) {
    final flags = reader.uint32(xing + 4);
    var field = xing + 8;
    if (flags & 0x1 != 0) field += 4; // число кадров
    if (flags & 0x2 == 0) return true;
    return _sameSize(reader.uint32(field), audioBytes);
  }

  // VBRI — всегда через 32 байта после заголовка кадра
  final vbri = first.offset + 4 + 32;
  if (_tagAt(reader, vbri, 'VBRI')) {
    return _sameSize(reader.uint32(vbri + 10), audioBytes);
  }
  return false;
}

/// Размер из заголовка совпадает с настоящим с точностью до 2%.
bool _sameSize(int declared, int actual) =>
    actual > 0 && (declared - actual).abs() <= actual * 0.02;

int _id3v1Size(_Reader reader) {
  final at = reader.length - 128;
  return at > 0 && _tagAt(reader, at, 'TAG') ? 128 : 0;
}

bool _tagAt(_Reader reader, int offset, String tag) {
  if (!reader.ensure(offset, tag.length)) return false;
  for (var i = 0; i < tag.length; i++) {
    if (reader.byte(offset + i) != tag.codeUnitAt(i)) return false;
  }
  return true;
}

/// Сумма длительностей всех кадров от [from] до конца файла.
///
/// Между кадрами склейки встречаются ID3-теги и мусор — тогда ищем следующий
/// настоящий кадр. Частота может меняться (склеили треки 44,1 и 48 кГц),
/// поэтому длительность каждого кадра считается по его частоте.
Duration? _scan(_Reader reader, int from) {
  var offset = from;
  var micros = 0.0;
  var frames = 0;
  final end = reader.length - 4;

  while (offset < end) {
    var frame = _frameAt(reader, offset);
    if (frame == null) {
      // Сбились: ищем следующий подтверждённый кадр
      var probe = offset + 1;
      while (probe < end) {
        if (!reader.ensure(probe, 4)) break;
        if (reader.byte(probe) == 0xFF) {
          frame = _confirmedFrameAt(reader, probe);
          if (frame != null) break;
        }
        probe++;
      }
      if (frame == null) break;
    }
    micros += frame.samples * 1e6 / frame.sampleRate;
    frames++;
    offset = frame.offset + frame.length;
  }

  if (frames < 10) return null;
  return Duration(microseconds: micros.round());
}

/// Чтение файла окнами: в памяти одновременно только окно, а не весь файл.
class _Reader {
  _Reader(this._file) : length = _file.lengthSync();

  final RandomAccessFile _file;
  final int length;

  static const _windowSize = 256 * 1024;
  Uint8List _window = Uint8List(0);
  int _windowStart = 0;

  /// Доступны ли [count] байт с [offset]; подгружает окно, если нужно.
  bool ensure(int offset, int count) {
    if (offset < 0 || offset + count > length) return false;
    if (offset >= _windowStart &&
        offset + count <= _windowStart + _window.length) {
      return true;
    }
    _file.setPositionSync(offset);
    _window = _file.readSync(math.max(_windowSize, count));
    _windowStart = offset;
    return offset + count <= _windowStart + _window.length;
  }

  /// Байт на [offset]; перед этим — [ensure].
  int byte(int offset) => _window[offset - _windowStart];

  /// Целое без знака, старший байт первым.
  int uint32(int offset) {
    if (!ensure(offset, 4)) return 0;
    return byte(offset) << 24 |
        byte(offset + 1) << 16 |
        byte(offset + 2) << 8 |
        byte(offset + 3);
  }
}
