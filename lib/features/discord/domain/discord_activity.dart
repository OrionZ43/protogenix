// lib/features/discord/domain/discord_activity.dart
//
// Статус «Слушает…» для Discord из играющего трека — только данные, без
// канала и плеера, поэтому проверяется тестами. Без Flutter-импортов.

import '../../listen/domain/listen_link.dart';

final _youtubeId = RegExp(r'^[A-Za-z0-9_-]{11}$');

/// Картинка приложения в Discord Developer Portal: Rich Presence → Art Assets.
const kDiscordLogoAsset = 'logo';

/// Текст для полей статуса: от 2 до 128 символов, иначе Discord не примет.
String discordText(String text, {String fallback = 'Protogenix'}) {
  var runes = text.replaceAll(RegExp(r'\s+'), ' ').trim().runes.toList();
  if (runes.isEmpty) runes = fallback.runes.toList();
  if (runes.length > 128) {
    return '${String.fromCharCodes(runes.take(127))}…';
  }
  final value = String.fromCharCodes(runes);
  // Один символ Discord не принимает — дописываем невидимый пробел
  return runes.length < 2 ? '$value${String.fromCharCode(0x200B)}' : value;
}

/// Статус трека. [start] — когда трек начался бы без пауз и перемоток
/// («сейчас минус позиция»): по нему Discord сам рисует полосу прогресса.
Map<String, dynamic> discordListeningActivity({
  required String trackId,
  required String title,
  required String artist,
  required String album,
  required DateTime start,
  required Duration duration,
}) {
  final youtube = _youtubeId.hasMatch(trackId);
  return {
    'type': 2, // «Слушает»
    // В списке участников — название трека, как у Spotify, а не имя
    // приложения
    'status_display_type': 2,
    'details': discordText(title, fallback: 'Без названия'),
    'state': discordText(artist, fallback: 'Неизвестный исполнитель'),
    if (duration > Duration.zero)
      'timestamps': {
        'start': start.millisecondsSinceEpoch,
        'end': start.add(duration).millisecondsSinceEpoch,
      },
    'assets': {
      // Обложки своих файлов лежат на диске, а Discord берёт картинку только
      // по ссылке — у них значок приложения. mqdefault — кадр 16:9 без
      // чёрных полос; Discord режет его в квадрат по центру, и у роликов
      // «Артист - Topic» там как раз обложка альбома
      'large_image': youtube
          ? 'https://i.ytimg.com/vi/$trackId/mqdefault.jpg'
          : kDiscordLogoAsset,
      'large_text': discordText(album),
      if (youtube) 'small_image': kDiscordLogoAsset,
      if (youtube) 'small_text': 'Protogenix',
    },
    // «Слушать в Protogenix»: страница сайта откроет приложение, а у кого
    // его нет — предложит скачать (listen_link.dart). Кнопку видят другие,
    // сам себе Discord её не показывает
    'buttons': [
      {
        'label': 'Слушать в Protogenix',
        'url': ListenLink.webUrl(
          videoId: youtube ? trackId : null,
          title: title,
          artist: artist,
          duration: duration,
        ),
      },
    ],
  };
}
