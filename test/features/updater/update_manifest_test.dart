import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/updater/update_manifest.dart';

Map<String, dynamic> assetJson({
  List<Object?>? urls,
  Object? size = 10,
  Object? sha256,
}) =>
    {
      'urls': urls ?? ['https://example.com/protogenix.apk'],
      'size': size,
      'sha256': sha256 ?? 'A' * 64,
    };

Map<String, dynamic> manifestJson({
  Map<String, dynamic>? assets,
  Object? build = 12,
}) =>
    {
      'version': '1.1.0',
      'build': build,
      'notes': 'Что нового',
      'message': '   ',
      'releaseUrl': 'https://github.com/OrionZ43/protogenix/releases/tag/v1.1.0',
      'assets': assets ?? {'windows-x64': assetJson()},
    };

void main() {
  test('разбирает манифест', () {
    final manifest = UpdateManifest.fromJson(manifestJson());

    expect(manifest.version, '1.1.0');
    expect(manifest.build, 12);
    expect(manifest.minSupportedBuild, 0);
    expect(manifest.notes, 'Что нового');
    expect(manifest.message, isNull, reason: 'пустое объявление игнорируется');
    expect(manifest.releaseUrl?.host, 'github.com');
    expect(manifest.assets['windows-x64']!.sha256, 'a' * 64,
        reason: 'хэш приводится к нижнему регистру');
  });

  test('отклоняет адрес не по https', () {
    expect(
      () => UpdateAsset.fromJson(assetJson(urls: ['http://example.com/a.apk'])),
      throwsFormatException,
    );
  });

  test('отклоняет файл без адресов', () {
    expect(() => UpdateAsset.fromJson(assetJson(urls: [])),
        throwsFormatException);
  });

  test('отклоняет неверный SHA-256', () {
    expect(() => UpdateAsset.fromJson(assetJson(sha256: 'abc')),
        throwsFormatException);
  });

  test('отклоняет нулевой и слишком большой размер', () {
    expect(() => UpdateAsset.fromJson(assetJson(size: 0)),
        throwsFormatException);
    expect(
      () => UpdateAsset.fromJson(assetJson(size: UpdateAsset.maxSize + 1)),
      throwsFormatException,
    );
  });

  test('отклоняет манифест без номера сборки', () {
    expect(() => UpdateManifest.fromJson(manifestJson(build: null)),
        throwsFormatException);
  });

  test('assetFor берёт первый подходящий ключ', () {
    final manifest = UpdateManifest.fromJson(manifestJson(assets: {
      'android-armeabi-v7a': assetJson(size: 1),
      'android-universal': assetJson(size: 2),
    }));

    expect(
      manifest.assetFor(['android-arm64-v8a', 'android-armeabi-v7a']),
      same(manifest.assets['android-armeabi-v7a']),
    );
    expect(manifest.assetFor(['windows-x64']), isNull);
  });

  test('имя файла очищается от опасных символов', () {
    final asset = UpdateAsset.fromJson(
      assetJson(urls: ['https://example.com/dl/evil%20name%3F.apk']),
    );
    expect(asset.fileName, 'evil_name_.apk');
  });
}
