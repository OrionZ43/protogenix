// lib/features/importer/domain/youtube_playlist_link.dart
//
// Ссылка на плейлист YouTube — или всё-таки на один ролик?
//
// Просил Elian (2026-09-27): «надеюсь, когда-нибудь добавит возможность
// импортировать сразу плейлисты». Spotify и Яндекс уже импортируются целиком,
// а ссылка YouTube всегда качала одно видео: параметр `list=` не разбирался.
//
// Главная тонкость — `watch?v=…&list=…`. Такую ссылку даёт YouTube, когда
// человек открыл ролик **внутри** плейлиста, и это самый частый вид ссылки
// вообще. Качать по ней весь плейлист нельзя: человек скопировал песню, а
// получил бы триста. Поэтому правило простое и предсказуемое:
//
//   • `youtube.com/playlist?list=…` — плейлист целиком;
//   • всё, где есть ролик (`watch?v=…`, `youtu.be/…`, `shorts/…`) — один
//     ролик, даже если рядом стоит `list=`.

/// Id плейлиста, если ссылка ведёт именно на плейлист. Иначе null.
String? youtubePlaylistId(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme) return null;

  final host = uri.host.toLowerCase();
  if (!host.contains('youtube.com') && !host.contains('youtu.be')) return null;

  final list = uri.queryParameters['list']?.trim();
  if (list == null || list.isEmpty) return null;

  // Ролик указан явно — значит человек хотел его, а не плейлист
  if ((uri.queryParameters['v']?.isNotEmpty ?? false)) return null;

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  // youtu.be/<id>?list=… — id в пути
  if (host.contains('youtu.be') && segments.isNotEmpty) return null;
  if (segments.contains('shorts') || segments.contains('embed')) return null;

  // Остаётся youtube.com/playlist?list=… и youtube.com/?list=…
  if (segments.isNotEmpty && !segments.contains('playlist')) return null;

  return list;
}
