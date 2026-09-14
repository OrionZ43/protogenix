// lib/features/player/presentation/providers/lyrics_display_provider.dart
//
// Как показывать текст с таймингами по словам или слогам: как есть («Слоги»)
// или только строками. По строкам рисовать заметно легче — выбор просили
// в отзывах, в том числе потому, что на слабом телефоне караоке тормозит.
// Текст с таймингами только по строкам от настройки не зависит.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/app_settings_store.dart';

class LyricsLinesOnlyNotifier extends StateNotifier<bool> {
  LyricsLinesOnlyNotifier(this._store) : super(false) {
    _load();
  }

  static const _key = 'lyricsLinesOnly';

  final AppSettingsStore _store;

  Future<void> _load() async {
    final saved = await _store.get<bool>(_key);
    if (mounted && saved != null) state = saved;
  }

  void toggle() {
    state = !state;
    _store.set(_key, state);
  }
}

final lyricsLinesOnlyProvider =
    StateNotifierProvider<LyricsLinesOnlyNotifier, bool>(
  (ref) => LyricsLinesOnlyNotifier(AppSettingsStore()),
);
