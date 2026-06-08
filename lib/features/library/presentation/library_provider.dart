// lib/features/library/presentation/library_provider.dart

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/library_database.dart';
import '../domain/library_track.dart';

class LibraryNotifier extends StateNotifier<List<LibraryTrack>> {
  LibraryNotifier() : super([]) {
    reload();
  }

  Future<void> reload() async {
    final tracks = await LibraryDatabase.instance.getAllTracks();
    state = tracks;
  }

  // ── Удалить трек + физические файлы с диска ──────────────────────────────

  Future<void> removeTrackWithFiles(LibraryTrack track) async {
    // 1. Удаляем из БД
    await LibraryDatabase.instance.deleteTrack(track.id);

    // 2. Удаляем аудиофайл
    try {
      final audio = File(track.filePath);
      if (await audio.exists()) await audio.delete();
    } catch (e) {
      debugPrint('[Library] Не удалось удалить аудиофайл: $e');
    }

    // 3. Удаляем .lrc файл (если он был сохранён в app-директории)
    if (track.lrcPath != null) {
      try {
        final lrc = File(track.lrcPath!);
        if (await lrc.exists()) await lrc.delete();
      } catch (e) {
        debugPrint('[Library] Не удалось удалить .lrc файл: $e');
      }
    }

    // 4. Обновляем стейт мгновенно
    state = state.where((t) => t.id != track.id).toList();
  }

  // ── Устаревший метод без удаления файлов (для обратной совместимости) ────

  Future<void> removeTrack(String id) async {
    await LibraryDatabase.instance.deleteTrack(id);
    state = state.where((t) => t.id != id).toList();
  }

  // ── Обновить путь к тексту после ручного выбора ──────────────────────────

  Future<void> updateLrcPath(String trackId, String lrcPath) async {
    await LibraryDatabase.instance.updateLrcPath(trackId, lrcPath);

    // Обновляем объект в стейте без перезагрузки всего списка
    state = state.map((t) {
      if (t.id != trackId) return t;
      return LibraryTrack(
        id: t.id,
        title: t.title,
        artist: t.artist,
        album: t.album,
        filePath: t.filePath,
        coverPath: t.coverPath,
        lrcPath: lrcPath,
        durationMs: t.durationMs,
        source: t.source,
        addedAt: t.addedAt,
      );
    }).toList();
  }
}

enum LibrarySortMode { dateAdded, title, artist, duration }

final librarySortModeProvider =
    StateProvider<LibrarySortMode>((ref) => LibrarySortMode.dateAdded);

final libraryProvider =
    StateNotifierProvider<LibraryNotifier, List<LibraryTrack>>((ref) {
  return LibraryNotifier();
});
