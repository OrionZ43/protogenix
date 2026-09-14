import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/importer/data/youtube_match.dart';

// Выдачи YouTube — настоящие, снятые 2026-09-13 для двух треков из отзыва
// (заголовок, канал, длительность; id — настоящие, где были известны).
YoutubeCandidate _c(String id, int seconds, String author, String title) =>
    YoutubeCandidate(
        id: id, title: title, author: author, durationMs: seconds * 1000);

final _tearsForFears = [
  _c('aGCdLKXNF3w', 291, 'Tears For Fears',
      'Tears For Fears - Everybody Wants To Rule The World (Official Music Video)'),
  _c('SFU1GeGFpzY', 251, 'Rewind Music Group',
      'Tears For Fears - Everybody Wants To Rule The World'),
  _c('7p2HqW9J1iU', 262, 'Tears For Fears',
      'Everybody Wants To Rule The World (Alternative Single Version)'),
  _c('tSBWmxwT8So', 262, 'Taj Tracks',
      'Tears For Fears - Everybody Wants To Rule The World (Lyrics)'),
  _c('4QgDE2fctjI', 3806, 'Fast Vibe',
      'Tears for Fears - Everybody Wants to Rule the World (1 HOUR/Lyrics) "nothing ever lasts forever"'),
  _c('Pkgd3tER1yI', 273, 'SiriusXM',
      'Tears for Fears — Everybody Wants to Rule the World | LIVE Performance | SiriusXM'),
  _c('uqItaKDc6oI', 189, 'bunarbashi',
      "Tears For Fears - Everybody Wants To Rule The World (Kenny Everett Show '85)"),
  _c('0DF25WDoRNk', 341, 'Tears For Fears',
      'Everybody Wants To Rule The World (Extended Version)'),
  _c('MJ-UPpc6uyo', 249, '7clouds Rock',
      'Tears For Fears - Everybody Wants To Rule The World (Lyrics)'),
  _c('JenUwAw3eYk', 252, 'Blue Fashion - Topic',
      'Everybody Wants to Rule the World'),
];

final _kaleo = [
  _c('0-7IHOXkiV8', 215, 'KALEO', 'KALEO - Way Down We Go (Official Music Video)'),
  _c('sZ5SI6n1Ljs', 210, 'The Current',
      'Kaleo - Way Down We Go (Live on 89.3 The Current)'),
  _c('9WIU5NN1Q0g', 295, 'KALEO', 'KALEO - "Way Down We Go" (LIVE in a volcano)'),
  _c('Uqrl-15a3f8', 209, 'KALEO', 'Way down We Go (Stripped)'),
  _c('ZOZFvoeMWek', 218, 'KALEO', 'KALEO "Way Down We Go" (Live at KROQ)'),
  _c('KxSQidzIiC0', 218, 'Lyric Videos', 'Way Down We Go - KALEO - Lyrics'),
  _c('xfLdXqQSnEg', 209, 'KALEO', 'KALEO "Way Down We Go" [Stripped Audio]'),
  _c('oCi0RHLrauU', 334, 'KALEO', 'KALEO "Save Yourself" (LIVE at Fjallsárlón)'),
  _c('mu8xOnxZB18', 197, 'Studio Brussel', 'Kaleo - Way Down We Go (live)'),
  _c('xAdDHY2_6Os', 266, 'KALEO', 'KALEO - Break My Baby [OFFICIAL AUDIO]'),
];

void main() {
  test('Tears For Fears: не кавер с «Blue Fashion - Topic», а та же запись',
      () {
    final matcher = YoutubeTrackMatcher(
      title: 'Everybody Wants To Rule The World',
      artist: 'Tears For Fears',
      durationMs: 251000,
    );
    expect(matcher.pick(_tearsForFears)?.id, 'SFU1GeGFpzY');
  });

  test('запись с канала исполнителя важнее перезалива той же длины', () {
    final matcher = YoutubeTrackMatcher(
      title: 'Everybody Wants To Rule The World',
      artist: 'Tears For Fears',
      durationMs: 251000,
    );
    final picked = matcher.pick([
      ..._tearsForFears,
      _c('official', 252, 'Tears For Fears', 'Everybody Wants To Rule The World'),
    ]);
    expect(picked?.id, 'official');
  });

  test('KALEO: не live и не stripped, а альбомная версия', () {
    final matcher = YoutubeTrackMatcher(
      title: 'Way Down We Go',
      artist: 'KALEO',
      durationMs: 219000,
    );
    expect(matcher.pick(_kaleo)?.id, 'KxSQidzIiC0');
  });

  test('подходящей записи нет — null, а не первый попавшийся', () {
    final matcher = YoutubeTrackMatcher(
      title: 'Way Down We Go',
      artist: 'KALEO',
      durationMs: 219000,
    );
    final onlyWrong =
        _kaleo.where((c) => c.id != 'KxSQidzIiC0' && c.id != '0-7IHOXkiV8');
    expect(matcher.pick(onlyWrong), isNull);
  });

  test('ремикс ищется как ремикс', () {
    final matcher = YoutubeTrackMatcher(
      title: 'Believer (Kaskade Remix)',
      artist: 'Imagine Dragons',
      durationMs: 210000,
    );
    final picked = matcher.pick([
      _c('orig', 204, 'Imagine Dragons', 'Imagine Dragons - Believer'),
      _c('remix', 210, 'Imagine Dragons', 'Believer (Kaskade Remix)'),
    ]);
    expect(picked?.id, 'remix');
  });

  test('исполнитель неизвестен — только при совпавшей длительности', () {
    final matcher =
        YoutubeTrackMatcher(title: 'Way Down We Go', artist: '', durationMs: 219000);
    expect(matcher.pick([_c('far', 230, 'Someone', 'Way Down We Go')]), isNull);
    expect(matcher.pick([_c('near', 218, 'Someone', 'Way Down We Go')])?.id,
        'near');
  });
}
