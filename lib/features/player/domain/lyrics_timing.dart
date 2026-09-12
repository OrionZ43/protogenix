// lib/features/player/domain/lyrics_timing.dart
//
// Растяжение таймингов и пометка масштаба в сохранённом тексте.
//
// Для slowed/sped up-версий подходит текст оригинала, если умножить все
// тайминги на отношение длительностей (lyrics_matcher.dart считает его как
// timeScale). Чтобы выбранный вручную текст после перезапуска открывался с тем
// же растяжением, масштаб сохраняется первой строкой файла: [pgscale:1.1398].

import 'advanced_lrc_parser.dart';

final _scaleTag = RegExp(r'^\[pgscale:([0-9.]+)\][ \t]*\r?\n?');

/// Все тайминги × [factor].
ParsedLyrics scaleLyricsTimings(ParsedLyrics lyrics, double factor) {
  if (factor == 1.0) return lyrics;
  int scale(int ms) => (ms * factor).round();
  return ParsedLyrics(
    format: lyrics.format,
    tags: lyrics.tags,
    lines: [
      for (final line in lyrics.lines)
        LyricLine(
          startMs: scale(line.startMs),
          endMs: scale(line.endMs),
          isOpposite: line.isOpposite,
          isBackgroundLine: line.isBackgroundLine,
          words: [
            for (final word in line.words)
              LyricWord(
                isBackground: word.isBackground,
                syllables: [
                  for (final s in word.syllables)
                    LyricSyllable(
                      text: s.text,
                      startMs: scale(s.startMs),
                      durationMs: scale(s.durationMs),
                      isPartOfWord: s.isPartOfWord,
                      isBackground: s.isBackground,
                    ),
                ],
              ),
          ],
        ),
    ],
  );
}

/// Текст с пометкой масштаба для сохранения в файл.
String withScaleTag(String content, double factor) {
  final clean = content.replaceFirst(_scaleTag, '');
  if (factor == 1.0) return clean;
  return '[pgscale:${factor.toStringAsFixed(4)}]\n$clean';
}

/// Масштаб из пометки и текст без неё.
({String content, double scale}) readScaleTag(String content) {
  final m = _scaleTag.firstMatch(content);
  if (m == null) return (content: content, scale: 1.0);
  final scale = double.tryParse(m.group(1)!) ?? 1.0;
  return (content: content.substring(m.end), scale: scale > 0 ? scale : 1.0);
}
