// lib/features/importer/data/importer_service.dart
//
// Импорт музыки: YouTube, Spotify и Яндекс Музыка (метаданные → поиск на
// YouTube → скачивание), прямые ссылки и локальные файлы.
//
// Скачивание с YouTube перебирает клиентов youtube_explode
// (youtube_clients.dart, первым — visionOS). Запасного пути нет: публичные
// Invidious/Piped перестали отдавать данные, и 2026-09-12 этот путь удалён
// (.claude/rules/known-issues.md). Если YouTube не отдал аудио, импорт
// сообщает об ошибке.

import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../library/data/library_database.dart';
import '../../library/data/playlist_database.dart';
import '../../library/data/lyrics_service.dart';
import '../../library/domain/library_track.dart';
import '../../../core/services/app_paths.dart';
import '../../../core/services/youtube_clients.dart';

// ── Модели прогресса ──────────────────────────────────────────────────────────

enum ImportStatus {
  idle,
  fetchingMeta,
  downloading,
  fetchingLyrics,
  done,
  error
}

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

// ── ImporterService ───────────────────────────────────────────────────────────

class ImporterService {
  ImporterService._();
  static final ImporterService instance = ImporterService._();

  final _dio = Dio();

  // Порядок клиентов YouTube и почему именно такой — youtube_clients.dart.
  static final _clientFallbackOrder = kYoutubeClientFallbackOrder;

  // ── Точка входа ───────────────────────────────────────────────────────────

  Future<void> importFromUrl({
    required String url,
    required void Function(ImportProgress) onProgress,
  }) async {
    try {
      if (!url.toLowerCase().startsWith('http://') &&
          !url.toLowerCase().startsWith('https://')) {
        onProgress(const ImportProgress(
          status: ImportStatus.error,
          message: 'Недопустимая схема URL',
          error: 'URL должен начинаться с http:// или https://',
        ));
        return;
      }

      if (_isSpotify(url)) {
        await _importSpotify(url: url, onProgress: onProgress);
      } else if (_isYandexMusic(url)) {
        await _importYandexMusic(url: url, onProgress: onProgress);
      } else if (_isYouTube(url)) {
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
      debugPrint('Ошибка импорта: $e');
      onProgress(const ImportProgress(
        status: ImportStatus.error,
        message: 'Ошибка импорта',
        error: 'Произошла непредвиденная ошибка во время импорта',
      ));
    }
  }

  // ── YouTube ───────────────────────────────────────────────────────────────

  Future<void> _importYouTube({
    required String url,
    required void Function(ImportProgress) onProgress,
  }) async {
    onProgress(const ImportProgress(
      status: ImportStatus.fetchingMeta,
      message: 'Получение метаданных...',
      progress: 0.03,
    ));

    final yt = YoutubeExplode();

    try {
      final video =
          await yt.videos.get(url).timeout(const Duration(seconds: 10));
      final title = _cleanYouTubeTitle(video.title);

      onProgress(ImportProgress(
        status: ImportStatus.fetchingMeta,
        message: 'Найдено: $title',
        progress: 0.10,
      ));

      await _downloadYouTubeVideo(
        yt: yt,
        video: video,
        cleanTitle: title,
        albumName: 'YouTube',
        onProgress: onProgress,
      );

      onProgress(ImportProgress(
        status: ImportStatus.done,
        message: '✓ "$title" добавлен!',
        progress: 1.0,
      ));
    } catch (e) {
      debugPrint('[YT] Импорт не удался: $e');
      onProgress(_extractYouTubeId(url) == null
          ? const ImportProgress(
              status: ImportStatus.error,
              message: 'Не удалось извлечь ID видео из URL',
              error: 'Некорректный YouTube URL',
            )
          : const ImportProgress(
              status: ImportStatus.error,
              message: 'Не удалось скачать трек',
              error: 'YouTube не отдал аудио для этого видео. '
                  'Попробуй ещё раз позже или выбери другой трек.',
            ));
    } finally {
      yt.close();
    }
  }

  // ── Скачивание с YouTube: клиенты по очереди ──────────────────────────────

  Future<String> _downloadYouTubeVideo({
    required YoutubeExplode yt,
    required Video video,
    required String cleanTitle,
    required String albumName,
    required void Function(ImportProgress) onProgress,
    String? artistOverride,
  }) async {
    final id = video.id.value;
    String? savePath;
    Exception? lastError;

    // Перебираем клиентов YouTube
    for (final client in _clientFallbackOrder) {
      debugPrint('[YT] Клиент: ${youtubeClientName(client)}');
      try {
        savePath = await _tryDownloadWithClient(
          yt: yt,
          videoId: id,
          client: client,
          onProgress: (prog, msg) => onProgress(ImportProgress(
            status: ImportStatus.downloading,
            message: msg,
            progress: prog,
          )),
        );
        debugPrint('[YT] Успех: ${youtubeClientName(client)}');
        break;
      } on _DownloadThrottledException catch (e) {
        debugPrint('[YT] Throttled (${youtubeClientName(client)}): $e');
        lastError = e;
      } on _NoStreamsException catch (e) {
        debugPrint('[YT] No streams (${youtubeClientName(client)}): $e');
        lastError = e;
      } catch (e) {
        debugPrint('[YT] Ошибка (${youtubeClientName(client)}): $e');
        lastError = Exception('Ошибка клиента ${youtubeClientName(client)}');
      }
    }

    if (savePath == null) {
      throw lastError ?? Exception('Не удалось загрузить аудио');
    }

    onProgress(const ImportProgress(
      status: ImportStatus.downloading,
      message: 'Сохранение в библиотеку...',
      progress: 0.92,
    ));

    final coverPath = await _downloadCover(video.thumbnails.highResUrl, id);

    await LibraryDatabase.instance.insertTrack(LibraryTrack(
      id: id,
      title: cleanTitle,
      artist: artistOverride ?? video.author,
      album: albumName,
      filePath: savePath,
      coverPath: coverPath,
      durationMs: video.duration?.inMilliseconds ?? 0,
      source: 'youtube',
      addedAt: DateTime.now(),
    ));

    return id;
  }

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
      ..sort((a, b) =>
          b.bitrate.kiloBitsPerSecond.compareTo(a.bitrate.kiloBitsPerSecond));

    if (audioStreams.isEmpty) {
      throw _NoStreamsException('${youtubeClientName(client)}: нет аудио-потоков');
    }

    final streamInfo = audioStreams.first;
    final ext = streamInfo.container.name;
    final savePath = await _getTrackPath('$videoId.$ext');
    final totalBytes = streamInfo.size.totalBytes;

    debugPrint('[YT] Поток: ${streamInfo.bitrate}, '
        'размер: ${(totalBytes / 1024 / 1024).toStringAsFixed(1)} MB');

    // Качаем во временный файл со своим именем и переименовываем только
    // целиком скачанный: сорванная попытка не портит готовый трек, а два
    // импорта одного видео не пишут в один файл. На Windows открытый файл
    // удалить нельзя, поэтому sink закрывается до удаления.
    final partFile =
        File('$savePath.${DateTime.now().microsecondsSinceEpoch}.part');
    final sink = partFile.openWrite();
    var saved = false;

    try {
      final audioStream = yt.videos.streamsClient.get(streamInfo);
      int downloaded = 0;
      int lastLogPercent = -1;

      const stallTimeout = Duration(seconds: 15);
      await for (final chunk in audioStream.timeout(
        stallTimeout,
        onTimeout: (events) => events.close(),
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

      if (downloaded < totalBytes * 0.95) {
        throw _DownloadThrottledException(
            'Поток оборвался: $downloaded / $totalBytes байт');
      }

      await sink.flush();
      await sink.close();
      final target = File(savePath);
      if (await target.exists()) await target.delete();
      await partFile.rename(savePath);
      saved = true;
      return savePath;
    } on _DownloadThrottledException {
      rethrow;
    } catch (e) {
      if (e is TimeoutException ||
          e.toString().contains('TimeoutException') ||
          e.toString().contains('timeout')) {
        throw _DownloadThrottledException('Таймаут потока: $e');
      }
      rethrow;
    } finally {
      if (!saved) {
        try {
          await sink.close();
        } catch (_) {
          // Ошибка записи уже случилась — закрывать больше нечего.
        }
        try {
          if (await partFile.exists()) await partFile.delete();
        } catch (e) {
          debugPrint('[YT] Не удалось удалить ${partFile.path}: $e');
        }
      }
    }
  }

  /// Ищет трек на YouTube (для Spotify и Яндекс Музыки). Из первых десяти
  /// результатов берёт «- Topic», VEVO или «(Official Audio)», иначе — первый.
  Future<Video> _searchYouTube(
    YoutubeExplode yt,
    String query,
    Duration timeout,
  ) async {
    final results = await yt.search.search(query).timeout(timeout);
    if (results.isEmpty) throw Exception('Не найдено на YouTube: $query');
    for (final v in results.take(10)) {
      final author = v.author.toLowerCase();
      if (author.contains('topic') ||
          author.contains('vevo') ||
          v.title.toLowerCase().contains('(official audio)')) {
        return v;
      }
    }
    return results.first;
  }

  // ── Spotify ───────────────────────────────────────────────────────────────

  Future<void> _importSpotify({
    required String url,
    required void Function(ImportProgress) onProgress,
  }) async {
    onProgress(const ImportProgress(
      status: ImportStatus.fetchingMeta,
      message: 'Получение данных со Spotify...',
      progress: 0.10,
    ));

    try {
      final response = await _dio.get(
        url,
        options: Options(headers: {
          'User-Agent': 'curl/7.81.0',
          'Accept': '*/*',
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Ошибка загрузки страницы Spotify');
      }

      final html = response.data.toString();
      final titleMatch = RegExp(r'<meta property="og:title" content="([^"]+)"')
          .firstMatch(html);
      final descMatch = RegExp(r'<meta name="description" content="([^"]+)"')
          .firstMatch(html);

      if (titleMatch == null || descMatch == null) {
        throw Exception('Не удалось извлечь метаданные Spotify');
      }

      final pageTitle = titleMatch.group(1)!;
      final pageDesc = descMatch.group(1)!;
      String trackTitle = pageTitle;
      String artist = 'Unknown Artist';

      if (pageDesc.contains('Song ·')) {
        final parts = pageDesc.split('·');
        if (parts.length >= 2) artist = parts[1].trim();
      } else if (pageDesc.contains('Playlist ·') ||
          pageDesc.contains('Album ·')) {
        throw Exception(
            'Поддерживается только импорт одиночных треков Spotify');
      }

      final query = '$artist - $trackTitle';

      onProgress(ImportProgress(
        status: ImportStatus.fetchingMeta,
        message: 'Поиск: $query',
        progress: 0.30,
      ));

      final yt = YoutubeExplode();
      try {
        final video =
            await _searchYouTube(yt, query, const Duration(seconds: 8));
        await _downloadYouTubeVideo(
          yt: yt,
          video: video,
          cleanTitle: trackTitle,
          albumName: 'Spotify Import',
          artistOverride: artist,
          onProgress: (p) => onProgress(ImportProgress(
            status: p.status,
            message: p.message,
            progress: 0.30 + p.progress * 0.70,
          )),
        );
      } finally {
        yt.close();
      }

      // Без этого шторка импорта не узнаёт об успехе: медиатека и очередь
      // обновляются только по статусу done (importer_sheet.dart).
      onProgress(ImportProgress(
        status: ImportStatus.done,
        message: '✓ "$trackTitle" добавлен!',
        progress: 1.0,
      ));
    } catch (e) {
      debugPrint('Ошибка импорта Spotify: $e');
      onProgress(const ImportProgress(
        status: ImportStatus.error,
        message: 'Ошибка импорта Spotify',
        error: 'Проверь ссылку или попробуй ещё раз позже.',
      ));
    }
  }

  // ── Yandex Music ──────────────────────────────────────────────────────────

  Future<void> _importYandexMusic({
    required String url,
    required void Function(ImportProgress) onProgress,
  }) async {
    onProgress(const ImportProgress(
      status: ImportStatus.fetchingMeta,
      message: 'Получение данных с Яндекс.Музыки...',
      progress: 0.05,
    ));

    try {
      final uri = Uri.parse(url);
      List<dynamic> tracksJson = [];
      String playlistName = 'Yandex Playlist';

      final headers = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
        'Accept': 'application/json, text/plain, */*',
      };

      if (url.contains('/album/')) {
        final pathSegments = uri.pathSegments;
        final albumIndex = pathSegments.indexOf('album');
        if (albumIndex != -1 && albumIndex + 1 < pathSegments.length) {
          final albumId = pathSegments[albumIndex + 1];
          final response = await _dio.get(
            'https://music.yandex.ru/handlers/album.jsx?album=$albumId',
            options: Options(headers: headers),
          );
          if (response.statusCode == 200) {
            final data = response.data;
            playlistName = data['title'] ?? 'Yandex Album';
            if (data['volumes'] != null) {
              for (var volume in data['volumes']) tracksJson.addAll(volume);
            }
          } else {
            throw Exception('Ошибка альбома (${response.statusCode})');
          }
        }
      } else if (url.contains('/playlists/')) {
        final pathSegments = uri.pathSegments;
        final usersIndex = pathSegments.indexOf('users');
        final playlistsIndex = pathSegments.indexOf('playlists');
        if (usersIndex != -1 && playlistsIndex != -1) {
          final owner = pathSegments[usersIndex + 1];
          final kind = pathSegments[playlistsIndex + 1];
          final response = await _dio.get(
            'https://music.yandex.ru/handlers/playlist.jsx?owner=$owner&kinds=$kind',
            options: Options(headers: headers),
          );
          if (response.statusCode == 200) {
            final playlist = response.data['playlist'];
            if (playlist != null) {
              playlistName = playlist['title'] ?? 'Yandex Playlist';
              tracksJson = playlist['tracks'] ?? [];
            } else {
              throw Exception('Плейлист не найден');
            }
          } else {
            throw Exception('Ошибка плейлиста (${response.statusCode})');
          }
        }
      }

      if (tracksJson.isEmpty) throw Exception('В плейлисте нет треков');

      await Future.microtask(() {});

      final parsedTracks = <Map<String, String>>[];
      for (var track in tracksJson) {
        if (track['available'] == false) continue;
        final title = track['title']?.toString() ?? 'Unknown Title';
        final artistsList = track['artists'] as List?;
        final artist = (artistsList != null && artistsList.isNotEmpty)
            ? artistsList.map((a) => a['name']).join(', ')
            : 'Unknown Artist';
        parsedTracks.add({'title': title, 'artist': artist});
      }

      if (parsedTracks.isEmpty) {
        throw Exception('Нет доступных треков');
      }

      onProgress(ImportProgress(
        status: ImportStatus.done,
        message: 'Создание плейлиста "$playlistName"...',
        progress: 0.05,
      ));
      final playlist =
          await PlaylistDatabase.instance.createPlaylist(playlistName);

      final yt = YoutubeExplode();
      final downloadedIds = <String>[];
      int i = 0;

      try {
        for (final track in parsedTracks) {
          i++;
          final query = "${track['artist']} - ${track['title']}";
          final progressBase = (i - 1) / parsedTracks.length;
          final progressStep = 1 / parsedTracks.length;

          onProgress(ImportProgress(
            status: ImportStatus.fetchingMeta,
            message: 'Поиск: $query ($i из ${parsedTracks.length})',
            progress: progressBase,
          ));

          try {
            final video =
                await _searchYouTube(yt, query, const Duration(seconds: 6));
            final trackId = await _downloadYouTubeVideo(
              yt: yt,
              video: video,
              cleanTitle: track['title'] ?? video.title,
              albumName: playlistName,
              artistOverride: track['artist'],
              onProgress: (p) => onProgress(ImportProgress(
                status: p.status,
                message: '$i/${parsedTracks.length}: ${p.message}',
                progress: progressBase + progressStep * p.progress,
              )),
            );

            downloadedIds.add(trackId);
            await PlaylistDatabase.instance.addTrackToPlaylist(
              playlistId: playlist.id,
              trackId: trackId,
            );
          } catch (e) {
            debugPrint('[Yandex] Пропуск "$query": $e');
          }
        }
      } finally {
        yt.close();
      }

      onProgress(ImportProgress(
        status: ImportStatus.done,
        message: '✓ Импортировано ${downloadedIds.length} из '
            '${parsedTracks.length} треков ("$playlistName")',
        progress: 1.0,
      ));
    } catch (e) {
      debugPrint('Ошибка Яндекс.Музыки: $e');
      onProgress(const ImportProgress(
        status: ImportStatus.error,
        message: 'Ошибка импорта Яндекс.Музыки',
        error: 'Проверь ссылку или попробуй ещё раз позже.',
      ));
    }
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
      progress: 0.10,
    ));

    await _dio.download(
      url,
      savePath,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          final pct = (received / total * 100).round();
          final mb = (received / 1024 / 1024).toStringAsFixed(1);
          final totalMb = (total / 1024 / 1024).toStringAsFixed(1);
          onProgress(ImportProgress(
            status: ImportStatus.downloading,
            message: '⬇ $mb / $totalMb MB ($pct%)',
            progress: 0.10 + (received / total) * 0.75,
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

  // ── Локальные файлы ───────────────────────────────────────────────────────

  Future<void> importLocalFiles({
    required List<String> paths,
    required void Function(ImportProgress) onProgress,
  }) async {
    int i = 0;
    final imported = <String>[];

    for (final path in paths) {
      i++;
      final file = File(path);
      if (!await file.exists()) continue;

      final fileName = p.basename(path);
      final title = p.basenameWithoutExtension(path);
      final id = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

      onProgress(ImportProgress(
        status: ImportStatus.downloading,
        message: 'Копирование: $title ($i из ${paths.length})',
        progress: i / paths.length,
      ));

      try {
        final savePath = await _getTrackPath(fileName);
        if (file.path != savePath) await file.copy(savePath);

        String? lrcPath;
        final srcLrc = File(path.replaceAll(p.extension(path), '.lrc'));
        if (await srcLrc.exists()) {
          final content = await srcLrc.readAsString();
          lrcPath = await LyricsService.instance.saveLrc(content, id);
        }

        await LibraryDatabase.instance.insertTrack(LibraryTrack(
          id: id,
          title: title,
          artist: 'Unknown Artist',
          album: 'Local Import',
          filePath: savePath,
          lrcPath: lrcPath,
          durationMs: 0,
          source: 'local',
          addedAt: DateTime.now(),
        ));

        imported.add(id);
      } catch (e) {
        debugPrint('Ошибка локального импорта $fileName: $e');
      }
    }

    onProgress(ImportProgress(
      status: ImportStatus.done,
      message: '✓ Импортировано ${imported.length} локальных файлов',
      progress: 1.0,
    ));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool _isYouTube(String url) =>
      url.contains('youtube.com') || url.contains('youtu.be');
  bool _isSoundCloud(String url) => url.contains('soundcloud.com');
  bool _isSpotify(String url) => url.contains('open.spotify.com');
  bool _isYandexMusic(String url) =>
      url.contains('music.yandex.ru') &&
      (url.contains('/playlists/') || url.contains('/album/'));
  bool _isDirectAudio(String url) =>
      url.endsWith('.mp3') ||
      url.endsWith('.flac') ||
      url.endsWith('.m4a') ||
      url.endsWith('.ogg') ||
      url.endsWith('.wav');

  /// Извлекает YouTube video ID из URL любого формата.
  String? _extractYouTubeId(String url) {
    try {
      final uri = Uri.parse(url);
      // youtube.com/watch?v=ID
      final v = uri.queryParameters['v'];
      if (v != null && v.length == 11) return v;
      // youtu.be/ID или youtube.com/shorts/ID
      if (uri.pathSegments.isNotEmpty) {
        final seg = uri.pathSegments.last;
        if (seg.length == 11 && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(seg)) {
          return seg;
        }
      }
    } catch (_) {}
    return null;
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

  Future<String> _getTrackPath(String fileName) async {
    final safeFileName =
        p.basename(fileName).replaceAll(RegExp(r'[^a-zA-Z0-9\.\-\_]'), '_');
    final music = Directory(AppPaths.musicDir);
    await music.create(recursive: true);
    return p.join(music.path, safeFileName);
  }

  Future<String?> _downloadCover(String url, String trackId) async {
    try {
      final safeId =
          p.basename(trackId).replaceAll(RegExp(r'[^a-zA-Z0-9\.\-\_]'), '_');
      final coversDir = Directory(AppPaths.coversDir);
      await coversDir.create(recursive: true);
      final path = p.join(coversDir.path, '$safeId.jpg');
      await _dio.download(url, path);
      return path;
    } catch (e) {
      debugPrint('Ошибка загрузки обложки: $e');
      return null;
    }
  }
}

// ── Служебные исключения ──────────────────────────────────────────────────────

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
