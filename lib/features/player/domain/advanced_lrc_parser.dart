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
//
// ─── WHISPER EFFECT (бэк-вокал / ад-либы) ──────────────────────────────────
// Слова/слоги, обёрнутые в круглые ( ) или квадратные [ ] скобки,
// помечаются флагом isBackground = true.
// Скобки удаляются из отображаемого текста.
// Если ВСЕ слова строки являются фоновыми — LyricLine.isBackgroundLine = true.
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

  /// true — слог является частью бэк-вокала / ад-либа (был в скобках).
  /// Отображается меньшим шрифтом, курсивом, сниженной непрозрачностью.
  final bool isBackground;

  const LyricSyllable({
    required this.text,
    required this.startMs,
    required this.durationMs,
    required this.isPartOfWord,
    this.isBackground = false,
  });

  int get endMs => startMs + durationMs;

  /// Акцентированный слог: долгий (≥800ms) И содержит >1 символа.
  /// Такой слог разбивается на побуквенную анимацию в _EmphasizedSyllable.
  bool get isEmphasized => durationMs >= 800 && text.length > 1;

  @override
  String toString() =>
      'Syl("$text" @$startMs +$durationMs${isBackground ? ' [bg]' : ''})';
}

class LyricWord {
  final List<LyricSyllable> syllables;

  /// true если ВСЕ слоги слова являются фоновыми.
  final bool isBackground;

  const LyricWord({
    required this.syllables,
    this.isBackground = false,
  });

  String get text => syllables.map((s) => s.text).join();
  int get startMs => syllables.first.startMs;
  int get endMs => syllables.last.endMs;
}

class LyricLine {
  final int startMs;
  final int endMs;
  final List<LyricWord> words;
  final bool isOpposite;

  /// true если ВСЕ слова строки являются бэк-вокалом.
  /// Вся строка рендерится в «фоновом» стиле.
  final bool isBackgroundLine;

  const LyricLine({
    required this.startMs,
    required this.endMs,
    required this.words,
    this.isOpposite = false,
    this.isBackgroundLine = false,
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
        isBackgroundLine: isBackgroundLine,
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

  /// Бэк-вокал: текст целиком в круглых или квадратных скобках
  /// Захватывает содержимое без скобок в группе 1.
  /// Примеры: "(yeah)", "[oh oh]", "(back vocals here)"

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

    final format = yrcCount > 0
        ? LyricsFormat.yrc
        : enhancedCount > 0
            ? LyricsFormat.enhancedLrc
            : lrcCount > 0
                ? LyricsFormat.syncedLrc
                : LyricsFormat.plain;

    // ── DEBUG: итог детекции ──────────────────────────────────────────────
    debugPrint(
      '[AdvancedLrcParser] detectFormat → ${format.label} '
      '(yrc=$yrcCount lrc=$lrcCount enhanced=$enhancedCount)',
    );
    return format;
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

    // ── DEBUG: первые строки сырого контента ─────────────────────────────
    final preview = content.split('\n').take(6).join(' | ');
    debugPrint('[AdvancedLrcParser] parse() format=${format.label}');
    debugPrint('[AdvancedLrcParser] preview: $preview');

    return switch (format) {
      LyricsFormat.yrc => _parseYrc(content),
      LyricsFormat.enhancedLrc => _parseEnhancedLrc(content),
      LyricsFormat.syncedLrc => _parseSyncedLrc(content),
      LyricsFormat.plain => _parsePlain(content),
    };
  }

  // ──────────────────────────────────────────────────────────────────────────
  // YRC PARSER
  // ──────────────────────────────────────────────────────────────────────────

  static ParsedLyrics _parseYrc(String content) {
    final rawLines = content.split('\n');
    final result = <LyricLine>[];
    final tags = <String, String>{};

    for (final raw in rawLines) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;

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

    // ─── СБОР СЫРЫХ СЛОГОВ (потоковый stateful парсинг скобок) ─────────
    // bgState переносится между слогами: "(Yeah" syl1 + "ay" syl2 + ")" syl3
    // → все три помечаются isBackground=true, скобки удаляются из текста.
    final rawSyls = <({int start, int dur, String text, bool isBackground})>[];
    var bgState = false; // состояние фонового режима между слогами

    for (final m in sylMatches) {
      final start = int.parse(m.group(1)!);
      final dur = int.parse(m.group(2)!);
      final rawText = _cleanYrcText(m.group(3) ?? '');

      // Пробел-граница слова не содержит скобок → просто пробрасываем состояние
      if (rawText.trim().isEmpty) continue;

      final r = _processWithState(rawText, bgState);
      bgState = r.nextState;

      // Слоги с пустым текстом (только скобки) пропускаем
      if (r.text.trim().isNotEmpty) {
        rawSyls
            .add((start: start, dur: dur, text: r.text, isBackground: r.isBg));
      }
    }

    if (rawSyls.isEmpty) return null;

    final allText = rawSyls.map((s) => s.text).join('');
    if (_cnMetaRx.hasMatch(allText) && rawSyls.length <= 3) return null;

    final syllables = rawSyls
        .map((s) => LyricSyllable(
              text: s.text,
              startMs: s.start,
              durationMs: s.dur > 0 ? s.dur : 100,
              isPartOfWord: false,
              isBackground: s.isBackground,
            ))
        .toList();

    final words = _groupSyllablesIntoWords(syllables);
    final isBackgroundLine =
        words.isNotEmpty && words.every((w) => w.isBackground);

    debugPrint(
      '[YRC] @$lineStartMs: ${words.map((w) => '"${w.text}"${w.isBackground ? '[bg]' : ''}').join(' | ')}',
    );

    return LyricLine(
      startMs: lineStartMs,
      endMs: lineEndMs,
      words: words,
      isBackgroundLine: isBackgroundLine,
    );
  }

  /// Очищает текст слога от вложенных технических тегов.
  ///
  /// ⚠️  НЕ вызывает .trim() на результате!
  static String _cleanYrcText(String raw) {
    return raw
        .replaceAll(RegExp(r'\(\d+,\d+,\d+\)'), '')
        .replaceAll(RegExp(r'\[\d+,\d+\]'), '');
    // .trim() — НАМЕРЕННО УБРАНО
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ENHANCED LRC PARSER
  // ──────────────────────────────────────────────────────────────────────────

  static ParsedLyrics _parseEnhancedLrc(String content) {
    final rawLines = content.split('\n');
    final result = <LyricLine>[];
    final tags = <String, String>{};
    var singerIdx = 0;
    var duetActive = false;

    for (final raw in rawLines) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;

      final meta = _metaTagRx.firstMatch(trimmed);
      if (meta != null) {
        final k = meta.group(1)!.toLowerCase();
        tags[k] = meta.group(2)!.trim();
        continue;
      }

      final lrcMatch = _lrcLineRx.firstMatch(trimmed);
      if (lrcMatch == null) continue;

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
      if (wordMatches.isEmpty) continue;

      final words = <LyricWord>[];
      var bgState = false; // состояние скобок сбрасывается на каждую строку

      for (var i = 0; i < wordMatches.length; i++) {
        final wm = wordMatches[i];
        final wStart = _lrcMs(wm.group(1)!, wm.group(2)!, wm.group(3)!);

        // rawText может содержать ведущий/замыкающий пробел (граница слов),
        // а также скобки в произвольной позиции
        final rawWordText = wm.group(4)!;
        final r = _processWithState(rawWordText, bgState);
        bgState = r.nextState;

        final cleanText = r.text.trim();
        if (cleanText.isEmpty) continue;

        final wEnd = i + 1 < wordMatches.length
            ? _lrcMs(wordMatches[i + 1].group(1)!, wordMatches[i + 1].group(2)!,
                wordMatches[i + 1].group(3)!)
            : wStart + 800;

        final syl = LyricSyllable(
          text: cleanText,
          startMs: wStart,
          durationMs: (wEnd - wStart).clamp(50, 10000),
          isPartOfWord: false,
          isBackground: r.isBg,
        );

        words.add(LyricWord(
          syllables: [syl],
          isBackground: r.isBg,
        ));
      }

      if (words.isEmpty) continue;

      final isBackgroundLine =
          words.isNotEmpty && words.every((w) => w.isBackground);

      result.add(LyricLine(
        startMs: words.first.startMs,
        endMs: words.last.endMs,
        words: words,
        isOpposite: isOpposite,
        isBackgroundLine: isBackgroundLine,
      ));
    }

    _fixLineEndTimes(result);
    debugPrint('[AdvancedLrcParser] Enhanced LRC: ${result.length} строк');
    return ParsedLyrics(
        lines: result, format: LyricsFormat.enhancedLrc, tags: tags);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SYNCED LRC PARSER
  // ──────────────────────────────────────────────────────────────────────────

  static ParsedLyrics _parseSyncedLrc(String content) {
    final rawLines = content.split('\n');
    final result = <LyricLine>[];
    final tags = <String, String>{};
    var singerIdx = 0;
    var duetActive = false;

    for (final raw in rawLines) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;

      final meta = _metaTagRx.firstMatch(trimmed);
      if (meta != null) {
        tags[meta.group(1)!.toLowerCase()] = meta.group(2)!.trim();
        continue;
      }

      final lrcMatch = _lrcLineRx.firstMatch(trimmed);
      if (lrcMatch == null) continue;

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
      if (text.isEmpty) continue;

      // Потоковый обход слов строки: каждое слово сканируется на скобки.
      // bgState переносится между словами → поддерживаем сквозные скобки.
      var bgState = false;
      final parsedWords = <LyricWord>[];

      for (final rawWord in text.split(' ')) {
        if (rawWord.isEmpty) continue;
        final r = _processWithState(rawWord, bgState);
        bgState = r.nextState;
        if (r.text.isEmpty) continue;
        parsedWords
            .add(_plainWord(r.text, startMs, 4000, isBackground: r.isBg));
      }

      if (parsedWords.isEmpty) continue;

      final isLineBackground = parsedWords.every((w) => w.isBackground);

      result.add(LyricLine(
        startMs: startMs,
        endMs: startMs + 4000,
        words: parsedWords,
        isOpposite: isOpposite,
        isBackgroundLine: isLineBackground,
      ));
    }

    _fixLineEndTimes(result);
    final expanded = result.map(_expandSyncedLine).toList();

    debugPrint('[AdvancedLrcParser] Synced LRC: ${expanded.length} строк');
    return ParsedLyrics(
        lines: expanded, format: LyricsFormat.syncedLrc, tags: tags);
  }

  /// Разбивает синхронизированную строку на слова→буквы с временны́ми таймингами.
  ///
  /// Использует `line.words` напрямую — флаги isBackground уже проставлены
  /// потоковым парсером в `_parseSyncedLrc`. Повторного сканирования скобок нет.
  static LyricLine _expandSyncedLine(LyricLine line) {
    if (line.words.isEmpty) return line;

    final lineStartMs = line.startMs;
    final lineDurMs = (line.endMs - line.startMs).clamp(800, 15000);
    final isBgLine = line.isBackgroundLine;

    const spaceW = 0.25;
    final totLetters = line.words.fold<int>(0, (s, w) => s + w.text.length);
    if (totLetters == 0) return line;

    final totalW = totLetters + (line.words.length - 1) * spaceW;
    final msPerW = lineDurMs / totalW;

    final words = <LyricWord>[];
    var curMs = lineStartMs;

    for (var wi = 0; wi < line.words.length; wi++) {
      final wordText = line.words[wi].text;
      if (wordText.isEmpty) continue;

      // Флаг isBg берётся из уже распарсенного word, _не_ сканируем заново
      final isBg = isBgLine || line.words[wi].isBackground;

      final wordDurMs = (wordText.length * msPerW).round();
      final msBpL = wordDurMs / wordText.length;
      final syllables = <LyricSyllable>[];

      for (var li = 0; li < wordText.length; li++) {
        final letterDurMs = msBpL.round().clamp(40, 2000);
        syllables.add(LyricSyllable(
          text: wordText[li],
          startMs: curMs,
          durationMs: letterDurMs,
          isPartOfWord: li < wordText.length - 1,
          isBackground: isBg,
        ));
        curMs += letterDurMs;
      }

      words.add(LyricWord(
          syllables: List.unmodifiable(syllables), isBackground: isBg));

      if (wi < line.words.length - 1) {
        curMs += (msPerW * spaceW).round();
      }
    }

    return LyricLine(
      startMs: line.startMs,
      endMs: line.endMs,
      words: words,
      isOpposite: line.isOpposite,
      isBackgroundLine: isBgLine,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PLAIN PARSER
  // ──────────────────────────────────────────────────────────────────────────

  static ParsedLyrics _parsePlain(String content) {
    final rawLines = content
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final result = <LyricLine>[];

    for (final rawLine in rawLines) {
      // Потоковый обход слов — обнаруживаем inline-скобки.
      // Пример: "Hello (yeah yeah) world" → Hello(main) yeah(bg) yeah(bg) world(main)
      var bgState = false;
      final parsedWords = <LyricWord>[];

      for (final rawWord in rawLine.split(' ')) {
        if (rawWord.isEmpty) continue;
        final r = _processWithState(rawWord, bgState);
        bgState = r.nextState;
        if (r.text.isEmpty) continue;
        parsedWords.add(_plainWord(r.text, 0, 3000, isBackground: r.isBg));
      }

      if (parsedWords.isEmpty) continue;

      final isLineBackground = parsedWords.every((w) => w.isBackground);

      debugPrint(
        '[Plain] "${parsedWords.map((w) => '"${w.text}"${w.isBackground ? '[bg]' : ''}').join(' | ')}"'
        '${isLineBackground ? ' → ALL-BG' : ''}',
      );

      result.add(LyricLine(
        startMs: 0,
        endMs: 0,
        words: parsedWords,
        isBackgroundLine: isLineBackground,
      ));
    }

    debugPrint('[AdvancedLrcParser] Plain: ${result.length} строк');
    return ParsedLyrics(lines: result, format: LyricsFormat.plain);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  /// Потоковый (stateful) обработчик одного токена (слога/слова).
  ///
  /// Сканирует [rawText] символ за символом:
  ///   • `(` / `[`  → переключает состояние в true  (не добавляется в вывод)
  ///   • `)` / `]`  → переключает состояние в false (не добавляется в вывод)
  ///   • любой другой символ → добавляется в буфер вывода
  ///
  /// [isBackground] — входящее состояние (из предыдущего токена).
  ///
  /// Возвращает:
  ///   • [text]      — очищенный текст без скобок
  ///   • [isBg]      — флаг для ЭТОГО токена (= состояние на первом реальном символе)
  ///   • [nextState] — состояние для СЛЕДУЮЩЕГО токена
  ///
  /// Аллокации: только один StringBuffer на вызов; никаких RegExp.
  static ({String text, bool isBg, bool nextState}) _processWithState(
    String rawText,
    bool isBackground,
  ) {
    final buf = StringBuffer();
    bool? firstCharBg; // состояние в момент первого реального символа

    for (var i = 0; i < rawText.length; i++) {
      final ch = rawText[i];
      // ASCII + полноширинные китайские скобки （U+FF08）(U+FF09)
      if (ch == '(' || ch == '[' || ch == '\uFF08') {
        isBackground = true;
      } else if (ch == ')' || ch == ']' || ch == '\uFF09') {
        isBackground = false;
      } else {
        firstCharBg ??= isBackground;
        buf.write(ch);
      }
    }

    return (
      text: buf.toString(),
      isBg: firstCharBg ?? isBackground,
      nextState: isBackground,
    );
  }

  /// Группирует плоский список слогов в LyricWord по пробелам.
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
        text: syl.text.trim(),
        startMs: syl.startMs,
        durationMs: syl.durationMs,
        isPartOfWord: !isWordEnd,
        isBackground: syl.isBackground,
      ));

      if (isWordEnd && current.isNotEmpty) {
        final isBg = current.every((s) => s.isBackground);
        words.add(LyricWord(
          syllables: List.unmodifiable(current),
          isBackground: isBg,
        ));
        current = [];
      }
    }

    if (current.isNotEmpty) {
      final isBg = current.every((s) => s.isBackground);
      words.add(LyricWord(
        syllables: List.unmodifiable(current),
        isBackground: isBg,
      ));
    }

    return words;
  }

  static LyricWord _plainWord(
    String text,
    int startMs,
    int durationMs, {
    bool isBackground = false,
  }) {
    return LyricWord(
      syllables: [
        LyricSyllable(
          text: text,
          startMs: startMs,
          durationMs: durationMs > 0 ? durationMs : 3000,
          isPartOfWord: false,
          isBackground: isBackground,
        ),
      ],
      isBackground: isBackground,
    );
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
