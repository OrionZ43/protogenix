import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/discord/domain/discord_activity.dart';

void main() {
  final start = DateTime.utc(2026, 9, 14, 12);
  const length = Duration(minutes: 3, seconds: 24);

  Map<String, dynamic> activity(String id) => discordListeningActivity(
        trackId: id,
        title: 'Believer',
        artist: 'Imagine Dragons',
        album: 'Evolve',
        start: start,
        duration: length,
      );

  test('«Слушает»: название, исполнитель и полоса времени', () {
    final a = activity('7wtfhZwyrcc');
    expect(a['type'], 2);
    expect(a['details'], 'Believer');
    expect(a['state'], 'Imagine Dragons');
    expect(a['timestamps'], {
      'start': start.millisecondsSinceEpoch,
      'end': start.add(length).millisecondsSinceEpoch,
    });
  });

  test('трек с YouTube — кадр ролика, свой файл — значок приложения', () {
    final youtube = activity('7wtfhZwyrcc')['assets'] as Map;
    expect(youtube['large_image'],
        'https://i.ytimg.com/vi/7wtfhZwyrcc/mqdefault.jpg');
    expect(youtube['small_image'], kDiscordLogoAsset);

    final local = activity('local_0123456789abcdef')['assets'] as Map;
    expect(local['large_image'], kDiscordLogoAsset);
    expect(local.containsKey('small_image'), isFalse);
  });

  test('кнопка «Слушать в Protogenix» ведёт на страницу сайта', () {
    final button = (activity('7wtfhZwyrcc')['buttons'] as List).single as Map;
    expect(button['label'], 'Слушать в Protogenix');
    expect(button['url'],
        'https://z43-studios.vercel.app/listen?v=7wtfhZwyrcc&t=Believer&a=Imagine+Dragons&d=204');

    final local = (activity('local_0123456789abcdef')['buttons'] as List)
        .single as Map;
    expect(Uri.parse(local['url'] as String).queryParameters.containsKey('v'),
        isFalse);
  });

  test('без длительности — без полосы времени', () {
    final a = discordListeningActivity(
      trackId: 'local_x',
      title: 'Трек',
      artist: 'Кто-то',
      album: '',
      start: start,
      duration: Duration.zero,
    );
    expect(a.containsKey('timestamps'), isFalse);
    expect((a['assets'] as Map)['large_text'], 'Protogenix');
  });

  test('поля — от 2 до 128 символов', () {
    expect(discordText('  много   пробелов  '), 'много пробелов');
    expect(discordText(''), 'Protogenix');
    expect(discordText(' ', fallback: 'Без названия'), 'Без названия');
    expect(discordText('A').runes.length, 2);
    final long = discordText('я' * 300);
    expect(long.runes.length, 128);
    expect(long.endsWith('…'), isTrue);
  });
}
