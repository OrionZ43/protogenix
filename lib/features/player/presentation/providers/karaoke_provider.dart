// lib/features/player/presentation/providers/karaoke_provider.dart
//
// v3.2 — Кэширование текстов + дебаунс при смене трека:
//   • Map<trackId, ParsedLyrics> _cache — тексты сохраняются между переключениями
//   • Debounce 400мс — если пользователь пролистал трек, запрос не уходит
//   • Отмена in-flight запроса при быстрой смене трека (_currentLoadToken)
//   • Это решает проблему "тексты с пролистанных треков накладываются"

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/advanced_lrc_parser.dart';
import '../../domain/track_model.dart';
import '../../../library/data/lyrics_service.dart';
import '../../../library/domain/lyrics_models.dart';
import 'player_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// STATE
// ─────────────────────────────────────────────────────────────────────────────

class KaraokeState {
  final List<LyricLine> lines;
  final int currentIndex;
  final bool isLoaded;
  final LyricsFormat format;

  const KaraokeState({
    this.lines = const [],
    this.currentIndex = -1,
    this.isLoaded = false,
    this.format = LyricsFormat.plain,
  });

  LyricLine? get currentLine => currentIndex >= 0 && currentIndex < lines.length
      ? lines[currentIndex]
      : null;

  LyricLine? get nextLine =>
      currentIndex + 1 < lines.length ? lines[currentIndex + 1] : null;

  bool get hasSyllableTimings => format == LyricsFormat.yrc;
  bool get hasWordTimings =>
      format == LyricsFormat.enhancedLrc || format == LyricsFormat.yrc;

  KaraokeState copyWith({
    List<LyricLine>? lines,
    int? currentIndex,
    bool? isLoaded,
    LyricsFormat? format,
  }) =>
      KaraokeState(
        lines: lines ?? this.lines,
        currentIndex: currentIndex ?? this.currentIndex,
        isLoaded: isLoaded ?? this.isLoaded,
        format: format ?? this.format,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTIFIER
// ─────────────────────────────────────────────────────────────────────────────

class KaraokeNotifier extends StateNotifier<KaraokeState> {
  KaraokeNotifier(this._ref) : super(const KaraokeState()) {
    _init();
  }

  final Ref _ref;
  int _lastLineIndex = -1;

  // ── Кэш текстов ─────────────────────────────────────────────────────────
  // trackId → ParsedLyrics. Тексты живут всё время сессии (~30 треков в памяти).
  final Map<String, ParsedLyrics> _cache = {};

  // ── Дебаунс / токен отмены ───────────────────────────────────────────────
  // При каждом запросе создаём уникальный токен.
  // Если трек снова сменился пока загружается — токен устарел, результат игнорируется.
  Object? _currentLoadToken;

  // Дебаунс: ждём 400мс тишины перед реальным запросом
  static const _kDebounceDuration = Duration(milliseconds: 400);

  void _init() {
    _ref.listen(playerProvider, (previous, next) {
      final prevId = previous?.currentTrack?.id;
      final nextId = next.currentTrack?.id;

      if (prevId != nextId) {
        final track = next.currentTrack;
        if (track != null) {
          _scheduleLoad(track);
        } else {
          _cancelLoad();
          state = const KaraokeState(isLoaded: true);
        }
      }
      _updateCurrentLine(next.position);
    });

    final current = _ref.read(playerProvider).currentTrack;
    if (current != null) {
      _scheduleLoad(current);
    }
  }

  // ── Дебаунс: откладываем загрузку на 400мс ───────────────────────────────

  void _scheduleLoad(TrackModel track) {
    // Показываем loading сразу, но запрос не делаем
    state = const KaraokeState(isLoaded: false);
    _lastLineIndex = -1;

    // Создаём новый токен — старый in-flight запрос его не получит
    final token = Object();
    _currentLoadToken = token;

    Future.delayed(_kDebounceDuration, () {
      // Если за 400мс трек снова поменялся — наш токен уже устарел
      if (_currentLoadToken != token) return;
      if (!mounted) return;
      _doLoad(track, token);
    });
  }

  void _cancelLoad() {
    _currentLoadToken = null;
  }

  // ── Реальная загрузка ─────────────────────────────────────────────────────

  Future<void> _doLoad(TrackModel track, Object token) async {
    // Проверяем кэш сначала
    if (_cache.containsKey(track.id)) {
      if (_currentLoadToken != token || !mounted) return;
      final cached = _cache[track.id]!;
      debugPrint('[Karaoke] ✓ Кэш hit для "${track.title}"');
      state = KaraokeState(
        lines: cached.lines,
        isLoaded: true,
        format: cached.format,
      );
      return;
    }

    try {
      String? content;
      LyricsType? sourceType;

      // 1. Кэшированный lrcPath из БД
      if (track.lrcPath != null) {
        final file = File(track.lrcPath!);
        if (await file.exists()) {
          content = await file.readAsString();
          sourceType = null;
          debugPrint('[Karaoke] Загружен файл: ${track.lrcPath}');
        }
      }

      // Проверяем токен после async операции
      if (_currentLoadToken != token || !mounted) return;

      // 2. Поиск через LyricsService
      if (content == null) {
        final results = await LyricsService.instance.fetchLyrics(
          title: track.title,
          artist: track.artist,
          filePath: track.filePath ?? '',
        );

        // Снова проверяем — пока шёл сетевой запрос, трек мог смениться
        if (_currentLoadToken != token || !mounted) return;

        if (results.isNotEmpty) {
          final best = results.first;
          content = best.metadata.content;
          sourceType = best.metadata.type;
          debugPrint(
            '[Karaoke] Найдено: ${best.metadata.type.label} '
            'score=${best.scoreLabel} '
            'source=${best.metadata.source}',
          );
        }
      }

      if (content == null || content.trim().isEmpty) {
        // Кэшируем пустой результат, чтобы не делать запрос повторно
        _cache[track.id] =
            const ParsedLyrics(lines: [], format: LyricsFormat.plain);
        state = const KaraokeState(isLoaded: true);
        debugPrint('[Karaoke] Текст не найден для "${track.title}"');
        return;
      }

      final parsed = _parseContent(content, sourceType);

      // Сохраняем в кэш
      _cache[track.id] = parsed;

      // Ограничиваем размер кэша (LRU-lite: просто сбрасываем если >50)
      if (_cache.length > 50) {
        final oldestKey = _cache.keys.first;
        _cache.remove(oldestKey);
      }

      if (parsed.isEmpty) {
        state = const KaraokeState(isLoaded: true);
        debugPrint('[Karaoke] Парсинг вернул пустой результат');
        return;
      }

      state = KaraokeState(
        lines: parsed.lines,
        isLoaded: true,
        format: parsed.format,
      );

      debugPrint(
        '[Karaoke] Загружено: ${parsed.lines.length} строк, '
        'формат=${parsed.format.label}',
      );
    } catch (e, st) {
      if (!mounted) return;
      debugPrint('[Karaoke] Ошибка загрузки: $e\n$st');
      state = const KaraokeState(isLoaded: true);
    }
  }

  ParsedLyrics _parseContent(String content, LyricsType? hint) {
    return AdvancedLrcParser.parse(content);
  }

  // ── Обновление активной строки ─────────────────────────────────────────────

  void _updateCurrentLine(Duration position) {
    if (!state.isLoaded || state.lines.isEmpty) return;
    if (state.format == LyricsFormat.plain) return;

    final index = AdvancedLrcParser.currentLineIndexFromDuration(
      state.lines,
      position,
    );

    if (index == _lastLineIndex) return;
    _lastLineIndex = index;

    if (index >= 0) {
      HapticFeedback.selectionClick();
    }

    state = state.copyWith(currentIndex: index);
  }

  // ── Публичные методы ───────────────────────────────────────────────────────

  Future<void> loadContent(String content) async {
    _cancelLoad();
    _lastLineIndex = -1;
    state = const KaraokeState(isLoaded: false);

    final parsed = AdvancedLrcParser.parse(content);

    // Обновляем кэш для текущего трека
    final trackId = _ref.read(playerProvider).currentTrack?.id;
    if (trackId != null) {
      _cache[trackId] = parsed;
    }

    state = KaraokeState(
      lines: parsed.lines,
      isLoaded: true,
      format: parsed.format,
    );
  }

  void setLyrics(ParsedLyrics parsed) {
    _cancelLoad();
    _lastLineIndex = -1;

    final trackId = _ref.read(playerProvider).currentTrack?.id;
    if (trackId != null) {
      _cache[trackId] = parsed;
    }

    state = KaraokeState(
      lines: parsed.lines,
      isLoaded: true,
      format: parsed.format,
    );
  }

  void clear() {
    _cancelLoad();
    _lastLineIndex = -1;
    state = const KaraokeState(isLoaded: true);
  }

  /// Сбросить кэш одного трека (например, после ручного выбора текста)
  void invalidateCache(String trackId) {
    _cache.remove(trackId);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROVIDER
// ─────────────────────────────────────────────────────────────────────────────

final karaokeProvider =
    StateNotifierProvider<KaraokeNotifier, KaraokeState>((ref) {
  return KaraokeNotifier(ref);
});

final karaokeIndexProvider = karaokeProvider.select((s) => s.currentIndex);
final karaokeFormatProvider = karaokeProvider.select((s) => s.format);
final hasSyllableTimingsProvider =
    karaokeProvider.select((s) => s.hasSyllableTimings);
