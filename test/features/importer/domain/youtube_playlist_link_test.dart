import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/importer/domain/youtube_playlist_link.dart';

// Самое важное здесь — не начать качать триста треков там, где человек
// скопировал одну песню: `watch?v=…&list=…` YouTube даёт, когда ролик открыт
// внутри плейлиста, и это самый частый вид ссылки.

void main() {
  test('ссылка на сам плейлист', () {
    expect(
      youtubePlaylistId('https://www.youtube.com/playlist?list=PLabc123'),
      'PLabc123',
    );
    expect(
      youtubePlaylistId('https://m.youtube.com/playlist?list=PLabc123&si=x'),
      'PLabc123',
    );
  });

  test('ролик внутри плейлиста — это ролик, а не плейлист', () {
    expect(
      youtubePlaylistId(
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLabc123'),
      isNull,
    );
    expect(
      youtubePlaylistId('https://youtu.be/dQw4w9WgXcQ?list=PLabc123'),
      isNull,
    );
    expect(
      youtubePlaylistId('https://www.youtube.com/shorts/abc?list=PLabc123'),
      isNull,
    );
  });

  test('без list= плейлиста нет', () {
    expect(youtubePlaylistId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        isNull);
    expect(youtubePlaylistId('https://www.youtube.com/playlist'), isNull);
    expect(youtubePlaylistId('https://www.youtube.com/playlist?list='), isNull);
  });

  test('чужие ссылки и мусор', () {
    expect(youtubePlaylistId('https://open.spotify.com/playlist/37i9dQ'), isNull);
    expect(youtubePlaylistId('не ссылка вовсе'), isNull);
    expect(youtubePlaylistId(''), isNull);
  });

  test('миксы и радио — тоже плейлист, качать по кнопке «Остановить»', () {
    expect(
      youtubePlaylistId('https://www.youtube.com/playlist?list=RDabc'),
      'RDabc',
    );
  });
}
