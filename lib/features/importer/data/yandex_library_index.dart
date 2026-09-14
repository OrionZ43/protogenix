// lib/features/importer/data/yandex_library_index.dart

import '../../library/domain/library_track.dart';
import 'yandex_music.dart';

/// Какие треки из Яндекса уже есть в медиатеке — без поиска на YouTube.
///
/// Импорт сохраняет трек из Яндекса с его же названием (с версией в скобках),
/// всеми исполнителями и альбомом (`_importYandexCollection`, `data.md`). По
/// этим трём полям повторный импорт узнаёт скачанное сразу. Раньше он искал на
/// YouTube каждый уже скачанный трек, чтобы узнать id ролика: сотня поисков
/// подряд — ровно то, на чём YouTube ограничивает запросы, а «Продолжить»
/// повторял их с начала плейлиста.
///
/// Подходит любой трек медиатеки с теми же тремя полями, в том числе свой
/// файл с такими тегами: это та же песня, качать её незачем. Треки, скачанные
/// до нового подбора записи (`youtube_match.dart`), тоже считаются скачанными —
/// неправильные удаляются руками (`known-issues.md`).
class YandexLibraryIndex {
  YandexLibraryIndex(Iterable<LibraryTrack> library) {
    final addedAt = <String, DateTime>{};
    for (final t in library) {
      final key = _key(t.title, t.artist, t.album);
      final previous = addedAt[key];
      // Две копии (старый и новый подбор записи) — берём свежую
      if (previous != null && !t.addedAt.isAfter(previous)) continue;
      addedAt[key] = t.addedAt;
      _ids[key] = t.id;
    }
  }

  final _ids = <String, String>{};

  /// id трека в медиатеке или null. [album] — то, что импорт пишет в альбом:
  /// альбом трека, а без него название плейлиста.
  String? find(YandexTrack track, {required String album}) {
    // Без исполнителей импорт пишет в исполнителя имя канала YouTube
    if (track.artists.isEmpty) return null;
    return _ids[_key(track.title, track.artists, album)];
  }

  /// Скачан в этом же импорте: повтор трека дальше по плейлисту — без поиска.
  void add(YandexTrack track, {required String album, required String id}) {
    if (track.artists.isEmpty) return;
    _ids[_key(track.title, track.artists, album)] = id;
  }

  // Разделитель — нулевой символ, в названиях его не бывает: через пробел
  // «A B» + «C» и «A» + «B C» дали бы один ключ
  static String _key(String title, String artist, String album) =>
      [title, artist, album].map(_normalize).join('\u0000');

  static String _normalize(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
