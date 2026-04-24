import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/player/domain/advanced_lrc_parser.dart';

void main() {
  group('AdvancedLrcParser - Format Detection & Metadata', () {
    test('detects YRC format', () {
      const content = '[100,200](100,200,0)Test';
      final result = AdvancedLrcParser.parse(content);
      expect(result.format, LyricsFormat.yrc);
    });

    test('detects Enhanced LRC format', () {
      const content = '[00:01.00] <00:01.00>Test';
      final result = AdvancedLrcParser.parse(content);
      expect(result.format, LyricsFormat.enhancedLrc);
    });

    test('detects Synced LRC format', () {
      const content = '[00:01.00] Test';
      final result = AdvancedLrcParser.parse(content);
      expect(result.format, LyricsFormat.syncedLrc);
    });

    test('detects Plain text format', () {
      const content = 'Just some text';
      final result = AdvancedLrcParser.parse(content);
      expect(result.format, LyricsFormat.plain);
    });

    test('parses metadata tags', () {
      const content = '''
[ti:Song Title]
[ar:Artist Name]
[al:Album Name]
[00:01.00] Lyric line
''';
      final result = AdvancedLrcParser.parse(content);
      expect(result.tags['ti'], 'Song Title');
      expect(result.tags['ar'], 'Artist Name');
      expect(result.tags['al'], 'Album Name');
    });
  });

  group('AdvancedLrcParser - YRC Format', () {
    test('parses YRC line and syllables correctly', () {
      const content =
          '[1000,2000](1000,500,0)One (1500,500,0)two (2000,1000,0)three';
      final result = AdvancedLrcParser.parse(content);

      expect(result.lines.length, 1);
      final line = result.lines.first;
      expect(line.startMs, 1000);
      expect(line.endMs, 3000);

      expect(line.words.length, 3);
      expect(line.words[0].text, 'One');
      expect(line.words[0].syllables[0].text, 'One');
      expect(line.words[0].syllables[0].startMs, 1000);
      expect(line.words[0].syllables[0].durationMs, 500);
      expect(line.words[0].syllables[0].isPartOfWord, false);

      expect(line.words[1].text, 'two');
      expect(line.words[2].text, 'three');
    });

    test('groups syllables into words based on spaces', () {
      const content =
          '[1000,1000](1000,200,0)Inter(1200,300,0)stellar (1500,500,0)Rocks';
      final result = AdvancedLrcParser.parse(content);

      final line = result.lines.first;
      expect(line.words.length, 2);
      expect(line.words[0].text, 'Interstellar');
      expect(line.words[0].syllables.length, 2);
      expect(line.words[0].syllables[0].isPartOfWord, true);
      expect(line.words[0].syllables[1].isPartOfWord, false);

      expect(line.words[1].text, 'Rocks');
    });

    test('filters out lines with Chinese metadata', () {
      const content = '''
[1000,500](1000,500,0)作词: Someone
[2000,500](2000,500,0)Actual lyric
''';
      final result = AdvancedLrcParser.parse(content);
      expect(result.lines.length, 1);
      expect(result.lines.first.plainText, 'Actual lyric');
    });
  });

  group('AdvancedLrcParser - Enhanced & Synced LRC', () {
    test('parses Enhanced LRC word timings', () {
      const content = '[00:01.00] <00:01.00>Word1 <00:01.50>Word2';
      final result = AdvancedLrcParser.parse(content);

      expect(result.format, LyricsFormat.enhancedLrc);
      final line = result.lines.first;
      expect(line.words.length, 2);
      expect(line.words[0].startMs, 1000);
      expect(line.words[1].startMs, 1500);
    });

    test('expands Synced LRC into character syllables', () {
      const content = '[00:01.00] Hello';
      final result = AdvancedLrcParser.parse(content);

      expect(result.format, LyricsFormat.syncedLrc);
      final line = result.lines.first;
      expect(line.words[0].syllables.length, 5);
      expect(line.words[0].syllables[0].text, 'H');
    });

    test('handles duet tags and alignment', () {
      const content = '''
[00:01.00] [Singer : 2] Second singer line
[00:02.00] Normal line
''';
      final result = AdvancedLrcParser.parse(content);
      expect(result.lines[0].isOpposite, true);
      expect(result.lines[1].isOpposite, true);
    });
  });

  group('AdvancedLrcParser - Navigation & Edge Cases', () {
    test('currentLineIndex finds correct line via binary search', () {
      final lines = [
        const LyricLine(startMs: 1000, endMs: 2000, words: []),
        const LyricLine(startMs: 2000, endMs: 3000, words: []),
        const LyricLine(startMs: 4000, endMs: 5000, words: []),
      ];

      expect(AdvancedLrcParser.currentLineIndex(lines, 500), -1);
      expect(AdvancedLrcParser.currentLineIndex(lines, 1000), 0);
      expect(AdvancedLrcParser.currentLineIndex(lines, 1500), 0);
      expect(AdvancedLrcParser.currentLineIndex(lines, 2000), 1);
      expect(AdvancedLrcParser.currentLineIndex(lines, 3500), 1);
      expect(AdvancedLrcParser.currentLineIndex(lines, 4000), 2);
      expect(AdvancedLrcParser.currentLineIndex(lines, 10000), 2);
    });

    test('handles empty content', () {
      final result = AdvancedLrcParser.parse('');
      expect(result.lines, isEmpty);
      expect(result.format, LyricsFormat.plain);
    });

    test('adjusts line end times', () {
      const content = '''
[00:01.00] Line 1
[00:05.00] Line 2
''';
      final result = AdvancedLrcParser.parse(content);
      expect(result.lines[0].endMs, 4950);
    });
  });
}
