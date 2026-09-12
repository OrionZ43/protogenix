// lib/features/updater/update_envelope.dart
//
// Подписанная обёртка манифеста — файл protogenix-update.json в каждом релизе:
//   {
//     "kid": "z43-2026",
//     "payload": "<base64 от UTF-8 JSON манифеста>",
//     "signature": "<base64 подписи Ed25519 по байтам payload>"
//   }
// Подпись проверяется по сырым байтам payload, поэтому никакой
// канонизации JSON не нужно: байты либо те же, либо подпись не сходится.
//
// Файл без Flutter-импортов: его использует и tool/update_signing.dart.

import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'update_manifest.dart';

class UpdateSignatureException implements Exception {
  const UpdateSignatureException(this.message);

  final String message;

  @override
  String toString() => 'UpdateSignatureException: $message';
}

class UpdateEnvelope {
  UpdateEnvelope._();

  /// Имя файла в ассетах GitHub Release.
  static const fileName = 'protogenix-update.json';

  /// Проверяет подпись и разбирает манифест.
  ///
  /// [trustedKeys]: kid → публичный ключ Ed25519 (32 байта).
  /// Бросает [UpdateSignatureException], если файл повреждён, ключ
  /// неизвестен или подпись не сходится, и [FormatException], если
  /// подписанный манифест сам по себе некорректен.
  static Future<UpdateManifest> verifyAndParse(
    String envelopeJson,
    Map<String, List<int>> trustedKeys,
  ) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(envelopeJson);
    } on FormatException {
      throw const UpdateSignatureException('Файл обновления повреждён');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const UpdateSignatureException('Файл обновления повреждён');
    }

    final kid = decoded['kid'];
    final payload = decoded['payload'];
    final signature = decoded['signature'];
    if (kid is! String || payload is! String || signature is! String) {
      throw const UpdateSignatureException('Файл обновления повреждён');
    }

    final publicKey = trustedKeys[kid];
    if (publicKey == null) {
      throw UpdateSignatureException('Неизвестный ключ подписи: $kid');
    }

    final List<int> payloadBytes;
    final bool valid;
    try {
      payloadBytes = base64Decode(payload);
      valid = await Ed25519().verify(
        payloadBytes,
        signature: Signature(
          base64Decode(signature),
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      );
    } catch (_) {
      throw const UpdateSignatureException('Подпись не сходится');
    }
    if (!valid) throw const UpdateSignatureException('Подпись не сходится');

    final manifest = jsonDecode(utf8.decode(payloadBytes));
    if (manifest is! Map<String, dynamic>) {
      throw const FormatException('Манифест должен быть JSON-объектом');
    }
    return UpdateManifest.fromJson(manifest);
  }

  /// Подписывает манифест. Нужен tool/update_signing.dart и тестам —
  /// приватного ключа в приложении нет.
  static Future<String> sign({
    required List<int> manifestBytes,
    required String kid,
    required SimpleKeyPair keyPair,
  }) async {
    final signature = await Ed25519().sign(manifestBytes, keyPair: keyPair);
    return const JsonEncoder.withIndent('  ').convert({
      'kid': kid,
      'payload': base64Encode(manifestBytes),
      'signature': base64Encode(signature.bytes),
    });
  }
}
