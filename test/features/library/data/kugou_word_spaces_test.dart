import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/library/data/providers/kugou_krc.dart';
import 'package:protogenix/features/player/domain/advanced_lrc_parser.dart';

// У Kugou пробел между словами — отдельное «слово» KRC со своим временем.
// До 2026-09-13 перевод в YRC оставлял его отдельным слогом, разбор такие
// слоги пропускал, и строка склеивалась в одно слово («It'sallabout»).
void main() {
  const krc = "[1000,2000]<0,300,0>It's<300,0,0> <300,200,0>all<500,0,0> "
      '<500,300,0>about';

  test('KRC → YRC: пробел уходит в конец предыдущего слога', () {
    expect(
      KugouKrc.toYrc(krc),
      "[1000,2000](1000,300,0)It's (1300,200,0)all (1500,300,0)about\n",
    );
  });

  test('после перевода строка разбирается на отдельные слова', () {
    final lyrics = AdvancedLrcParser.parse(KugouKrc.toYrc(krc));
    expect(lyrics.lines.single.words.map((w) => w.text), ["It's", 'all', 'about']);
  });

  test('сохранённый раньше YRC с пробелами-слогами тоже не склеивается', () {
    const oldYrc = "[1000,2000](1000,300,0)It's(1300,0,0) (1300,200,0)all"
        '(1500,0,0) (1500,300,0)about';
    final lyrics = AdvancedLrcParser.parse(oldYrc);
    expect(lyrics.lines.single.words.map((w) => w.text), ["It's", 'all', 'about']);
  });
}
