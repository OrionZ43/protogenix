// lib/features/library/domain/track_duplicates.dart
//
// Тот же трек уже есть в медиатеке?
//
// Просил Elian (2026-09-27): «чтобы приложение не разрешало добавить 2
// одинаковых трека, достаточно проверять название и автора». Решение Orion —
// **спрашивать**, а не пропускать молча: у одной песни бывают законные
// варианты (студия, live, ремикс, другой битрейт), и по названию с
// исполнителем они неотличимы.
//
// Чем это отличается от `ImportedTracksIndex` (importer/data): тот сравнивает
// **с альбомом** и нужен, чтобы при повторном импорте плейлиста не искать на
// YouTube уже скачанное. Здесь альбом не сравнивается: один и тот же трек
// приходит из сингла, из альбома и из плейлиста с разным полем «альбом», и
// для пользователя это один и тот же трек.
//
// Сравнение намеренно строгое — без транслита и без похожести. Ошибиться
// в другую сторону дешевле: лишний вопрос человек закроет, а вот не
// предложенный вариант песни он не получит никак.

import 'library_track.dart';

/// Трек медиатеки с тем же названием и исполнителем, или null.
///
/// [artist] — строка исполнителей как её пишет импорт: «A, B».
LibraryTrack? findDuplicate(
  Iterable<LibraryTrack> library, {
  required String title,
  required String artist,
}) {
  final wantedTitle = normalizeForDuplicates(title);
  final wantedArtist = normalizeForDuplicates(artist);
  if (wantedTitle.isEmpty) return null;

  for (final track in library) {
    if (normalizeForDuplicates(track.title) != wantedTitle) continue;
    final existing = normalizeForDuplicates(track.artist);
    // Исполнитель неизвестен с одной из сторон — считаем совпадением: у своих
    // файлов без тегов это «Unknown Artist», и второй раз тот же файл
    // спросить всё равно надо
    if (existing.isEmpty || wantedArtist.isEmpty) return track;
    if (existing == wantedArtist) return track;
  }
  return null;
}

/// Приведение к виду для сравнения: регистр, пробелы и «ё».
String normalizeForDuplicates(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'\s+'), ' ');
