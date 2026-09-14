import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/discord/data/discord_ipc.dart';

void main() {
  test('кадр: код операции и длина — little-endian, затем JSON', () {
    final bytes =
        encodeDiscordFrame(DiscordOp.frame, {'v': 1, 'client_id': '42'});
    final header = decodeDiscordHeader(Uint8List.sublistView(bytes, 0, 8));
    expect(header.op, DiscordOp.frame);
    expect(header.length, bytes.length - 8);
    expect(bytes.sublist(0, 4), [1, 0, 0, 0]);
    expect(utf8.decode(bytes.sublist(8)), '{"v":1,"client_id":"42"}');
  });

  test('путь к каналу — в форме, которую открывает dart:io', () {
    final bs = String.fromCharCode(92);
    expect(discordPipePath(3), '$bs$bs?${bs}pipe${bs}discord-ipc-3');
  });
}
