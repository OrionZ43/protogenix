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
import '../../domain/track_model.dart';
import '../providers/karaoke_provider.dart';
import '../../../../features/library/data/lyrics_service.dart';
import '../../../../features/library/domain/lyrics_models.dart';
import '../../../../features/player/domain/advanced_lrc_parser.dart';
import '../../../../features/library/presentation/library_provider.dart';

/// Открыть шторку ручного поиска текста
void showLyricsSearchSheet(
  BuildContext context,
  WidgetRef ref,
  TrackModel track,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => UncontrolledProviderScope(
      container: ProviderScope.containerOf(context),
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
      final results = await LyricsService.instance.fetchLyrics(
        title: title,
        artist: artist,
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
      if (mounted) {
        setState(() {
          _isSearching = false;
          _error = 'Ошибка: $e';
        });
      }
    }
  }

  void _apply(ScoredLyric scored) {
    final parsed = AdvancedLrcParser.parse(scored.metadata.content);

    // 1. Мгновенно применяем к karaoke (UI обновляется сразу)
    ref.read(karaokeProvider.notifier).invalidateCache(widget.track.id);
    ref.read(karaokeProvider.notifier).setLyrics(parsed);

    // 2. Захватываем нотифаер ДО pop, чтобы не потерять ref после unmount
    final trackId = widget.track.id;
    final content = scored.metadata.content;
    final libraryNotifier = ref.read(libraryProvider.notifier);

    Navigator.of(context).pop();

    // 3. Сохраняем .lrc файл и обновляем БД (fire-and-forget, UI не блокируется)
    LyricsService.instance
        .saveLrc(content, trackId)
        .then((lrcPath) {
          libraryNotifier.updateLrcPath(trackId, lrcPath);
        })
        .catchError((e) {
          debugPrint('[LyricsSearch] Не удалось сохранить .lrc: $e');
        });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Текст применён: ${scored.metadata.artistName} — ${scored.metadata.trackName}',
        ),
        backgroundColor: Colors.black87,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.88,
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(200),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withAlpha(30)),
          ),
          child: Column(
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
                      hint: 'Название песни',
                      icon: Icons.music_note_rounded,
                      onSubmitted: (_) => _search(),
                    ),
                    const SizedBox(height: 10),
                    _SearchField(
                      controller: _artistCtrl,
                      hint: 'Артист',
                      icon: Icons.person_rounded,
                      onSubmitted: (_) => _search(),
                    ),
                    const SizedBox(height: 14),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSearching ? null : _search,
                        icon: _isSearching
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.search_rounded),
                        label: Text(_isSearching ? 'Ищу...' : 'Найти'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7B5EA7),
                          foregroundColor: Colors.white,
                          padding: const Duration(milliseconds: 300) > Duration.zero 
                              ? const EdgeInsets.symmetric(vertical: 14) 
                              : EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              Expanded(
                child: _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : _results.isEmpty && !_isSearching
                        ? const SizedBox.shrink()
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
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

              SizedBox(height: viewInsets.bottom),
            ],
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
    required this.hint,
    required this.icon,
    this.onSubmitted,
  });

  final TextEditingController controller;
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