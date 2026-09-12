import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/library/data/providers/kugou_krc.dart';
import 'package:protogenix/features/player/domain/advanced_lrc_parser.dart';

void main() {
  // Слова-заглушки вместо настоящего текста песни.
  const krc = '[ti:Test]\n[offset:0]\n'
      '[1000,2000]<0,500,0>one <500,700,0>two\n'
      '[4000,1000]<0,1000,0>three\n';

  test('decrypt inverts the Kugou packing', () {
    expect(KugouKrc.decrypt(KugouKrc.encrypt(krc)), krc);
  });

  test('rejects content without the krc1 header', () {
    expect(() => KugouKrc.decrypt(base64.encode(utf8.encode('not krc at all'))),
        throwsFormatException);
  });

  test('converts relative word offsets to absolute YRC timings', () {
    final yrc = KugouKrc.toYrc(krc);
    expect(yrc,
        '[1000,2000](1000,500,0)one (1500,700,0)two\n[4000,1000](4000,1000,0)three\n');

    final parsed = AdvancedLrcParser.parse(yrc);
    expect(parsed.format, LyricsFormat.yrc);
    expect(parsed.lines, hasLength(2));
    expect(parsed.lines.first.words.last.startMs, 1500);
  });
}
