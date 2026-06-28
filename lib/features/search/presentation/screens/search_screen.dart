// lib/features/search/presentation/screens/search_screen.dart
//
// Экран поиска с Invidious-фолбэком и «сломом 4-й стены».
//
// Изменения по сравнению с оригиналом:
//  • Использует SearchTrack вместо Video из youtube_explode_dart
//  • _PlayButton создаёт TrackModel с filePath: null — toAudioSource()
//    автоматически строит Invidious-прокси URL без 403
//  • _ProxyBanner появляется, если result.usingProxy == true
//  • _LoadingState иногда показывает фразу «слом 4-й стены»

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../player/presentation/widgets/glass_card.dart';
import '../../../player/presentation/widgets/protogenix_background.dart';
import '../../../importer/data/importer_service.dart';
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
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Ошибка поиска: $error',
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

class _ImportButton extends ConsumerStatefulWidget {
  final SearchTrack track;
  const _ImportButton({required this.track});

  @override
  ConsumerState<_ImportButton> createState() => _ImportButtonState();
}

class _ImportButtonState extends ConsumerState<_ImportButton> {
  bool _isLoading = false;

  Future<void> _onImport() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final url = 'https://www.youtube.com/watch?v=${widget.track.id}';

      await ImporterService.instance.importFromUrl(
        url: url,
        onProgress: (progress) {
          if (!mounted) return;
          if (progress.status == ImportStatus.error) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(progress.error ?? progress.message)),
            );
          } else if (progress.status == ImportStatus.done) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(progress.message)),
            );
            ref.read(libraryProvider.notifier).reload();
          }
        },
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _GlassActionButton(
      onPressed: _onImport,
      isLoading: _isLoading,
      icon: Icons.add_rounded,
      label: 'В медиатеку',
    );
  }
}

// ── Glass Action Button ───────────────────────────────────────────────────────

class _GlassActionButton extends StatelessWidget {
  final VoidCallback onPressed;
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
