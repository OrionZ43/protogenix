// lib/core/services/app_visibility.dart
//
// Видно ли приложение. Пока оно свёрнуто или экран выключен, музыка играет,
// а остальное может подождать: поиск текстов (karaoke_provider.dart) и цвета
// обложки (player_provider.dart) догоняют, когда приложение вернётся на экран.
// На слабых телефонах это заметно по батарее.
//
// «Видно» — resumed и inactive: в inactive (шторка уведомлений, звонок
// поверх) приложение ещё на экране. hidden, paused, detached — не видно.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppVisibilityNotifier extends StateNotifier<bool> {
  AppVisibilityNotifier()
      : super(isVisible(WidgetsBinding.instance.lifecycleState)) {
    _listener =
        AppLifecycleListener(onStateChange: (s) => state = isVisible(s));
  }

  late final AppLifecycleListener _listener;

  /// До первого кадра состояние неизвестно (null) — считаем, что видно.
  static bool isVisible(AppLifecycleState? s) =>
      s == null ||
      s == AppLifecycleState.resumed ||
      s == AppLifecycleState.inactive;

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }
}

final appVisibleProvider = StateNotifierProvider<AppVisibilityNotifier, bool>(
    (ref) => AppVisibilityNotifier());
