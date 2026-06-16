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
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
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
        // YouTube-трек: прокидываем через Invidious, чтобы избежать 403 и IP-локов.
        // НЕ используем googlevideo.com URL из youtube_explode напрямую.
        return _buildInvidiousSource();
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

    // ── YouTube-трек без локального файла: стрим через Invidious ─────────
    // (например, временный трек из поиска, созданный с filePath: null)
    if (isYtVideoId) {
      return _buildInvidiousSource();
    }

    // ── Тишина-заглушка (нет ни файла, ни YouTube ID) ────────────────────
    return AudioSource.asset('assets/mock/silence.mp3');
  }

  // ── Построение Invidious LockCachingAudioSource ───────────────────────────

  Future<LockCachingAudioSource> _buildInvidiousSource() async {
    // Убеждаемся, что рабочий инстанс найден (кэшируется на 30 мин)
    await InvidiousProxyService.instance.findWorkingInstance();
    final streamUrl = InvidiousProxyService.instance.buildStreamUrl(id);
    final cacheFile = await _cacheFile('$id.m4a');

    return LockCachingAudioSource(
      Uri.parse(streamUrl),
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
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
