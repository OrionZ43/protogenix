// lib/features/library/presentation/playlist_provider.dart
//
// Riverpod-провайдеры для плейлистов и избранного.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/playlist_database.dart';
import '../data/library_database.dart';
import '../domain/library_track.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ПЛЕЙЛИСТЫ
// ─────────────────────────────────────────────────────────────────────────────

class PlaylistsNotifier extends StateNotifier<List<Playlist>> {
  PlaylistsNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    try {
      state = await PlaylistDatabase.instance.getAllPlaylists();
    } catch (e) {
      debugPrint('PlaylistsNotifier._load: $e');
    }
  }

  Future<Playlist> create(String name) async {
    final pl = await PlaylistDatabase.instance.createPlaylist(name);
    state = [pl, ...state];
    return pl;
  }

  Future<void> rename(String id, String newName) async {
    await PlaylistDatabase.instance.renamePlaylist(id, newName);
    state =
        state.map((p) => p.id == id ? p.copyWith(name: newName) : p).toList();
  }

  Future<void> delete(String id) async {
    await PlaylistDatabase.instance.deletePlaylist(id);
    state = state.where((p) => p.id != id).toList();
  }

  Future<void> reload() => _load();
}

final playlistsProvider =
    StateNotifierProvider<PlaylistsNotifier, List<Playlist>>((ref) {
  return PlaylistsNotifier();
});

// ─────────────────────────────────────────────────────────────────────────────
// ТРЕКИ ПЛЕЙЛИСТА
// ─────────────────────────────────────────────────────────────────────────────

/// Треки конкретного плейлиста (как полные LibraryTrack объекты)
final playlistTracksProvider =
    FutureProvider.family<List<LibraryTrack>, String>(
  (ref, playlistId) async {
    final ids =
        await PlaylistDatabase.instance.getTrackIdsForPlaylist(playlistId);
    final db = LibraryDatabase.instance;
    final result = <LibraryTrack>[];

    for (final id in ids) {
      // Получаем трек из библиотеки по id
      final tracks = await db.getAllTracks();
      final match = tracks.where((t) => t.id == id).toList();
      if (match.isNotEmpty) result.add(match.first);
    }
    return result;
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// ИЗБРАННОЕ
// ─────────────────────────────────────────────────────────────────────────────

class FavoritesNotifier extends StateNotifier<Set<String>> {
  FavoritesNotifier() : super({}) {
    _load();
  }

  Future<void> _load() async {
    try {
      final ids = await PlaylistDatabase.instance.getFavoriteTrackIds();
      state = ids.toSet();
    } catch (e) {
      debugPrint('FavoritesNotifier._load: $e');
    }
  }

  Future<void> toggle(String trackId) async {
    await PlaylistDatabase.instance.toggleFavorite(trackId);
    if (state.contains(trackId)) {
      state = {...state}..remove(trackId);
    } else {
      state = {...state, trackId};
    }
  }

  bool isFavorite(String trackId) => state.contains(trackId);
}

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, Set<String>>((ref) {
  return FavoritesNotifier();
});

/// Удобный провайдер для одного трека
final isFavoriteProvider = Provider.family<bool, String>((ref, trackId) {
  return ref.watch(favoritesProvider).contains(trackId);
});
