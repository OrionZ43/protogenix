import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../domain/library_track.dart';

class LibraryDatabase {
  LibraryDatabase._();
  static final LibraryDatabase instance = LibraryDatabase._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      join(dbPath, 'protogenix.db'),
      version: 1,
      onCreate: (db, version) {
        return db.execute('''
          CREATE TABLE tracks (
            id         TEXT PRIMARY KEY,
            title      TEXT NOT NULL,
            artist     TEXT NOT NULL,
            album      TEXT NOT NULL,
            filePath   TEXT NOT NULL,
            coverPath  TEXT,
            lrcPath    TEXT,
            durationMs INTEGER NOT NULL,
            source     TEXT NOT NULL,
            addedAt    INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  Future<void> insertTrack(LibraryTrack track) async {
    final database = await db;
    await database.insert(
      'tracks',
      track.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateTrack(LibraryTrack track) async {
    final database = await db;
    await database.update(
      'tracks',
      track.toMap(),
      where: 'id = ?',
      whereArgs: [track.id],
    );
  }

  /// Обновляет только путь к .lrc файлу — без перезаписи всего трека.
  Future<void> updateLrcPath(String id, String lrcPath) async {
    final database = await db;
    await database.update(
      'tracks',
      {'lrcPath': lrcPath},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<LibraryTrack>> getAllTracks() async {
    final database = await db;
    final maps = await database.query('tracks', orderBy: 'addedAt DESC');
    return maps.map(LibraryTrack.fromMap).toList();
  }

  Future<LibraryTrack?> getTrackById(String id) async {
    final database = await db;
    final maps = await database.query(
      'tracks',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return maps.isEmpty ? null : LibraryTrack.fromMap(maps.first);
  }

  Future<void> deleteTrack(String id) async {
    final database = await db;
    await database.delete('tracks', where: 'id = ?', whereArgs: [id]);
  }

  Future<bool> exists(String filePath) async {
    final database = await db;
    final result = await database.query(
      'tracks',
      where: 'filePath = ?',
      whereArgs: [filePath],
      limit: 1,
    );
    return result.isNotEmpty;
  }
}
