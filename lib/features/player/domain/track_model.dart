import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

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

  Future<AudioSource> toAudioSource() async {
    final path = filePath;

    if (path != null && (path.startsWith('http://') || path.startsWith('https://'))) {
      final appDocDir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${appDocDir.path}/audio_cache');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final cacheFile = File('${cacheDir.path}/$id.m4a');

      return LockCachingAudioSource(
        Uri.parse(path),
        headers: const {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': 'https://www.youtube.com/',
          'Origin': 'https://www.youtube.com',
        },
        cacheFile: cacheFile,
      );
    }

    if (path != null && await File(path).exists()) {
      return AudioSource.file(path);
    }

    return AudioSource.asset('assets/mock/silence.mp3');
  }
}


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
