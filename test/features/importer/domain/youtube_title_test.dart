import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/importer/domain/youtube_title.dart';

// Заголовки Monstercat вида «[Electro] - Nitro Fun - New Game [Monstercat
// Release]»: скобки вырезались, а тире в начале оставалось, и в медиатеке
// появлялось «- Nitro Fun - New Game» (отзыв Orion 2026-09-27).

void main() {
  test('тире от вырезанных скобок не остаётся по краям', () {
    expect(
      cleanYoutubeTitle('[Electro] - Nitro Fun - New Game [Monstercat Release]'),
      'Nitro Fun - New Game',
    );
    expect(
      cleanYoutubeTitle('[Electro] Nitro Fun - Cheat Codes [Monstercat Release]'),
      'Nitro Fun - Cheat Codes',
    );
  });

  test('тире внутри названия не трогаем — это «Артист - Название»', () {
    expect(
      cleanYoutubeTitle('Nitro Fun - Soldiers'),
      'Nitro Fun - Soldiers',
    );
    expect(
      cleanYoutubeTitle('Sound Remedy & Nitro Fun - Turbo Penguin'),
      'Sound Remedy & Nitro Fun - Turbo Penguin',
    );
  });

  test('вырезаются приписки о видео, а не о песне', () {
    expect(cleanYoutubeTitle('Song (Official Video)'), 'Song');
    expect(cleanYoutubeTitle('Song (Lyrics)'), 'Song');
    expect(cleanYoutubeTitle('Song (Audio)'), 'Song');
    expect(cleanYoutubeTitle('Song (HD)'), 'Song');
  });

  test('скобки с версией песни остаются', () {
    expect(
      cleanYoutubeTitle('Televisor - Old Skool (Nitro Fun Remix)'),
      'Televisor - Old Skool (Nitro Fun Remix)',
    );
  });

  test('если после чистки ничего не осталось — берём исходный заголовок', () {
    expect(cleanYoutubeTitle('[Monstercat Release]'), '[Monstercat Release]');
    expect(cleanYoutubeTitle('  ---  '), '---');
  });

  test('лишние пробелы схлопываются', () {
    expect(cleanYoutubeTitle('Nitro Fun   -   New Game'), 'Nitro Fun - New Game');
  });
}
