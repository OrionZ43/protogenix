// lib/features/player/data/spectrum_store.dart
//
// Спектр трека считается один раз и лежит рядом с обложками:
// `<dataDir>/waveforms/<trackId>.spec` (`AppPaths.waveformsDir`).
// У трёхминутного трека это ~72 КБ: 16 полос по 25 кадров в секунду.
//
// Считать дорого (декодирование плюс FFT), поэтому:
//   • всё происходит в отдельном изоляте — кадр UI не страдает
//     (`performance.md`, правило 2);
//   • один трек за раз, повторный запрос того же трека ждёт тот же расчёт;
//   • в памяти держим только последние несколько треков.
//
// Декодирование — `pcm_decoder.dart`, математика — `domain/spectrogram.dart`.

import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../core/services/app_paths.dart';
import '../domain/spectrogram.dart';
import 'pcm_decoder.dart';

/// Сколько спектров держим в памяти: 16 полос × 25 кадров/с — это ~24 КБ
/// на минуту трека, так что шесть треков заметными не будут.
const _kMemoryLimit = 6;

/// Сколько спектров держим на диске: 80 файлов — это около 6 МБ.
const _kFileLimit = 80;

class SpectrumStore {
  SpectrumStore._();
  static final SpectrumStore instance = SpectrumStore._();

  final _cache = <String, Spectrogram?>{};
  final _inFlight = <String, Future<Spectrogram?>>{};

  File _fileFor(String trackId) {
    final safe =
        p.basename(trackId).replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return File(p.join(AppPaths.waveformsDir, '$safe.spec'));
  }

  /// Готовый спектр, если он уже в памяти. Визуализатор рисует по нему каждый
  /// кадр, поэтому в painter должен приходить именно готовый объект.
  Spectrogram? cached(String trackId) => _cache[trackId];

  /// Спектр трека: из памяти, с диска или посчитанный заново.
  /// null — на этой платформе нечем декодировать или файл не разобрался.
  Future<Spectrogram?> forTrack({
    required String trackId,
    required String? filePath,
  }) {
    if (_cache.containsKey(trackId)) return Future.value(_cache[trackId]);
    final running = _inFlight[trackId];
    if (running != null) return running;

    final future = _load(trackId, filePath);
    _inFlight[trackId] = future;
    return future.whenComplete(() => _inFlight.remove(trackId));
  }

  void _remember(String trackId, Spectrogram? spectrum) {
    _cache[trackId] = spectrum;
    while (_cache.length > _kMemoryLimit) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<Spectrogram?> _load(String trackId, String? filePath) async {
    final file = _fileFor(trackId);
    try {
      if (await file.exists()) {
        final spectrum = unpackSpectrogram(await file.readAsBytes());
        if (spectrum != null) {
          _remember(trackId, spectrum);
          return spectrum;
        }
        // Файл от прошлой версии формата — посчитаем заново
        await file.delete();
      }
    } catch (e) {
      debugPrint('[Spectrum] не прочитал $trackId: $e');
    }

    // Сетевой трек без своего файла декодировать нечего
    if (filePath == null ||
        filePath.isEmpty ||
        filePath.startsWith('http://') ||
        filePath.startsWith('https://')) {
      _remember(trackId, null);
      return null;
    }
    if (!pcmDecodingSupported) {
      _remember(trackId, null);
      return null;
    }

    Uint8List? packed;
    final scratch = AppPaths.waveformsDir;
    try {
      final watch = Stopwatch()..start();
      packed = await Isolate.run(() => _computePacked(filePath, scratch));
      debugPrint('[Spectrum] $trackId: ${packed == null ? 'не вышло' : '${packed.length} Б'} '
          'за ${watch.elapsedMilliseconds} мс');
    } catch (e) {
      debugPrint('[Spectrum] не посчитал $trackId: $e');
    }

    final spectrum = packed == null ? null : unpackSpectrogram(packed);
    _remember(trackId, spectrum);
    if (packed != null) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(packed, flush: false);
        await _prune(file.parent);
      } catch (e) {
        debugPrint('[Spectrum] не сохранил $trackId: $e');
      }
    }
    return spectrum;
  }

  /// Спектр весит около 80 КБ, а медиатека бывает на сотни треков — на
  /// телефоне это выросло бы в десятки мегабайт незаметно для пользователя.
  /// Держим только последние [_kFileLimit], остальные удаляем по дате: их
  /// пересчитают за секунду, если трек снова заиграет.
  Future<void> _prune(Directory dir) async {
    try {
      final files = await dir
          .list()
          .where((e) => e is File && e.path.endsWith('.spec'))
          .cast<File>()
          .toList();
      if (files.length <= _kFileLimit) return;

      final dated = <(File, DateTime)>[];
      for (final file in files) {
        dated.add((file, (await file.stat()).modified));
      }
      dated.sort((a, b) => a.$2.compareTo(b.$2));
      for (final entry in dated.take(dated.length - _kFileLimit)) {
        await entry.$1.delete();
      }
      debugPrint('[Spectrum] убрал ${dated.length - _kFileLimit} старых файлов');
    } catch (e) {
      debugPrint('[Spectrum] не почистил папку: $e');
    }
  }

  /// Стереть посчитанное: файл трека заменили или трек удалили.
  Future<void> forget(String trackId) async {
    _cache.remove(trackId);
    try {
      final file = _fileFor(trackId);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

/// Считается в отдельном изоляте, поэтому верхнего уровня и без состояния.
///
/// Звук идёт в спектр кусками по мере чтения: трек целиком в памяти не
/// лежит ни разу (`pcm_decoder.dart`, `SpectrumAnalyzer`).
Uint8List? _computePacked(String filePath, String scratchDir) {
  SpectrumAnalyzer? analyzer;
  final decoded = decodePcm(
    filePath,
    (samples, sampleRate) =>
        (analyzer ??= SpectrumAnalyzer(sampleRate: sampleRate)).add(samples),
    scratchDir: scratchDir,
  );
  if (!decoded || analyzer == null) return null;
  final spectrum = analyzer!.finish();
  if (spectrum.isEmpty) return null;
  return packSpectrogram(spectrum);
}

// ─── Формат файла ──────────────────────────────────────────────────────────
//
// «PGS1», число полос, шаг кадра в сотых миллисекунды, число кадров, значения.
// Версия в заголовке нужна, чтобы файлы от прошлого формата не читались как
// свои: поменяется число полос или частота — старые просто пересчитаются.

const _magic = [0x50, 0x47, 0x53, 0x31]; // PGS1
const _headerSize = 4 + 1 + 2 + 4;

Uint8List packSpectrogram(Spectrogram spectrum) {
  final out = Uint8List(_headerSize + spectrum.values.length);
  out.setRange(0, 4, _magic);
  final view = ByteData.sublistView(out);
  view.setUint8(4, spectrum.bands);
  view.setUint16(5, (spectrum.frameMs * 100).round(), Endian.little);
  view.setUint32(7, spectrum.frames, Endian.little);
  out.setRange(_headerSize, out.length, spectrum.values);
  return out;
}

Spectrogram? unpackSpectrogram(Uint8List bytes) {
  if (bytes.length <= _headerSize) return null;
  for (var i = 0; i < 4; i++) {
    if (bytes[i] != _magic[i]) return null;
  }
  final view = ByteData.sublistView(bytes);
  final bands = view.getUint8(4);
  final frameMs = view.getUint16(5, Endian.little) / 100;
  final frames = view.getUint32(7, Endian.little);
  if (bands <= 0 || frameMs <= 0 || frames <= 0) return null;
  if (bytes.length - _headerSize != bands * frames) return null;
  return Spectrogram(
    values: Uint8List.sublistView(bytes, _headerSize),
    bands: bands,
    frameMs: frameMs,
  );
}
