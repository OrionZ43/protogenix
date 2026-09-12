// Живой замер поиска текстов по медиатеке Orion: настоящая сеть, база
// открывается только на чтение. По умолчанию пропускается. Запуск:
//   flutter test test/live/lyrics_bench_test.dart --run-skipped
// Печатает только метаданные вариантов — самих текстов песен в выводе нет.
// Базовая линия (до переделки 2026-09-12) — docs/CHANGELOG_CLAUDE.md.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:protogenix/features/library/data/lyrics_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Case {
  const _Case(this.title, this.artist, this.durationMs, this.from);
  final String title;
  final String artist;
  final int? durationMs;
  final String from;
}

const _curated = [
  _Case('Believer', 'Imagine Dragons', null, 'curated'),
  _Case('Blinding Lights', 'The Weeknd', null, 'curated'),
  _Case('Numb', 'Linkin Park', null, 'curated'),
  _Case('Группа крови', 'Кино', null, 'curated'),
  _Case('Мотылёк', 'Макс Корж', null, 'curated'),
  _Case('Imagine Dragons - Believer (Official Music Video)',
      'ImagineDragonsVEVO', null, 'curated-yt'),
  _Case('The Weeknd - Blinding Lights (Official Video)', 'TheWeekndVEVO',
      null, 'curated-yt'),
  _Case('Кино - Группа крови (official audio)', 'Kino', null, 'curated-yt'),
];

String _sec(int? ms) => ms == null ? '-' : '${(ms / 1000).round()}s';

void main() {
  test(
    'lyrics bench',
    () async {
      debugPrint = (String? message, {int? wrapWidth}) {};
      sqfliteFfiInit();
      final dbPath = p.join(Platform.environment['LOCALAPPDATA']!,
          'Z43 Studios', 'Protogenix', 'databases', 'protogenix.db');
      final db = await databaseFactoryFfi.openDatabase(dbPath,
          options: OpenDatabaseOptions(readOnly: true));
      final rows =
          await db.query('tracks', orderBy: 'addedAt DESC', limit: 25);
      await db.close();

      final cases = [
        for (final r in rows)
          _Case('${r['title']}', '${r['artist']}', r['durationMs'] as int?,
              'lib:${r['source']}'),
        ..._curated,
      ];

      var found = 0, scaled = 0, unsynced = 0, totalMs = 0;
      final formats = <String, int>{};
      for (final c in cases) {
        final sw = Stopwatch()..start();
        final results = await LyricsService.instance.fetchLyrics(
            title: c.title, artist: c.artist, trackDurationMs: c.durationMs);
        totalMs += sw.elapsedMilliseconds;
        final best =
            results.isNotEmpty && results.first.isConfident ? results.first : null;
        stdout.writeln('\n### ${c.artist} | ${c.title} [${c.from}] '
            'dur=${_sec(c.durationMs)} (${results.length} cand, '
            '${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s)');
        if (best == null) {
          stdout.writeln('  → не найдено');
        } else {
          found++;
          final m = best.metadata;
          formats[m.type.name] = (formats[m.type.name] ?? 0) + 1;
          if (best.timeScale != 1.0) scaled++;
          if (!best.timingsReliable) unsynced++;
          stdout.writeln('  → ${m.type.name} ${m.source} ${_sec(m.durationMs)} '
              '${m.artistName} | ${m.trackName}'
              '${best.timeScale != 1.0 ? ' ×${best.timeScale.toStringAsFixed(3)}' : ''}'
              '${best.timingsReliable ? '' : ' (без синхронизации)'}');
        }
        for (final r in results.take(4)) {
          final m = r.metadata;
          stdout.writeln('    ${r.isConfident ? '✓' : '·'} '
              '${r.scoreLabel.padLeft(6)} ${m.type.name.padRight(8)} '
              '${m.source.padRight(10)} ${_sec(m.durationMs).padLeft(5)}  '
              '${m.artistName} | ${m.trackName}');
        }
      }
      stdout.writeln('\n=== SUMMARY: found $found/${cases.length}, '
          'formats $formats, stretched $scaled, unsynced $unsynced, '
          'avg ${(totalMs / cases.length / 1000).toStringAsFixed(1)}s');
    },
    skip: 'живой замер: сеть и база Orion — '
        'flutter test test/live/lyrics_bench_test.dart --run-skipped',
    timeout: const Timeout(Duration(minutes: 25)),
  );
}
