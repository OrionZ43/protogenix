import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/updater/update_envelope.dart';

final Map<String, Object> _manifest = {
  'version': '1.1.0',
  'build': 12,
  'assets': {
    'windows-x64': {
      'urls': ['https://example.com/Protogenix-Setup.exe'],
      'size': 10,
      'sha256': 'c' * 64,
    },
  },
};

void main() {
  late SimpleKeyPair keyPair;
  late Map<String, List<int>> trusted;

  setUpAll(() async {
    keyPair = await Ed25519().newKeyPair();
    trusted = {'k1': (await keyPair.extractPublicKey()).bytes};
  });

  Future<String> signed({SimpleKeyPair? by}) => UpdateEnvelope.sign(
        manifestBytes: utf8.encode(jsonEncode(_manifest)),
        kid: 'k1',
        keyPair: by ?? keyPair,
      );

  test('подпись сходится — манифест разбирается', () async {
    final manifest =
        await UpdateEnvelope.verifyAndParse(await signed(), trusted);
    expect(manifest.build, 12);
    expect(manifest.assets.keys, ['windows-x64']);
  });

  test('подменённый манифест отклоняется', () async {
    final envelope = jsonDecode(await signed()) as Map<String, dynamic>;
    envelope['payload'] =
        base64Encode(utf8.encode(jsonEncode({..._manifest, 'build': 99})));

    await expectLater(
      UpdateEnvelope.verifyAndParse(jsonEncode(envelope), trusted),
      throwsA(isA<UpdateSignatureException>()),
    );
  });

  test('подпись чужим ключом отклоняется', () async {
    final stranger = await Ed25519().newKeyPair();
    await expectLater(
      UpdateEnvelope.verifyAndParse(await signed(by: stranger), trusted),
      throwsA(isA<UpdateSignatureException>()),
    );
  });

  test('неизвестный kid отклоняется', () async {
    await expectLater(
      UpdateEnvelope.verifyAndParse(
          await signed(), {'other': trusted['k1']!}),
      throwsA(isA<UpdateSignatureException>()),
    );
  });

  test('мусор вместо файла отклоняется', () async {
    await expectLater(
      UpdateEnvelope.verifyAndParse('<html>blocked</html>', trusted),
      throwsA(isA<UpdateSignatureException>()),
    );
    await expectLater(
      UpdateEnvelope.verifyAndParse(
          '{"kid":"k1","payload":"%%%","signature":"%%%"}', trusted),
      throwsA(isA<UpdateSignatureException>()),
    );
  });
}
