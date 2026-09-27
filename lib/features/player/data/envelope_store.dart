// lib/features/player/data/envelope_store.dart
//
// Огибающая громкости трека считается один раз и лежит рядом с обложками:
// `<dataDir>/waveforms/<trackId>.env2` (`AppPaths.waveformsDir`), по точке на
// каждые 20 мс трека — около 9 КБ на трёхминутную песню.
//
// Расширение с номером неспроста: у первой версии точек было 400 на весь трек
// (полсекунды на точку), и такой файл прочитался бы как новый, только грубый.
// Меняется шаг — поднять номер, старые файлы тогда просто пересчитаются.
//
// Читают её волна под прогрессом и визуализатор. Сам разбор файла — в
// `player/domain/audio_envelope.dart`, он без декодирования звука.

import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../core/services/app_paths.dart';
import '../domain/audio_envelope.dart';

class EnvelopeStore {
  EnvelopeStore._();
  static final EnvelopeStore instance = EnvelopeStore._();

  /// Уже посчитанные огибающие этой сессии: у визуализатора и у волны трек
  /// один и тот же, читать файл дважды незачем.
  final _cache = <String, AudioEnvelope?>{};

  /// Треки, которые сейчас считаются: не запускаем разбор второй раз.
  final _inFlight = <String, Future<AudioEnvelope?>>{};

  File _fileFor(String trackId) {
    final safe = p.basename(trackId).replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return File(p.join(AppPaths.waveformsDir, '$safe.env2'));
  }

  /// Готовая огибающая, если её уже считали в этой сессии.
  AudioEnvelope? cached(String trackId) => _cache[trackId];

  /// Огибающая трека: из памяти, с диска или из файла трека.
  /// null — формат не разобрали (тогда волна рисуется как раньше).
  Future<AudioEnvelope?> forTrack({
    required String trackId,
    required String? filePath,
    required int durationMs,
  }) {
    if (_cache.containsKey(trackId)) return Future.value(_cache[trackId]);
    final running = _inFlight[trackId];
    if (running != null) return running;

    final future = _load(trackId, filePath, durationMs);
    _inFlight[trackId] = future;
    return future.whenComplete(() => _inFlight.remove(trackId));
  }

  Future<AudioEnvelope?> _load(
      String trackId, String? filePath, int durationMs) async {
    final file = _fileFor(trackId);
    try {
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          final envelope =
              AudioEnvelope(points: bytes, durationMs: durationMs);
          _cache[trackId] = envelope;
          return envelope;
        }
      }
    } catch (e) {
      debugPrint('[Envelope] не прочитал $trackId: $e');
    }

    if (filePath == null || filePath.isEmpty) {
      _cache[trackId] = null;
      return null;
    }
    // Сетевой трек без локального файла разбирать нечего
    if (filePath.startsWith('http://') || filePath.startsWith('https://')) {
      _cache[trackId] = null;
      return null;
    }

    AudioEnvelope? envelope;
    try {
      // Чтение файла на несколько мегабайт и разбор — в отдельном изоляте,
      // чтобы не задеть кадр (`performance.md`, правило 2)
      final points = await Isolate.run(() => _computePoints(filePath));
      if (points != null && points.isNotEmpty) {
        envelope = AudioEnvelope(points: points, durationMs: durationMs);
      }
    } catch (e) {
      debugPrint('[Envelope] не посчитал $trackId: $e');
    }

    _cache[trackId] = envelope;
    if (envelope != null) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(envelope.points, flush: false);
      } catch (e) {
        debugPrint('[Envelope] не сохранил $trackId: $e');
      }
    }
    return envelope;
  }

  /// Стереть посчитанное для трека: файл заменили или трек удалили.
  Future<void> forget(String trackId) async {
    _cache.remove(trackId);
    try {
      final file = _fileFor(trackId);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

/// Считается в отдельном изоляте, поэтому верхнего уровня и без состояния.
Future<Uint8List?> _computePoints(String filePath) async {
  final envelope = await computeEnvelope(File(filePath));
  return envelope?.points;
}
