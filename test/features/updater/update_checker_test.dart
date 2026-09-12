import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/updater/update_checker.dart';
import 'package:protogenix/features/updater/update_envelope.dart';
import 'package:protogenix/features/updater/update_keys.dart';

Map<String, dynamic> manifestJson() => {
      'version': '1.1.0',
      'build': 12,
      'minSupportedBuild': 9,
      'notes': 'Что нового',
      'assets': {
        'android-arm64-v8a': {
          'urls': ['https://example.com/protogenix-arm64-v8a.apk'],
          'size': 10,
          'sha256': 'a' * 64,
        },
        'android-universal': {
          'urls': ['https://example.com/protogenix-universal.apk'],
          'size': 20,
          'sha256': 'b' * 64,
        },
        'windows-x64': {
          'urls': ['https://example.com/Protogenix-Setup.exe'],
          'size': 30,
          'sha256': 'c' * 64,
        },
      },
    };

void main() {
  late SimpleKeyPair keyPair;
  late Map<String, List<int>> trusted;
  late HttpServer server;
  late String envelope;
  late int hits;

  setUpAll(() async {
    keyPair = await Ed25519().newKeyPair();
    trusted = {'test': (await keyPair.extractPublicKey()).bytes};
  });

  setUp(() async {
    hits = 0;
    envelope = await UpdateEnvelope.sign(
      manifestBytes: utf8.encode(jsonEncode(manifestJson())),
      kid: 'test',
      keyPair: keyPair,
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      hits++;
      if (request.uri.path == '/update.json') {
        request.response.write(envelope);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  UpdateChecker checker({
    List<String> paths = const ['/update.json'],
    Map<String, List<int>>? keys,
  }) =>
      UpdateChecker(
        manifestUrls: [
          for (final path in paths)
            Uri.parse('http://127.0.0.1:${server.port}$path'),
        ],
        trustedKeys: keys ?? trusted,
      );

  test('находит обновление и файл под архитектуру устройства', () async {
    final update = await checker().check(
      currentBuild: 10,
      assetKeys: androidAssetKeys(['arm64-v8a', 'armeabi-v7a']),
    );

    expect(update, isNotNull);
    expect(update!.manifest.build, 12);
    expect(update.asset!.size, 10);
    expect(update.isMandatory, isFalse);
  });

  test('без подходящей архитектуры берёт универсальный APK', () async {
    final update = await checker()
        .check(currentBuild: 10, assetKeys: androidAssetKeys(['x86']));
    expect(update!.asset!.size, 20);
  });

  test('нет файла для платформы — обновление есть, файла нет', () async {
    final update =
        await checker().check(currentBuild: 10, assetKeys: const ['linux-x64']);
    expect(update, isNotNull);
    expect(update!.asset, isNull);
  });

  test('та же или более новая сборка — обновления нет', () async {
    expect(
      await checker().check(currentBuild: 12, assetKeys: const ['windows-x64']),
      isNull,
    );
    expect(
      await checker().check(currentBuild: 13, assetKeys: const ['windows-x64']),
      isNull,
    );
  });

  test('сборка ниже minSupportedBuild — обновление обязательное', () async {
    final update =
        await checker().check(currentBuild: 5, assetKeys: const ['windows-x64']);
    expect(update!.isMandatory, isTrue);
  });

  test('без доверенных ключей в сеть не ходит', () async {
    final update = await checker(keys: const {})
        .check(currentBuild: 1, assetKeys: const ['windows-x64']);
    expect(update, isNull);
    expect(hits, 0);
  });

  test('чужая подпись — обновления нет', () async {
    final stranger = await Ed25519().newKeyPair();
    final keys = {'test': (await stranger.extractPublicKey()).bytes};
    final update = await checker(keys: keys)
        .check(currentBuild: 1, assetKeys: const ['windows-x64']);
    expect(update, isNull);
  });

  test('если первый адрес не ответил — берёт следующий', () async {
    final update = await checker(paths: const ['/missing.json', '/update.json'])
        .check(currentBuild: 1, assetKeys: const ['windows-x64']);
    expect(update, isNotNull);
    expect(hits, 2);
  });

  test('checkDetailed отличает «новее нет» от «проверить не удалось»',
      () async {
    const keys = ['windows-x64'];

    final upToDate =
        await checker().checkDetailed(currentBuild: 12, assetKeys: keys);
    expect(upToDate.outcome, UpdateCheckOutcome.upToDate);
    expect(upToDate.update, isNull);

    final available =
        await checker().checkDetailed(currentBuild: 10, assetKeys: keys);
    expect(available.outcome, UpdateCheckOutcome.available);
    expect(available.update!.manifest.build, 12);

    final offline = await checker(paths: const ['/missing.json'])
        .checkDetailed(currentBuild: 1, assetKeys: keys);
    expect(offline.outcome, UpdateCheckOutcome.failed);

    final stranger = await Ed25519().newKeyPair();
    final badSignature = await checker(
      keys: {'test': (await stranger.extractPublicKey()).bytes},
    ).checkDetailed(currentBuild: 1, assetKeys: keys);
    expect(badSignature.outcome, UpdateCheckOutcome.failed);

    final disabled = await checker(keys: const {})
        .checkDetailed(currentBuild: 1, assetKeys: keys);
    expect(disabled.outcome, UpdateCheckOutcome.disabled);
  });

  test('встроенные ключи подписи — корректные Ed25519 (по 32 байта)', () {
    final keys = decodeUpdateSigningKeys();
    expect(keys, isNotEmpty);
    for (final entry in keys.entries) {
      expect(entry.value, hasLength(32), reason: 'ключ ${entry.key}');
    }
  });

  test('androidAssetKeys: сначала архитектуры устройства, потом универсальный',
      () {
    expect(
      androidAssetKeys(['arm64-v8a', 'armeabi-v7a']),
      ['android-arm64-v8a', 'android-armeabi-v7a', 'android-universal'],
    );
  });
}
