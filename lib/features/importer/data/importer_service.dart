import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../library/data/library_database.dart';
import '../../library/data/lyrics_service.dart';
import '../../library/domain/library_track.dart';

enum ImportStatus { idle, fetchingMeta, downloading, fetchingLyrics, done, error }

class ImportProgress {
  final ImportStatus status;
  final String message;
  final double progress;
  final String? error;

  const ImportProgress({
    required this.status,
    required this.message,
    this.progress = 0.0,
    this.error,
  });

  static const idle = ImportProgress(status: ImportStatus.idle, message: '');
}

class ImporterService {
  ImporterService._();
  static final ImporterService instance = ImporterService._();

  final _dio = Dio();

  // Порядок клиентов: от наиболее стабильных к запасным.
  // androidVr и ios дают незащищённые (non-throttled) потоки чаще всего.
  static final _clientFallbackOrder = [
    YoutubeApiClient.androidVr,
    YoutubeApiClient.ios,
    YoutubeApiClient.android,
    YoutubeApiClient.mweb,
  ];

  Future<void> importFromUrl({
    required String url,
    required void Function(ImportProgress) onProgress,
  }) async {
    try {
      if (_isYouTube(url)) {
        await _importYouTube(url: url, onProgress: onProgress);
      } else if (_isSoundCloud(url)) {
        await _importSoundCloud(url: url, onProgress: onProgress);
      } else if (_isDirectAudio(url)) {
        await _importDirectUrl(url: url, onProgress: onProgress);
      } else {
        onProgress(const ImportProgress(
          status: ImportStatus.error,
          message: 'Неизвестный формат ссылки',
          error: 'Поддерживаются: YouTube, прямые ссылки на MP3/FLAC',
        ));
      }
    } catch (e) {
      onProgress(ImportProgress(
        status: ImportStatus.error,
        message: 'Ошибка импорта',
        error: e.toString(),
      ));
    }
  }

  // ── YouTube ──────────────────────────────────────────────────────────────

  Future<void> _importYouTube({
    required String url,
    required void Function(ImportProgress) onProgress,
  }) async {
    onProgress(const ImportProgress(
      status: ImportStatus.fetchingMeta,
      message: 'Получение метаданных...',
      progress: 0.03,
    ));

    // Создаём ОДИН экземпляр на всю операцию. URL и скачивание — один клиент.
    final yt = YoutubeExplode();

    try {
      final video = await yt.videos.get(url);
      final id = video.id.value;
      final title = _cleanYouTubeTitle(video.title);

      onProgress(ImportProgress(
        status: ImportStatus.fetchingMeta,
        message: 'Найдено: $title',
        progress: 0.1,
      ));

      // Пробуем клиентов по очереди до первого успешного скачивания
      bool downloaded = false;
      String? savePath;
      Exception? lastError;

      for (final client in _clientFallbackOrder) {
        debugPrint('[YT] Пробуем клиент: $client');
        try {
          savePath = await _tryDownloadWithClient(
            yt: yt,
            videoId: id,
            client: client,
            onProgress: (p, msg) => onProgress(ImportProgress(
              status: ImportStatus.downloading,
              message: msg,
              progress: p,
            )),
          );
          downloaded = true;
          debugPrint('[YT] Успех с клиентом: $client');
          break;
        } on _DownloadThrottledException catch (e) {
          debugPrint('[YT] Клиент $client завис (throttled): $e');
          lastError = e;
          // Продолжаем к следующему клиенту
        } on _NoStreamsException catch (e) {
          debugPrint('[YT] Клиент $client не вернул потоки: $e');
          lastError = e;
          // Продолжаем к следующему клиенту
        } catch (e) {
          debugPrint('[YT] Клиент $client — ошибка: $e');
          lastError = Exception(e.toString());
          // При неизвестной ошибке тоже пробуем дальше
        }
      }

      if (!downloaded || savePath == null) {
        throw lastError ?? Exception('Все клиенты YouTube исчерпаны');
      }

      onProgress(const ImportProgress(
        status: ImportStatus.downloading,
        message: 'Сохранение в библиотеку...',
        progress: 0.92,
      ));

      final coverPath = await _downloadCover(video.thumbnails.highResUrl, id);

      await LibraryDatabase.instance.insertTrack(LibraryTrack(
        id: id,
        title: title,
        artist: video.author,
        album: 'YouTube',
        filePath: savePath,
        coverPath: coverPath,
        durationMs: video.duration?.inMilliseconds ?? 0,
        source: 'youtube',
        addedAt: DateTime.now(),
      ));

      onProgress(ImportProgress(
        status: ImportStatus.done,
        message: '✓ "$title" добавлен!',
        progress: 1.0,
      ));
    } finally {
      // Всегда закрываем — освобождает HTTP-сессию и предотвращает утечки
      yt.close();
    }
  }

  /// Пытается скачать с конкретным клиентом.
  /// Бросает [_DownloadThrottledException] если поток завис.
  /// Бросает [_NoStreamsException] если клиент не дал аудио-потоков.
  Future<String> _tryDownloadWithClient({
    required YoutubeExplode yt,
    required String videoId,
    required YoutubeApiClient client,
    required void Function(double progress, String message) onProgress,
  }) async {
    final manifest = await yt.videos.streamsClient.getManifest(
      videoId,
      ytClients: [client],
    );

    final audioStreams = manifest.audioOnly.toList()
      ..sort((a, b) => b.bitrate.kiloBitsPerSecond.compareTo(
          a.bitrate.kiloBitsPerSecond));

    if (audioStreams.isEmpty) {
      throw _NoStreamsException('Клиент $client не вернул аудио-потоков');
    }

    final streamInfo = audioStreams.first;
    final ext = streamInfo.container.name; // обычно 'mp4' или 'webm'
    final savePath = await _getTrackPath('$videoId.$ext');
    final totalBytes = streamInfo.size.totalBytes;

    debugPrint('[YT] Поток: ${streamInfo.bitrate}, размер: ${(totalBytes / 1024 / 1024).toStringAsFixed(1)} MB');

    final file = File(savePath);
    if (await file.exists()) await file.delete();
    final sink = file.openWrite();

    try {
      // Используем pipe() через внутренний http-клиент библиотеки.
      // Это единственный способ не получить 403 — URL подписан под этот же экземпляр yt.
      final audioStream = yt.videos.streamsClient.get(streamInfo);

      int downloaded = 0;
      int lastLogPercent = -1;

      // Таймаут-детектор: если за N секунд не пришло ни байта — считаем throttled
      const stallTimeout = Duration(seconds: 15);
      await for (final chunk in audioStream.timeout(
        stallTimeout,
        onTimeout: (sink) {
          // Закрываем стрим-контроллер, что бросит TimeoutException наверх
          sink.close();
        },
      )) {
        sink.add(chunk);
        downloaded += chunk.length;
        final percent = (downloaded / totalBytes * 100).round();
        if (percent != lastLogPercent) {
          lastLogPercent = percent;
          final mb = (downloaded / 1024 / 1024).toStringAsFixed(1);
          final totalMb = (totalBytes / 1024 / 1024).toStringAsFixed(1);
          onProgress(
            0.15 + (downloaded / totalBytes) * 0.75,
            'Загрузка: $percent% ($mb / $totalMb MB)',
          );
        }
      }

      // Проверяем: скачали хотя бы 95% (мелкие погрешности totalBytes допустимы)
      if (downloaded < totalBytes * 0.95) {
        throw _DownloadThrottledException(
          'Поток оборвался: $downloaded / $totalBytes байт',
        );
      }

      return savePath;
    } on _DownloadThrottledException {
      // Удаляем неполный файл перед следующей попыткой
      if (await file.exists()) await file.delete();
      rethrow;
    } catch (e) {
      if (await file.exists()) await file.delete();
      // Таймаут стрима — это наш throttle-сигнал
      if (e.toString().contains('TimeoutException') ||
          e.toString().contains('timeout')) {
        throw _DownloadThrottledException('Таймаут потока: $e');
      }
      rethrow;
    } finally {
      await sink.flush();
      await sink.close();
    }
  }

  String _cleanYouTubeTitle(String title) {
    return title
        .replaceAll(RegExp(r'\(Official.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'\(Lyrics.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(Audio.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(HD.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  // ── Прямая ссылка ─────────────────────────────────────────────────────────

  Future<void> _importDirectUrl({
    required String url,
    required void Function(ImportProgress) onProgress,
  }) async {
    onProgress(const ImportProgress(
      status: ImportStatus.fetchingMeta,
      message: 'Определяем файл...',
    ));

    final fileName = url.split('/').last.split('?').first;
    final id = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final savePath = await _getTrackPath(fileName);

    onProgress(const ImportProgress(
      status: ImportStatus.downloading,
      message: 'Скачиваем файл...',
      progress: 0.1,
    ));

    await _dio.download(
      url,
      savePath,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          final receivedMB = (received / 1024 / 1024).toStringAsFixed(1);
          final totalMB = (total / 1024 / 1024).toStringAsFixed(1);
          final percent = (received / total * 100).round();
          onProgress(ImportProgress(
            status: ImportStatus.downloading,
            message: '⬇ $receivedMB / $totalMB MB ($percent%)',
            progress: 0.1 + (received / total) * 0.75,
          ));
        }
      },
    );

    final title = p.basenameWithoutExtension(fileName);

    onProgress(const ImportProgress(
      status: ImportStatus.fetchingLyrics,
      message: 'Ищем текст песни...',
      progress: 0.88,
    ));

    final lrcContent = await LyricsService.instance.getLrc(
      filePath: savePath,
      title: title,
      artist: 'Unknown',
    );

    String? lrcPath;
    if (lrcContent != null) {
      lrcPath = await LyricsService.instance.saveLrc(lrcContent, id);
    }

    await LibraryDatabase.instance.insertTrack(LibraryTrack(
      id: id,
      title: title,
      artist: 'Unknown Artist',
      album: 'Imported',
      filePath: savePath,
      lrcPath: lrcPath,
      durationMs: 0,
      source: 'direct',
      addedAt: DateTime.now(),
    ));

    onProgress(ImportProgress(
      status: ImportStatus.done,
      message: '✓ "$title" добавлен в библиотеку',
      progress: 1.0,
    ));
  }

  // ── SoundCloud — заглушка ─────────────────────────────────────────────────

  Future<void> _importSoundCloud({
    required String url,
    required void Function(ImportProgress) onProgress,
  }) async {
    onProgress(const ImportProgress(
      status: ImportStatus.error,
      message: 'SoundCloud в следующем обновлении',
      error: 'Используй прямую ссылку на MP3 или YouTube',
    ));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool _isYouTube(String url) =>
      url.contains('youtube.com') || url.contains('youtu.be');

  bool _isSoundCloud(String url) => url.contains('soundcloud.com');

  bool _isDirectAudio(String url) =>
      url.endsWith('.mp3') ||
          url.endsWith('.flac') ||
          url.endsWith('.m4a') ||
          url.endsWith('.ogg') ||
          url.endsWith('.wav');

  Future<String> _getTrackPath(String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final music = Directory(p.join(dir.path, 'music'));
    await music.create(recursive: true);
    return p.join(music.path, fileName);
  }

  Future<String?> _downloadCover(String url, String trackId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final coversDir = Directory(p.join(dir.path, 'covers'));
      await coversDir.create(recursive: true);
      final path = p.join(coversDir.path, '$trackId.jpg');
      await _dio.download(url, path);
      return path;
    } catch (_) {
      return null;
    }
  }
}

// ── Служебные исключения ─────────────────────────────────────────────────────

class _DownloadThrottledException implements Exception {
  final String message;
  _DownloadThrottledException(this.message);
  @override
  String toString() => 'DownloadThrottledException: $message';
}

class _NoStreamsException implements Exception {
  final String message;
  _NoStreamsException(this.message);
  @override
  String toString() => 'NoStreamsException: $message';
}