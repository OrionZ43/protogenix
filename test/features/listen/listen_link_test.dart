import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/listen/domain/listen_link.dart';

void main() {
  test('ссылка приложения: ролик, название, исполнитель, длительность', () {
    final link = ListenLink.parse(
        'protogenix://listen?v=7wtfhZwyrcc&t=Believer&a=Imagine+Dragons&d=204')!;
    expect(link.videoId, '7wtfhZwyrcc');
    expect(link.title, 'Believer');
    expect(link.artist, 'Imagine Dragons');
    expect(link.duration, const Duration(seconds: 204));
    expect(link.label, '«Believer» — Imagine Dragons');
  });

  test('«/» после хоста — та же ссылка', () {
    // Так её отдаёт Windows при запуске по схеме из реестра (проверено
    // 2026-09-14): protogenix://listen?… → protogenix://listen/?…
    final link = ListenLink.parse(
        'protogenix://listen/?v=7wtfhZwyrcc&t=Believer&a=Imagine+Dragons&d=204')!;
    expect(link.videoId, '7wtfhZwyrcc');
    expect(link.artist, 'Imagine Dragons');
  });

  test('ссылка сайта — то же самое, кириллица цела', () {
    final url = Uri.https(kListenHost, kListenPath,
        {'t': 'Группа крови', 'a': 'Кино'}).toString();
    final link = ListenLink.parse(url)!;
    expect(link.videoId, isNull);
    expect(link.title, 'Группа крови');
    expect(link.artist, 'Кино');
  });

  test('чужие ссылки и мусор не принимаются', () {
    expect(ListenLink.parse('https://evil.example/listen?v=7wtfhZwyrcc'),
        isNull);
    expect(ListenLink.parse('protogenix://import?url=file:///C:/secret'),
        isNull);
    expect(ListenLink.parse('protogenix://listen'), isNull,
        reason: 'ни ролика, ни названия');
    expect(ListenLink.parse('protogenix://listen?v=../../etc'), isNull);
    expect(ListenLink.parse('protogenix://listen?v=bad&t=Song')!.videoId,
        isNull);
  });

  test('управляющие символы убраны, длина ограничена', () {
    final link =
        ListenLink.parse('protogenix://listen?t=A%00B%0AC&a=${'x' * 500}')!;
    expect(link.title, 'ABC');
    expect(link.artist.runes.length, 200);
  });

  test('адрес для Discord — не длиннее 512 символов, ролик на месте', () {
    final url = ListenLink.webUrl(
      videoId: '7wtfhZwyrcc',
      title: 'Я' * 300,
      artist: 'Б' * 300,
      duration: const Duration(minutes: 3),
    );
    expect(url.length, lessThanOrEqualTo(512));
    final back = ListenLink.parse(url)!;
    expect(back.videoId, '7wtfhZwyrcc');
    expect(back.duration, const Duration(minutes: 3));
  });
}
