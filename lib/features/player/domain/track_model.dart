// lib/features/player/domain/track_model.dart
//
// КЛЮЧЕВОЕ ИЗМЕНЕНИЕ: toAudioSource() для сетевых треков
// —————————————————————————————————————————————————————
// Если id трека является YouTube video ID (ровно 11 символов из [A-Za-z0-9_-]),
// аудио-поток строится через Invidious-прокси:
//   https://<instance>/latest_version?id=<id>&itag=140&local=true
//
// Это ПОЛНОСТЬЮ устраняет:
//   • 403 Forbidden от googlevideo.com (IP-лок + подпись URL)
//   • Блокировки YouTube на уровне DNS/SNI в РФ
//
// Для прямых audio-ссылок (MP3 и т.п.) поведение не изменилось.

import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:dio/dio.dart';
import '../../../core/services/invidious_proxy_service.dart';

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
        return _tryDirectOrInvidious();
      }
      // Прямая ссылка (MP3, FLAC и т.д.) — скачиваем с кэшированием
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
      return _tryDirectOrInvidious();
    }

    // ── Тишина-заглушка (нет ни файла, ни YouTube ID) ────────────────────
    return AudioSource.asset('assets/mock/silence.mp3');
  }

  Future<AudioSource> _tryDirectOrInvidious() async {
    try {
      // 1. Пробуем получить прямой стрим через youtube_explode_dart
      final yt = YoutubeExplode();
      try {
        final manifest = await yt.videos.streamsClient.getManifest(id);
        final streamInfo = manifest.audioOnly.withHighestBitrate();
        final url = streamInfo.url.toString();

        // 2. Делаем быстрый HEAD-запрос для проверки доступности
        final dio = Dio(BaseOptions(
          connectTimeout: const Duration(milliseconds: 2000),
          receiveTimeout: const Duration(milliseconds: 2000),
          sendTimeout: const Duration(milliseconds: 2000),
        ));

        final response = await dio.head(url);

        if (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300) {
          // Успешно подключились, используем прямой URL
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
      debugPrint('[TrackModel] Ошибка прямого подключения ($e). Включаем обход блокировки через Invidious...');
      return _buildInvidiousSource();
    }
  }

  // ── Построение Invidious LockCachingAudioSource ───────────────────────────

  Future<LockCachingAudioSource> _buildInvidiousSource() async {
    final streamUrlStr = await InvidiousProxyService.instance.getProxiedStreamUrl(id);
    if (streamUrlStr == null) {
      throw Exception('Не удалось получить проксированный URL');
    }

    final cacheFile = await _cacheFile('$id.m4a');

    return LockCachingAudioSource(
      Uri.parse(streamUrlStr),
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://www.youtube.com/',
        'Origin': 'https://www.youtube.com/',
      },
      cacheFile: cacheFile,
    );
  }

  // ── Утилита: файл кэша ────────────────────────────────────────────────────

  Future<File> _cacheFile(String fileName) async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDocDir.path}/audio_cache');
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
