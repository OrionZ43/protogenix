// lib/features/search/presentation/screens/search_screen.dart
//
// Экран поиска: результаты с YouTube (searchProvider; SearchTrack вместо
// типов youtube_explode_dart) и кнопка «В медиатеку» — через общий
// ImportManager, с плашкой и очередью.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../player/presentation/widgets/glass_card.dart';
import '../../../player/presentation/widgets/protogenix_background.dart';
import '../../../importer/presentation/import_manager.dart';
import '../../../library/presentation/library_provider.dart';
import '../providers/search_provider.dart';

// ── Утилита очистки заголовка ─────────────────────────────────────────────────

String _cleanTitle(String title) {
  final patterns = [
    r'\(Official.*?\)',
    r'\[Official.*?\]',
    r'\(Lyrics.*?\)',
    r'\(Audio.*?\)',
    r'\(.*?Video.*?\)',
    r'\(.*?HQ.*?\)',
  ];
  var cleaned = title;
  for (final pattern in patterns) {
    cleaned = cleaned.replaceAll(RegExp(pattern, caseSensitive: false), '');
  }
  return cleaned.trim();
}

// ── SearchScreen ──────────────────────────────────────────────────────────────

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ProtogenixBackground(
        child: SafeArea(
          child: Column(
            children: [
              _SearchHeader(controller: _controller),
              Expanded(child: _SearchBody(state: searchState)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _SearchHeader extends ConsumerWidget {
  final TextEditingController controller;
  const _SearchHeader({required this.controller});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: GlassCard(
        borderRadius: 16,
        padding: EdgeInsets.zero,
        opacity: 0.08,
        child: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            hintText: 'Исполнитель, трек, альбом...',
            hintStyle: TextStyle(color: Colors.white.withAlpha(102)),
            prefixIcon:
                Icon(Icons.search_rounded, color: Colors.white.withAlpha(153)),
            suffixIcon: ValueListenableBuilder(
              valueListenable: controller,
              builder: (_, value, __) => value.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear_rounded,
                          color: Colors.white.withAlpha(153)),
                      onPressed: () {
                        controller.clear();
                        ref.read(searchProvider.notifier).search('');
                      },
                    )
                  : const SizedBox.shrink(),
            ),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          onChanged: (value) =>
              ref.read(searchProvider.notifier).search(value),
        ),
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _SearchBody extends StatelessWidget {
  final AsyncValue<SearchResult> state;
  const _SearchBody({required this.state});

  @override
  Widget build(BuildContext context) {
    return state.when(
      data: (result) {
        if (result.isEmpty) return const _EmptyState();
        return ListView.builder(
          itemCount: result.tracks.length,
          itemBuilder: (context, index) =>
              _SearchResultCard(track: result.tracks[index]),
        );
      },
      loading: () => const _LoadingState(),
      // Текст исключения пользователю не показываем (security.md, п. 3):
      // он уже в логе провайдера
      error: (_, __) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Не получилось выполнить поиск. '
            'Попробуй другой запрос или повтори позже.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withAlpha(153)),
          ),
        ),
      ),
    );
  }
}

// ── Загрузка ─────────────────────────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation(Colors.white54),
        strokeWidth: 2,
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_rounded,
              size: 64, color: Colors.white.withAlpha(51)),
          const SizedBox(height: 16),
          Text(
            'Введи запрос для поиска',
            style:
                TextStyle(color: Colors.white.withAlpha(153), fontSize: 16),
          ),
        ],
      ),
    );
  }
}

// ── Search Result Card ────────────────────────────────────────────────────────

class _SearchResultCard extends ConsumerWidget {
  final SearchTrack track;
  const _SearchResultCard({required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = _cleanTitle(track.title);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: GlassCard(
        borderRadius: 16,
        padding: const EdgeInsets.all(12),
        opacity: 0.07,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Обложка
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                track.thumbnailUrl,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(26),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.music_note_rounded,
                      color: Colors.white.withAlpha(77)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Инфо + кнопки
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    track.artist,
                    style: TextStyle(
                        color: Colors.white.withAlpha(140), fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  _ImportButton(track: track),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Import Button ─────────────────────────────────────────────────────────────

/// Что с треком этой карточки в общем импорте.
enum _ImportPhase { idle, queued, running }

/// «В медиатеку» — через общий ImportManager: плашка с прогрессом,
/// «Остановить» и очередь, если нажать у нескольких треков подряд. Раньше
/// карточка качала сама, мимо плашки, а итог показывала всплывашкой.
class _ImportButton extends ConsumerWidget {
  final SearchTrack track;
  const _ImportButton({required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = 'https://www.youtube.com/watch?v=${track.id}';
    final phase = ref.watch(importManagerProvider.select((job) {
      if (job == null || !job.running) return _ImportPhase.idle;
      if (job.url == url) return _ImportPhase.running;
      if (job.queue.contains(url)) return _ImportPhase.queued;
      return _ImportPhase.idle;
    }));
    // Уже скачан: id трека в медиатеке — id ролика
    final inLibrary = ref.watch(libraryProvider
        .select((tracks) => tracks.any((t) => t.id == track.id)));

    if (inLibrary && phase == _ImportPhase.idle) {
      return const _GlassActionButton(
        onPressed: null,
        isLoading: false,
        icon: Icons.check_rounded,
        label: 'В медиатеке',
      );
    }
    return _GlassActionButton(
      onPressed: phase == _ImportPhase.idle
          ? () => ref
              .read(importManagerProvider.notifier)
              .importUrl(url, title: _cleanTitle(track.title))
          : null,
      isLoading: phase == _ImportPhase.running,
      icon: phase == _ImportPhase.queued
          ? Icons.schedule_rounded
          : Icons.add_rounded,
      label: switch (phase) {
        _ImportPhase.running => 'Скачивается…',
        _ImportPhase.queued => 'В очереди',
        _ImportPhase.idle => 'В медиатеку',
      },
    );
  }
}

// ── Glass Action Button ───────────────────────────────────────────────────────

class _GlassActionButton extends StatelessWidget {
  /// null — кнопка не нажимается (трек уже в медиатеке или в очереди).
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData icon;
  final String label;

  const _GlassActionButton({
    required this.onPressed,
    required this.isLoading,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 8,
      padding: EdgeInsets.zero,
      opacity: 0.10,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation(Colors.white.withAlpha(179)),
                    ),
                  )
                else
                  Icon(icon, size: 16, color: Colors.white.withAlpha(217)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withAlpha(217),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
