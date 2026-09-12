import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/player/domain/advanced_lrc_parser.dart';
import 'package:protogenix/features/player/domain/lyrics_timing.dart';

void main() {
  test('scaleLyricsTimings multiplies every timing', () {
    final parsed = AdvancedLrcParser.parse('[00:10.00] one\n[00:20.00] two');
    final scaled = scaleLyricsTimings(parsed, 1.5);
    expect(scaled.lines[0].startMs, 15000);
    expect(scaled.lines[1].startMs, 30000);
    expect(scaled.format, parsed.format);
  });

  test('scale tag round-trip', () {
    final tagged = withScaleTag('[00:10.00] one', 1.14);
    final read = readScaleTag(tagged);
    expect(read.scale, closeTo(1.14, 0.0001));
    expect(read.content, '[00:10.00] one');
    expect(withScaleTag('[00:10.00] one', 1.0), '[00:10.00] one');
    expect(readScaleTag('[00:10.00] one').scale, 1.0);
  });
}
