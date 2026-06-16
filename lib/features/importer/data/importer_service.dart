// lib/features/importer/data/importer_service.dart
//
// Импорт музыки с автоматическим Invidious-фолбэком.
//
// Стратегия фолбэка:
//  _importYouTube:
//    1. Пробуем стандартный путь через YoutubeExplode
//    2. При ЛЮБОЙ ошибке → _importYouTubeViaInvidious
//
//  _downloadYouTubeVideo (вызывается из Spotify/Yandex):
//    1. Пробуем все клиенты youtube_explode (_clientFallbackOrder)
//    2. Если все провалились → _downloadViaInvidious (уже есть Video-объект
//       с метаданными, нужен только аудио-поток)
//
//  _importSpotify / _importYandexMusic:
//    1. Поиск через yt.search.search()
//    2. При сетевой ошибке поиска → InvidiousProxyService.searchVideos()
//    3. Скачивание через _downloadYouTubeVideo (с встроенным Invidious-фолбэком)
//       или напрямую через _importYouTubeViaInvidious
//
//  Фразы «слом 4-й стены» появляются в progress.message каждый раз,
//  когда активируется прокси-путь.

import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../library/data/library_database.dart';
import '../../library/data/playlist_database.dart';
import '../../library/data/lyrics_service.dart';
import '../../library/domain/library_track.dart';
import '../../../core/services/invidious_proxy_service.dart';

// ── Модели прогресса ──────────────────────────────────────────────────────────

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

// ── ImporterService ───────────────────────────────────────────────────────────

class ImporterService {
  ImporterService._();
  static final ImporterService instance = ImporterService._();

  final _dio = Dio();

  // Порядок клиентов: от наиболее стабильных к запасным.
  static final _clientFallbackOrder = [
    YoutubeApiClient.androidVr,
    YoutubeApiClient.ios,
    YoutubeApiClient.android,
    YoutubeApiClient.mweb,
  ];

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

    bool directSucceeded = false;
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
      directSucceeded = true;
    } catch (e) {
      debugPrint('[YT] Прямой импорт недоступен ($e) → Invidious');
    } finally {
      yt.close();
    }

    if (directSucceeded) return;

    // ── Фолбэк: Invidious ─────────────────────────────────────────────────
    final videoId = _extractYouTubeId(url);
    if (videoId == null) {
      onProgress(const ImportProgress(
        status: ImportStatus.error,
        message: 'Не удалось извлечь ID видео из URL',
        error: 'Некорректный YouTube URL',
      ));
      return;
    }

    try {
      await _importYouTubeViaInvidious(
        videoId: videoId,
        titleOverride: null,
        artistOverride: null,
        albumName: 'YouTube',
        onProgress: onProgress,
      );
    } catch (e) {
      debugPrint('[Invidious] Также недоступен: $e');
      onProgress(ImportProgress(
        status: ImportStatus.error,
        message: 'YouTube заблокирован, Invidious тоже недоступен',
        error: e.toString(),
      ));
    }
  }

  // ── Скачивание через YouTube (с Invidious-фолбэком после всех клиентов) ───

  Future<String> _downloadYouTubeVideo({
    required YoutubeExplode yt,
    required Video video,
    required String cleanTitle,
    required String albumName,
    required void Function(ImportProgress) onProgress,
    String? artistOverride,
  }) async {
    final id = video.id.value;
    bool downloaded = false;
    String? savePath;
    Exception? lastError;

    // Перебираем клиентов YouTube
    for (final client in _clientFallbackOrder) {
      debugPrint('[YT] Клиент: $client');
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
        downloaded = true;
        debugPrint('[YT] Успех: $client');
        break;
      } on _DownloadThrottledException catch (e) {
        debugPrint('[YT] Throttled ($client): $e');
        lastError = e;
      } on _NoStreamsException catch (e) {
        debugPrint('[YT] No streams ($client): $e');
        lastError = e;
      } catch (e) {
        debugPrint('[YT] Ошибка ($client): $e');
        lastError = Exception('Ошибка клиента $client');
      }
    }

    // Если все клиенты провалились — скачиваем через Invidious
    if (!downloaded) {
      debugPrint('[YT] Все клиенты исчерпаны → Invidious download');
      savePath = await _downloadViaInvidious(id, onProgress);
      if (savePath != null) {
        downloaded = true;
      }
    }

    if (!downloaded || savePath == null) {
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
      throw _NoStreamsException('$client: нет аудио-потоков');
    }

    final streamInfo = audioStreams.first;
    final ext = streamInfo.container.name;
    final savePath = await _getTrackPath('$videoId.$ext');
    final totalBytes = streamInfo.size.totalBytes;

    debugPrint(
        '[YT] Поток: ${streamInfo.bitrate}, '
        'размер: ${(totalBytes / 1024 / 1024).toStringAsFixed(1)} MB');

    final file = File(savePath);
    if (await file.exists()) await file.delete();
    final sink = file.openWrite();

    try {
      final audioStream = yt.videos.streamsClient.get(streamInfo);
      int downloaded = 0;
      int lastLogPercent = -1;

      const stallTimeout = Duration(seconds: 15);
      await for (final chunk in audioStream.timeout(
        stallTimeout,
        onTimeout: (sink) => sink.close(),
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

      return savePath;
    } on _DownloadThrottledException {
      if (await file.exists()) await file.delete();
      rethrow;
    } catch (e) {
      if (await file.exists()) await file.delete();
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

  // ── Скачивание через Invidious (аудио-поток) ──────────────────────────────

  Future<String?> _downloadViaInvidious(
    String videoId,
    void Function(ImportProgress) onProgress,
  ) async {
    try {
      onProgress(ImportProgress(
        status: ImportStatus.downloading,
        message: InvidiousProxyService.randomPhrase(),
        progress: 0.15,
      ));

      final proxiedStreamUrl = await InvidiousProxyService.instance.getProxiedStreamUrl(videoId);
      if (proxiedStreamUrl == null) {
        throw Exception('Не удалось получить аудио-поток через Invidious proxy');
      }
      final streamUrl = proxiedStreamUrl;

      final savePath = await _getTrackPath('$videoId.m4a');

      await _dio.download(
        streamUrl,
        savePath,
        options: Options(headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        }),
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final pct = (received / total * 100).round();
            final mb = (received / 1024 / 1024).toStringAsFixed(1);
            final totalMb = (total / 1024 / 1024).toStringAsFixed(1);
            onProgress(ImportProgress(
              status: ImportStatus.downloading,
              message: '⚡ Прокси: $pct% ($mb / $totalMb MB)',
              progress: 0.15 + (received / total) * 0.75,
            ));
          } else {
            onProgress(const ImportProgress(
              status: ImportStatus.downloading,
              message: '⚡ Загружается через прокси...',
              progress: 0.50,
            ));
          }
        },
      );

      return savePath;
    } catch (e) {
      debugPrint('[Invidious] download failed: $e');
      return null;
    }
  }

  // ── Импорт через Invidious (метаданные + аудио + обложка) ────────────────

  Future<void> _importYouTubeViaInvidious({
    required String videoId,
    required String? titleOverride,
    required String? artistOverride,
    required String albumName,
    required void Function(ImportProgress) onProgress,
  }) async {
    onProgress(ImportProgress(
      status: ImportStatus.fetchingMeta,
      message: InvidiousProxyService.randomPhrase(),
      progress: 0.05,
    ));

    final meta = await InvidiousProxyService.instance.getVideoInfo(videoId);
    if (meta == null) {
      throw Exception('Invidious: не удалось получить метаданные $videoId');
    }

    final title =
        titleOverride ?? _cleanYouTubeTitle(meta['title'] as String? ?? 'Unknown');
    final artist =
        artistOverride ?? (meta['author'] as String? ?? 'Unknown');
    final durationSec = meta['lengthSeconds'] as int? ?? 0;

    onProgress(ImportProgress(
      status: ImportStatus.fetchingMeta,
      message: '⚡ Подключено через прокси: $title',
      progress: 0.12,
    ));

    // Аудио через Invidious stream URL
    final proxiedStreamUrl = await InvidiousProxyService.instance.getProxiedStreamUrl(videoId);
    if (proxiedStreamUrl == null) {
      throw Exception('Не удалось получить аудио-поток через Invidious proxy');
    }
    final streamUrl = proxiedStreamUrl;

    final savePath = await _getTrackPath('$videoId.m4a');

    await _dio.download(
      streamUrl,
      savePath,
      options: Options(headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      }),
      onReceiveProgress: (received, total) {
        if (total > 0) {
          final pct = (received / total * 100).round();
          final mb = (received / 1024 / 1024).toStringAsFixed(1);
          final totalMb = (total / 1024 / 1024).toStringAsFixed(1);
          onProgress(ImportProgress(
            status: ImportStatus.downloading,
            message: '⚡ Прокси: $pct% ($mb / $totalMb MB)',
            progress: 0.15 + (received / total) * 0.75,
          ));
        } else {
          onProgress(const ImportProgress(
            status: ImportStatus.downloading,
            message: '⚡ Загружается через прокси...',
            progress: 0.50,
          ));
        }
      },
    );

    // Обложка через миниатюры Invidious
    final thumbnails = meta['videoThumbnails'] as List? ?? [];
    String? coverUrl;
    if (thumbnails.isNotEmpty) {
      coverUrl = (thumbnails.first['url'] as String?)
          ?.replaceFirst('http://', 'https://');
    }
    final coverPath =
        coverUrl != null ? await _downloadCover(coverUrl, videoId) : null;

    await LibraryDatabase.instance.insertTrack(LibraryTrack(
      id: videoId,
      title: title,
      artist: artist,
      album: albumName,
      filePath: savePath,
      coverPath: coverPath,
      durationMs: durationSec * 1000,
      source: 'youtube',
      addedAt: DateTime.now(),
    ));

    onProgress(ImportProgress(
      status: ImportStatus.done,
      message: '✓ "$title" добавлен через прокси!',
      progress: 1.0,
    ));
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
      final titleMatch =
          RegExp(r'<meta property="og:title" content="([^"]+)"').firstMatch(html);
      final descMatch =
          RegExp(r'<meta name="description" content="([^"]+)"').firstMatch(html);

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
        throw Exception('Поддерживается только импорт одиночных треков Spotify');
      }

      final query = '$artist - $trackTitle';

      onProgress(ImportProgress(
        status: ImportStatus.fetchingMeta,
        message: 'Поиск: $query',
        progress: 0.30,
      ));

      final yt = YoutubeExplode();
      try {
        Video? selectedVideo;
        bool usingInvidious = false;
        String? invidiousVideoId;

        // ── Поиск на YouTube ────────────────────────────────────────────
        try {
          final results = await yt.search
              .search(query)
              .timeout(const Duration(seconds: 8));

          if (results.isEmpty) throw Exception('Не найдено на YouTube');

          selectedVideo = results.first;
          final maxLen = results.length.clamp(0, 10);
          for (int j = 0; j < maxLen; j++) {
            final v = results.elementAt(j);
            if (v.author.toLowerCase().contains('topic') ||
                v.author.toLowerCase().contains('vevo') ||
                v.title.toLowerCase().contains('(official audio)')) {
              selectedVideo = v;
              break;
            }
          }
        } catch (e) {
          debugPrint('[Spotify] YouTube Search недоступен → Invidious: $e');
          usingInvidious = true;
          onProgress(ImportProgress(
            status: ImportStatus.fetchingMeta,
            message: InvidiousProxyService.randomPhrase(),
            progress: 0.35,
          ));
          final invRes =
              await InvidiousProxyService.instance.searchVideos(query);
          if (invRes.isEmpty) throw Exception('Трек не найден: $query');
          invidiousVideoId = invRes.first.videoId;
        }

        // ── Скачивание ──────────────────────────────────────────────────
        if (usingInvidious) {
          await _importYouTubeViaInvidious(
            videoId: invidiousVideoId!,
            titleOverride: trackTitle,
            artistOverride: artist,
            albumName: 'Spotify Import',
            onProgress: (p) => onProgress(ImportProgress(
              status: p.status,
              message: p.message,
              progress: 0.30 + p.progress * 0.70,
            )),
          );
        } else {
          try {
            await _downloadYouTubeVideo(
              yt: yt,
              video: selectedVideo!,
              cleanTitle: trackTitle,
              albumName: 'Spotify Import',
              artistOverride: artist,
              onProgress: (p) => onProgress(ImportProgress(
                status: p.status,
                message: p.message,
                progress: 0.30 + p.progress * 0.70,
              )),
            );
          } catch (e) {
            // YouTube download провалился — пробуем Invidious с уже известным ID
            debugPrint('[Spotify] YouTube download failed → Invidious: $e');
            await _importYouTubeViaInvidious(
              videoId: selectedVideo!.id.value,
              titleOverride: trackTitle,
              artistOverride: artist,
              albumName: 'Spotify Import',
              onProgress: (p) => onProgress(ImportProgress(
                status: p.status,
                message: p.message,
                progress: 0.30 + p.progress * 0.70,
              )),
            );
          }
        }
      } finally {
        yt.close();
      }
    } catch (e) {
      debugPrint('Ошибка импорта Spotify: $e');
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
      final playlist = await PlaylistDatabase.instance.createPlaylist(playlistName);

      final yt = YoutubeExplode();
      final downloadedIds = <String>[];
      int i = 0;

      // ytBlocked: после первой ошибки YouTube Search — сразу идём в Invidious
      bool ytBlocked = false;

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
            Video? selectedVideo;
            bool useInvidious = ytBlocked;
            String? invidiousId;

            if (!ytBlocked) {
              try {
                final results = await yt.search
                    .search(query)
                    .timeout(const Duration(seconds: 6));

                if (results.isEmpty) throw Exception('Не найдено');

                selectedVideo = results.first;
                final maxLen = results.length.clamp(0, 10);
                for (int j = 0; j < maxLen; j++) {
                  final v = results.elementAt(j);
                  if (v.author.toLowerCase().contains('topic') ||
                      v.author.toLowerCase().contains('vevo') ||
                      v.title.toLowerCase().contains('(official audio)')) {
                    selectedVideo = v;
                    break;
                  }
                }
              } catch (e) {
                debugPrint('[Yandex] YouTube Search недоступен → Invidious: $e');
                ytBlocked = true;
                useInvidious = true;
                onProgress(ImportProgress(
                  status: ImportStatus.fetchingMeta,
                  message: InvidiousProxyService.randomPhrase(),
                  progress: progressBase + progressStep * 0.1,
                ));
              }
            }

            if (useInvidious) {
              final invRes =
                  await InvidiousProxyService.instance.searchVideos(query);
              if (invRes.isEmpty) {
                debugPrint('[Yandex] Invidious: не найдено "$query"');
                continue;
              }
              invidiousId = invRes.first.videoId;
            }

            String trackId;
            if (useInvidious && invidiousId != null) {
              await _importYouTubeViaInvidious(
                videoId: invidiousId,
                titleOverride: track['title'],
                artistOverride: track['artist'],
                albumName: playlistName,
                onProgress: (p) => onProgress(ImportProgress(
                  status: p.status,
                  message: '$i/${parsedTracks.length}: ${p.message}',
                  progress: progressBase + progressStep * p.progress,
                )),
              );
              trackId = invidiousId;
            } else {
              try {
                trackId = await _downloadYouTubeVideo(
                  yt: yt,
                  video: selectedVideo!,
                  cleanTitle: track['title'] ?? selectedVideo.title,
                  albumName: playlistName,
                  artistOverride: track['artist'],
                  onProgress: (p) => onProgress(ImportProgress(
                    status: p.status,
                    message: '$i/${parsedTracks.length}: ${p.message}',
                    progress:
                        progressBase + progressStep * p.progress,
                  )),
                );
              } catch (e) {
                // YouTube download провалился — пробуем Invidious
                debugPrint('[Yandex] YT download failed → Invidious: $e');
                final vid = selectedVideo!.id.value;
                await _importYouTubeViaInvidious(
                  videoId: vid,
                  titleOverride: track['title'],
                  artistOverride: track['artist'],
                  albumName: playlistName,
                  onProgress: (p) => onProgress(ImportProgress(
                    status: p.status,
                    message: '$i/${parsedTracks.length}: ${p.message}',
                    progress:
                        progressBase + progressStep * p.progress,
                  )),
                );
                trackId = vid;
              }
            }

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
      onProgress(ImportProgress(
        status: ImportStatus.error,
        message: 'Ошибка импорта Яндекс.Музыки',
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
        if (seg.length == 11 &&
            RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(seg)) {
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
    final dir = await getApplicationDocumentsDirectory();
    final music = Directory(p.join(dir.path, 'music'));
    await music.create(recursive: true);
    return p.join(music.path, safeFileName);
  }

  Future<String?> _downloadCover(String url, String trackId) async {
    try {
      final safeId =
          p.basename(trackId).replaceAll(RegExp(r'[^a-zA-Z0-9\.\-\_]'), '_');
      final dir = await getApplicationDocumentsDirectory();
      final coversDir = Directory(p.join(dir.path, 'covers'));
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
