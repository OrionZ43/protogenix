// lib/features/listen/domain/listen_link.dart
//
// «Слушать в Protogenix»: ссылка на трек, который слушает друг. Кнопка в
// статусе Discord ведёт на страницу сайта (Discord пускает в кнопки только
// https), страница открывает приложение по protogenix://listen?… с теми же
// полями:
//   v — id ролика YouTube (11 символов), если трек оттуда;
//   t, a — название и исполнитель (у своих файлов по ним ищется запись);
//   d — длительность в секундах, для подбора записи.
//
// Такую ссылку может открыть любой сайт, поэтому разбор строгий: только эти
// поля, id — по формату, текст — без управляющих символов и не длиннее 200
// символов; адресов в ссылке нет и быть не может. Перед скачиванием
// приложение всё равно спрашивает (listen_links.dart). Без Flutter-импортов.

const kListenHost = 'z43-studios.vercel.app';
const kListenPath = '/listen';

final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');

class ListenLink {
  const ListenLink({
    this.videoId,
    this.title = '',
    this.artist = '',
    this.duration,
  });

  final String? videoId;
  final String title;
  final String artist;
  final Duration? duration;

  /// «Название» — Исполнитель, для вопроса перед скачиванием.
  String get label {
    if (title.isEmpty) return 'Трек с YouTube';
    return artist.isEmpty ? '«$title»' : '«$title» — $artist';
  }

  /// null — это не наша ссылка или в ней нет трека.
  static ListenLink? parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    final app = uri.scheme == 'protogenix' && uri.host == 'listen';
    final web = uri.scheme == 'https' &&
        uri.host == kListenHost &&
        uri.path == kListenPath;
    if (!app && !web) return null;

    final query = uri.queryParameters;
    final v = query['v'];
    final videoId = v != null && _videoId.hasMatch(v) ? v : null;
    final title = _text(query['t']);
    final artist = _text(query['a']);
    final seconds = int.tryParse(query['d'] ?? '');
    // Без ролика искать можно только по названию
    if (videoId == null && title.isEmpty) return null;
    return ListenLink(
      videoId: videoId,
      title: title,
      artist: artist,
      duration: seconds != null && seconds > 0 && seconds < 36000
          ? Duration(seconds: seconds)
          : null,
    );
  }

  /// Страница на сайте — для кнопки в Discord: не длиннее 512 символов, иначе
  /// Discord кнопку не примет. Длинные название и исполнитель укорачиваются.
  static String webUrl({
    String? videoId,
    required String title,
    required String artist,
    Duration? duration,
  }) {
    final id = videoId != null && _videoId.hasMatch(videoId) ? videoId : null;
    for (final limit in const [120, 60, 30, 0]) {
      final url = Uri.https(kListenHost, kListenPath, {
        if (id != null) 'v': id,
        if (limit > 0 && title.isNotEmpty) 't': _cut(title, limit),
        if (limit > 0 && artist.isNotEmpty) 'a': _cut(artist, limit),
        if (duration != null && duration > Duration.zero)
          'd': '${duration.inSeconds}',
      }).toString();
      if (url.length <= 512) return url;
    }
    return Uri.https(kListenHost, kListenPath).toString();
  }

  static String _text(String? value) {
    if (value == null) return '';
    // Управляющие символы (0–31 и 127–159) — вон
    final clean = String.fromCharCodes(value.runes
        .where((r) => r >= 0x20 && (r < 0x7F || r > 0x9F)));
    return _cut(clean.trim(), 200);
  }

  static String _cut(String text, int limit) {
    final runes = text.runes.toList();
    return runes.length <= limit
        ? text
        : String.fromCharCodes(runes.take(limit));
  }
}
