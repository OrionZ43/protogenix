import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/library/domain/lyrics_text.dart';

void main() {
  group('normalizeForMatch', () {
    test('keeps Cyrillic letters (the old \\w-based cleanup erased them)', () {
      expect(normalizeForMatch('Кино - Группа крови!'), 'кино группа крови');
    });

    test('treats ё as е', () {
      expect(normalizeForMatch('Мотылёк'), normalizeForMatch('Мотылек'));
    });
  });

  group('textSimilarity', () {
    test('matches transliteration', () {
      expect(textSimilarity('Kino', 'Кино'), 1.0);
    });

    test('ignores spaces', () {
      expect(textSimilarity('TheWeeknd', 'The Weeknd'), 1.0);
    });

    test('е/э spelling variants stay close', () {
      expect(textSimilarity('Илюха рэп', 'илюха реп'), greaterThan(0.7));
    });

    test('different titles stay far apart', () {
      expect(textSimilarity('Пятнистый ягуар', 'Её парень'), lessThan(0.3));
    });
  });

  test('splitArtists handles common separators', () {
    expect(splitArtists('5opka, MellSher'), ['5opka', 'MellSher']);
    expect(splitArtists('5opka & MellSher'), ['5opka', 'MellSher']);
    expect(splitArtists('5opka x 6055'), ['5opka', '6055']);
    expect(splitArtists('5opka и илюха реп'), ['5opka', 'илюха реп']);
    expect(splitArtists('Lil Nas X'), ['Lil Nas X']);
    // Kugou пишет совместные треки через китайскую запятую
    expect(splitArtists('The Weeknd、Daft Punk'), ['The Weeknd', 'Daft Punk']);
  });
}
