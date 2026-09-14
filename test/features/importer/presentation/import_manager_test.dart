import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/core/services/app_paths.dart';
import 'package:protogenix/features/importer/data/importer_service.dart';
import 'package:protogenix/features/importer/presentation/import_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Плеер в тестах не создать: audioHandler есть только в main()
// (known-issues.md, «Тесты»). База и настройки — во временной папке.
class _Manager extends ImportManager {
  _Manager(super.ref);

  @override
  Future<void> reloadPlayerIfIdle() async {}
}

void main() {
  late ProviderContainer container;
  late ImportManager manager;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tmp = await Directory.systemTemp.createTemp('protogenix_queue_');
    AppPaths.databasesDir = tmp.path;
    AppPaths.dataDir = tmp.path;
  });

  setUp(() {
    container = ProviderContainer(overrides: [
      importManagerProvider.overrideWith((ref) => _Manager(ref)),
    ]);
    manager = container.read(importManagerProvider.notifier);
  });

  tearDown(() => container.dispose());

  ImportJob job() => container.read(importManagerProvider)!;

  ImportRun done(List<String> log, String name) =>
      (control, onProgress) async {
        log.add(name);
        onProgress(
            const ImportProgress(status: ImportStatus.done, message: '✓'));
      };

  test('пока идёт импорт, следующие ждут в очереди, дубль не встаёт',
      () async {
    final log = <String>[];
    final gate = Completer<void>();
    final chain = manager.enqueue('A', (control, onProgress) async {
      log.add('A');
      await gate.future;
    }, url: 'u1');
    expect(job().url, 'u1');

    await manager.enqueue('B', done(log, 'B'), url: 'u2');
    await manager.enqueue('B ещё раз', done(log, 'B2'), url: 'u2');
    await manager.enqueue('A ещё раз', done(log, 'A2'), url: 'u1');
    expect(job().queue, ['u2']);

    gate.complete();
    await chain;
    expect(log, ['A', 'B']);
    expect(job().running, isFalse);
    expect(job().progress.message, 'Готово: 2 из 2');
  });

  test('«Остановить» останавливает текущий и очищает очередь', () async {
    final log = <String>[];
    final gate = Completer<void>();
    final chain = manager.enqueue('A', (control, onProgress) async {
      await gate.future;
      onProgress(ImportProgress(
        status: ImportStatus.done,
        message: control.cancelled ? '■ Остановлено' : '✓',
      ));
    }, url: 'u1');
    await manager.enqueue('B', done(log, 'B'), url: 'u2');

    manager.stop();
    expect(job().stopping, isTrue);
    expect(job().queue, isEmpty);
    gate.complete();
    await chain;

    expect(log, isEmpty, reason: 'из очереди ничего не запускалось');
    expect(job().progress.message, '■ Остановлено');
  });

  test('неудачный импорт в очереди виден в итоге', () async {
    final gate = Completer<void>();
    final chain = manager.enqueue('Песня A', (control, onProgress) async {
      await gate.future;
      onProgress(const ImportProgress(
          status: ImportStatus.error, message: 'x', error: 'y'));
    }, url: 'u1');
    await manager.enqueue('Песня B', done([], 'B'), url: 'u2');

    gate.complete();
    await chain;

    expect(job().progress.status, ImportStatus.error);
    expect(job().progress.error,
        'Не получилось: «Песня A». Остальное добавлено.');
  });
}
