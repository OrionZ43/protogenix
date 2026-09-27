// lib/features/importer/domain/youtube_title.dart
//
// Заголовок ролика YouTube в название трека.
//
// Убираем то, что к песне не относится: [Electro], [Monstercat Release],
// (Official Video), (Lyrics), (Audio), (HD).
//
// **И обязательно подчищаем края.** У Monstercat заголовки вида
// «[Electro] - Nitro Fun - New Game [Monstercat Release]»: скобки уходят, а
// тире в начале остаётся, и в медиатеке появляется «- Nitro Fun - New Game»
// (отзыв Orion 2026-09-27, видно на импорте плейлиста).
//
// Разбором «Артист - Название» здесь не занимаемся: этим ведает
// `track_query.dart`, и на нём держится подбор текстов (`lyrics.md`).

/// Название трека из заголовка ролика.
String cleanYoutubeTitle(String title) {
  var clean = title
      .replaceAll(RegExp(r'\(Official.*?\)', caseSensitive: false), '')
      .replaceAll(RegExp(r'\[.*?\]'), '')
      .replaceAll(RegExp(r'\(Lyrics.*?\)', caseSensitive: false), '')
      .replaceAll(RegExp(r'\(Audio.*?\)', caseSensitive: false), '')
      .replaceAll(RegExp(r'\(HD.*?\)', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();

  // Края: тире, дефисы, точки и запятые, оставшиеся от вырезанных скобок
  clean = clean
      .replaceAll(RegExp(r'^[\s\-–—•·,.|]+'), '')
      .replaceAll(RegExp(r'[\s\-–—•·,|]+$'), '')
      .trim();

  // Всё оказалось мусором — лучше исходный заголовок, чем пустая строка
  return clean.isEmpty ? title.trim() : clean;
}
