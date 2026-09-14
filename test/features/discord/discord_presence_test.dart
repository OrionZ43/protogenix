import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/discord/data/discord_ipc.dart';
import 'package:protogenix/features/discord/presentation/discord_presence.dart';
import 'package:protogenix/features/player/domain/track_model.dart';

// Discord вместо настоящего канала: запоминает, что ему отправили.
class _FakeIpc extends DiscordIpc {
  _FakeIpc() : super('test');

  bool discordRunning = true;
  bool _connected = false;
  int connects = 0;
  final sent = <Map<String, dynamic>?>[];

  @override
  bool get isConnected => _connected;

  @override
  Future<bool> connect() async {
    connects++;
    _connected = discordRunning;
    return _connected;
  }

  @override
  Future<bool> setActivity(Map<String, dynamic>? activity) async {
    if (!_connected) return false;
    sent.add(activity);
    return true;
  }

  @override
  Future<void> close() async {
    _connected = false;
  }
}

const _track = TrackModel(
  id: '7wtfhZwyrcc',
  title: 'Believer',
  artist: 'Imagine Dragons',
  album: 'Evolve',
  duration: Duration(minutes: 3, seconds: 24),
  coverImage: AssetImage('assets/images/cover_placeholder.png'),
);

void main() {
  final t0 = DateTime(2026, 9, 14, 12);
  late DateTime now;
  late _FakeIpc ipc;
  late DiscordPresenceController presence;

  void start() {
    now = t0;
    ipc = _FakeIpc();
    presence = DiscordPresenceController(ipc, clock: () => now)
      ..setEnabled(true);
  }

  void play(Duration position, {bool playing = true}) => presence.onPlayer(
        track: _track,
        playing: playing,
        position: position,
        total: _track.duration,
      );

  Future<void> wait(WidgetTester tester, Duration duration) async {
    now = now.add(duration);
    await tester.pump(duration);
  }

  testWidgets('играет — статус; позиция идёт — Discord не дёргаем; пауза — пусто',
      (tester) async {
    start();
    play(const Duration(seconds: 10));
    await wait(tester, Duration.zero);
    expect(ipc.sent, hasLength(1));
    expect(ipc.sent.single!['details'], 'Believer');

    for (var s = 11; s <= 20; s++) {
      await wait(tester, const Duration(seconds: 1));
      play(Duration(seconds: s));
    }
    await wait(tester, const Duration(seconds: 5));
    expect(ipc.sent, hasLength(1), reason: 'время начала то же');

    play(const Duration(seconds: 25), playing: false);
    await wait(tester, const Duration(seconds: 5));
    expect(ipc.sent.last, isNull);
    presence.dispose();
  });

  testWidgets('перемотка — новое время, но не чаще раза в 4 секунды',
      (tester) async {
    start();
    play(const Duration(seconds: 10));
    await wait(tester, Duration.zero);

    play(const Duration(seconds: 100)); // перемотали сразу после отправки
    await wait(tester, const Duration(seconds: 1));
    expect(ipc.sent, hasLength(1), reason: 'ещё не прошло 4 секунды');

    await wait(tester, const Duration(seconds: 3));
    expect(ipc.sent, hasLength(2));
    final timestamps = ipc.sent.last!['timestamps'] as Map;
    expect(timestamps['start'],
        t0.subtract(const Duration(seconds: 100)).millisecondsSinceEpoch);
    presence.dispose();
  });

  testWidgets('выключили — статус убран, соединение закрыто; включили — снова',
      (tester) async {
    start();
    play(const Duration(seconds: 10));
    await wait(tester, Duration.zero);

    presence.setEnabled(false);
    await wait(tester, const Duration(seconds: 4));
    expect(ipc.sent.last, isNull);
    expect(ipc.isConnected, isFalse);

    presence.setEnabled(true);
    await wait(tester, const Duration(seconds: 4));
    expect(ipc.sent.last?['details'], 'Believer');
    presence.dispose();
  });

  testWidgets('Discord не запущен — пробуем не чаще раза в 30 секунд',
      (tester) async {
    start();
    ipc.discordRunning = false;
    play(const Duration(seconds: 10));
    await wait(tester, Duration.zero);
    expect(ipc.connects, 1);

    // Перемотки — поводы отправить, но подключаться рано
    for (var i = 1; i <= 5; i++) {
      play(Duration(seconds: 10 + i * 20));
      await wait(tester, const Duration(seconds: 5));
    }
    expect(ipc.connects, 1);

    ipc.discordRunning = true;
    await wait(tester, const Duration(seconds: 10));
    expect(ipc.connects, 2);
    expect(ipc.sent.last?['details'], 'Believer');
    presence.dispose();
  });
}
