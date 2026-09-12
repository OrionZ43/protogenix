// Кандидаты — метаданные реальных результатов замера поиска текстов
// 2026-09-12 (источник, формат, длительность, артист, название). Самих текстов
// в тестах нет: выбор от них не зависит.
import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/library/domain/lyrics_matcher.dart';
import 'package:protogenix/features/library/domain/lyrics_models.dart';

const _syl = LyricsType.syllable;
const _line = LyricsType.synced;
const _plain = LyricsType.plain;

LyricsMetadata _c(
        String source, LyricsType type, int? sec, String artist, String track) =>
    LyricsMetadata(
      id: '$source|$artist|$track|$sec|${type.name}',
      trackName: track,
      artistName: artist,
      durationMs: sec == null ? null : sec * 1000,
      content: '',
      type: type,
      source: source,
    );

LyricsMatch? _best(String title, String artist, int? sec,
    List<LyricsMetadata> candidates) {
  final matcher = LyricsMatcher(
      title: title, artist: artist, durationMs: sec == null ? null : sec * 1000);
  return LyricsMatcher.best(matcher.rank(candidates));
}

void main() {
  test('syllable version of the same song wins over a line-synced one', () {
    final best = _best('The Hills', 'The Weeknd - Topic', 242, [
      _c('lrclib', _line, 242, 'The Weeknd - Topic', 'The Hills'),
      _c('netease', _syl, 242, 'The Weeknd', 'The Hills'),
      _c('lrclib', _line, 234, 'The Weeknd', 'The Hills'),
      _c('netease', _line, 243, 'The Weeknd', 'The Hills  (Remix)'),
      _c('lrclib', _line, 242, 'The Weeknd', 'The Hills (Explicit)'),
    ]);
    expect(best?.metadata.source, 'netease');
    expect(best?.metadata.type, _syl);
  });

  test('dirty LRCLIB title does not beat a clean syllable match', () {
    final best = _best('2WEI & Edda Hayes - BURN', '2WEI', 202, [
      _c('lrclib', _line, 202, '2WEI', '2WEI & Edda Hayes - BURN'),
      _c('netease', _syl, 202, '2WEI', 'Burn'),
      _c('lrclib', _line, 226, '2WEI', 'Burn'),
      _c('netease', _syl, 234, '2WEI', 'Internal Burn'),
    ]);
    expect(best?.metadata.type, _syl);
    expect(best?.metadata.trackName, 'Burn');
  });

  test('only other songs found → nothing instead of wrong lyrics', () {
    expect(
        _best('MellSher, 5opka - Пятнистый ягуар (SUPERNOVA, альбом 2024)',
            'ФУГА TV', 136, [
          _c('netease', _line, 72, 'Shluzov', 'Её парень'),
          _c('netease', _line, 137, 'Георгий Виноградов', 'Катюша'),
        ]),
        isNull);
    expect(
        _best('5opka x 6055 - 42 (клип)', 'ФУГА TV', 102, [
          _c('netease', _line, 123, 'Lil 9ap', '6055'),
          _c('netease', _syl, 237, 'Coldplay', '42'),
          _c('netease', _syl, 175, 'Diplo', '42'),
        ]),
        isNull);
    expect(
        _best('World of Tanks Original Soundtrack: Studzianki', 'WoT Music',
            149, [
          _c('netease', _syl, 106, 'Rocco Deluca', 'Crash of Worlds'),
          _c('netease', _syl, 148, 'Willie Nelson', 'Cruel World'),
        ]),
        isNull);
  });

  test('synced lyrics beat plain ones for the same song', () {
    final best = _best('ELA DANCA', 'Release - Topic', 92, [
      _c('lrclib', _plain, 93, 'Sayfalse, 5opka, MellSher', 'ELA DANCA'),
      _c('lrclib', _plain, 106, 'Sayfalse, 5opka и MellSher',
          'ELA DANCA (Slowed)'),
      _c('netease', _line, 93, 'Sayfalse', 'ELA DANCA'),
    ]);
    expect(best?.metadata.type, _line);
    expect(best?.timeScale, 1.0);
  });

  test('slowed track takes the original lyrics with stretched timings', () {
    final best = _best('ELA DANCA (Slowed) - Sayfalse, 5opka, MellSher',
        'Sayfalse', 106, [
      _c('netease', _line, 93, 'Sayfalse', 'ELA DANCA'),
      _c('netease', _line, 109, 'Sayfalse', 'AL NACER!'),
      _c('lrclib', _plain, 106, 'Sayfalse, 5opka и MellSher',
          'ELA DANCA (Slowed)'),
    ]);
    expect(best?.metadata.type, _line);
    expect(best?.metadata.durationMs, 93000);
    expect(best?.timeScale, closeTo(106 / 93, 0.001));
    expect(best?.timingsReliable, isTrue);
  });

  test('version with the matching duration wins (music video intro)', () {
    final best =
        _best('The Weeknd - Starboy ft. Daft Punk ft. Daft Punk', 'TheWeekndVEVO', 273, [
      _c('lrclib', _line, 231, 'The Weeknd',
          'The Weeknd - Starboy (Audio) ft. Daft Punk'),
      _c('lrclib', _line, 273, 'The Weeknd',
          'The Weeknd - Starboy ft. Daft Punk (Official Video)'),
      _c('netease', _syl, 230, 'The Weeknd', 'Starboy'),
    ]);
    expect(best?.metadata.durationMs, 273000);
  });

  test('remixes, live and 8D versions are not picked for the original', () {
    final believer = _best('Believer', 'Imagine Dragons', null, [
      _c('netease', _syl, 191, 'Imagine Dragons', 'Believer (Kaskade Remix)'),
      _c('netease', _syl, 236, 'Imagine Dragons', 'Believer (Live/Acoustic)'),
      _c('netease', _syl, 204, 'Imagine Dragons', 'Believer'),
      _c('lrclib', _line, 203, 'Imagine Dragons', 'Believer (Audio)'),
    ]);
    expect(believer?.metadata.trackName, 'Believer');
    expect(believer?.metadata.type, _syl);

    final motylek = _best('Мотылёк', 'Макс Корж', null, [
      _c('lrclib', _line, 237, 'Макс Корж', 'Мотылёк 8D'),
      _c('netease', _line, 172, 'до конечной', 'Мотылёк'),
      _c('netease', _line, 253, 'Piknik', 'Мотылёк'),
      _c('netease', _line, 237, 'Макс Корж', 'Мотылёк'),
    ]);
    expect(motylek?.metadata.artistName, 'Макс Корж');
    expect(motylek?.metadata.trackName, 'Мотылёк');
  });

  test('Cyrillic titles are compared, not erased', () {
    final best = _best('5opka, Илюха рэп - Пожарники (Альбом CLAY)', 'ФУГА TV',
        218, [
      _c('netease', _line, 228, 'Игорёк', 'My Love Танюха'),
      _c('netease', _line, 250, 'Оркестр Большого театра', 'Интернационал'),
      _c('lrclib', _line, 218, '5opka, илюха реп', 'Пожарники'),
    ]);
    expect(best?.metadata.trackName, 'Пожарники');

    final kino = _best('Группа крови', 'Кино', null, [
      _c('netease', _line, 284, 'Виктор Цой', 'Группа крови'),
      _c('lrclib', _line, 277, 'Кино', 'Группа крови'),
    ]);
    expect(kino?.metadata.artistName, 'Кино');
  });

  test('big duration mismatch keeps the song but drops the timings', () {
    final best = _best(
        'The Weeknd - Intro/Starboy (Live from Vevo Presents) ft. Daft Punk',
        'TheWeekndVEVO',
        260, [
      _c('netease', _syl, 230, 'The Weeknd', 'Starboy'),
    ]);
    expect(best, isNotNull);
    expect(best!.timingsReliable, isFalse);
  });

  test('a mashup with the song is not the song', () {
    final best = _best('Numb', 'Linkin Park', null, [
      _c('netease', _syl, 205, 'JAY-Z, Linkin Park', 'Numb / Encore'),
      _c('netease', _syl, 188, 'Linkin Park', 'Numb'),
    ]);
    expect(best?.metadata.trackName, 'Numb');
  });
}
