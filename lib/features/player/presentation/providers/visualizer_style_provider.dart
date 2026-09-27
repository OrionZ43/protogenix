// lib/features/player/presentation/providers/visualizer_style_provider.dart
//
// Какой визуализатор показывать вместо пустого места, когда у трека нет
// текста. Выбор — на экране «Настройки», хранится в `settings.json`
// (`AppSettingsStore`, `data.md`). Сами стили — в `audio_visualizer.dart`.
//
// По умолчанию «Свет» — мягкие пятна цвета обложки. «Кольцо» и «Капля» были
// и удалены 2026-09-27: Orion забраковал «приборную» графику целиком
// («какие-то страшные они»), столбики оставлены вторым вариантом.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/app_settings_store.dart';

enum VisualizerStyle {
  glow('Свет'),
  bars('Столбики');

  const VisualizerStyle(this.label);

  final String label;
}

class VisualizerStyleNotifier extends StateNotifier<VisualizerStyle> {
  VisualizerStyleNotifier(this._store) : super(VisualizerStyle.glow) {
    _load();
  }

  static const _key = 'visualizerStyle';

  final AppSettingsStore _store;

  Future<void> _load() async {
    final saved = await _store.get<String>(_key);
    if (!mounted || saved == null) return;
    for (final style in VisualizerStyle.values) {
      if (style.name == saved) {
        state = style;
        return;
      }
    }
  }

  void select(VisualizerStyle style) {
    if (state == style) return;
    state = style;
    _store.set(_key, style.name);
  }
}

final visualizerStyleProvider =
    StateNotifierProvider<VisualizerStyleNotifier, VisualizerStyle>(
  (ref) => VisualizerStyleNotifier(AppSettingsStore()),
);
