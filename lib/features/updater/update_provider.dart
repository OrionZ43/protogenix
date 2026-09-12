// lib/features/updater/update_provider.dart
//
// Состояние обновления для баннера и страницы «Инфо»: проверка → скачивание
// → установка. Проверка идёт при запуске и по кнопке «Проверить» на странице
// «Инфо» (checkNow); ошибок наружу не отдаёт.

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
    this.checking = false,
    this.outcome,
    this.checkedAt,
  });

  final AvailableUpdate? update;
  final UpdatePhase phase;
  final double progress;

  /// Текст ошибки для пользователя (только в фазе [UpdatePhase.failed]).
  final String? error;
  final bool dismissed;

  /// Идёт проверка.
  final bool checking;

  /// Чем кончилась последняя проверка; null — ещё не проверяли.
  final UpdateCheckOutcome? outcome;
  final DateTime? checkedAt;

  bool get isVisible => update != null && (!dismissed || update!.isMandatory);

  UpdateState copyWith({
    UpdatePhase? phase,
    double? progress,
    String? error,
    bool? dismissed,
    bool? checking,
    UpdateCheckOutcome? outcome,
    DateTime? checkedAt,
  }) =>
      UpdateState(
        update: update,
        phase: phase ?? this.phase,
        progress: progress ?? this.progress,
        error: error,
        dismissed: dismissed ?? this.dismissed,
        checking: checking ?? this.checking,
        outcome: outcome ?? this.outcome,
        checkedAt: checkedAt ?? this.checkedAt,
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

  /// Проверить ещё раз — кнопка на странице «Инфо». Пока идёт скачивание или
  /// установка, ничего не делает.
  Future<void> checkNow() => _check();

  Future<void> _check() async {
    if (state.checking ||
        state.phase == UpdatePhase.downloading ||
        state.phase == UpdatePhase.installing) {
      return;
    }
    state = state.copyWith(checking: true);
    try {
      final result = await _checker.checkDetailed(
        currentBuild: await currentBuildNumber(),
        assetKeys: await currentAssetKeys(),
      );
      if (!mounted) return;
      if (result.outcome == UpdateCheckOutcome.failed) {
        // Найденное раньше обновление из-за сбоя сети не теряем
        state = state.copyWith(
            checking: false, outcome: result.outcome, checkedAt: DateTime.now());
      } else {
        state = UpdateState(
          update: result.update,
          outcome: result.outcome,
          checkedAt: DateTime.now(),
        );
      }
    } catch (e) {
      debugPrint('[Updater] Проверка обновлений не удалась: $e');
      if (mounted) {
        state = state.copyWith(
          checking: false,
          outcome: UpdateCheckOutcome.failed,
          checkedAt: DateTime.now(),
        );
      }
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
