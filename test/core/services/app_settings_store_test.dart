import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:protogenix/core/services/app_settings_store.dart';

void main() {
  late Directory tmp;
  late String path;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('protogenix_settings_');
    path = p.join(tmp.path, 'settings.json');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('без файла — значений нет', () async {
    expect(await AppSettingsStore(path).get<bool>('lyricsLinesOnly'), isNull);
  });

  test('значение переживает перезапуск, соседние ключи не теряются', () async {
    final store = AppSettingsStore(path);
    await store.set('lyricsLinesOnly', true);
    await store.set('other', 3);

    final reopened = AppSettingsStore(path);
    expect(await reopened.get<bool>('lyricsLinesOnly'), isTrue);
    expect(await reopened.get<int>('other'), 3);
  });

  test('другой тип — null, а не исключение', () async {
    final store = AppSettingsStore(path);
    await store.set('lyricsLinesOnly', 'yes');
    expect(await AppSettingsStore(path).get<bool>('lyricsLinesOnly'), isNull);
  });

  test('повреждённый файл — умолчания, и он перезаписывается', () async {
    await File(path).writeAsString('{не json');
    final store = AppSettingsStore(path);
    expect(await store.get<bool>('lyricsLinesOnly'), isNull);

    await store.set('lyricsLinesOnly', true);
    expect(await AppSettingsStore(path).get<bool>('lyricsLinesOnly'), isTrue);
  });
}
