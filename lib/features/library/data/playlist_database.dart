// lib/features/library/data/playlist_database.dart
//
// Плейлисты и Избранное.
// Хранит:
//   • playlists  — id, name, createdAt
//   • playlist_tracks — playlistId, trackId, position
//   • favorites  — trackId, addedAt (отдельная таблица = быстрый запрос)

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────────────────────

class Playlist {
  final String id;
  final String name;
  final int    createdAt;

  const Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id':        id,
    'name':      name,
    'createdAt': createdAt,
  };

  static Playlist fromMap(Map<String, dynamic> m) => Playlist(
    id:        m['id'] as String,
    name:      m['name'] as String,
    createdAt: m['createdAt'] as int,
  );

  Playlist copyWith({String? name}) => Playlist(
    id:        id,
    name:      name ?? this.name,
    createdAt: createdAt,
  );
}

class PlaylistTrack {
  final String playlistId;
  final String trackId;
  final int    position;

  const PlaylistTrack({
    required this.playlistId,
    required this.trackId,
    required this.position,
  });

  Map<String, dynamic> toMap() => {
    'playlistId': playlistId,
    'trackId':    trackId,
    'position':   position,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// DATABASE
// ─────────────────────────────────────────────────────────────────────────────

class PlaylistDatabase {
  PlaylistDatabase._();
  static final PlaylistDatabase instance = PlaylistDatabase._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      join(dbPath, 'protogenix_playlists.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE playlists (
            id        TEXT PRIMARY KEY,
            name      TEXT NOT NULL,
            createdAt INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE playlist_tracks (
            playlistId TEXT NOT NULL,
            trackId    TEXT NOT NULL,
            position   INTEGER NOT NULL,
            PRIMARY KEY (playlistId, trackId),
            FOREIGN KEY (playlistId) REFERENCES playlists(id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE favorites (
            trackId TEXT PRIMARY KEY,
            addedAt INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  // ── Плейлисты ──────────────────────────────────────────────────────────────

  Future<Playlist> createPlaylist(String name) async {
    final database = await db;
    final playlist = Playlist(
      id:        '${DateTime.now().millisecondsSinceEpoch}_${name.hashCode}',
      name:      name,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await database.insert('playlists', playlist.toMap());
    return playlist;
  }

  Future<void> renamePlaylist(String id, String newName) async {
    final database = await db;
    await database.update(
      'playlists',
      {'name': newName},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deletePlaylist(String id) async {
    final database = await db;
    await database.delete('playlists', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Playlist>> getAllPlaylists() async {
    final database = await db;
    final maps = await database.query('playlists', orderBy: 'createdAt DESC');
    return maps.map(Playlist.fromMap).toList();
  }

  // ── Треки в плейлисте ──────────────────────────────────────────────────────

  Future<void> addTrackToPlaylist({
    required String playlistId,
    required String trackId,
  }) async {
    final database = await db;
    // Считаем текущую позицию
    final count = Sqflite.firstIntValue(await database.rawQuery(
      'SELECT COUNT(*) FROM playlist_tracks WHERE playlistId = ?',
      [playlistId],
    )) ?? 0;

    await database.insert(
      'playlist_tracks',
      PlaylistTrack(
        playlistId: playlistId,
        trackId:    trackId,
        position:   count,
      ).toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removeTrackFromPlaylist({
    required String playlistId,
    required String trackId,
  }) async {
    final database = await db;
    await database.delete(
      'playlist_tracks',
      where: 'playlistId = ? AND trackId = ?',
      whereArgs: [playlistId, trackId],
    );
  }

  Future<List<String>> getTrackIdsForPlaylist(String playlistId) async {
    final database = await db;
    final maps = await database.query(
      'playlist_tracks',
      where:   'playlistId = ?',
      whereArgs: [playlistId],
      orderBy: 'position ASC',
    );
    return maps.map((m) => m['trackId'] as String).toList();
  }

  Future<bool> isTrackInPlaylist({
    required String playlistId,
    required String trackId,
  }) async {
    final database = await db;
    final result = await database.query(
      'playlist_tracks',
      where: 'playlistId = ? AND trackId = ?',
      whereArgs: [playlistId, trackId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  // ── Избранное ──────────────────────────────────────────────────────────────

  Future<void> addToFavorites(String trackId) async {
    final database = await db;
    await database.insert(
      'favorites',
      {
        'trackId': trackId,
        'addedAt': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removeFromFavorites(String trackId) async {
    final database = await db;
    await database.delete('favorites', where: 'trackId = ?', whereArgs: [trackId]);
  }

  Future<bool> isFavorite(String trackId) async {
    final database = await db;
    final result = await database.query(
      'favorites',
      where: 'trackId = ?',
      whereArgs: [trackId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<List<String>> getFavoriteTrackIds() async {
    final database = await db;
    final maps = await database.query('favorites', orderBy: 'addedAt DESC');
    return maps.map((m) => m['trackId'] as String).toList();
  }

  Future<void> toggleFavorite(String trackId) async {
    final fav = await isFavorite(trackId);
    if (fav) {
      await removeFromFavorites(trackId);
    } else {
      await addToFavorites(trackId);
    }
  }
}