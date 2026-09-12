// Названия — реальные треки из замера поиска текстов 2026-09-12.
import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/library/domain/track_query.dart';

ParsedTrack _parse(String title, String artist) =>
    TrackQueryParser.parse(title, artist);

void main() {
  test('label channel upload: artists come from the title', () {
    final t = _parse('5opka, Илюха рэп - Пожарники (Альбом CLAY)', 'ФУГА TV');
    expect(t.title, 'Пожарники');
    expect(t.artists, ['5opka', 'Илюха рэп']);
  });

  test('Topic and VEVO uploaders', () {
    expect(_parse('The Hills', 'The Weeknd - Topic').artists, ['The Weeknd']);
    final t = _parse(
        'Imagine Dragons - Believer (Official Music Video)', 'ImagineDragonsVEVO');
    expect(t.title, 'Believer');
    expect(t.artists, ['Imagine Dragons']);
  });

  test('feat. outside brackets goes to artists', () {
    final t =
        _parse('The Weeknd - Starboy ft. Daft Punk ft. Daft Punk', 'TheWeekndVEVO');
    expect(t.title, 'Starboy');
    expect(t.artists, ['The Weeknd', 'Daft Punk']);
  });

  test('versions from brackets and suffixes', () {
    expect(_parse('Believer (Kaskade Remix)', 'Imagine Dragons').variants,
        {TrackVariant.remix});
    final slowed = _parse('ELA DANCA - Slowed', 'Sayfalse');
    expect(slowed.title, 'ELA DANCA');
    expect(slowed.variants, {TrackVariant.slowed});
    final eightD = _parse('Мотылёк 8D', 'Макс Корж');
    expect(eightD.title, 'Мотылёк');
    expect(eightD.variants, {TrackVariant.eightD});
  });

  test('reversed "Title - Artists" is among the interpretations', () {
    final all = TrackQueryParser.interpretations(
        'ELA DANCA (Slowed) - Sayfalse, 5opka, MellSher', 'Sayfalse');
    expect(
        all.any((t) => t.title == 'ELA DANCA' && t.artists.contains('Sayfalse')),
        isTrue);
    expect(all.first.variants, {TrackVariant.slowed});
  });

  test('track numbers and medleys', () {
    final t = _parse('01. Кино - Группа крови', 'Кино');
    expect(t.artists, ['Кино']);
    expect(t.title, 'Группа крови');
    expect(
        _parse('The Weeknd - Intro/Starboy (Live from Vevo Presents)',
                'TheWeekndVEVO')
            .titles,
        contains('Starboy'));
  });

  test('unknown artist is dropped', () {
    expect(_parse('Song title', 'Unknown').artists, isEmpty);
  });
}
