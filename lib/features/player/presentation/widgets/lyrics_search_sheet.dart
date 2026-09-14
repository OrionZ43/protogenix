// lib/features/player/presentation/widgets/lyrics_search_sheet.dart
//
// Ручной поиск текста.
// После выбора результата:
//   1. Применяет текст к karaokeProvider (мгновенно)
//   2. Сохраняет .lrc файл через LyricsService.saveLrc()
//   3. Обновляет lrcPath в LibraryDatabase через libraryProvider.updateLrcPath()
//      → при следующем запуске поиск не запускается заново

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:protogenix/core/utils/system_insets.dart';
import 'package:protogenix/core/widgets/accent_button.dart';
import '../../domain/track_model.dart';
import '../providers/karaoke_provider.dart';
import '../providers/palette_provider.dart';
import '../../../../features/library/data/lyrics_service.dart';
import '../../../../features/library/domain/lyrics_models.dart';
import '../../../../features/player/domain/advanced_lrc_parser.dart';
import '../../../../features/player/domain/lyrics_timing.dart';
import '../../../../features/library/presentation/library_provider.dart';

/// Открыть шторку ручного поиска текста
void showLyricsSearchSheet(
  BuildContext context,
  dynamic refOrContainer,
  TrackModel track,
) {
  final container = refOrContainer is ProviderContainer
    ? refOrContainer
    : ProviderScope.containerOf(context);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => UncontrolledProviderScope(
      container: container,
      child: LyricsSearchSheet(track: track),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class LyricsSearchSheet extends ConsumerStatefulWidget {
  const LyricsSearchSheet({super.key, required this.track});
  final TrackModel track;

  @override
  ConsumerState<LyricsSearchSheet> createState() => _LyricsSearchSheetState();
}

class _LyricsSearchSheetState extends ConsumerState<LyricsSearchSheet> {
  late TextEditingController _titleCtrl;
  late TextEditingController _artistCtrl;

  bool _isSearching = false;
  List<ScoredLyric> _results = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.track.title);
    _artistCtrl = TextEditingController(text: widget.track.artist);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _artistCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final title = _titleCtrl.text.trim();
    final artist = _artistCtrl.text.trim();

    if (title.isEmpty) return;

    setState(() {
      _isSearching = true;
      _results = [];
      _error = null;
    });

    try {
      // Длительность трека: по ней видно ту же версию, и для slowed/sped up
      // считается растяжение таймингов.
      final durationMs = widget.track.duration.inMilliseconds;
      final results = await LyricsService.instance.fetchLyrics(
        title: title,
        artist: artist,
        trackDurationMs: durationMs > 0 ? durationMs : null,
      );
      if (mounted) {
        setState(() {
          _results = results;
          _isSearching = false;
          if (results.isEmpty) {
            _error = 'Ничего не найдено. Попробуй другой запрос.';
          }
        });
      }
    } catch (e) {
      debugPrint('[LyricsSearch] Ошибка поиска: $e');
      if (mounted) {
        setState(() {
          _isSearching = false;
          _error = 'Не получилось выполнить поиск. Попробуй ещё раз.';
        });
      }
    }
  }

  void _apply(ScoredLyric scored) {
    final meta = scored.metadata;
    // Для slowed/sped up — текст оригинала с растянутыми таймингами
    final parsed = scaleLyricsTimings(
        AdvancedLrcParser.parse(meta.content), scored.timeScale);

    // 1. Мгновенно применяем к karaoke (UI обновляется сразу)
    ref.read(karaokeProvider.notifier).invalidateCache(widget.track.id);
    ref.read(karaokeProvider.notifier).setLyrics(parsed);

    // 2. Захватываем нотифаер ДО pop, чтобы не потерять ref после unmount
    final trackId = widget.track.id;
    final content = meta.type == LyricsType.plain
        ? meta.content
        : withScaleTag(meta.content, scored.timeScale);
    final libraryNotifier = ref.read(libraryProvider.notifier);

    Navigator.of(context).pop();

    // 3. Сохраняем .lrc файл и обновляем БД (fire-and-forget, UI не блокируется)
    LyricsService.instance.saveLrc(content, trackId).then((lrcPath) {
      libraryNotifier.updateLrcPath(trackId, lrcPath);
    }).catchError((e) {
      debugPrint('[LyricsSearch] Не удалось сохранить .lrc: $e');
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Текст применён: ${scored.metadata.artistName} — ${scored.metadata.trackName}',
        ),
        // Вид плашки — из темы (AppTheme.snackBarTheme)
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final maxHeight = MediaQuery.of(context).size.height * 0.88;
    final hasContent = _error != null || _results.isNotEmpty || _isSearching;
    final accent = ref.watch(paletteProvider.select((p) => p.primary));

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(200),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withAlpha(30)),
          ),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Ручка (Drag handle)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                const SizedBox(height: 20),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Найти текст вручную',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Введи название и артиста, чтобы найти нужный текст',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      _SearchField(
                        controller: _titleCtrl,
                        accent: accent,
                        hint: 'Название песни',
                        icon: Icons.music_note_rounded,
                        onSubmitted: (_) => _search(),
                      ),
                      const SizedBox(height: 10),
                      _SearchField(
                        controller: _artistCtrl,
                        accent: accent,
                        hint: 'Артист',
                        icon: Icons.person_rounded,
                        onSubmitted: (_) => _search(),
                      ),
                      const SizedBox(height: 14),
                      // Цвет — от обложки, как у главной кнопки импорта
                      // (был зашит фиолетовый)
                      AccentButton(
                        label: _isSearching ? 'Ищу…' : 'Найти',
                        icon: Icons.search_rounded,
                        busy: _isSearching,
                        accent: accent,
                        onTap: _isSearching ? null : _search,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Результаты выезжают плавно: пока поиска не было — место не
                // занимается, шторка остаётся компактной.
                if (hasContent)
                  Flexible(
                    child: _error != null
                        ? Padding(
                            padding: EdgeInsets.fromLTRB(
                                24, 24, 24, bottomSafePadding(context, min: 40)),
                            child: Center(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : _isSearching && _results.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.fromLTRB(24, 24, 24, 40),
                                child: Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white24,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                padding: EdgeInsets.fromLTRB(
                                    24, 8, 24, bottomSafePadding(context, min: 40)),
                                itemCount: _results.length,
                                separatorBuilder: (_, __) =>
                                    Divider(color: Colors.white.withAlpha(12)),
                                itemBuilder: (context, i) {
                                  final scored = _results[i];
                                  return _LyricResultTile(
                                    scored: scored,
                                    onTap: () => _apply(scored),
                                  ).animate().fadeIn(
                                        duration: 200.ms,
                                        delay: (i * 40).ms,
                                      );
                                },
                              ),
                  ),

                SizedBox(height: viewInsets.bottom + (hasContent ? 0 : 24)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Поле ввода ─────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.accent,
    required this.hint,
    required this.icon,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final Color accent;
  final String hint;
  final IconData icon;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withAlpha(10),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: TextField(
        controller: controller,
        onSubmitted: onSubmitted,
        cursorColor: accent,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withAlpha(50)),
          prefixIcon: Icon(icon, color: Colors.white38, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}

// ── Элемент результата ─────────────────────────────────────────────────────

class _LyricResultTile extends StatelessWidget {
  const _LyricResultTile({required this.scored, required this.onTap});

  final ScoredLyric scored;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = scored.metadata;

    final typeColor = switch (meta.type) {
      LyricsType.syllable => const Color(0xFFCE93D8),
      LyricsType.enhanced => const Color(0xFF80DEEA),
      LyricsType.synced => const Color(0xFFA5D6A7),
      LyricsType.plain => Colors.white38,
    };

    final typeLabel = switch (meta.type) {
      LyricsType.syllable => 'Слоги',
      LyricsType.enhanced => 'Слова',
      LyricsType.synced => 'Строки',
      LyricsType.plain => 'Текст',
    };

    return ListTile(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      contentPadding: EdgeInsets.zero,
      title: Text(
        meta.trackName,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        meta.artistName,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 13,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: typeColor.withAlpha(30),
              border: Border.all(color: typeColor.withAlpha(80)),
            ),
            child: Text(
              typeLabel,
              style: TextStyle(
                color: typeColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Та же песня (lyrics_matcher.dart) — такой вариант выбрал бы автопоиск
          if (scored.isConfident) ...[
            const Tooltip(
              message: 'Точно эта песня',
              child: Icon(
                Icons.verified_rounded,
                color: Color(0xFF66BB6A),
                size: 16,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            scored.scoreLabel,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.chevron_right_rounded,
            color: Colors.white24,
            size: 20,
          ),
        ],
      ),
    );
  }
}
