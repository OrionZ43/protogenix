// lib/features/player/presentation/providers/karaoke_provider.dart
//
// v3.2 — Кэширование текстов + дебаунс при смене трека:
//   • Map<trackId, ParsedLyrics> _cache — тексты сохраняются между переключениями
//   • Debounce 400мс — если пользователь пролистал трек, запрос не уходит
//   • Отмена in-flight запроса при быстрой смене трека (_currentLoadToken)
//   • Это решает проблему "тексты с пролистанных треков накладываются"
// v3.3 — автопоиск берёт только «ту же песню» (lyrics_matcher.dart) и
//   передаёт длительность трека; тайминги slowed/sped up растягиваются,
//   тайминги от другой версии трека не показываются (lyrics_timing.dart).
// v3.4 — пока приложение свёрнуто (app_visibility.dart), текст не ищется и
//   активная строка не считается: догоняем, когда вернётся на экран.
//   Вибрация на смене строки — только в самом виде текста
//   (beautiful_lyrics_view.dart): раньше провайдер вибрировал и со свёрнутым
//   плеером, и со свёрнутым приложением.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/app_visibility.dart';
import '../../domain/advanced_lrc_parser.dart';
import '../../domain/lyrics_timing.dart';
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

  // Трек, чей текст ждёт возвращения приложения на экран
  TrackModel? _deferredTrack;

  // Дебаунс: ждём 400мс тишины перед реальным запросом
  static const _kDebounceDuration = Duration(milliseconds: 400);

  void _init() {
    _ref.listen<bool>(appVisibleProvider, (_, visible) {
      final track = _deferredTrack;
      final token = _currentLoadToken;
      if (!visible || track == null || token == null) return;
      _deferredTrack = null;
      _doLoad(track, token);
    });

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
    _deferredTrack = null;

    // Создаём новый токен — старый in-flight запрос его не получит
    final token = Object();
    _currentLoadToken = token;

    Future.delayed(_kDebounceDuration, () {
      // Если за 400мс трек снова поменялся — наш токен уже устарел
      if (_currentLoadToken != token) return;
      if (!mounted) return;
      // Свёрнутому приложению текст не нужен: до 30 запросов в сеть на
      // каждый трек. Загрузим, когда приложение вернётся на экран.
      if (!_ref.read(appVisibleProvider)) {
        _deferredTrack = track;
        return;
      }
      _doLoad(track, token);
    });
  }

  void _cancelLoad() {
    _currentLoadToken = null;
    _deferredTrack = null;
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
      var timeScale = 1.0;
      var timingsReliable = true;

      // 1. Сохранённый текст (ручной выбор или импорт) — lrcPath из БД
      if (track.lrcPath != null) {
        final file = File(track.lrcPath!);
        if (await file.exists()) {
          final saved = readScaleTag(await file.readAsString());
          content = saved.content;
          timeScale = saved.scale;
          debugPrint('[Karaoke] Загружен файл: ${track.lrcPath}');
        }
      }

      // Проверяем токен после async операции
      if (_currentLoadToken != token || !mounted) return;

      // 2. Поиск: только «та же песня», иначе — «текст не найден»
      if (content == null) {
        final durationMs = track.duration.inMilliseconds;
        final best = await LyricsService.instance.findBest(
          title: track.title,
          artist: track.artist,
          filePath: track.filePath ?? '',
          trackDurationMs: durationMs > 0 ? durationMs : null,
        );

        // Снова проверяем — пока шёл сетевой запрос, трек мог смениться
        if (_currentLoadToken != token || !mounted) return;

        if (best != null) {
          content = best.metadata.content;
          timeScale = best.timeScale;
          timingsReliable = best.timingsReliable;
          debugPrint(
            '[Karaoke] Найдено: ${best.metadata.type.label} '
            'score=${best.scoreLabel} '
            'source=${best.metadata.source}'
            '${timeScale != 1.0 ? ' ×${timeScale.toStringAsFixed(3)}' : ''}'
            '${timingsReliable ? '' : ' (без синхронизации)'}',
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

      final parsed = _prepare(content, timeScale, timingsReliable);

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

  /// Разбор + растяжение для slowed/sped up. Тайминги от другой версии трека
  /// уехали бы — такой текст показываем без синхронизации.
  ParsedLyrics _prepare(String content, double timeScale, bool timingsReliable) {
    final parsed =
        scaleLyricsTimings(AdvancedLrcParser.parse(content), timeScale);
    if (timingsReliable) return parsed;
    return ParsedLyrics(
      lines: parsed.lines,
      format: LyricsFormat.plain,
      tags: parsed.tags,
    );
  }

  // ── Обновление активной строки ─────────────────────────────────────────────

  void _updateCurrentLine(Duration position) {
    if (!state.isLoaded || state.lines.isEmpty) return;
    if (state.format == LyricsFormat.plain) return;
    // Позиция приходит несколько раз в секунду; свёрнутому приложению
    // активная строка не нужна — пересчитаем по возвращении на экран.
    if (!_ref.read(appVisibleProvider)) return;

    final index = AdvancedLrcParser.currentLineIndexFromDuration(
      state.lines,
      position,
    );

    if (index == _lastLineIndex) return;
    _lastLineIndex = index;
    state = state.copyWith(currentIndex: index);
  }

  // ── Публичные методы ───────────────────────────────────────────────────────

  Future<void> loadContent(String content) async {
    _cancelLoad();
    _lastLineIndex = -1;
    state = const KaraokeState(isLoaded: false);

    final saved = readScaleTag(content);
    final parsed = _prepare(saved.content, saved.scale, true);

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
