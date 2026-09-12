// tool/youtube_health_check.dart
//
// Проверка «скачивание с YouTube ещё работает» (ежедневно на машине Orion).
// Для каждого трека — метаданные (videos.get, первый шаг импорта) и первые
// 256 КБ аудио через клиентов в том же порядке, что у импорта
// (kYoutubeClientFallbackOrder). Плюс поиск: через него идут импорт из Spotify
// и Яндекс Музыки и экран поиска. Запускается из tool/youtube_health_check.ps1.
//
//   dart run tool/youtube_health_check.dart [--log <файл>] [id ...]
//
// Коды выхода:
//   0 — всё качается первым клиентом (visionOS);
//   1 — первый клиент не справился, выручили следующие: похоже, YouTube
//       закрывает обход — смотреть .claude/rules/known-issues.md;
//   2 — какой-то трек не качается ни одним клиентом или не работает поиск;
//   3 — нет сети, проверка не состоялась.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:protogenix/core/services/youtube_clients.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

// Треки из медиатеки Orion, на которых скачивание ломалось в августе 2026.
// Популярные видео сюда не брать: они проходят и через сломанные клиенты.
const _defaultIds = ['jYvm-77C7XY', 'AEay6p5LdQg'];
const _searchQuery = 'Кино Группа крови';
const _wantedBytes = 256 * 1024;
const _timeout = Duration(seconds: 20);

Future<void> main(List<String> args) async {
  String? logPath;
  final ids = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--log' && i + 1 < args.length) {
      logPath = args[++i];
    } else {
      ids.add(args[i]);
    }
  }
  if (ids.isEmpty) ids.addAll(_defaultIds);

  final report = <String>[];
  void line(String text) {
    report.add(text);
    stdout.writeln(text);
  }

  line('=== ${_now()} · youtube_explode_dart ${_libraryVersion()}');
  var code = 0;
  if (!await _networkUp()) {
    line('итог: нет сети — проверка не состоялась');
    code = 3;
  } else {
    final yt = YoutubeExplode();
    for (final id in ids) {
      final result = await _checkTrack(yt, id);
      line('$id: ${result.text}');
      if (result.code > code) code = result.code;
    }
    final search = await _checkSearch(yt);
    line('поиск «$_searchQuery»: ${search.text}');
    if (search.code > code) code = search.code;
    yt.close();
    line(switch (code) {
      0 => 'итог: ок',
      1 => 'итог: первый клиент не справился, выручили запасные',
      _ => 'итог: СЛОМАНО',
    });
  }

  if (logPath != null) {
    final file = File(logPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('${report.join('\n')}\n',
        mode: FileMode.append, encoding: utf8);
  }
  // Отмена потоков youtube_explode может зависнуть — выходим явно.
  exit(code);
}

class _Result {
  const _Result(this.code, this.text);
  final int code;
  final String text;
}

Future<_Result> _checkTrack(YoutubeExplode yt, String id) async {
  try {
    await yt.videos.get(id).timeout(_timeout);
  } catch (e) {
    return _Result(2, 'НЕ КАЧАЕТСЯ — метаданные: ${_short(e)}');
  }
  final failures = <String>[];
  for (var i = 0; i < kYoutubeClientFallbackOrder.length; i++) {
    final client = kYoutubeClientFallbackOrder[i];
    final name = youtubeClientName(client);
    try {
      final manifest = await yt.videos.streamsClient
          .getManifest(id, ytClients: [client]).timeout(_timeout);
      if (manifest.audioOnly.isEmpty) {
        failures.add('$name: нет аудио');
        continue;
      }
      final stream = manifest.audioOnly.withHighestBitrate();
      final total = stream.size.totalBytes;
      final wanted = total < _wantedBytes ? total : _wantedBytes;
      final watch = Stopwatch()..start();
      final got = await _readHead(yt.videos.streamsClient.get(stream), wanted);
      if (got < wanted) {
        failures.add('$name: поток отдал $got байт из $wanted');
        continue;
      }
      final secs = (watch.elapsedMilliseconds / 1000).toStringAsFixed(1);
      final text = 'ок — $name, ${got ~/ 1024} КБ за $secs с';
      return i == 0
          ? _Result(0, text)
          : _Result(1, '$text (не прошли: ${failures.join('; ')})');
    } catch (e) {
      failures.add('$name: ${_short(e)}');
    }
  }
  return _Result(2, 'НЕ КАЧАЕТСЯ — ${failures.join('; ')}');
}

Future<_Result> _checkSearch(YoutubeExplode yt) async {
  try {
    final results = await yt.search.search(_searchQuery).timeout(_timeout);
    return results.isEmpty
        ? const _Result(2, 'НЕ РАБОТАЕТ — пустая выдача')
        : _Result(0, 'ок, результатов: ${results.length}');
  } catch (e) {
    return _Result(2, 'НЕ РАБОТАЕТ — ${_short(e)}');
  }
}

/// Читает поток, пока не наберётся [wanted] байт или он не замолчит на
/// [_timeout]; возвращает, сколько пришло. Ошибку потока пробрасывает.
Future<int> _readHead(Stream<List<int>> stream, int wanted) {
  final done = Completer<int>();
  var got = 0;
  Timer? stall;
  late final StreamSubscription<List<int>> sub;

  void finish() {
    if (done.isCompleted) return;
    stall?.cancel();
    done.complete(got);
    unawaited(sub.cancel()); // отмена может зависнуть — не ждём
  }

  void rearm() {
    stall?.cancel();
    stall = Timer(_timeout, finish);
  }

  sub = stream.listen(
    (chunk) {
      got += chunk.length;
      if (got >= wanted) {
        finish();
      } else {
        rearm();
      }
    },
    onError: (Object e, StackTrace s) {
      if (done.isCompleted) return;
      stall?.cancel();
      done.completeError(e, s);
    },
    onDone: finish,
    cancelOnError: true,
  );
  rearm();
  return done.future;
}

/// Отвечает ли youtube.com вообще: любой HTTP-ответ — сеть есть.
Future<bool> _networkUp() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client
        .headUrl(Uri.parse('https://www.youtube.com/'))
        .timeout(_timeout);
    final response = await request.close().timeout(_timeout);
    await response.drain<void>();
    return true;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

/// Версия youtube_explode_dart из pubspec.lock: по логу видно, после какого
/// обновления что-то поменялось.
String _libraryVersion() {
  try {
    final lock = File('pubspec.lock').readAsStringSync();
    return RegExp(r'youtube_explode_dart:[\s\S]*?version: "([^"]+)"')
            .firstMatch(lock)
            ?.group(1) ??
        '?';
  } catch (_) {
    return '?';
  }
}

String _now() {
  final t = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// Исключение одной строкой, не длиннее 140 символов, плюс «Reason:» от
/// youtube_explode, если он не попал в обрезанную часть.
String _short(Object e) {
  final text = e.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  final reason = RegExp(r'Reason: ([^.]+)').firstMatch(text)?.group(1);
  final head = text.length > 140 ? '${text.substring(0, 140)}…' : text;
  return reason != null && !head.contains(reason) ? '$head [$reason]' : head;
}
