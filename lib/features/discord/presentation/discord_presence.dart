// lib/features/discord/presentation/discord_presence.dart
//
// Статус «Слушает…» в Discord — только Windows: Discord для ПК слушает
// локальный канал (discord_ipc.dart), мобильный — нет. Играет трек — статус
// с названием, исполнителем и временем; пауза или ничего не играет — статуса
// нет. Выключается на странице «Инфо»; по умолчанию включён.
//
// Отправляем, только когда что-то поменялось — трек, пауза, перемотка, — и
// не чаще раза в 4 секунды (у Discord ограничение: 5 обновлений за 20 секунд).
// Позиция плеера меняется непрерывно, а время начала «сейчас минус позиция»
// стоит на месте — по его скачку и видна перемотка.
//
// Discord не запущен или его закрыли — пробуем снова не чаще раза в 30
// секунд. Когда приложение закрывается, Discord сам убирает статус.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_settings_store.dart';
import '../../player/domain/player_state.dart';
import '../../player/domain/track_model.dart';
import '../../player/presentation/providers/player_provider.dart';
import '../data/discord_ipc.dart';
import '../domain/discord_activity.dart';

/// ID приложения Protogenix в Discord Developer Portal. Не секрет: по нему
/// Discord находит только название и картинки приложения.
const kDiscordClientId = '1514647875706163280';

class DiscordPresenceEnabledNotifier extends StateNotifier<bool> {
  // До чтения настроек — выключено: не мелькнуть статусом у того, кто его
  // выключил
  DiscordPresenceEnabledNotifier(this._store) : super(false) {
    _load();
  }

  static const _key = 'discordPresence';

  final AppSettingsStore _store;

  Future<void> _load() async {
    final saved = await _store.get<bool>(_key);
    if (mounted) state = saved ?? true;
  }

  void toggle() {
    state = !state;
    _store.set(_key, state);
  }
}

final discordPresenceEnabledProvider =
    StateNotifierProvider<DiscordPresenceEnabledNotifier, bool>(
  (ref) => DiscordPresenceEnabledNotifier(AppSettingsStore()),
);

/// Что показано или должно быть показано в статусе.
@immutable
class _Shown {
  const _Shown(this.track, this.start, this.duration);

  final TrackModel track;
  final DateTime start;
  final Duration duration;

  /// Для Discord то же самое: тот же трек, время начала — в пределах 2 с.
  bool sameAs(_Shown other) =>
      track.id == other.track.id &&
      start.difference(other.start).abs() < const Duration(seconds: 2) &&
      duration == other.duration;

  Map<String, dynamic> toActivity() => discordListeningActivity(
        trackId: track.id,
        title: track.title,
        artist: track.artist,
        album: track.album,
        start: start,
        duration: duration,
      );
}

/// Держит статус Discord в соответствии с плеером. Без Riverpod — чтобы
/// проверять тестами; связь с плеером и настройкой — в
/// [discordPresenceProvider].
class DiscordPresenceController {
  DiscordPresenceController(this._ipc, {DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  static const minInterval = Duration(seconds: 4);
  static const retryInterval = Duration(seconds: 30);

  final DiscordIpc _ipc;
  final DateTime Function() _now;

  bool _enabled = false;
  _Shown? _wanted;
  _Shown? _shown;
  DateTime? _lastSend;
  DateTime? _lastConnect;
  Timer? _timer;
  bool _busy = false;
  bool _disposed = false;

  _Shown? get _target => _enabled ? _wanted : null;

  void setEnabled(bool enabled) {
    _enabled = enabled;
    _schedule();
  }

  /// На каждое изменение плеера. Дёшево: сравниваются трек и время начала.
  void onPlayer({
    required TrackModel? track,
    required bool playing,
    required Duration position,
    required Duration total,
  }) {
    _wanted = track != null && playing
        ? _Shown(track, _now().subtract(position),
            total > Duration.zero ? total : track.duration)
        : null;
    if (!_matches(_target, _shown)) _schedule();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _ipc.close();
  }

  static bool _matches(_Shown? a, _Shown? b) =>
      a == null ? b == null : b != null && a.sameAs(b);

  void _schedule([Duration? after]) {
    if (_disposed || (_timer?.isActive ?? false)) return;
    var wait = after ?? Duration.zero;
    final last = _lastSend;
    if (after == null && last != null) {
      final left = minInterval - _now().difference(last);
      if (left > wait) wait = left;
    }
    _timer = Timer(wait, _flush);
  }

  Future<void> _flush() async {
    if (_disposed || _busy) return;
    final target = _target;
    if (_matches(target, _shown)) return;
    _busy = true;
    Duration? retry;
    try {
      if (target == null) {
        // Нет соединения — нет и статуса
        if (_ipc.isConnected) await _ipc.setActivity(null);
        if (!_enabled) {
          await _ipc.close();
          // Закрыли сами — при включении подключаться сразу
          _lastConnect = null;
        }
        _shown = null;
      } else if (await _ensureConnected()) {
        _shown = await _ipc.setActivity(target.toActivity()) ? target : null;
        if (_shown == null) retry = retryInterval;
      } else {
        retry = retryInterval;
      }
      _lastSend = _now();
    } finally {
      _busy = false;
    }
    if (retry != null) {
      _schedule(retry);
    } else if (!_matches(_target, _shown)) {
      _schedule(); // пока отправляли, в плеере что-то поменялось
    }
  }

  Future<bool> _ensureConnected() async {
    if (_ipc.isConnected) return true;
    final last = _lastConnect;
    if (last != null && _now().difference(last) < retryInterval) return false;
    _lastConnect = _now();
    return _ipc.connect();
  }
}

/// Связь статуса с плеером и настройкой. Живёт, пока его смотрит
/// ProtogenixApp; не на Windows ничего не делает.
final discordPresenceProvider = Provider<void>((ref) {
  if (!Platform.isWindows) return;
  final controller = DiscordPresenceController(
    DiscordIpc(kDiscordClientId, log: debugPrint),
  );
  ref.onDispose(controller.dispose);
  ref.listen<bool>(
    discordPresenceEnabledProvider,
    (_, enabled) => controller.setEnabled(enabled),
    fireImmediately: true,
  );
  ref.listen<ProtogenixPlayerState>(
    playerProvider,
    (_, state) => controller.onPlayer(
      track: state.currentTrack as TrackModel?,
      playing: state.isPlaying,
      position: state.position,
      total: state.total,
    ),
    fireImmediately: true,
  );
});
