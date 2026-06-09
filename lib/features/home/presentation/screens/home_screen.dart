import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../library/presentation/library_provider.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../../player/presentation/widgets/glass_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(libraryProvider);
    final sortedTracks = List.of(tracks)
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    final recentTracks = sortedTracks.take(12).toList();

    // Greeting logic
    final hour = DateTime.now().hour;
    String greeting;
    if (hour >= 5 && hour < 12) {
      greeting = 'Доброе утро';
    } else if (hour >= 12 && hour < 18) {
      greeting = 'Добрый день';
    } else if (hour >= 18 && hour < 23) {
      greeting = 'Добрый вечер';
    } else {
      greeting = 'Доброй ночи';
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 48, 32, 24),
              child: Text(
                greeting,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 280,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 2.8,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = recentTracks[index];
                  return _RecentTrackCard(track: track);
                },
                childCount: recentTracks.length,
              ),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }
}

class _RecentTrackCard extends ConsumerStatefulWidget {
  const _RecentTrackCard({required this.track});

  final dynamic track; // LibraryTrack

  @override
  ConsumerState<_RecentTrackCard> createState() => _RecentTrackCardState();
}

class _RecentTrackCardState extends ConsumerState<_RecentTrackCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerProvider);
    final isPlaying =
        player.isPlaying && player.currentTrack?.id == widget.track.id;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () async {
          final notifier = ref.read(playerProvider.notifier);
          // If the clicked track is already in the queue, we can just skip to it
          // Wait, simple loadPlaylist is better for play track now.
          await notifier
              .loadPlaylist([widget.track.toTrackModel()], initialIndex: 0);
          await notifier.play();
        },
        child: GlassCard(
          padding: EdgeInsets.zero,
          borderRadius: 8,
          opacity: _isHovered ? 0.2 : 0.12,
          child: Row(
            children: [
              // Cover
              SizedBox(
                width: 64,
                height: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image(
                      image: widget.track.toTrackModel().coverImage,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.white10,
                        child: const Icon(
                          Icons.music_note_rounded,
                          color: Colors.white24,
                        ),
                      ),
                    ),
                    if (_isHovered || isPlaying)
                      Container(
                        color: Colors.black.withValues(alpha: 0.4),
                        child: Center(
                          child: Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.track.toTrackModel().title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.track.toTrackModel().artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }
}
