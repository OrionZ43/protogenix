// lib/features/library/data/providers/kugou_krc.dart
//
// Формат KRC от Kugou. Текст приходит как base64: «krc1» + XOR с известным
// 16-байтовым ключом + zlib. Внутри — строки [начало,длительность] и слова
// <смещение от начала строки,длительность,0>текст. AdvancedLrcParser понимает
// YRC от NetEase, где у слов абсолютное время, поэтому KRC переводим в YRC.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class KugouKrc {
  KugouKrc._();

  static const _magic = [0x6b, 0x72, 0x63, 0x31]; // «krc1»
  static const _key = [
    0x40, 0x47, 0x61, 0x77, 0x5e, 0x32, 0x74, 0x47,
    0x51, 0x36, 0x31, 0x2d, 0xce, 0xd2, 0x6e, 0x69,
  ];

  static final _line = RegExp(r'^\[(\d+),(\d+)\](.*)$');
  static final _word = RegExp(r'<(\d+),(\d+),\d+>([^<]*)');

  /// base64 из ответа /download → текст KRC. Не KRC — [FormatException].
  static String decrypt(String base64Content) {
    final bytes = base64.decode(base64Content.trim());
    if (bytes.length <= _magic.length ||
        !listEquals(bytes.sublist(0, _magic.length), _magic)) {
      throw const FormatException('Не KRC: нет заголовка krc1');
    }
    final data = Uint8List(bytes.length - _magic.length);
    for (var i = 0; i < data.length; i++) {
      data[i] = bytes[i + _magic.length] ^ _key[i % _key.length];
    }
    return utf8.decode(zlib.decode(data), allowMalformed: true);
  }

  /// Обратное [decrypt] — для тестов.
  @visibleForTesting
  static String encrypt(String krc) {
    final packed = zlib.encode(utf8.encode(krc));
    final out = Uint8List(packed.length + _magic.length)..setAll(0, _magic);
    for (var i = 0; i < packed.length; i++) {
      out[i + _magic.length] = packed[i] ^ _key[i % _key.length];
    }
    return base64.encode(out);
  }

  /// KRC → YRC с абсолютным временем слов. Метатеги ([ti:], [language:] …)
  /// и строки без слов пропускаются.
  static String toYrc(String krc) {
    final out = StringBuffer();
    for (final raw in const LineSplitter().convert(krc)) {
      final m = _line.firstMatch(raw.trimRight());
      if (m == null) continue;
      final start = int.parse(m.group(1)!);
      final words = _word.allMatches(m.group(3)!).toList();
      if (words.isEmpty) continue;
      out.write('[$start,${m.group(2)}]');
      for (final w in words) {
        out.write(
            '(${start + int.parse(w.group(1)!)},${w.group(2)},0)${w.group(3)}');
      }
      out.write('\n');
    }
    return out.toString();
  }
}
