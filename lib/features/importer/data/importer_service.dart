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
import '../../library/domain/lyrics_text.dart';
import '../../../core/services/app_paths.dart';
import '../../../core/services/youtube_clients.dart';
import 'device_music.dart';
import 'local_tags.dart';
import 'yandex_library_index.dart';
import 'yandex_music.dart';
import 'youtube_match.dart';

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

  /// Что импортируется, если известно: название плейлиста или альбома.
  final String? label;

  /// Импорт оборвался по внешней причине (YouTube ограничил запросы) —
  /// ссылку стоит предложить продолжить (import_manager.dart).
  final bool resumable;

  const ImportProgress({
    required this.status,
    required this.message,
    this.progress = 0.0,
    this.error,
    this.label,
    this.resumable = false,
  });

  static const idle = ImportProgress(status: ImportStatus.idle, message: '');
}

/// Управление долгим импортом из фона (import_manager.dart): остановка между
/// треками и сигнал «трек сохранён» — по нему медиатека обновляется по ходу.
class ImportControl {
  ImportControl({this.onTrackSaved});

  final void Function()? onTrackSaved;
  bool _cancelled = false;

  bool get cancelled => _cancelled;

  /// Остановиться после трека, который обрабатывается сейчас.
  void cancel() => _cancelled = true;
}

/// Среди роликов YouTube нет той же записи (youtube_match.dart).
class _NoMatchException implements Exception {
  const _NoMatchException();

  @override
  String toString() => 'Нет подходящей записи на YouTube';
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
    ImportControl? control,
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
        await _importYandexMusic(
            url: url, onProgress: onProgress, control: control);
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
          error: 'Подойдут ссылки YouTube, Spotify, Яндекс Музыки '
              'и прямые ссылки на аудиофайлы',
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
    String? coverUrlOverride,
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

    // Квадратная обложка альбома (из Яндекса) лучше кадра из ролика;
    // не скачалась — берём кадр
    String? coverPath;
    if (coverUrlOverride != null) {
      coverPath = await _downloadCover(coverUrlOverride, id);
    }
    coverPath ??= await _downloadCover(video.thumbnails.highResUrl, id);

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

  /// Ролик для трека из Яндекс Музыки или Spotify; что подходит — решает
  /// youtube_match.dart. Сначала запрос «Артист - Название», не нашлось
  /// подходящего — ещё один, с «topic»: он выводит в выдачу записи с канала
  /// исполнителя. Нет и там — _NoMatchException: лучше пропустить трек,
  /// чем скачать чужую запись.
  Future<Video> _findOnYouTube(
    YoutubeExplode yt, {
    required String title,
    required String artist,
    int? durationMs,
  }) async {
    final matcher = YoutubeTrackMatcher(
        title: title, artist: artist, durationMs: durationMs);
    final artists = splitArtists(artist);
    final mainArtist = artists.isEmpty ? '' : artists.first;
    final queries = mainArtist.isEmpty
        ? [title]
        : ['$mainArtist - $title', '$mainArtist $title topic'];
    for (final query in queries) {
      final results = await _throttledSearch(yt, query);
      final byId = <String, Video>{
        for (final v in results.take(15)) v.id.value: v,
      };
      final picked = matcher.pick([
        for (final v in byId.values)
          YoutubeCandidate(
            id: v.id.value,
            title: v.title,
            author: v.author,
            durationMs: v.duration?.inMilliseconds,
          ),
      ]);
      if (picked != null) return byId[picked.id]!;
    }
    throw const _NoMatchException();
  }

  /// Поиск с одной паузой на минуту, если YouTube ограничил запросы.
  /// null — во время паузы импорт остановили. Повторное ограничение уходит
  /// наверх как RequestLimitExceededException.
  Future<Video?> _findWithBackoff(
    YoutubeExplode yt,
    YandexTrack track,
    ImportControl? control, {
    required void Function() onPause,
  }) async {
    try {
      return await _findOnYouTube(yt,
          title: track.title,
          artist: track.artists,
          durationMs: track.durationMs);
    } on RequestLimitExceededException {
      debugPrint('[YT] YouTube ограничил запросы — пауза');
      onPause();
      for (var s = 0; s < 60; s++) {
        if (control?.cancelled ?? false) return null;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      return _findOnYouTube(yt,
          title: track.title,
          artist: track.artists,
          durationMs: track.durationMs);
    }
  }

  DateTime _lastSearchAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Не чаще раза в 1,5 секунды: сотни поисков подряд (например, плейлист,
  /// где многое уже скачано) быстро упираются в ограничение YouTube.
  Future<VideoSearchList> _throttledSearch(
      YoutubeExplode yt, String query) async {
    final wait = const Duration(milliseconds: 1500) -
        DateTime.now().difference(_lastSearchAt);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    _lastSearchAt = DateTime.now();
    return yt.search.search(query).timeout(const Duration(seconds: 8));
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
        final video = await _findOnYouTube(
          yt,
          title: trackTitle,
          artist: artist == 'Unknown Artist' ? '' : artist,
        );
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
    } on _NoMatchException {
      onProgress(const ImportProgress(
        status: ImportStatus.error,
        message: 'На YouTube нет подходящей записи',
        error: 'Нашлись только другие версии — клипы, концерты, каверы. '
            'Попробуй найти трек через поиск.',
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

  // Список треков — из API Яндекса (yandex_music.dart), сами треки — с YouTube.
  Future<void> _importYandexMusic({
    required String url,
    required void Function(ImportProgress) onProgress,
    ImportControl? control,
  }) async {
    onProgress(const ImportProgress(
      status: ImportStatus.fetchingMeta,
      message: 'Получение данных с Яндекс Музыки...',
      progress: 0.05,
    ));

    final link = YandexLink.parse(url);
    if (link == null) {
      onProgress(const ImportProgress(
        status: ImportStatus.error,
        message: 'Эту ссылку Яндекс Музыки импорт не понимает',
        error: 'Подойдёт ссылка на трек, альбом или плейлист.',
      ));
      return;
    }

    final YandexCollection collection;
    try {
      collection = await YandexMusicApi().fetch(link);
    } on YandexMusicException catch (e) {
      onProgress(ImportProgress(
        status: ImportStatus.error,
        message: 'Ошибка импорта из Яндекс Музыки',
        error: e.message,
      ));
      return;
    }

    if (collection.tracks.isEmpty) {
      onProgress(const ImportProgress(
        status: ImportStatus.error,
        message: 'Ошибка импорта из Яндекс Музыки',
        error: 'Здесь нет доступных треков.',
      ));
      return;
    }

    await _importYandexCollection(collection, onProgress, control);
  }

  /// Треки из Яндекса ищутся и качаются с YouTube. Альбом или плейлист
  /// становится плейлистом Protogenix (_playlistNamed), отдельный трек —
  /// просто трек медиатеки. Уже скачанные треки не ищутся и не качаются
  /// заново (YandexLibraryIndex): повторный импорт той же ссылки — после
  /// прерванного или когда в плейлист добавили песен — сразу переходит к
  /// недостающим. Остановка — между треками (ImportControl).
  Future<void> _importYandexCollection(
    YandexCollection collection,
    void Function(ImportProgress) onProgress, [
    ImportControl? control,
  ]) async {
    final tracks = collection.tracks;
    final single = collection.isSingleTrack;
    final label = single ? null : collection.title;
    String? playlistId;
    var saved = 0;
    var alreadyHad = 0;
    var notFound = 0;
    var stopped = false;
    var rateLimited = false;
    final known =
        YandexLibraryIndex(await LibraryDatabase.instance.getAllTracks());

    final yt = YoutubeExplode();
    try {
      for (var i = 0; i < tracks.length; i++) {
        if (control?.cancelled ?? false) {
          stopped = true;
          break;
        }
        final track = tracks[i];
        final artist = track.artists.split(', ').first;
        final query =
            artist.isEmpty ? track.title : '$artist - ${track.title}';
        final ofTotal = single ? '' : ' (${i + 1} из ${tracks.length})';
        final base = i / tracks.length;
        final step = 1 / tracks.length;
        // То же, что уходит в альбом трека: по нему YandexLibraryIndex
        // узнаёт трек при повторном импорте
        final album = track.album ?? collection.title;

        try {
          final String trackId;
          final knownId = known.find(track, album: album);
          if (knownId != null) {
            trackId = knownId;
            alreadyHad++;
            onProgress(ImportProgress(
              status: ImportStatus.fetchingMeta,
              message: 'Уже в медиатеке: $query$ofTotal',
              progress: base + step,
              label: label,
            ));
          } else {
            onProgress(ImportProgress(
              status: ImportStatus.fetchingMeta,
              message: 'Поиск на YouTube: $query$ofTotal',
              progress: base,
              label: label,
            ));
            final video = await _findWithBackoff(
              yt,
              track,
              control,
              onPause: () => onProgress(ImportProgress(
                status: ImportStatus.fetchingMeta,
                message: 'YouTube просит подождать — пауза на минуту$ofTotal',
                progress: base,
                label: label,
              )),
            );
            if (video == null) {
              stopped = true;
              break;
            }
            // Мог быть скачан и не отсюда (поиск, ссылка YouTube) — тогда
            // метаданные другие, но ролик тот же
            if (await LibraryDatabase.instance.getTrackById(video.id.value) !=
                null) {
              trackId = video.id.value;
              alreadyHad++;
            } else {
              trackId = await _downloadYouTubeVideo(
                yt: yt,
                video: video,
                cleanTitle: track.title,
                albumName: album,
                artistOverride: track.artists.isEmpty ? null : track.artists,
                coverUrlOverride: track.coverUrl,
                onProgress: (p) => onProgress(ImportProgress(
                  status: p.status,
                  message: '${p.message}$ofTotal',
                  progress: base + step * p.progress,
                  label: label,
                )),
              );
            }
            known.add(track, album: album, id: trackId);
          }
          if (!single) {
            playlistId ??= await _playlistNamed(collection.title);
            await PlaylistDatabase.instance.addTrackToPlaylist(
              playlistId: playlistId,
              trackId: trackId,
            );
          }
          saved++;
          control?.onTrackSaved?.call();
        } on RequestLimitExceededException {
          // Второй раз подряд, уже после паузы: дальше будет только хуже.
          // Стоп с «продолжи позже» — скачанное при этом пропустится
          rateLimited = true;
          break;
        } on _NoMatchException {
          notFound++;
          debugPrint('[Yandex] Нет подходящей записи: "$query"');
        } catch (e) {
          debugPrint('[Yandex] Пропуск "$query": $e');
        }
      }
    } finally {
      yt.close();
    }

    if (saved == 0 && !stopped && !rateLimited) {
      onProgress(ImportProgress(
        status: ImportStatus.error,
        message: notFound > 0
            ? 'На YouTube нет подходящей записи'
            : 'Не удалось скачать с YouTube',
        error: notFound > 0
            ? 'Нашлись только другие версии — клипы, концерты, каверы. '
                'Попробуй найти трек через поиск.'
            : 'YouTube не отдал аудио. Попробуй ещё раз позже.',
        label: label,
      ));
      return;
    }

    final notes = [
      if (alreadyHad > 0) 'уже были: $alreadyHad',
      if (notFound > 0) 'не нашлось на YouTube: $notFound',
      if (collection.unavailable > 0)
        'недоступны в самом Яндексе: ${collection.unavailable}',
    ];
    final tail = notes.isEmpty ? '' : ', ${notes.join(', ')}';
    onProgress(ImportProgress(
      status: ImportStatus.done,
      message: rateLimited
          ? '■ YouTube ограничил запросы: $saved из ${tracks.length}$tail. '
              'Продолжи позже — скачанное пропустится'
          : single
              ? alreadyHad > 0
                  ? '✓ "${tracks.first.title}" уже есть в медиатеке'
                  : '✓ "${tracks.first.title}" добавлен!'
              : stopped
                  ? '■ Остановлено: $saved из ${tracks.length}$tail'
                  : '✓ Готово: $saved из ${tracks.length}$tail',
      progress: 1.0,
      label: label,
      resumable: rateLimited,
    ));
  }

  /// Плейлист для импорта: тот же, если такой уже есть, — повторный импорт
  /// той же ссылки дополняет его, а не плодит копии. Иначе новый.
  Future<String> _playlistNamed(String name) async {
    final existing = await PlaylistDatabase.instance.findPlaylistByName(name);
    if (existing != null) return existing.id;
    return (await PlaylistDatabase.instance.createPlaylist(name)).id;
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
    ImportControl? control,
  }) async {
    int i = 0;
    var alreadyInLibrary = 0;
    var stopped = false;
    final imported = <String>[];

    for (final path in paths) {
      if (control?.cancelled ?? false) {
        stopped = true;
        break;
      }
      i++;
      final file = File(path);
      if (!await file.exists()) continue;

      final fileName = p.basename(path);
      final title = p.basenameWithoutExtension(path);

      onProgress(ImportProgress(
        status: ImportStatus.downloading,
        message: 'Копирование: $title ($i из ${paths.length})',
        progress: i / paths.length,
      ));

      try {
        // id по содержимому, а не по имени файла: из имени оставались только
        // латиница и цифры, и у русских названий одинаковой длины id совпадал —
        // второй трек затирал первый (как и одноимённые файлы из разных папок)
        final id = await localTrackId(file);
        if (await LibraryDatabase.instance.getTrackById(id) != null) {
          alreadyInLibrary++;
          continue;
        }

        final tags = await readLocalTags(path);
        final (nameArtist, nameTitle) = splitArtistTitle(title);
        final savePath =
            await _getTrackPath('$id${p.extension(path).toLowerCase()}');
        if (!p.equals(file.path, savePath)) await file.copy(savePath);

        String? lrcPath;
        final srcLrc = File(p.setExtension(path, '.lrc'));
        if (await srcLrc.exists()) {
          final content = await srcLrc.readAsString();
          lrcPath = await LyricsService.instance.saveLrc(content, id);
        }

        await LibraryDatabase.instance.insertTrack(LibraryTrack(
          id: id,
          title: tags.title ?? nameTitle,
          artist: tags.artist ?? nameArtist ?? 'Unknown Artist',
          album: tags.album ?? 'Local Import',
          filePath: savePath,
          coverPath: await _saveLocalCover(id, tags),
          lrcPath: lrcPath,
          durationMs: tags.duration?.inMilliseconds ?? 0,
          source: 'local',
          addedAt: DateTime.now(),
        ));

        imported.add(id);
        control?.onTrackSaved?.call();
      } catch (e) {
        debugPrint('Ошибка локального импорта $fileName: $e');
      }
    }

    onProgress(ImportProgress(
      status: ImportStatus.done,
      message: [
        stopped
            ? '■ Остановлено: импортировано ${imported.length} '
                'из ${paths.length}'
            : '✓ Импортировано файлов: ${imported.length}',
        if (alreadyInLibrary > 0) 'уже были в медиатеке: $alreadyInLibrary',
      ].join(', '),
      progress: 1.0,
    ));
  }

  /// Музыка с телефона (device_music.dart): треки добавляются с места, без
  /// копирования. Уже добавленные — по пути или по содержимому — пропускаются.
  Future<void> importDeviceTracks({
    required List<DeviceTrack> tracks,
    required void Function(ImportProgress) onProgress,
    ImportControl? control,
  }) async {
    var added = 0;
    var already = 0;
    var stopped = false;
    for (var i = 0; i < tracks.length; i++) {
      if (control?.cancelled ?? false) {
        stopped = true;
        break;
      }
      final track = tracks[i];
      final baseName = p.basenameWithoutExtension(track.path);
      onProgress(ImportProgress(
        status: ImportStatus.downloading,
        message: 'Добавление: ${track.title ?? baseName} '
            '(${i + 1} из ${tracks.length})',
        progress: (i + 1) / tracks.length,
      ));
      try {
        final file = File(track.path);
        if (!await file.exists()) continue;
        if (await LibraryDatabase.instance.exists(track.path)) {
          already++;
          continue;
        }
        final id = await localTrackId(file);
        if (await LibraryDatabase.instance.getTrackById(id) != null) {
          already++;
          continue;
        }
        final tags = await readLocalTags(track.path);
        final (nameArtist, nameTitle) = splitArtistTitle(baseName);
        await LibraryDatabase.instance.insertTrack(LibraryTrack(
          id: id,
          title: tags.title ?? track.title ?? nameTitle,
          artist:
              tags.artist ?? track.artist ?? nameArtist ?? 'Unknown Artist',
          album: tags.album ?? track.album ?? 'На телефоне',
          filePath: track.path,
          coverPath: await _saveLocalCover(id, tags),
          durationMs: tags.duration?.inMilliseconds ?? track.durationMs ?? 0,
          source: 'device',
          addedAt: DateTime.now(),
        ));
        added++;
        control?.onTrackSaved?.call();
      } catch (e) {
        debugPrint('Ошибка добавления с телефона: $e');
      }
    }

    onProgress(ImportProgress(
      status: ImportStatus.done,
      message: [
        stopped
            ? '■ Остановлено: добавлено $added'
            : '✓ Добавлено с телефона: $added',
        if (already > 0) 'уже были в медиатеке: $already',
      ].join(', '),
      progress: 1.0,
    ));
  }

  /// Встроенная обложка своего файла — в папку обложек.
  Future<String?> _saveLocalCover(String id, LocalTags tags) async {
    final bytes = tags.cover;
    if (bytes == null) return null;
    try {
      final ext = tags.coverMime == 'image/png' ? 'png' : 'jpg';
      final dir = Directory(AppPaths.coversDir);
      await dir.create(recursive: true);
      final path = p.join(dir.path, '$id.$ext');
      await File(path).writeAsBytes(bytes, flush: true);
      return path;
    } catch (e) {
      debugPrint('Не удалось сохранить обложку $id: $e');
      return null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool _isYouTube(String url) =>
      url.contains('youtube.com') || url.contains('youtu.be');
  bool _isSoundCloud(String url) => url.contains('soundcloud.com');
  bool _isSpotify(String url) => url.contains('open.spotify.com');
  // Любой домен Яндекс Музыки; непонятный вид ссылки (исполнитель) получит
  // своё сообщение в _importYandexMusic, а не «неизвестный формат»
  bool _isYandexMusic(String url) =>
      YandexLink.isYandexMusicHost(Uri.tryParse(url)?.host ?? '');
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
