import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/core/services/app_paths.dart';
import 'package:protogenix/features/library/data/playlist_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// База — во временной папке, не в данных приложения (known-issues.md, «Тесты»).
void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppPaths.databasesDir =
        (await Directory.systemTemp.createTemp('protogenix_playlists_')).path;
  });

  test('несколько треков разом: дубли пропускаются, порядок сохраняется',
      () async {
    final db = PlaylistDatabase.instance;
    final playlist = await db.createPlaylist('Треки со Спотифая');

    expect(
      await db.addTracksToPlaylist(
          playlistId: playlist.id, trackIds: ['a', 'b', 'a']),
      2,
    );
    expect(
      await db.addTracksToPlaylist(playlistId: playlist.id, trackIds: ['b', 'c']),
      1,
    );
    expect(await db.getTrackIdsForPlaylist(playlist.id), ['a', 'b', 'c']);
  });

  test('плейлист находится по имени после той же очистки', () async {
    final db = PlaylistDatabase.instance;
    final playlist = await db.createPlaylist('  Мой плейлист из Яндекса  ');
    expect((await db.findPlaylistByName('Мой плейлист из Яндекса'))?.id,
        playlist.id);
    expect(await db.findPlaylistByName('Другой плейлист'), isNull);
  });
}
