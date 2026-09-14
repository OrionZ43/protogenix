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
  AppSettingsStore([String? filePath])
      : _file = File(filePath ?? p.join(AppPaths.dataDir, 'settings.json'));

  final File _file;
  Map<String, Object?>? _values;

  /// Значение нужного типа; null — нет такого ключа или тип другой.
  Future<T?> get<T>(String key) async {
    final value = (await _read())[key];
    return value is T ? value : null;
  }

  Future<void> set(String key, Object? value) async {
    final values = {...await _read(), key: value};
    _values = values;
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
    return _values = values;
  }
}
