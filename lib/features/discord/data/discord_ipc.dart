// lib/features/discord/data/discord_ipc.dart
//
// Клиент локального канала Discord для ПК — через него Protogenix ставит
// статус «Слушает…» (Rich Presence). Discord для ПК слушает именованный
// канал discord-ipc-0…9 (берёт первый свободный номер). Кадр: код операции
// и длина (int32, little-endian), затем JSON в UTF-8.
//
// Протокол «запрос — ответ»: у одного RandomAccessFile в Dart не может быть
// двух операций сразу, поэтому фонового чтения нет — после каждой команды
// читается её ответ. Без Flutter-импортов: клиент проверяется и обычным
// `dart`; лог — через [DiscordIpc.log].

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Коды операций канала Discord.
abstract final class DiscordOp {
  static const handshake = 0;
  static const frame = 1;
  static const close = 2;
  static const ping = 3;
  static const pong = 4;
}

class DiscordFrame {
  const DiscordFrame(this.op, this.data);

  final int op;
  final Map<String, dynamic> data;
}

/// Кадр: 8 байт заголовка (код операции и длина JSON) и JSON в UTF-8.
Uint8List encodeDiscordFrame(int op, Map<String, dynamic> data) {
  final payload = utf8.encode(jsonEncode(data));
  final bytes = Uint8List(8 + payload.length);
  ByteData.sublistView(bytes)
    ..setInt32(0, op, Endian.little)
    ..setInt32(4, payload.length, Endian.little);
  bytes.setRange(8, bytes.length, payload);
  return bytes;
}

/// Заголовок кадра: код операции и длина JSON.
({int op, int length}) decodeDiscordHeader(Uint8List header) {
  final view = ByteData.sublistView(header);
  return (
    op: view.getInt32(0, Endian.little),
    length: view.getInt32(4, Endian.little),
  );
}

/// Канал номер [index]. Путь — в форме со знаком вопроса после двух обратных
/// слэшей: привычную форму с точкой dart:io превращает в сетевой путь и
/// падает с ошибкой 53 (проверено 2026-09-14).
String discordPipePath(int index) {
  final bs = String.fromCharCode(92); // обратный слэш
  return '$bs$bs?${bs}pipe${bs}discord-ipc-$index';
}

void _noLog(String _) {}

/// Соединение с Discord для ПК. Методы вызывать по очереди, дожидаясь
/// каждого: у канала одна операция за раз.
class DiscordIpc {
  DiscordIpc(this.clientId, {this.log = _noLog});

  final String clientId;
  final void Function(String message) log;

  static const _timeout = Duration(seconds: 5);

  RandomAccessFile? _pipe;
  int _nonce = 0;

  bool get isConnected => _pipe != null;

  /// Подключиться и поздороваться. false — Discord не запущен или не принял
  /// приложение.
  Future<bool> connect() async {
    if (_pipe != null) return true;
    for (var index = 0; index < 10; index++) {
      final RandomAccessFile pipe;
      try {
        pipe = await File(discordPipePath(index)).open(mode: FileMode.append);
      } on FileSystemException {
        continue; // канала с таким номером нет
      }
      try {
        await pipe.writeFrom(encodeDiscordFrame(
            DiscordOp.handshake, {'v': 1, 'client_id': clientId}));
        final reply = await _readFrame(pipe).timeout(_timeout);
        if (reply.op == DiscordOp.frame && reply.data['evt'] == 'READY') {
          _pipe = pipe;
          return true;
        }
        log('[Discord] Отказ при подключении: ${reply.data}');
      } catch (e) {
        log('[Discord] Не удалось подключиться: $e');
      }
      _abandon(pipe);
      return false;
    }
    return false;
  }

  /// Поставить статус; null — убрать. false — соединение потеряно (Discord
  /// закрыли); статус тогда Discord убирает сам.
  Future<bool> setActivity(Map<String, dynamic>? activity) async {
    final pipe = _pipe;
    if (pipe == null) return false;
    try {
      await pipe.writeFrom(encodeDiscordFrame(DiscordOp.frame, {
        'cmd': 'SET_ACTIVITY',
        'args': {'pid': pid, if (activity != null) 'activity': activity},
        'nonce': '${++_nonce}',
      }));
      while (true) {
        final reply = await _readFrame(pipe).timeout(_timeout);
        if (reply.op == DiscordOp.ping) {
          await pipe
              .writeFrom(encodeDiscordFrame(DiscordOp.pong, reply.data));
          continue;
        }
        if (reply.op == DiscordOp.close) {
          throw StateError('Discord закрыл соединение: ${reply.data}');
        }
        // Отказ в самом статусе: слать его снова бессмысленно — считаем
        // отправленным, в лог причину
        if (reply.data['evt'] == 'ERROR') {
          log('[Discord] Статус не принят: ${reply.data['data']}');
        }
        return true;
      }
    } catch (e) {
      log('[Discord] Соединение потеряно: $e');
      _pipe = null;
      _abandon(pipe);
      return false;
    }
  }

  Future<void> close() async {
    final pipe = _pipe;
    _pipe = null;
    if (pipe != null) _abandon(pipe);
  }

  static Future<DiscordFrame> _readFrame(RandomAccessFile pipe) async {
    final (:op, :length) = decodeDiscordHeader(await _readExactly(pipe, 8));
    if (length < 0 || length > 1 << 20) {
      throw FormatException('Неверная длина кадра: $length');
    }
    if (length == 0) return DiscordFrame(op, const <String, dynamic>{});
    final decoded = jsonDecode(utf8.decode(await _readExactly(pipe, length)));
    return DiscordFrame(
        op, decoded is Map<String, dynamic> ? decoded : const {});
  }

  static Future<Uint8List> _readExactly(
      RandomAccessFile pipe, int count) async {
    final bytes = BytesBuilder(copy: false);
    while (bytes.length < count) {
      final chunk = await pipe.read(count - bytes.length);
      if (chunk.isEmpty) {
        throw const FileSystemException('Канал Discord закрыт');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  /// Закрыть, не дожидаясь: если операция повисла, close() падает — такое
  /// соединение всё равно бросаем.
  static void _abandon(RandomAccessFile pipe) {
    try {
      pipe.close().catchError((Object _) {});
    } catch (_) {}
  }
}
