// lib/core/services/app_settings_store.dart
//
// Мелкие настройки интерфейса между запусками: settings.json в папке данных
// (AppPaths). Ключ — строка, значение — то, что переживает jsonEncode.
// Эквалайзер хранится отдельно (eq_settings_store.dart): у него своя проверка
// числа полос.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'app_paths.dart';

class AppSettingsStore {
  /// Без пути — общий экземпляр на всё приложение (settings.json в папке
  /// данных); с путём — отдельный, для тестов («как после перезапуска»).
  ///
  /// Общий — не для красоты. Раньше каждый провайдер создавал свой экземпляр
  /// со своим кэшем файла, и тот, кто писал последним, затирал ключи,
  /// записанные другими: переключил «Слоги/Строки», потом стиль визуализатора
  /// — после перезапуска «Слоги/Строки» откатывались.
  factory AppSettingsStore([String? filePath]) => filePath == null
      ? _shared ??= AppSettingsStore._(
          File(p.join(AppPaths.dataDir, 'settings.json')))
      : AppSettingsStore._(File(filePath));

  AppSettingsStore._(this._file);

  static AppSettingsStore? _shared;

  final File _file;
  Map<String, Object?>? _values;
  Future<Map<String, Object?>>? _loading;

  /// Записи идут по очереди: иначе более ранняя могла закончиться позже и
  /// оставить в файле старое состояние.
  Future<void> _writing = Future.value();

  /// Значение нужного типа; null — нет такого ключа или тип другой.
  Future<T?> get<T>(String key) async {
    final value = (await _read())[key];
    return value is T ? value : null;
  }

  Future<void> set(String key, Object? value) async {
    await _read();
    // Всегда от последнего состояния: два set подряд не теряют друг друга
    final values = {..._values!, key: value};
    _values = values;
    final write = _writing.then((_) => _write(values));
    _writing = write;
    await write;
  }

  Future<void> _write(Map<String, Object?> values) async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(jsonEncode(values), flush: true);
    } catch (e) {
      debugPrint('[Settings] Не удалось сохранить настройки: $e');
    }
  }

  Future<Map<String, Object?>> _read() async {
    final cached = _values;
    if (cached != null) return cached;
    // Файл читается один раз, даже если первыми пришли сразу несколько
    final loaded = await (_loading ??= _load());
    return _values ??= loaded;
  }

  Future<Map<String, Object?>> _load() async {
    var values = <String, Object?>{};
    try {
      if (await _file.exists()) {
        final json = jsonDecode(await _file.readAsString());
        if (json is Map) {
          values = {
            for (final entry in json.entries) '${entry.key}': entry.value,
          };
        }
      }
    } catch (e) {
      // Повреждённый файл — начинаем с умолчаний, он перезапишется
      debugPrint('[Settings] Не удалось прочитать настройки: $e');
    }
    return values;
  }
}
