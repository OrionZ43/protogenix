// lib/features/updater/update_provider.dart
//
// Состояние обновления для баннера: проверка при запуске → скачивание →
// установка. Проверка идёт один раз за запуск и ошибок наружу не отдаёт.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'update_checker.dart';
import 'update_downloader.dart';
import 'update_installer.dart';

enum UpdatePhase { available, downloading, installing, failed }

class UpdateState {
  const UpdateState({
    this.update,
    this.phase = UpdatePhase.available,
    this.progress = 0,
    this.error,
    this.dismissed = false,
  });

  final AvailableUpdate? update;
  final UpdatePhase phase;
  final double progress;

  /// Текст ошибки для пользователя (только в фазе [UpdatePhase.failed]).
  final String? error;
  final bool dismissed;

  bool get isVisible => update != null && (!dismissed || update!.isMandatory);

  UpdateState copyWith({
    UpdatePhase? phase,
    double? progress,
    String? error,
    bool? dismissed,
  }) =>
      UpdateState(
        update: update,
        phase: phase ?? this.phase,
        progress: progress ?? this.progress,
        error: error,
        dismissed: dismissed ?? this.dismissed,
      );
}

class UpdateNotifier extends StateNotifier<UpdateState> {
  UpdateNotifier({UpdateChecker? checker})
      : _checker = checker ?? UpdateChecker(),
        super(const UpdateState()) {
    _check();
  }

  final UpdateChecker _checker;
  double _lastProgress = 0;

  Future<void> _check() async {
    try {
      final update = await _checker.check(
        currentBuild: await currentBuildNumber(),
        assetKeys: await currentAssetKeys(),
      );
      if (mounted && update != null) state = UpdateState(update: update);
    } catch (e) {
      debugPrint('[Updater] Проверка обновлений не удалась: $e');
    }
  }

  Future<void> downloadAndInstall() async {
    final asset = state.update?.asset;
    if (asset == null ||
        state.phase == UpdatePhase.downloading ||
        state.phase == UpdatePhase.installing) {
      return;
    }

    _lastProgress = 0;
    state = state.copyWith(phase: UpdatePhase.downloading, progress: 0);
    try {
      final directory = Directory(
        p.join((await getTemporaryDirectory()).path, 'protogenix-update'),
      );
      final file = await UpdateDownloader(directory: directory)
          .download(asset, onProgress: _onProgress);
      if (!mounted) return;

      state = state.copyWith(phase: UpdatePhase.installing, progress: 1);
      await UpdateInstaller.install(file);

      // На Android открылся системный установщик. Если его закрыли,
      // кнопку можно нажать ещё раз — файл уже скачан.
      if (mounted) state = state.copyWith(phase: UpdatePhase.available);
    } on UpdateInstallException catch (e) {
      if (mounted) {
        state = state.copyWith(phase: UpdatePhase.failed, error: e.message);
      }
    } catch (e) {
      debugPrint('[Updater] Обновление не удалось: $e');
      if (mounted) {
        state = state.copyWith(
          phase: UpdatePhase.failed,
          error: state.phase == UpdatePhase.installing
              ? 'Не удалось запустить установку'
              : 'Не удалось скачать обновление',
        );
      }
    }
  }

  /// Прогресс в состояние — не чаще раза в процент, иначе баннер
  /// перерисовывается на каждом пакете из сети.
  void _onProgress(double progress) {
    if (!mounted) return;
    if (progress - _lastProgress < 0.01 && progress < 1) return;
    _lastProgress = progress;
    state = state.copyWith(progress: progress);
  }

  /// «Позже» — скрыть до следующего запуска. Обязательное обновление
  /// не скрывается.
  void dismiss() {
    if (state.update?.isMandatory ?? false) return;
    state = state.copyWith(dismissed: true);
  }
}

final updateProvider =
    StateNotifierProvider<UpdateNotifier, UpdateState>((ref) {
  return UpdateNotifier();
});
