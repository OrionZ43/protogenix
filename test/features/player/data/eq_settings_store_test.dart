import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:protogenix/features/player/data/eq_settings_store.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('eq_settings_test');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('сохранённые настройки читаются обратно', () async {
    final store = EqSettingsStore(p.join(dir.path, 'equalizer.json'));
    await store.save(const EqSettings(enabled: true, gains: [3, -1.5, 0, 2, 6]));
    await store.save(const EqSettings(enabled: false, gains: [1, 2, 3, 4, 5]));

    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.enabled, isFalse);
    expect(loaded.gains, [1, 2, 3, 4, 5]);
  });

  test('нет файла — null', () async {
    final store = EqSettingsStore(p.join(dir.path, 'missing.json'));
    expect(await store.load(), isNull);
  });

  test('повреждённый или чужой файл — null, без исключения', () async {
    final path = p.join(dir.path, 'equalizer.json');
    final store = EqSettingsStore(path);

    await File(path).writeAsString('{не json');
    expect(await store.load(), isNull);

    await File(path).writeAsString('{"enabled": "yes", "gains": [1]}');
    expect(await store.load(), isNull);

    await File(path).writeAsString('{"enabled": true, "gains": [1, "x"]}');
    expect(await store.load(), isNull);
  });
}
