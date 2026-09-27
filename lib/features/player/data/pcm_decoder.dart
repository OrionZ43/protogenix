// lib/features/player/data/pcm_decoder.dart
//
// Раскодировать звук трека в PCM, чтобы посчитать по нему настоящий спектр
// (`player/domain/spectrogram.dart`).
//
// Своего декодера Opus и AAC у нас нет и писать его незачем: **libmpv уже едет
// в сборке**. На Windows это `libmpv-2.dll` (28 МБ рядом с exe), на Android —
// `libmpv.so` в APK (11,8 МБ на arm64, там он сейчас вообще не используется:
// звук играет ExoPlayer). Оба пришли с `media_kit_libs_video`
// (`dependencies.md`). Мы просто просим у него ещё одну работу.
//
// Как: второй экземпляр mpv со звуковым выходом `pcm` — он не идёт в колонки,
// а пишет WAV в файл. Плюс `untimed`, чтобы не ждать реального времени.
// Замер на машине Orion: трек 148 с раскодировался за 470 мс, то есть
// в 300 раз быстрее воспроизведения.
//
// Всё это вызывается **только из отдельного изолята** (`SpectrumStore`):
// `mpv_wait_event` блокирует свой поток.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Раскодированный звук: моно, значения −1..1.
class PcmAudio {
  const PcmAudio({required this.samples, required this.sampleRate});

  final Float32List samples;
  final int sampleRate;

  int get durationMs =>
      sampleRate <= 0 ? 0 : (samples.length * 1000 / sampleRate).round();
}

/// Для спектра хватает 22050 Гц: выше 11 кГц на картинке всё равно ничего не
/// показываем, а памяти и времени уходит вдвое меньше.
const kDecodeSampleRate = 22050;

/// Дольше этого не ждём: обычный трек укладывается в секунду.
const _timeout = Duration(seconds: 90);

/// Есть ли на этой платформе чем декодировать.
bool get pcmDecodingSupported =>
    Platform.isWindows || Platform.isAndroid || Platform.isLinux;

/// [filePath] в PCM, или null, если не получилось (формат, битый файл,
/// нет libmpv). Исключений не бросает: спектр — украшение, без него
/// визуализатор просто ровно дышит.
///
/// [scratchDir] — куда положить временный WAV. На Android системная temp
/// приложению доступна, но папку лучше задавать явно.
PcmAudio? decodePcm(String filePath, {String? scratchDir}) {
  if (!pcmDecodingSupported) return null;
  if (!File(filePath).existsSync()) return null;

  final mpv = _openMpv();
  if (mpv == null) return null;

  final dir = Directory(scratchDir ?? Directory.systemTemp.path);
  final name = 'pg_pcm_${pid}_${DateTime.now().microsecondsSinceEpoch}.wav';
  final wav = File('${dir.path}${Platform.pathSeparator}$name');

  try {
    dir.createSync(recursive: true);
    return _decodeWith(mpv, filePath, wav);
  } catch (_) {
    return null;
  } finally {
    try {
      if (wav.existsSync()) wav.deleteSync();
    } catch (_) {}
  }
}

PcmAudio? _decodeWith(_Mpv mpv, String filePath, File wav) {
  final handle = mpv.create();
  if (handle == nullptr) return null;

  try {
    // Без картинки и без колонок — только декодировать в файл
    final options = {
      'vo': 'null',
      'video': 'no',
      'ao': 'pcm',
      'ao-pcm-file': wav.path,
      'ao-pcm-waveheader': 'yes',
      'untimed': 'yes',
      'audio-samplerate': '$kDecodeSampleRate',
      'audio-channels': 'mono',
      'audio-format': 's16',
      'terminal': 'no',
      'load-scripts': 'no',
      'config': 'no',
    };
    for (final option in options.entries) {
      mpv.setOption(handle, option.key, option.value);
    }
    if (mpv.initialize(handle) != 0) return null;

    if (mpv.command(handle, ['loadfile', filePath]) != 0) return null;

    final watch = Stopwatch()..start();
    var finished = false;
    while (!finished && watch.elapsed < _timeout) {
      final event = mpv.waitEvent(handle, 0.5);
      if (event == nullptr) break;
      final id = event.ref.eventId;
      if (id == _eventEndFile || id == _eventShutdown) finished = true;
    }
    if (!finished) return null;
  } finally {
    // Закрыть mpv надо до чтения файла: он дописывает размер в заголовок
    mpv.destroy(handle);
  }

  if (!wav.existsSync()) return null;
  return _readWav(wav.readAsBytesSync());
}

/// WAV от mpv в моно −1..1. Заголовок разбираем по чанкам, а не по смещению 44:
/// у mpv формат бывает WAVE_FORMAT_EXTENSIBLE, и тогда `fmt ` длиннее.
PcmAudio? _readWav(Uint8List bytes) {
  if (bytes.length < 44) return null;
  final view = ByteData.sublistView(bytes);
  if (_tag(bytes, 0) != 'RIFF' || _tag(bytes, 8) != 'WAVE') return null;

  var channels = 1;
  var rate = kDecodeSampleRate;
  var bits = 16;
  var dataStart = -1;
  var dataLength = 0;

  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = _tag(bytes, offset);
    final size = view.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (id == 'fmt ' && body + 16 <= bytes.length) {
      channels = view.getUint16(body + 2, Endian.little);
      rate = view.getUint32(body + 4, Endian.little);
      bits = view.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      dataStart = body;
      // mpv дописывает размер в конце; если не успел — берём остаток файла
      dataLength = (size == 0 || body + size > bytes.length)
          ? bytes.length - body
          : size;
      break;
    }
    if (size == 0) break;
    offset = body + size + (size.isOdd ? 1 : 0);
  }

  if (dataStart < 0 || dataLength <= 0) return null;
  if (bits != 16 || channels < 1 || rate <= 0) return null;

  final frames = dataLength ~/ (2 * channels);
  if (frames <= 0) return null;
  final samples = Float32List(frames);
  for (var i = 0; i < frames; i++) {
    var sum = 0;
    final base = dataStart + i * 2 * channels;
    for (var c = 0; c < channels; c++) {
      sum += view.getInt16(base + c * 2, Endian.little);
    }
    samples[i] = sum / channels / 32768.0;
  }
  return PcmAudio(samples: samples, sampleRate: rate);
}

String _tag(Uint8List bytes, int offset) => offset + 4 <= bytes.length
    ? ascii.decode(bytes.sublist(offset, offset + 4), allowInvalid: true)
    : '';

// ─── libmpv через FFI ───────────────────────────────────────────────────────

const _eventShutdown = 1;
const _eventEndFile = 7;

final class _MpvEvent extends Struct {
  @Int32()
  external int eventId;
  @Int32()
  external int error;
  @Uint64()
  external int replyUserdata;
  external Pointer<Void> data;
}

typedef _CreateC = Pointer<Void> Function();
typedef _SetOptionC = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _SetOptionDart = int Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _InitC = Int32 Function(Pointer<Void>);
typedef _InitDart = int Function(Pointer<Void>);
typedef _CommandC = Int32 Function(Pointer<Void>, Pointer<Pointer<Utf8>>);
typedef _CommandDart = int Function(Pointer<Void>, Pointer<Pointer<Utf8>>);
typedef _WaitEventC = Pointer<_MpvEvent> Function(Pointer<Void>, Double);
typedef _WaitEventDart = Pointer<_MpvEvent> Function(Pointer<Void>, double);
typedef _DestroyC = Void Function(Pointer<Void>);
typedef _DestroyDart = void Function(Pointer<Void>);

class _Mpv {
  _Mpv(DynamicLibrary lib)
      : create = lib.lookupFunction<_CreateC, _CreateC>('mpv_create'),
        _setOption = lib.lookupFunction<_SetOptionC, _SetOptionDart>(
            'mpv_set_option_string'),
        initialize = lib.lookupFunction<_InitC, _InitDart>('mpv_initialize'),
        _command = lib.lookupFunction<_CommandC, _CommandDart>('mpv_command'),
        waitEvent =
            lib.lookupFunction<_WaitEventC, _WaitEventDart>('mpv_wait_event'),
        destroy = lib
            .lookupFunction<_DestroyC, _DestroyDart>('mpv_terminate_destroy');

  final Pointer<Void> Function() create;
  final _SetOptionDart _setOption;
  final _InitDart initialize;
  final _CommandDart _command;
  final _WaitEventDart waitEvent;
  final _DestroyDart destroy;

  void setOption(Pointer<Void> handle, String name, String value) {
    final n = name.toNativeUtf8();
    final v = value.toNativeUtf8();
    try {
      _setOption(handle, n, v);
    } finally {
      calloc.free(n);
      calloc.free(v);
    }
  }

  int command(Pointer<Void> handle, List<String> args) {
    final argv = calloc<Pointer<Utf8>>(args.length + 1);
    final allocated = <Pointer<Utf8>>[];
    try {
      for (var i = 0; i < args.length; i++) {
        final arg = args[i].toNativeUtf8();
        allocated.add(arg);
        argv[i] = arg;
      }
      argv[args.length] = nullptr;
      return _command(handle, argv);
    } finally {
      for (final arg in allocated) {
        calloc.free(arg);
      }
      calloc.free(argv);
    }
  }
}

_Mpv? _cachedMpv;
var _mpvTried = false;

/// libmpv уже загружен в процесс (на Windows его держит `just_audio_media_kit`),
/// так что это не вторая копия библиотеки, а тот же модуль.
_Mpv? _openMpv() {
  if (_mpvTried) return _cachedMpv;
  _mpvTried = true;
  for (final name in _libraryNames) {
    try {
      _cachedMpv = _Mpv(DynamicLibrary.open(name));
      return _cachedMpv;
    } catch (_) {
      continue;
    }
  }
  return null;
}

List<String> get _libraryNames {
  if (Platform.isWindows) {
    final dir = File(Platform.resolvedExecutable).parent.path;
    return [
      'libmpv-2.dll',
      '$dir\\libmpv-2.dll',
      'mpv-2.dll',
      'mpv-1.dll',
    ];
  }
  return ['libmpv.so', 'libmpv.so.2', 'libmpv.so.1'];
}
