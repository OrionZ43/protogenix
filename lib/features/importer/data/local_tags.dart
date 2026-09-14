// lib/features/importer/data/local_tags.dart
//
// Свои файлы при импорте: теги (название, исполнитель, альбом, длительность,
// встроенная обложка) и id трека. До 1.0.1 теги не читались совсем: название
// бралось из имени файла, исполнитель — «Unknown Artist», длительность 0
// (а по ней ищется текст). Чтение — audio_metadata_reader: чистый Dart, без
// нативной сборки (почему это важно — dependencies.md, история с audiotags).

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';

/// Форматы своих файлов, которые принимает импорт (в нижнем регистре).
/// Все их играют и ExoPlayer на Android, и mpv на ПК.
const kLocalAudioExtensions = [
  '.mp3',
  '.m4a',
  '.mp4',
  '.aac',
  '.flac',
  '.ogg',
  '.opus',
  '.wav',
];

class LocalTags {
  const LocalTags({
    this.title,
    this.artist,
    this.album,
    this.duration,
    this.cover,
    this.coverMime,
  });

  final String? title;
  final String? artist;
  final String? album;
  final Duration? duration;
  final Uint8List? cover;
  final String? coverMime;

  static const empty = LocalTags();
}

/// Теги файла. Разбор — в отдельном изоляте: библиотека синхронная, а файлов
/// за раз бывают сотни. Любая ошибка разбора — пустые теги, импорт идёт по
/// имени файла.
Future<LocalTags> readLocalTags(String path) =>
    Isolate.run(() => readLocalTagsSync(path));

LocalTags readLocalTagsSync(String path) {
  try {
    final meta = readMetadata(File(path), getImage: true);
    Picture? picture;
    for (final candidate in meta.pictures) {
      if (candidate.bytes.isNotEmpty) {
        picture = candidate;
        break;
      }
    }
    final duration = meta.duration;
    return LocalTags(
      title: _clean(meta.title),
      artist: _clean(meta.artist) ?? _clean(meta.albumArtist),
      album: _clean(meta.album),
      duration:
          duration == null || duration <= Duration.zero ? null : duration,
      cover: picture?.bytes,
      coverMime: picture?.mimetype,
    );
  } catch (_) {
    return LocalTags.empty;
  }
}

/// Управляющие символы убираются (как в именах плейлистов, security.md п. 4),
/// пустая строка — «тега нет».
String? _clean(String? value) {
  final cleaned =
      value?.replaceAll(RegExp(r'[\x00-\x1F\x7F-\x9F]'), '').trim();
  return cleaned == null || cleaned.isEmpty ? null : cleaned;
}

/// «Артист - Название» из имени файла, когда в тегах пусто. Номер трека
/// («01 - Intro») за артиста не считается.
(String?, String) splitArtistTitle(String baseName) {
  final dash = baseName.indexOf(' - ');
  if (dash <= 0) return (null, baseName);
  final artist = baseName.substring(0, dash).trim();
  final title = baseName.substring(dash + 3).trim();
  if (title.isEmpty || RegExp(r'^\d+$').hasMatch(artist)) {
    return (null, baseName);
  }
  return (artist, title);
}

/// id своего трека по содержимому: размер и первые 64 КБ. Тот же файл,
/// выбранный повторно, даёт тот же id, даже если путь другой, а разные файлы
/// с одинаковыми именами — разные.
Future<String> localTrackId(File file) async {
  final length = await file.length();
  final raf = await file.open();
  try {
    final head = await raf.read(64 * 1024);
    final digest = sha1.convert([...utf8.encode('$length:'), ...head]);
    return 'local_${digest.toString().substring(0, 16)}';
  } finally {
    await raf.close();
  }
}

/// Аудиофайлы из путей, брошенных в окно: файлы — по расширению
/// ([kLocalAudioExtensions], регистр не важен), папки — целиком, со
/// вложенными. Папку без доступа пропускаем, а не роняем весь импорт.
Future<List<String>> collectAudioFiles(List<String> paths) async {
  bool isAudio(String path) =>
      kLocalAudioExtensions.any((ext) => path.toLowerCase().endsWith(ext));
  final result = <String>[];
  for (final path in paths) {
    if (await FileSystemEntity.isDirectory(path)) {
      try {
        await for (final entity
            in Directory(path).list(recursive: true, followLinks: false)) {
          if (entity is File && isAudio(entity.path)) result.add(entity.path);
        }
      } catch (_) {
        // Нет доступа к части папки — берём то, что успели найти
      }
    } else if (isAudio(path)) {
      result.add(path);
    }
  }
  return result;
}
