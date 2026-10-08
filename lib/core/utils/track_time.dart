// lib/core/utils/track_time.dart
//
// Длительность и позиция трека для подписи: «03:33», а от часа — «2:00:00».
//
// Раньше у медиатеки и у волны в плеере был свой формат с минутами по модулю
// 60, и часы просто терялись: двухчасовой сборник показывался как «00:00», а
// позиция после часа начиналась заново. Пока длина длинных MP3 считалась
// неверно (`mp3_duration.dart`), до часа они и не дотягивали — поэтому этого
// никто не видел.

String formatTrackTime(Duration d) {
  final total = d.isNegative ? 0 : d.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total ~/ 60) % 60;
  final seconds = total % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${two(minutes)}:${two(seconds)}'
      : '${two(minutes)}:${two(seconds)}';
}
