import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../library/data/library_database.dart';
import '../../library/data/playlist_database.dart';
import '../../library/data/lyrics_service.dart';
import '../../library/domain/library_track.dart';

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
      final title = _cleanYouTubeTitle(video.title);

      onProgress(ImportProgress(
        status: ImportStatus.fetchingMeta,
        message: 'Найдено: $title',
        progress: 0.1,
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
      onProgress(ImportProgress(
        status: ImportStatus.error,
        message: 'Ошибка скачивания YouTube',
        error: e.toString(),
      ));
    } finally {
      // Всегда закрываем — освобождает HTTP-сессию и предотвращает утечки
      yt.close();
    }
  }

  /// Пытается скачать с конкретным клиентом.
  /// Бросает [_DownloadThrottledException] если поток завис.
  /// Бросает [_NoStreamsException] если клиент не дал аудио-потоков.
    Future<String> _downloadYouTubeVideo({
    required YoutubeExplode yt,
    required Video video,
    required String cleanTitle,
    required String albumName,
    required void Function(ImportProgress) onProgress,
    String? artistOverride,
  }) async {
    final id = video.id.value;

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
      } on _NoStreamsException catch (e) {
        debugPrint('[YT] Клиент $client не вернул потоки: $e');
        lastError = e;
      } catch (e) {
        debugPrint('[YT] Клиент $client — ошибка: $e');
        lastError = Exception(e.toString());
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
      throw _NoStreamsException('Клиент $client не вернул аудио-потоков');
    }

    final streamInfo = audioStreams.first;
    final ext = streamInfo.container.name; // обычно 'mp4' или 'webm'
    final savePath = await _getTrackPath('$videoId.$ext');
    final totalBytes = streamInfo.size.totalBytes;

    debugPrint(
        '[YT] Поток: ${streamInfo.bitrate}, размер: ${(totalBytes / 1024 / 1024).toStringAsFixed(1)} MB');

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

  // ── Spotify ───────────────────────────────────────────────────────────────

  Future<void> _importSpotify({
    required String url,
    required void Function(ImportProgress) onProgress,
  }) async {
    onProgress(const ImportProgress(
      status: ImportStatus.fetchingMeta,
      message: 'Получение данных со Spotify...',
      progress: 0.1,
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

      final titleRegex = RegExp(r'<meta property="og:title" content="([^"]+)"');
      final descRegex = RegExp(r'<meta name="description" content="([^"]+)"');

      final titleMatch = titleRegex.firstMatch(html);
      final descMatch = descRegex.firstMatch(html);

      if (titleMatch == null || descMatch == null) {
        throw Exception('Не удалось извлечь метаданные Spotify');
      }

      final pageTitle = titleMatch.group(1)!;
      final pageDesc = descMatch.group(1)!;

      String trackTitle = pageTitle;
      String artist = 'Unknown Artist';

      // Если это трек, описание обычно выглядит так: "Listen to [Title] on Spotify. Song · [Artist] · [Year]"
      if (pageDesc.contains('Song ·')) {
         final parts = pageDesc.split('·');
         if (parts.length >= 2) {
           artist = parts[1].trim();
         }
      } else if (pageDesc.contains('Playlist ·')) {
         throw Exception('Поддерживается только импорт одиночных треков Spotify');
      } else if (pageDesc.contains('Album ·')) {
         throw Exception('Поддерживается только импорт одиночных треков Spotify');
      }

      final query = "$artist - $trackTitle";

      onProgress(ImportProgress(
        status: ImportStatus.fetchingMeta,
        message: 'Поиск: $query',
        progress: 0.3,
      ));

      final yt = YoutubeExplode();
      try {
        final searchResults = await yt.search.search(query);
        if (searchResults.isEmpty) {
          throw Exception('Трек не найден на YouTube');
        }

        var video = searchResults.first;
        final maxResults = searchResults.length > 10 ? 10 : searchResults.length;
        for (int j = 0; j < maxResults; j++) {
          final v = searchResults.elementAt(j);
          final authorLow = v.author.toLowerCase();
          final titleLow = v.title.toLowerCase();

          if (authorLow.contains('topic') ||
              authorLow.contains('vevo') ||
              titleLow.contains('(official audio)')) {
            video = v;
            debugPrint('[Spotify] Выбрано приоритетное аудио: ${v.title} (${v.author})');
            break;
          }
        }

        await _downloadYouTubeVideo(
          yt: yt,
          video: video,
          cleanTitle: trackTitle,
          albumName: 'Spotify Import',
          artistOverride: artist, // use Spotify artist!
          onProgress: (p) => onProgress(ImportProgress(
            status: p.status,
            message: p.message,
            progress: 0.3 + (p.progress * 0.7),
          )),
        );

      } finally {
        yt.close();
      }

    } catch (e) {
      onProgress(ImportProgress(
        status: ImportStatus.error,
        message: 'Ошибка импорта Spotify',
        error: e.toString(),
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

      // Setup headers to pretend we are a browser
      final headers = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
        'Accept': 'application/json, text/plain, */*',
      };

      if (url.contains('/album/')) {
        // Extract album id
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
              for (var volume in data['volumes']) {
                tracksJson.addAll(volume);
              }
            }
          } else {
            throw Exception('Не удалось загрузить альбом (Код: ${response.statusCode})');
          }
        } else {
          throw Exception('Неверный URL альбома');
        }
      } else if (url.contains('/playlists/')) {
        // Extract owner and kind
        final pathSegments = uri.pathSegments;
        final usersIndex = pathSegments.indexOf('users');
        final playlistsIndex = pathSegments.indexOf('playlists');

        if (usersIndex != -1 && playlistsIndex != -1 &&
            usersIndex + 1 < pathSegments.length &&
            playlistsIndex + 1 < pathSegments.length) {

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
            throw Exception('Не удалось загрузить плейлист (Код: ${response.statusCode})');
          }
        } else {
          throw Exception('Неверный URL плейлиста');
        }
      }

      if (tracksJson.isEmpty) {
        throw Exception('В плейлисте/альбоме нет треков');
      }

      // Parse metadata off main thread via microtask
      await Future.microtask(() {});

      final parsedTracks = <Map<String, String>>[];
      for (var track in tracksJson) {
        if (track['available'] == false) continue;

        final title = track['title']?.toString() ?? 'Unknown Title';
        final artistsList = track['artists'] as List?;
        final artist = (artistsList != null && artistsList.isNotEmpty)
            ? artistsList.map((a) => a['name']).join(', ')
            : 'Unknown Artist';

        // Use default cover from first track if available? We just leave it empty for now, YouTube will provide a cover
        parsedTracks.add({
          'title': title,
          'artist': artist,
        });
      }

      if (parsedTracks.isEmpty) {
        throw Exception('Нет доступных треков для скачивания');
      }

      // Download each track using YouTube fallback
      final yt = YoutubeExplode();
      final downloadedTrackIds = <String>[];
      int i = 0;

      onProgress(ImportProgress(
        status: ImportStatus.done,
        message: 'Создание плейлиста "$playlistName"...',
        progress: 0.05,
      ));
      final playlist = await PlaylistDatabase.instance.createPlaylist(playlistName);

      try {
        for (final track in parsedTracks) {
          i++;
          final query = "${track['artist']} - ${track['title']}";

          onProgress(ImportProgress(
            status: ImportStatus.fetchingMeta,
            message: 'Поиск: $query ($i из ${parsedTracks.length})',
            progress: i / parsedTracks.length,
          ));

          try {
            final searchResults = await yt.search.search(query);
            if (searchResults.isEmpty) {
              debugPrint('Не найдено на YouTube: $query');
              continue;
            }

            var video = searchResults.first;

            // Smart YouTube Search (Topic & Audio Priority)
            final maxResults = searchResults.length > 10 ? 10 : searchResults.length;
            for (int j = 0; j < maxResults; j++) {
              final v = searchResults.elementAt(j);
              final authorLow = v.author.toLowerCase();
              final titleLow = v.title.toLowerCase();

              if (authorLow.contains('topic') ||
                  authorLow.contains('vevo') ||
                  titleLow.contains('(official audio)')) {
                video = v;
                debugPrint('Выбрано приоритетное аудио: ${v.title} (${v.author})');
                break;
              }
            }

            // Re-use standard YouTube download flow
            final trackId = await _downloadYouTubeVideo(
              yt: yt,
              video: video,
              cleanTitle: track['title'] ?? video.title, // use Yandex title!
              albumName: playlistName,
              artistOverride: track['artist'], // use Yandex artist!
              onProgress: (p) {
                // Wrapper progress to show playlist context
                onProgress(ImportProgress(
                  status: p.status,
                  message: '$i/${parsedTracks.length}: ${p.message}',
                  progress: (i - 1) / parsedTracks.length + (p.progress * (1 / parsedTracks.length)),
                ));
              },
            );

            downloadedTrackIds.add(trackId);
            await PlaylistDatabase.instance.addTrackToPlaylist(
              playlistId: playlist.id,
              trackId: trackId,
            );
          } catch (e) {
            debugPrint('Ошибка загрузки $query: $e');
            // Continue to next track, but optionally notify? No, just continue to not break the whole playlist.
          }
        }
      } finally {
        yt.close();
      }



      onProgress(ImportProgress(
        status: ImportStatus.done,
        message: '✓ Импортировано ${downloadedTrackIds.length} из ${parsedTracks.length} треков ("$playlistName")',
        progress: 1.0,
      ));

    } catch (e) {
      onProgress(ImportProgress(
        status: ImportStatus.error,
        message: 'Ошибка парсинга Яндекс.Музыки',
        error: e.toString(),
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

  // ── Local Files ───────────────────────────────────────────────────────────

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
      // Create a clean alphanumeric id for the DB
      final id = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

      onProgress(ImportProgress(
        status: ImportStatus.downloading,
        message: 'Копирование: $title ($i из ${paths.length})',
        progress: i / paths.length,
      ));

      try {
        final savePath = await _getTrackPath(fileName);

        // Only copy if it's not already in the music directory
        if (file.path != savePath) {
          await file.copy(savePath);
        }

        // Search for existing LRC if available in the same source folder
        String? lrcPath;
        final srcLrc = File(path.replaceAll(p.extension(path), '.lrc'));
        if (await srcLrc.exists()) {
           final lrcContent = await srcLrc.readAsString();
           lrcPath = await LyricsService.instance.saveLrc(lrcContent, id);
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
