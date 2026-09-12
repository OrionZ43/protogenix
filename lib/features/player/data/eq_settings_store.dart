// lib/features/player/data/eq_settings_store.dart
//
// Настройки эквалайзера между запусками: включён ли он и усиление каждой
// полосы в дБ. Файл equalizer.json в папке данных (AppPaths). Число и частоты
// полос у каждого телефона свои, поэтому PlayerNotifier применяет сохранённое,
// только если полос столько же.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../core/services/app_paths.dart';

class EqSettings {
  const EqSettings({required this.enabled, required this.gains});

  final bool enabled;
  final List<double> gains;

  Map<String, Object> toJson() => {'enabled': enabled, 'gains': gains};

  /// null — файл повреждён или записан не нами.
  static EqSettings? fromJson(Object? json) {
    if (json is! Map) return null;
    final enabled = json['enabled'];
    final gains = json['gains'];
    if (enabled is! bool || gains is! List) return null;
    final values = <double>[];
    for (final gain in gains) {
      if (gain is! num || !gain.isFinite) return null;
      values.add(gain.toDouble());
    }
    return EqSettings(enabled: enabled, gains: values);
  }
}

class EqSettingsStore {
  EqSettingsStore([String? filePath])
      : _file = File(filePath ?? p.join(AppPaths.dataDir, 'equalizer.json'));

  final File _file;

  Future<EqSettings?> load() async {
    try {
      if (!await _file.exists()) return null;
      return EqSettings.fromJson(jsonDecode(await _file.readAsString()));
    } catch (e) {
      debugPrint('[EQ] Не удалось прочитать настройки: $e');
      return null;
    }
  }

  Future<void> save(EqSettings settings) async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(jsonEncode(settings.toJson()), flush: true);
    } catch (e) {
      debugPrint('[EQ] Не удалось сохранить настройки: $e');
    }
  }
}
