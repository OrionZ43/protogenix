// lib/features/importer/data/local_tags_migration.dart
//
// Один раз после обновления: у своих файлов, добавленных до того, как импорт
// научился читать теги (до 1.1), теги перечитываются. Трогаются только треки,
// которые явно не правили руками: исполнитель «Unknown Artist», альбом
// «Local Import» и название, совпадающее с именем скопированного файла, —
// ровно так их записывал старый импорт.

import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../core/services/app_paths.dart';
import '../../../core/services/app_settings_store.dart';
import '../../library/data/library_database.dart';
import '../../library/domain/library_track.dart';
import 'local_tags.dart';

class LocalTagsMigration {
  LocalTagsMigration._();

  static const _doneKey = 'localTagsReread';

  /// Старый импорт копировал файл под именем, где всё, кроме латиницы, цифр
  /// и `.-_`, заменено на `_`.
  static final _unsafe = RegExp(r'[^a-zA-Z0-9\.\-\_]');

  /// Из main() — после AppPaths.init и до загрузки плеера, чтобы очередь
  /// сразу получила новые названия. Ошибка запуску не мешает: треки просто
  /// остаются как были, а попытка повторится при следующем запуске.
  static Future<void> runOnce() async {
    final settings = AppSettingsStore();
    try {
      if (await settings.get<bool>(_doneKey) == true) return;
      final tracks = await LibraryDatabase.instance.getAllTracks();
      final candidates = tracks.where(needsReread).toList();
      if (candidates.isNotEmpty) {
        final jobs = [
          for (final track in candidates) (id: track.id, path: track.filePath),
        ];
        final coversDir = AppPaths.coversDir;
        final read = await Isolate.run(() => _readAll(jobs, coversDir));
        var updated = 0;
        for (final track in candidates) {
          final result = read[track.id];
          if (result == null) continue;
          final retagged =
              retag(track, result.tags, coverPath: result.coverPath);
          if (retagged == null) continue;
          await LibraryDatabase.instance.updateTrack(retagged);
          updated++;
        }
        debugPrint('[Tags] Перечитаны теги: $updated из ${candidates.length}');
      }
      await settings.set(_doneKey, true);
    } catch (e) {
      debugPrint('[Tags] Не удалось перечитать теги: $e');
    }
  }

  /// Трек старого импорта, который не правили руками.
  static bool needsReread(LibraryTrack track) =>
      track.source == 'local' &&
      track.artist == 'Unknown Artist' &&
      track.album == 'Local Import' &&
      track.title.replaceAll(_unsafe, '_') ==
          p.basenameWithoutExtension(track.filePath);

  /// Трек с данными из тегов, а без них — с «Артист - Название» из имени
  /// файла. null — менять нечего.
  static LibraryTrack? retag(
    LibraryTrack track,
    LocalTags tags, {
    String? coverPath,
  }) {
    final (nameArtist, nameTitle) = splitArtistTitle(track.title);
    final title = tags.title ?? nameTitle;
    final artist = tags.artist ?? nameArtist ?? track.artist;
    final album = tags.album ?? track.album;
    final durationMs = tags.duration?.inMilliseconds ?? track.durationMs;
    final cover = coverPath ?? track.coverPath;
    if (title == track.title &&
        artist == track.artist &&
        album == track.album &&
        durationMs == track.durationMs &&
        cover == track.coverPath) {
      return null;
    }
    return track.copyWith(
      title: title,
      artist: artist,
      album: album,
      durationMs: durationMs,
      coverPath: cover,
    );
  }

  /// В изоляте: теги каждого файла и встроенная обложка — сразу на диск,
  /// чтобы не гонять картинки между изолятами.
  static Map<String, ({LocalTags tags, String? coverPath})> _readAll(
    List<({String id, String path})> jobs,
    String coversDir,
  ) {
    final results = <String, ({LocalTags tags, String? coverPath})>{};
    for (final job in jobs) {
      if (!File(job.path).existsSync()) continue;
      final tags = readLocalTagsSync(job.path);
      String? coverPath;
      final cover = tags.cover;
      if (cover != null) {
        try {
          Directory(coversDir).createSync(recursive: true);
          final ext = tags.coverMime == 'image/png' ? 'png' : 'jpg';
          final path =
              p.join(coversDir, '${job.id.replaceAll(_unsafe, '_')}.$ext');
          File(path).writeAsBytesSync(cover, flush: true);
          coverPath = path;
        } catch (_) {
          // Без обложки — не повод терять остальные теги
        }
      }
      results[job.id] = (
        tags: LocalTags(
          title: tags.title,
          artist: tags.artist,
          album: tags.album,
          duration: tags.duration,
        ),
        coverPath: coverPath,
      );
    }
    return results;
  }
}
