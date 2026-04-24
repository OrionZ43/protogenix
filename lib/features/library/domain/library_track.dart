import 'dart:io';
import 'package:flutter/material.dart';
import '../../player/domain/track_model.dart';

class LibraryTrack {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String filePath;
  final String? coverPath;
  final String? lrcPath;
  final int durationMs;
  final String source;
  final DateTime addedAt;

  const LibraryTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.filePath,
    this.coverPath,
    this.lrcPath,
    required this.durationMs,
    required this.source,
    required this.addedAt,
  });

  Duration get duration => Duration(milliseconds: durationMs);

  /// Конвертация в TrackModel для плеера
  TrackModel toTrackModel() {
    return TrackModel(
      id: id,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      coverImage: coverPath != null
          ? FileImage(File(coverPath!))
          : const AssetImage('assets/images/mock_cover.jpg') as ImageProvider,
      filePath: filePath,
      lrcPath: lrcPath,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'filePath': filePath,
        'coverPath': coverPath,
        'lrcPath': lrcPath,
        'durationMs': durationMs,
        'source': source,
        'addedAt': addedAt.millisecondsSinceEpoch,
      };

  factory LibraryTrack.fromMap(Map<String, dynamic> map) => LibraryTrack(
        id: map['id'] as String,
        title: map['title'] as String,
        artist: map['artist'] as String,
        album: map['album'] as String,
        filePath: map['filePath'] as String,
        coverPath: map['coverPath'] as String?,
        lrcPath: map['lrcPath'] as String?,
        durationMs: map['durationMs'] as int,
        source: map['source'] as String,
        addedAt: DateTime.fromMillisecondsSinceEpoch(map['addedAt'] as int),
      );
}
