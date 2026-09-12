// tool/update_signing.dart
//
// Ключи и подпись манифеста обновлений (Ed25519).
//
//   dart run tool/update_signing.dart keygen <kid> <файл-ключа>
//       Создаёт приватный ключ (32 байта seed в base64) и печатает строку
//       для lib/features/updater/update_keys.dart. Существующий файл не
//       перезаписывается, внутри репозитория ключ не создаётся.
//
//   dart run tool/update_signing.dart sign <kid> <файл-ключа> <manifest.json> <выходной-файл>
//       Проверяет manifest.json, подписывает и пишет protogenix-update.json,
//       затем сам проверяет подпись.
//
// Приватный ключ хранить вне репозитория, минимум в двух местах: без него
// приложение не примет ни одного следующего обновления.

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:protogenix/features/updater/update_envelope.dart';
import 'package:protogenix/features/updater/update_manifest.dart';

Future<void> main(List<String> args) async {
  switch (args) {
    case ['keygen', final kid, final keyPath]:
      await _keygen(kid, keyPath);
    case ['sign', final kid, final keyPath, final manifestPath, final outPath]:
      await _sign(kid, keyPath, manifestPath, outPath);
    default:
      stderr.writeln(
        'Использование:\n'
        '  dart run tool/update_signing.dart keygen <kid> <файл-ключа>\n'
        '  dart run tool/update_signing.dart sign <kid> <файл-ключа> '
        '<manifest.json> <выходной-файл>',
      );
      exit(64);
  }
}

Future<void> _keygen(String kid, String keyPath) async {
  final file = File(p.absolute(keyPath));
  if (p.isWithin(Directory.current.path, file.path)) {
    _fail('Ключ нельзя хранить внутри репозитория — он публичный. '
        'Укажи путь вне ${Directory.current.path}');
  }
  if (await file.exists()) {
    _fail('Файл ${file.path} уже существует — не перезаписываю.');
  }

  final keyPair = await Ed25519().newKeyPair();
  final seed = await keyPair.extractPrivateKeyBytes();
  final publicKey = await keyPair.extractPublicKey();

  await file.parent.create(recursive: true);
  await file.writeAsString(base64Encode(seed));

  stdout
    ..writeln('Приватный ключ записан: ${file.path}')
    ..writeln('Сделай резервную копию и не клади его в репозиторий.')
    ..writeln()
    ..writeln('Строка для kUpdateSigningKeys в '
        'lib/features/updater/update_keys.dart:')
    ..writeln("  '$kid': '${base64Encode(publicKey.bytes)}',");
}

Future<void> _sign(
  String kid,
  String keyPath,
  String manifestPath,
  String outPath,
) async {
  final manifestBytes = await File(manifestPath).readAsBytes();
  final json = jsonDecode(utf8.decode(manifestBytes));
  if (json is! Map<String, dynamic>) {
    _fail('manifest.json должен быть JSON-объектом');
  }
  // Бросит FormatException, если в манифесте ошибка.
  final manifest = UpdateManifest.fromJson(json);

  final seed = base64Decode((await File(keyPath).readAsString()).trim());
  final keyPair = await Ed25519().newKeyPairFromSeed(seed);
  final envelope = await UpdateEnvelope.sign(
    manifestBytes: manifestBytes,
    kid: kid,
    keyPair: keyPair,
  );

  // Самопроверка: подпись должна сходиться с публичной частью этого ключа.
  final publicKey = await keyPair.extractPublicKey();
  await UpdateEnvelope.verifyAndParse(envelope, {kid: publicKey.bytes});

  await File(outPath).writeAsString(envelope);
  stdout.writeln('Подписано: $outPath '
      '(версия ${manifest.version}, сборка ${manifest.build}, ключ $kid)');
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
