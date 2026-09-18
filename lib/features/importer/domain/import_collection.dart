// lib/features/importer/domain/import_collection.dart
//
// Что импортируем: альбом, плейлист или отдельный трек. Откуда — Яндекс
// Музыка (data/yandex_music.dart) или Spotify (data/spotify_page.dart); сам
// импорт общий (ImporterService): треки ищутся и качаются с YouTube, а
// альбом или плейлист становится плейлистом медиатеки.

class ImportTrack {
  const ImportTrack({
    required this.title,
    required this.artists,
    this.durationMs,
    this.coverUrl,
    this.album,
  });

  /// Название с версией в скобках: «Song (Remastered 2011)» — так его
  /// разбирает подбор ролика (youtube_match.dart).
  final String title;

  /// Исполнители через «, ».
  final String artists;

  final int? durationMs;
  final String? coverUrl;

  /// Альбом; нет — вместо него берётся название коллекции.
  final String? album;
}

class ImportCollection {
  const ImportCollection({
    required this.title,
    required this.tracks,
    required this.sourceName,
    this.isSingleTrack = false,
    this.unavailable = 0,
    this.note,
  });

  /// Название альбома или плейлиста; у отдельного трека — его название.
  final String title;

  final List<ImportTrack> tracks;

  /// Откуда это — для строки «недоступны в самом …»: «Яндексе», «Spotify».
  final String sourceName;

  final bool isSingleTrack;

  /// Треков нет в самом источнике: удалены или недоступны в регионе.
  final int unavailable;

  /// Строка в итог импорта — например, что Spotify без входа отдал не весь
  /// плейлист.
  final String? note;

  ImportCollection withNote(String note) => ImportCollection(
        title: title,
        tracks: tracks,
        sourceName: sourceName,
        isSingleTrack: isSingleTrack,
        unavailable: unavailable,
        note: note,
      );
}
