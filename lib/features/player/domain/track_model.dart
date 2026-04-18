import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class TrackModel {
  final String        id;
  final String        title;
  final String        artist;
  final String        album;
  final Duration      duration;
  final ImageProvider coverImage;
  final String?       filePath;
  final String?       lrcPath;

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

  AudioSource toAudioSource() {
    if (filePath != null) {
      return AudioSource.file(filePath!);
    }
    return AudioSource.asset('assets/mock/silence.mp3');
  }
}

// Мок только для UI-разработки — больше не используется в продакшене
const mockTrack = TrackModel(
  id:         'mock_001',
  title:      'Midnight Protocol',
  artist:     'Neon Circuits',
  album:      'Protogenix OST',
  duration:   Duration(minutes: 4, seconds: 32),
  coverImage: AssetImage('assets/images/mock_cover.jpg'),
);

final mockPlaylist = <TrackModel>[];