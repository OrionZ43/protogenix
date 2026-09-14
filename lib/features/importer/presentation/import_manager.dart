// lib/features/importer/presentation/import_manager.dart
//
// Импорт в фоне. Живёт отдельно от шторки «Добавить трек»: её можно закрыть,
// импорт продолжится, а плашка поверх приложения (import_status_overlay.dart)
// покажет прогресс и даст остановить.
//
// Одновременно идёт один импорт, остальные ждут в очереди: ссылки из шторки,
// «В медиатеку» в поиске, свои файлы, перетаскивание, музыка с телефона. Та же
// ссылка второй раз в очередь не встаёт. «Остановить» останавливает текущий
// импорт и очищает очередь. Очередь живёт в памяти: если закрыть приложение,
// продолжить предложат только ссылку, которая шла.
//
// Медиатека и плейлисты обновляются по ходу, не чаще раза в 2 секунды, и после
// каждого импорта очереди. Раньше они обновлялись только в конце, и после
// закрытия шторки казалось, что из плейлиста на 500 треков ничего не скачалось
// (отзыв после 1.0.0). Очередь плеера трогается, только если она пуста:
// reloadFromLibrary начинает её с первого трека и сбил бы и игру, и паузу
// (data.md).
//
// Импорт по ссылке запоминается в settings.json, пока идёт: если приложение
// закрыли на середине, при следующем запуске плашка предложит продолжить.
// Повторный импорт той же ссылки пропускает уже скачанные треки.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_settings_store.dart';
import '../../library/presentation/library_provider.dart';
import '../../library/presentation/playlist_provider.dart';
import '../../player/presentation/providers/player_provider.dart';
import '../data/device_music.dart';
import '../data/importer_service.dart';

class ImportJob {
  const ImportJob({
    required this.title,
    required this.progress,
    this.running = true,
    this.stopping = false,
    this.url,
    this.queue = const [],
  });

  /// Что импортируется: «Яндекс Музыка», «Свои файлы», название трека из
  /// поиска…
  final String title;
  final ImportProgress progress;
  final bool running;

  /// Нажали «Остановить»: импорт доделает текущий трек и остановится.
  final bool stopping;

  /// Ссылка текущего импорта (у своих файлов и музыки с телефона — null).
  /// По ней карточка в поиске узнаёт, что качается именно её трек.
  final String? url;

  /// Ждут своей очереди: ссылки, у импорта без ссылки — null.
  final List<String?> queue;

  ImportJob copyWith({
    ImportProgress? progress,
    bool? stopping,
    List<String?>? queue,
  }) =>
      ImportJob(
        title: title,
        progress: progress ?? this.progress,
        running: running,
        stopping: stopping ?? this.stopping,
        url: url,
        queue: queue ?? this.queue,
      );
}

/// Сам импорт: сообщает прогресс, между треками проверяет [ImportControl].
typedef ImportRun = Future<void> Function(
    ImportControl control, void Function(ImportProgress) onProgress);

class _Queued {
  const _Queued(this.title, this.run, this.url);

  final String title;
  final ImportRun run;
  final String? url;
}

class ImportManager extends StateNotifier<ImportJob?> {
  ImportManager(this._ref) : super(null);

  static const _pendingKey = 'pendingImportUrl';

  final Ref _ref;
  final _settings = AppSettingsStore();
  final _queue = <_Queued>[];
  ImportControl? _control;
  bool _stopRequested = false;
  Timer? _refreshThrottle;
  bool _refreshQueued = false;
  Timer? _hideTimer;

  bool get busy => state?.running ?? false;

  /// [title] — что показать на плашке; по умолчанию — откуда ссылка.
  Future<void> importUrl(String url, {String? title}) => enqueue(
        title ?? _titleForUrl(url),
        (control, onProgress) => ImporterService.instance.importFromUrl(
            url: url, onProgress: onProgress, control: control),
        url: url,
      );

  Future<void> importLocalFiles(List<String> paths) => enqueue(
        'Свои файлы',
        (control, onProgress) => ImporterService.instance.importLocalFiles(
            paths: paths, onProgress: onProgress, control: control),
      );

  Future<void> importDeviceTracks(List<DeviceTrack> tracks) => enqueue(
        'Музыка на телефоне',
        (control, onProgress) => ImporterService.instance.importDeviceTracks(
            tracks: tracks, onProgress: onProgress, control: control),
      );

  /// По названию и исполнителю — «Слушать в Protogenix» для своих файлов
  /// друга (listen_link.dart): запись ищется на YouTube.
  Future<void> importSearchedTrack({
    required String title,
    required String artist,
    Duration? duration,
  }) =>
      enqueue(
        title,
        (control, onProgress) => ImporterService.instance.importSearchedTrack(
          title: title,
          artist: artist,
          duration: duration,
          onProgress: onProgress,
          control: control,
        ),
      );

  /// Запустить импорт, а если что-то уже идёт — поставить в очередь. Future
  /// завершается, когда пройдёт вся очередь; у поставленного в очередь — сразу.
  @visibleForTesting
  Future<void> enqueue(String title, ImportRun run, {String? url}) async {
    final task = _Queued(title, run, url);
    if (!busy) return _drain(task);
    // Та же ссылка уже качается или ждёт — второй раз не ставим
    if (url != null &&
        (state?.url == url || _queue.any((t) => t.url == url))) {
      return;
    }
    _queue.add(task);
    _publishQueue();
  }

  /// Остановить текущий импорт (доделает трек) и очистить очередь.
  void stop() {
    final job = state;
    if (job == null || !job.running) return;
    _stopRequested = true;
    _queue.clear();
    _control?.cancel();
    state = job.copyWith(stopping: true, queue: const []);
  }

  /// Убрать итог с экрана.
  void dismiss() {
    if (busy) return;
    _hideTimer?.cancel();
    state = null;
  }

  /// Ссылка, импорт которой оборвался: приложение закрыли на середине.
  Future<String?> interruptedUrl() => _settings.get<String>(_pendingKey);

  Future<void> forgetInterrupted() => _settings.set(_pendingKey, null);

  static String _titleForUrl(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host.contains('yandex')) return 'Яндекс Музыка';
    if (host.contains('spotify')) return 'Spotify';
    if (host.contains('youtu')) return 'YouTube';
    return 'Импорт по ссылке';
  }

  void _publishQueue() {
    final job = state;
    if (job != null) {
      state = job.copyWith(queue: [for (final t in _queue) t.url]);
    }
  }

  /// Импорт и следом вся очередь. Итог — по последнему импорту, а если их было
  /// несколько — по всей очереди, с названиями тех, что не получились.
  Future<void> _drain(_Queued first) async {
    _hideTimer?.cancel();
    _stopRequested = false;
    var task = first;
    var total = 0;
    final failed = <String>[];
    ImportProgress last;
    while (true) {
      last = await _runOne(task);
      total++;
      if (last.status == ImportStatus.error) failed.add(task.title);
      // Остановили или YouTube ограничил запросы — дальше очередь не идёт
      if (_stopRequested || last.resumable || _queue.isEmpty) break;
      // Скачанное — сразу в медиатеку: у ролика YouTube нет onTrackSaved
      await _refresh();
      if (_stopRequested || _queue.isEmpty) break;
      task = _queue.removeAt(0);
    }
    _queue.clear();

    await _refresh(endOfJob: true);
    if (!mounted) return;
    final chain = total > 1 && !_stopRequested && !last.resumable;
    final result = chain ? _chainResult(total, failed) : last;
    state = ImportJob(
      title: chain ? 'Очередь импорта' : task.title,
      progress: result,
      running: false,
    );
    // Итог висит несколько секунд; ошибка — пока не закроют
    if (result.status != ImportStatus.error) {
      _hideTimer = Timer(const Duration(seconds: 6), dismiss);
    }
  }

  Future<ImportProgress> _runOne(_Queued task) async {
    final control = ImportControl(onTrackSaved: _scheduleRefresh);
    _control = control;
    var last = const ImportProgress(
      status: ImportStatus.fetchingMeta,
      message: 'Подготовка…',
    );
    state = ImportJob(
      title: task.title,
      progress: last,
      url: task.url,
      queue: [for (final t in _queue) t.url],
    );
    final url = task.url;
    if (url != null) await _settings.set(_pendingKey, url);

    try {
      await task.run(control, (progress) {
        last = progress;
        final job = state;
        if (mounted && job != null) state = job.copyWith(progress: progress);
      });
    } catch (e) {
      debugPrint('[Import] Импорт упал: $e');
      last = const ImportProgress(
        status: ImportStatus.error,
        message: 'Ошибка импорта',
        error: 'Произошла непредвиденная ошибка во время импорта',
      );
    }

    _control = null;
    // Закончился или остановлен — продолжать при следующем запуске нечего.
    // Кроме ограничения YouTube: тогда ссылка остаётся для «Продолжить»
    if (url != null && !last.resumable) {
      await _settings.set(_pendingKey, null);
    }
    return last;
  }

  static ImportProgress _chainResult(int total, List<String> failed) {
    final ok = total - failed.length;
    if (failed.isEmpty) {
      return ImportProgress(
        status: ImportStatus.done,
        message: 'Готово: $ok из $total',
        progress: 1,
      );
    }
    return ImportProgress(
      status: ImportStatus.error,
      message: 'Не всё получилось',
      error: 'Не получилось: ${failed.map((t) => '«$t»').join(', ')}.'
          '${ok > 0 ? ' Остальное добавлено.' : ''}',
    );
  }

  /// Не чаще раза в 2 секунды: медиатека перечитывается целиком.
  void _scheduleRefresh() {
    if (_refreshThrottle != null) {
      _refreshQueued = true;
      return;
    }
    _refresh();
    _refreshThrottle = Timer(const Duration(seconds: 2), () {
      _refreshThrottle = null;
      if (_refreshQueued) {
        _refreshQueued = false;
        _scheduleRefresh();
      }
    });
  }

  Future<void> _refresh({bool endOfJob = false}) async {
    try {
      await _ref.read(libraryProvider.notifier).reload();
      await _ref.read(playlistsProvider.notifier).reload();
      _ref.invalidate(playlistTracksProvider);
      _ref.invalidate(playlistTracksNotifierProvider);
      if (endOfJob) await reloadPlayerIfIdle();
    } catch (e) {
      debugPrint('[Import] Не удалось обновить медиатеку: $e');
    }
  }

  /// Пустую очередь плеера — заполнить медиатекой. Играющую не трогаем:
  /// reloadFromLibrary начинает с первого трека (data.md). Отдельным методом —
  /// чтобы тест мог обойтись без плеера (audioHandler есть только в main()).
  @protected
  Future<void> reloadPlayerIfIdle() async {
    if (_ref.read(playerProvider).currentTrack == null) {
      await _ref.read(playerProvider.notifier).reloadFromLibrary();
    }
  }

  @override
  void dispose() {
    _refreshThrottle?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }
}

final importManagerProvider =
    StateNotifierProvider<ImportManager, ImportJob?>(ImportManager.new);

/// Текст для плашки и шторки: у ошибки — пояснение. Значки ✓ и ■ в начале
/// итога убираются — состояние видно по иконке.
String importText(ImportProgress p) {
  final text =
      p.status == ImportStatus.error ? (p.error ?? p.message) : p.message;
  return text.replaceFirst(RegExp(r'^[✓■]\s*'), '');
}
