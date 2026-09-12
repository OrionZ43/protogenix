// lib/features/player/domain/track_model.dart
//
// toAudioSource() выбирает источник звука трека:
//   • трек с YouTube ID (ровно 11 символов из [A-Za-z0-9_-]) без локального
//     файла или со ссылкой на YouTube — прямой поток через youtube_explode
//     (сначала клиент visionOS, см. youtube_clients.dart). Запасного пути нет
//     (Invidious удалён 2026-09-12, .claude/rules/known-issues.md): если
//     YouTube не отдал поток — тишина-заглушка;
//   • прямая audio-ссылка (MP3 и т.п.) — как есть, на мобильных с кэшем;
//   • локальный файл, если он есть;
//   • иначе — тишина-заглушка.
//
// toAudioSource() не бросает исключений: PlayerNotifier.loadPlaylist ждёт
// источники всей очереди через Future.wait, и одна ошибка сорвала бы загрузку
// всей очереди.

import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:dio/dio.dart';
import '../../../core/services/app_paths.dart';
import '../../../core/services/youtube_clients.dart';

// YouTube video ID — ровно 11 символов из A-Za-z0-9_-
final _ytIdRegex = RegExp(r'^[A-Za-z0-9_-]{11}$');

class TrackModel {
  final String id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final ImageProvider coverImage;
  final String? filePath;
  final String? lrcPath;

  const TrackModel({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.coverImage,
    this.filePath,
    this.lrcPath,
  });

  // ─────────────────────────────────────────────────────────────────────────
  // toAudioSource
  // ─────────────────────────────────────────────────────────────────────────

  Future<AudioSource> toAudioSource() async {
    final path = filePath;
    final isYtVideoId = _ytIdRegex.hasMatch(id);

    // ── Сетевой URL ───────────────────────────────────────────────────────
    if (path != null &&
        (path.startsWith('http://') || path.startsWith('https://'))) {
      if (isYtVideoId) {
        return _tryDirectYouTube();
      }
      // Прямая ссылка (MP3, FLAC и т.д.)
      final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
      if (isDesktop) {
        return AudioSource.uri(
          Uri.parse(path),
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        );
      }
      // Скачиваем с кэшированием на мобилках
      final cacheFile = await _cacheFile('${id.hashCode}.m4a');
      return LockCachingAudioSource(
        Uri.parse(path),
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
        cacheFile: cacheFile,
      );
    }

    // ── Локальный файл ────────────────────────────────────────────────────
    if (path != null && await File(path).exists()) {
      return AudioSource.file(path);
    }

    // ── YouTube-трек без локального файла ────────────────────────────────
    if (isYtVideoId) {
      return _tryDirectYouTube();
    }

    // ── Тишина-заглушка (нет ни файла, ни YouTube ID) ────────────────────
    return AudioSource.asset('assets/mock/silence.mp3');
  }

  // Сначала visionOS: клиент по умолчанию (android) с августа 2026 на многих
  // видео отдаёт пустые потоки (youtube_clients.dart).
  Future<StreamManifest> _getManifest(YoutubeExplode yt) async {
    try {
      return await yt.videos.streamsClient
          .getManifest(id, ytClients: [kVisionOsClient]);
    } catch (e) {
      debugPrint('[TrackModel] VISIONOS не отдал потоки ($e), '
          'пробуем клиент по умолчанию');
      return yt.videos.streamsClient.getManifest(id);
    }
  }

  Future<AudioSource> _tryDirectYouTube() async {
    try {
      // 1. Пробуем получить прямой стрим через youtube_explode_dart
      final yt = YoutubeExplode();
      try {
        final manifest = await _getManifest(yt);

        // Берем лучший audio/mp4 поток, чтобы избежать проблем с кодеками (например на iOS)
        final audioStreams = manifest.audioOnly.where((s) => s.container.name == 'mp4').toList();
        if (audioStreams.isEmpty) throw Exception('No mp4 audio streams found');

        audioStreams.sort((a, b) => b.bitrate.compareTo(a.bitrate));
        final url = audioStreams.first.url.toString();

        // 2. Делаем быстрый HEAD-запрос для проверки доступности
        final dio = Dio(BaseOptions(
          connectTimeout: const Duration(milliseconds: 2000),
          receiveTimeout: const Duration(milliseconds: 2000),
          sendTimeout: const Duration(milliseconds: 2000),
        ));

        final response = await dio.head(url);

        if (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300) {
          // Успешно подключились, используем прямой URL
          final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
          if (isDesktop) {
            return AudioSource.uri(
              Uri.parse(url),
              headers: const {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              },
            );
          }

          final cacheFile = await _cacheFile('$id.m4a');
          return LockCachingAudioSource(
            Uri.parse(url),
            headers: const {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
            cacheFile: cacheFile,
          );
        } else {
          throw Exception('Status code: ${response.statusCode}');
        }
      } finally {
        yt.close();
      }
    } catch (e) {
      // Запасного пути нет, а исключение сорвало бы загрузку всей очереди
      // (шапка файла) — трек просто молчит.
      debugPrint('[TrackModel] YouTube не отдал поток для $id: $e');
      return AudioSource.asset('assets/mock/silence.mp3');
    }
  }

  // ── Утилита: файл кэша ────────────────────────────────────────────────────

  Future<File> _cacheFile(String fileName) async {
    final cacheDir = Directory(AppPaths.audioCacheDir);
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return File('${cacheDir.path}/$fileName');
  }
}

// ── Моки ─────────────────────────────────────────────────────────────────────

// Мок только для UI-разработки — больше не используется в продакшене
const mockTrack = TrackModel(
  id: 'mock_001',
  title: 'Midnight Protocol',
  artist: 'Neon Circuits',
  album: 'Protogenix OST',
  duration: Duration(minutes: 4, seconds: 32),
  coverImage: AssetImage('assets/images/mock_cover.jpg'),
);

final mockPlaylist = <TrackModel>[];
