import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/core/utils/plural_ru.dart';

// На карточке плейлиста из 21 трека было «21 треков» (отзыв Orion 2026-09-27).

void main() {
  test('единственное число', () {
    for (final n in [1, 21, 101, 1001]) {
      expect(trackCountLabel(n), '$n трек');
    }
  });

  test('два, три, четыре', () {
    for (final n in [2, 3, 4, 22, 33, 104]) {
      expect(trackCountLabel(n), '$n трека');
    }
  });

  test('множественное число', () {
    for (final n in [0, 5, 9, 10, 20, 25, 100]) {
      expect(trackCountLabel(n), '$n треков');
    }
  });

  test('11–14 всегда «треков», хотя кончаются на 1–4', () {
    for (final n in [11, 12, 13, 14, 111, 112, 113, 114]) {
      expect(trackCountLabel(n), '$n треков');
    }
  });
}
