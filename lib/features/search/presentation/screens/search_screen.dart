import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../player/presentation/widgets/glass_card.dart';
import '../../../player/presentation/widgets/protogenix_background.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../../player/domain/track_model.dart';
import '../../../importer/data/importer_service.dart';
import '../../../library/presentation/library_provider.dart';
import '../providers/search_provider.dart';

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
            hintStyle: TextStyle(color: Colors.white.withAlpha(102)), // ~0.4
            prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withAlpha(153)), // ~0.6
            suffixIcon: ValueListenableBuilder(
              valueListenable: controller,
              builder: (_, value, __) => value.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear_rounded, color: Colors.white.withAlpha(153)),
                      onPressed: () {
                        controller.clear();
                        ref.read(searchProvider.notifier).search('');
                      },
                    )
                  : const SizedBox.shrink(),
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          onChanged: (value) => ref.read(searchProvider.notifier).search(value),
        ),
      ),
    );
  }
}

class _SearchBody extends StatelessWidget {
  final AsyncValue<List<Video>> state;
  const _SearchBody({required this.state});

  @override
  Widget build(BuildContext context) {
    return state.when(
      data: (videos) {
        if (videos.isEmpty) {
          return const _EmptyState();
        }
        return ListView.builder(
          itemCount: videos.length,
          itemBuilder: (context, index) => _SearchResultCard(video: videos[index]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Text(
          'Ошибка поиска: $error',
          style: TextStyle(color: Colors.white.withAlpha(153)),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_rounded, size: 64, color: Colors.white.withAlpha(51)),
          const SizedBox(height: 16),
          Text(
            'Введи запрос для поиска',
            style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 16),
          ),
        ],
      ),
    );
  }
}

String _cleanTitle(String title) {
  final patterns = [
    r'\(Official.*?\)',
    r'\[Official.*?\]',
    r'\(Lyrics.*?\)',
    r'\(Audio.*?\)',
    r'\(.*?Video.*?\)',
    r'\(.*?HQ.*?\)'
  ];
  var cleaned = title;
  for (final pattern in patterns) {
    cleaned = cleaned.replaceAll(RegExp(pattern, caseSensitive: false), '');
  }
  return cleaned.trim();
}

class _SearchResultCard extends ConsumerWidget {
  final Video video;
  const _SearchResultCard({required this.video});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = _cleanTitle(video.title);
    final author = video.author;
    final thumbnailUrl = video.thumbnails.lowResUrl;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: GlassCard(
        borderRadius: 16,
        padding: const EdgeInsets.all(12),
        opacity: 0.07,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                thumbnailUrl,
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
                  child: Icon(Icons.music_note_rounded, color: Colors.white.withAlpha(77)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(author,
                      style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 12),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _PlayButton(video: video, title: title),
                      const SizedBox(width: 8),
                      _ImportButton(video: video),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayButton extends ConsumerStatefulWidget {
  final Video video;
  final String title;
  const _PlayButton({required this.video, required this.title});

  @override
  ConsumerState<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends ConsumerState<_PlayButton> {
  bool _isLoading = false;

  Future<void> _onPlay() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient.getManifest(widget.video.id);

      final audioStreams = manifest.audioOnly
          .where((s) => s.codec.mimeType.contains('audio/mp4'))
          .toList();

      if (audioStreams.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось получить аудио-поток')),
          );
        }
        return;
      }

      final bestStream = audioStreams.reduce((a, b) => a.bitrate.bitsPerSecond > b.bitrate.bitsPerSecond ? a : b);

      final tempTrack = TrackModel(
        id: widget.video.id.value,
        title: widget.title,
        artist: widget.video.author,
        album: 'YouTube',
        duration: widget.video.duration ?? Duration.zero,
        coverImage: NetworkImage(widget.video.thumbnails.highResUrl),
        filePath: bestStream.url.toString(),
      );

      await ref.read(playerProvider.notifier).loadPlaylist([tempTrack], initialIndex: 0);
      await ref.read(playerProvider.notifier).play();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Воспроизводится: ${widget.title}'), duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    } finally {
      yt.close();
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _GlassActionButton(
      onPressed: _onPlay,
      isLoading: _isLoading,
      icon: Icons.play_arrow_rounded,
      label: 'Слушать',
    );
  }
}

class _ImportButton extends ConsumerStatefulWidget {
  final Video video;
  const _ImportButton({required this.video});

  @override
  ConsumerState<_ImportButton> createState() => _ImportButtonState();
}

class _ImportButtonState extends ConsumerState<_ImportButton> {
  bool _isLoading = false;

  Future<void> _onImport() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final url = 'https://www.youtube.com/watch?v=${widget.video.id.value}';

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
      opacity: 0.1,
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
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white.withAlpha(179)),
                    ),
                  )
                else
                  Icon(icon, size: 16, color: Colors.white.withAlpha(217)),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(color: Colors.white.withAlpha(217), fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
