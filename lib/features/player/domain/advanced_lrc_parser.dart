// lib/features/player/domain/advanced_lrc_parser.dart
//
// Единый парсер для всех форматов текстов:
//   • YRC  — NetEase послоговой: [startMs,dur](startMs,dur,0)word (startMs,dur,0)word
//   • Enhanced LRC — пословной:  [mm:ss.xx] <mm:ss.xx>word<mm:ss.xx>word
//   • Synced LRC  — построчный:  [mm:ss.xx] text
//   • Plain       — без таймингов
//
// ─── КЛЮЧЕВОЕ ПРАВИЛО ПРОБЕЛОВ ─────────────────────────────────────────────
// В YRC пробел В КОНЦЕ текста слога — это граница слова:
//   (15300,500,0)Twenty (15800,300,0)racks,
// → "Twenty " сигнализирует конец слова, "racks," — начало следующего.
// Никогда не вызывай .trim() на всей строке до детектирования границы!
// ──────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ENUM
// ─────────────────────────────────────────────────────────────────────────────

enum LyricsFormat { yrc, enhancedLrc, syncedLrc, plain }

extension LyricsFormatExt on LyricsFormat {
  String get label => switch (this) {
        LyricsFormat.yrc => 'YRC (Syllable)',
        LyricsFormat.enhancedLrc => 'Enhanced LRC (Word)',
        LyricsFormat.syncedLrc => 'Synced LRC (Line)',
        LyricsFormat.plain => 'Plain',
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────────────────────

class LyricSyllable {
  final String text;
  final int startMs;
  final int durationMs;
  final bool isPartOfWord;
  final bool isBackground;

  const LyricSyllable({
    this.isBackground = false,
    required this.text,
    required this.startMs,
    required this.durationMs,
    required this.isPartOfWord,
  });

  int get endMs => startMs + durationMs;

  /// Акцентированный слог: долгий (≥800ms) И содержит >1 символа.
  /// Такой слог разбивается на побуквенную анимацию в _EmphasizedSyllable.
  bool get isEmphasized => durationMs >= 800 && text.length > 1;

  @override
  String toString() =>
      'Syl("$text" @$startMs +$durationMs${isBackground ? " BG" : ""})';
}

class LyricWord {
  final List<LyricSyllable> syllables;
  const LyricWord({required this.syllables});

  String get text => syllables.map((s) => s.text).join();
  int get startMs => syllables.first.startMs;
  int get endMs => syllables.last.endMs;
}

class LyricLine {
  final int startMs;
  final int endMs;
  final List<LyricWord> words;
  final bool isOpposite;

  const LyricLine({
    required this.startMs,
    required this.endMs,
    required this.words,
    this.isOpposite = false,
  });

  int get durationMs => endMs - startMs;

  List<LyricSyllable> get allSyllables =>
      words.expand((w) => w.syllables).toList();

  /// Текст для неактивных строк и отладки.
  /// Слова соединяются пробелом — пробелы НЕ хранятся внутри syllable.text.
  String get plainText => words.map((w) => w.text).join(' ');

  bool get hasDetailedTimings =>
      words.isNotEmpty && words.any((w) => w.syllables.isNotEmpty);

  LyricLine copyWith({int? endMs}) => LyricLine(
        startMs: startMs,
        endMs: endMs ?? this.endMs,
        words: words,
        isOpposite: isOpposite,
      );
}

class ParsedLyrics {
  final List<LyricLine> lines;
  final LyricsFormat format;
  final Map<String, String> tags;

  const ParsedLyrics({
    required this.lines,
    required this.format,
    this.tags = const {},
  });

  bool get isEmpty => lines.isEmpty;
}

// ─────────────────────────────────────────────────────────────────────────────
// PARSER
// ─────────────────────────────────────────────────────────────────────────────

class AdvancedLrcParser {
  // ── Regex ─────────────────────────────────────────────────────────────────

  /// YRC заголовок строки: [startMs,durationMs]
  static final _yrcHeaderRx = RegExp(r'^\[(\d+),(\d+)\]');

  /// YRC слог: (startMs,durationMs,flag)text
  /// ВАЖНО: группа 3 захватывает текст ВКЛЮЧАЯ trailing-пробел
  static final _yrcSylRx = RegExp(r'\((\d+),(\d+),\d+\)([^(]*)');

  /// Synced/Enhanced LRC строка: [mm:ss.xx]
  static final _lrcLineRx = RegExp(r'^\[(\d{1,2}):(\d{2})\.(\d{2,3})\](.*)$');

  /// Enhanced LRC тег слова: <mm:ss.xx>text
  static final _enhancedWordRx =
      RegExp(r'<(\d{1,2}):(\d{2})\.(\d{2,3})>([^<]*)');

  /// LRC метатег: [ti:Title]
  static final _metaTagRx = RegExp(r'^\[([a-zA-Z]+):(.+)\]$');

  /// Маркеры дуэта
  static final _duetTagRx = RegExp(
    r'\[Singer\s*:\s*2\]|\[v2\]|\[OppositeAlignment\]|\[F:\s*\]|\(background\)',
    caseSensitive: false,
  );

  /// Китайские метаданные (作词/作曲) — строки с ними пропускаем
  static final _cnMetaRx = RegExp(r'作词|作曲|编曲|制作人|出品|录音|混音|母带');

  // ── Определение формата ──────────────────────────────────────────────────

  static LyricsFormat _detectFormat(String content) {
    final lines =
        content.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);

    int yrcCount = 0;
    int lrcCount = 0;
    int enhancedCount = 0;

    for (final line in lines) {
      if (_isYrcLine(line)) {
        yrcCount++;
      } else if (_lrcLineRx.hasMatch(line)) {
        lrcCount++;
        if (_enhancedWordRx.hasMatch(line)) enhancedCount++;
      }
    }

    if (yrcCount > 0) return LyricsFormat.yrc;
    if (enhancedCount > 0) return LyricsFormat.enhancedLrc;
    if (lrcCount > 0) return LyricsFormat.syncedLrc;
    return LyricsFormat.plain;
  }

  static bool _isYrcLine(String line) {
    if (!_yrcHeaderRx.hasMatch(line)) return false;
    return RegExp(r'\(\d+,\d+,\d+\)').hasMatch(line);
  }

  // ── Главный метод ────────────────────────────────────────────────────────

  static ParsedLyrics parse(String content) {
    if (content.trim().isEmpty) {
      return const ParsedLyrics(lines: [], format: LyricsFormat.plain);
    }
    final format = _detectFormat(content);
    debugPrint('[AdvancedLrcParser] Формат: ${format.label}');

    return switch (format) {
      LyricsFormat.yrc => _parseYrc(content),
      LyricsFormat.enhancedLrc => _parseEnhancedLrc(content),
      LyricsFormat.syncedLrc => _parseSyncedLrc(content),
      LyricsFormat.plain => _parsePlain(content),
    };
  }

  // ──────────────────────────────────────────────────────────────────────────
  // YRC PARSER
  // Реальный формат NetEase: [startMs,dur](startMs,dur,0)Twenty (startMs,dur,0)racks
  // ──────────────────────────────────────────────────────────────────────────

  static ParsedLyrics _parseYrc(String content) {
    final rawLines = content.split('\n');
    final result = <LyricLine>[];
    final tags = <String, String>{};

    for (final raw in rawLines) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      final meta = _metaTagRx.firstMatch(trimmed);
      if (meta != null) {
        tags[meta.group(1)!.toLowerCase()] = meta.group(2)!.trim();
        continue;
      }

      final line = _parseYrcLine(trimmed);
      if (line != null) result.add(line);
    }

    _fixLineEndTimes(result);
    debugPrint('[AdvancedLrcParser] YRC: ${result.length} строк');
    return ParsedLyrics(lines: result, format: LyricsFormat.yrc, tags: tags);
  }

  static LyricLine? _parseYrcLine(String raw) {
    final headerMatch = _yrcHeaderRx.firstMatch(raw);
    if (headerMatch == null) return null;

    final lineStartMs = int.parse(headerMatch.group(1)!);
    final lineDurMs = int.parse(headerMatch.group(2)!);
    final lineEndMs = lineStartMs + lineDurMs;
    final rest = raw.substring(headerMatch.end);

    final sylMatches = _yrcSylRx.allMatches(rest).toList();
    if (sylMatches.isEmpty) return null;

    // ─── СБОР СЫРЫХ СЛОГОВ ───────────────────────────────────────────────
    // _cleanYrcText НЕ вызывает .trim() — trailing-пробел это граница слова!
    final rawSyls = <({int start, int dur, String text})>[];
    for (final m in sylMatches) {
      final start = int.parse(m.group(1)!);
      final dur = int.parse(m.group(2)!);
      final text = _cleanYrcText(m.group(3) ?? '');

      // Пропускаем пустые (только пробелы или пустую строку)
      if (text.trim().isNotEmpty) {
        rawSyls.add((start: start, dur: dur, text: text));
      }
    }

    if (rawSyls.isEmpty) return null;

    // Пропускаем строки с китайскими метаданными
    final allText = rawSyls.map((s) => s.text).join('');
    if (_cnMetaRx.hasMatch(allText) && rawSyls.length <= 3) return null;

    // ─── КОНВЕРТИРУЕМ В LyricSyllable ────────────────────────────────────
    // text СОХРАНЯЕМ С ПРОБЕЛАМИ — _groupSyllablesIntoWords использует их
    // для определения границ слов, затем strip-ает при сохранении в модель.
    final syllables = rawSyls
        .map((s) => LyricSyllable(
              text: s.text, // с trailing-пробелом если есть
              startMs: s.start,
              durationMs: s.dur > 0 ? s.dur : 100,
              isPartOfWord: false, // определим в _groupSyllablesIntoWords
            ))
        .toList();

    final words = _groupSyllablesIntoWords(syllables);

    debugPrint(
      '[YRC] @$lineStartMs: ${words.map((w) => '"${w.text}"').join(' | ')}',
    );

    return LyricLine(
      startMs: lineStartMs,
      endMs: lineEndMs,
      words: words,
    );
  }

  /// Очищает текст слога от вложенных технических тегов.
  ///
  /// ⚠️  НЕ вызывает .trim() на результате!
  /// Trailing-пробел ("Twenty ") — маркер границы слова в YRC.
  /// Без него все слоги упадут в одно LyricWord.
  static String _cleanYrcText(String raw) {
    return raw
        .replaceAll(RegExp(r'\(\d+,\d+,\d+\)'), '') // вложенные слоговые теги
        .replaceAll(RegExp(r'\[\d+,\d+\]'), ''); // вложенные временны́е теги
    // .trim() — НАМЕРЕННО УБРАНО
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ENHANCED LRC PARSER
  // Формат: [mm:ss.xx] <mm:ss.xx>word <mm:ss.xx>word
  // ──────────────────────────────────────────────────────────────────────────

  static ParsedLyrics _parseEnhancedLrc(String content) {
    final rawLines = content.split('\n');
    final result = <LyricLine>[];
    final tags = <String, String>{};
    var singerIdx = 0;
    var duetActive = false;

    for (final raw in rawLines) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      final meta = _metaTagRx.firstMatch(trimmed);
      if (meta != null) {
        final k = meta.group(1)!.toLowerCase();
        tags[k] = meta.group(2)!.trim();
        continue;
      }

      final lrcMatch = _lrcLineRx.firstMatch(trimmed);
      if (lrcMatch == null) {
        continue;
      }

      var payload = lrcMatch.group(4)!;

      bool isOpposite = false;
      if (_duetTagRx.hasMatch(payload)) {
        duetActive = true;
        isOpposite = true;
        payload = payload.replaceAll(_duetTagRx, '').trim();
      } else if (duetActive) {
        isOpposite = singerIdx.isOdd;
      }
      singerIdx++;

      final wordMatches = _enhancedWordRx.allMatches(payload).toList();
      if (wordMatches.isEmpty) {
        continue;
      }

      final words = <LyricWord>[];

      final plainPayload =
          payload.replaceAll(RegExp(r'<\d{1,2}:\d{2}\.\d{2,3}>'), '').trim();
      final lineBgInfo = _processBackgroundText(plainPayload);
      final bool isLineBg = lineBgInfo.isBg;

      for (var i = 0; i < wordMatches.length; i++) {
        final wm = wordMatches[i];
        final wStart = _lrcMs(wm.group(1)!, wm.group(2)!, wm.group(3)!);
        var wTextRaw = wm.group(4)!.trim();
        if (wTextRaw.isEmpty) {
          continue;
        }

        if (isLineBg) {
          if (i == 0) {
            wTextRaw = wTextRaw.replaceFirst(RegExp(r'^[\(\[]'), '');
          }
          if (i == wordMatches.length - 1) {
            wTextRaw = wTextRaw.replaceFirst(RegExp(r'[\)\]]$'), ''); }
        }

        final bgInfo = _processBackgroundText(wTextRaw);
        final wText = bgInfo.text;

        final wEnd = i + 1 < wordMatches.length
            ? _lrcMs(wordMatches[i + 1].group(1)!, wordMatches[i + 1].group(2)!,
                wordMatches[i + 1].group(3)!)
            : wStart + 800;

        words.add(LyricWord(syllables: [
          LyricSyllable(
            text: wText,
            startMs: wStart,
            durationMs: (wEnd - wStart).clamp(50, 10000),
            isPartOfWord: false,
            isBackground: isLineBg || bgInfo.isBg,
          ),
        ]));
      }

      if (words.isEmpty) {
        continue;
      }

      result.add(LyricLine(
        startMs: words.first.startMs,
        endMs: words.last.endMs,
        words: words,
        isOpposite: isOpposite,
      ));
    }

    _fixLineEndTimes(result);
    debugPrint('[AdvancedLrcParser] Enhanced LRC: ${result.length} строк');
    return ParsedLyrics(
        lines: result, format: LyricsFormat.enhancedLrc, tags: tags);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SYNCED LRC PARSER
  // Формат: [mm:ss.xx] text
  // Для Beautiful Lyrics каждая строка разбивается на буквы
  // с искусственными таймингами — эффект Apple Music.
  // ──────────────────────────────────────────────────────────────────────────

  static ParsedLyrics _parseSyncedLrc(String content) {
    final rawLines = content.split('\n');
    final result = <LyricLine>[];
    final tags = <String, String>{};
    var singerIdx = 0;
    var duetActive = false;

    for (final raw in rawLines) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      final meta = _metaTagRx.firstMatch(trimmed);
      if (meta != null) {
        tags[meta.group(1)!.toLowerCase()] = meta.group(2)!.trim();
        continue;
      }

      final lrcMatch = _lrcLineRx.firstMatch(trimmed);
      if (lrcMatch == null) {
        continue;
      }

      final startMs =
          _lrcMs(lrcMatch.group(1)!, lrcMatch.group(2)!, lrcMatch.group(3)!);
      var payload = lrcMatch.group(4)!;

      bool isOpposite = false;
      if (_duetTagRx.hasMatch(payload)) {
        duetActive = true;
        isOpposite = true;
        payload = payload.replaceAll(_duetTagRx, '').trim();
      } else if (duetActive) {
        isOpposite = singerIdx.isOdd;
      }
      singerIdx++;

      final text = payload.trim();
      if (text.isEmpty) {
        continue;
      }

      final bgInfo = _processBackgroundText(text);

      result.add(LyricLine(
        startMs: startMs,
        endMs: startMs + 4000, // placeholder — уточним ниже
        words: [_plainWord(bgInfo.text, startMs, 4000, isBg: bgInfo.isBg)],
        isOpposite: isOpposite,
      ));
    }

    // Уточняем endMs = startMs следующей строки
    _fixLineEndTimes(result);

    // Разбиваем каждую строку на буквы с искусственными таймингами
    final expanded = result.map(_expandSyncedLine).toList();

    debugPrint('[AdvancedLrcParser] Synced LRC: ${expanded.length} строк');
    return ParsedLyrics(
        lines: expanded, format: LyricsFormat.syncedLrc, tags: tags);
  }

  /// Разбивает синхронизированную строку на слова→буквы с временны́ми таймингами.
  /// Каждая буква получает отдельный LyricSyllable — spring сработает на каждой.
  static LyricLine _expandSyncedLine(LyricLine line) {
    final text = line.plainText;
    final isLineBg =
        line.words.isNotEmpty && line.words.first.syllables.first.isBackground;
    final wordStrs = text.split(' ').where((w) => w.isNotEmpty).toList();
    if (wordStrs.isEmpty) return line;

    final lineStartMs = line.startMs;
    final lineDurMs = (line.endMs - line.startMs).clamp(800, 15000);

    // Суммарный вес = буквы + пробелы (25% веса буквы)
    const spaceW = 0.25;
    final totLetters = wordStrs.fold<int>(0, (s, w) => s + w.length);
    final totalW = totLetters + (wordStrs.length - 1) * spaceW;
    final msPerW = lineDurMs / totalW;

    final words = <LyricWord>[];
    var curMs = lineStartMs;

    for (var wi = 0; wi < wordStrs.length; wi++) {
      final word = wordStrs[wi];
      final wordDurMs = (word.length * msPerW).round();
      final msBpL = wordDurMs / word.length;
      final syllables = <LyricSyllable>[];

      final bgInfo = _processBackgroundText(wordStrs[wi]);
      final cleanWord = bgInfo.text;

      for (var li = 0; li < word.length; li++) {
        final letterDurMs = msBpL.round().clamp(40, 2000);
        syllables.add(LyricSyllable(
          text: cleanWord[li],
          startMs: curMs,
          durationMs: letterDurMs,
          isPartOfWord: li < word.length - 1,
          isBackground: isLineBg || bgInfo.isBg,
        ));
        curMs += letterDurMs;
      }

      words.add(LyricWord(syllables: syllables));

      // Пауза между словами
      if (wi < wordStrs.length - 1) {
        curMs += (msPerW * spaceW).round();
      }
    }

    return LyricLine(
      startMs: line.startMs,
      endMs: line.endMs,
      words: words,
      isOpposite: line.isOpposite,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PLAIN PARSER
  // ──────────────────────────────────────────────────────────────────────────

  static ParsedLyrics _parsePlain(String content) {
    final lines = content
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final result = lines
        .map((text) => LyricLine(
              startMs: 0,
              endMs: 0,
              words: [_plainWord(text, 0, 3000)],
            ))
        .toList();

    return ParsedLyrics(lines: result, format: LyricsFormat.plain);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  // ─── BACKGROUND TEXT PROCESSING ──────────────────────────────────────────
  static ({String text, bool isBg}) _processBackgroundText(String input) {
    if (input.isEmpty) return (text: input, isBg: false);

    final trimmed = input.trim();
    if ((trimmed.startsWith('(') && trimmed.endsWith(')')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      bool startsWithSpace = input.startsWith(' ');
      bool endsWithSpace = input.endsWith(' ');

      String stripped = trimmed.substring(1, trimmed.length - 1);

      return (
        text: (startsWithSpace ? ' ' : '') +
            stripped +
            (endsWithSpace ? ' ' : ''),
        isBg: true
      );
    }

    return (text: input, isBg: false);
  }

  /// Группирует плоский список слогов в LyricWord по пробелам.
  ///
  /// АЛГОРИТМ:
  ///   1. Детектируем границу слова: trailing-пробел в тексте слога ИЛИ
  ///      leading-пробел в следующем слоге.
  ///   2. Сохраняем текст БЕЗ пробелов (trim) — они нужны только для детекции.
  ///   3. Всё от текущей позиции до границы = один LyricWord.
  static List<LyricWord> _groupSyllablesIntoWords(
      List<LyricSyllable> syllables) {
    final words = <LyricWord>[];
    var current = <LyricSyllable>[];

    for (var i = 0; i < syllables.length; i++) {
      final syl = syllables[i];

      final endsSpace = syl.text.endsWith(' ');
      final nextSpace =
          i + 1 < syllables.length && syllables[i + 1].text.startsWith(' ');
      final isWordEnd = endsSpace || nextSpace || i == syllables.length - 1;

      current.add(LyricSyllable(
        text: syl.text,
        startMs: syl.startMs,
        durationMs: syl.durationMs,
        isPartOfWord: !isWordEnd,
        isBackground: syl.isBackground,
      ));

      if (isWordEnd && current.isNotEmpty) {
        final wordText = current.map((s) => s.text).join().trim();
        final bgInfo = _processBackgroundText(wordText);

        final processedSyllables = <LyricSyllable>[];

        if (bgInfo.isBg) {
          bool removedStart = false;
          for (var j = 0; j < current.length; j++) {
            var t = current[j].text;
            if (!removedStart &&
                (t.trimLeft().startsWith('(') ||
                    t.trimLeft().startsWith('['))) {
              t = t.replaceFirst(RegExp(r'^\s*[\(\[]'), '');
              removedStart = true;
            }
            current[j] = LyricSyllable(
              text: t,
              startMs: current[j].startMs,
              durationMs: current[j].durationMs,
              isPartOfWord: current[j].isPartOfWord,
              isBackground: true,
            );
          }

          bool removedEnd = false;
          for (var j = current.length - 1; j >= 0; j--) {
            var t = current[j].text;
            if (!removedEnd &&
                (t.trimRight().endsWith(')') || t.trimRight().endsWith(']'))) {
              t = t.replaceFirst(RegExp(r'[\)\]]\s*$'), '');
              removedEnd = true;
            }
            current[j] = LyricSyllable(
              text: t,
              startMs: current[j].startMs,
              durationMs: current[j].durationMs,
              isPartOfWord: current[j].isPartOfWord,
              isBackground: true,
            );
          }
        }

        for (var s in current) {
          processedSyllables.add(LyricSyllable(
            text: s.text.trim(),
            startMs: s.startMs,
            durationMs: s.durationMs,
            isPartOfWord: s.isPartOfWord,
            isBackground: s.isBackground || bgInfo.isBg,
          ));
        }

        words.add(LyricWord(syllables: List.unmodifiable(processedSyllables)));
        current = [];
      }
    }

    if (current.isNotEmpty) {
      words.add(LyricWord(syllables: List.unmodifiable(current)));
    }

    return words;
  }

  static LyricWord _plainWord(String text, int startMs, int durationMs,
      {bool isBg = false}) {
    final bgInfo = _processBackgroundText(text);
    return LyricWord(syllables: [
      LyricSyllable(
        text: bgInfo.text,
        startMs: startMs,
        durationMs: durationMs > 0 ? durationMs : 3000,
        isPartOfWord: false,
        isBackground: isBg || bgInfo.isBg,
      ),
    ]);
  }

  /// [mm:ss.xx] или [mm:ss.xxx] → миллисекунды
  static int _lrcMs(String mm, String ss, String frac) {
    final minutes = int.parse(mm);
    final seconds = int.parse(ss);
    final millis = frac.length == 2 ? int.parse(frac) * 10 : int.parse(frac);
    return Duration(
      minutes: minutes,
      seconds: seconds,
      milliseconds: millis,
    ).inMilliseconds;
  }

  /// Уточняет endMs каждой строки = startMs следующей - 50мс
  static void _fixLineEndTimes(List<LyricLine> lines) {
    for (var i = 0; i < lines.length - 1; i++) {
      final next = lines[i + 1].startMs;
      final current = lines[i];
      if (current.endMs >= next || current.endMs == current.startMs + 4000) {
        lines[i] = current.copyWith(
          endMs: (next - 50).clamp(current.startMs + 100, next),
        );
      }
    }
  }

  // ── Навигация ─────────────────────────────────────────────────────────────

  /// Бинарный поиск O(log n) — вызывается 60 FPS от плеера
  static int currentLineIndex(List<LyricLine> lines, int positionMs) {
    if (lines.isEmpty) return -1;
    var lo = 0, hi = lines.length - 1, result = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].startMs <= positionMs) {
        result = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return result;
  }

  static int currentLineIndexFromDuration(
          List<LyricLine> lines, Duration position) =>
      currentLineIndex(lines, position.inMilliseconds);
}
