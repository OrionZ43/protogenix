// lib/features/updater/update_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'updater_service.dart';

/// Провайдер хранит UpdateInfo или null (нет обновлений / ещё не проверено).
/// Проверка происходит один раз при первом listen.
final updateProvider = StateNotifierProvider<UpdateNotifier, UpdateInfo?>(
  (ref) => UpdateNotifier(),
);

class UpdateNotifier extends StateNotifier<UpdateInfo?> {
  UpdateNotifier() : super(null) {
    _check();
  }

  bool _dismissed = false;

  Future<void> _check() async {
    final info = await UpdaterService.checkForUpdate();
    if (mounted) state = info;
  }

  /// Пользователь нажал «Позже» — скрываем баннер до следующего запуска.
  void dismiss() {
    _dismissed = true;
    state = null;
  }

  bool get isDismissed => _dismissed;

  /// Перепроверить вручную.
  Future<void> refresh() async => _check();
}
