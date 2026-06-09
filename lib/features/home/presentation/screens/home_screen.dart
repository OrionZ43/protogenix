import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../library/presentation/library_provider.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../../player/presentation/widgets/glass_card.dart';

import 'dart:math' as math;

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final scale = (width / 1200).clamp(1.0, 1.6);

    final tracks = ref.watch(libraryProvider);
    final sortedTracks = List.of(tracks)
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    final recentTracks = sortedTracks.take(12).toList();

    // Greeting logic with Easter eggs
    final hour = DateTime.now().hour;
    final random = math.Random();
    String greeting;
    if (hour >= 5 && hour < 12) {
      final options = [
        'Доброе утро',
        'Просыпайся, самурай',
        'Время для утреннего вайба',
      ];
      greeting = options[random.nextInt(options.length)];
    } else if (hour >= 12 && hour < 18) {
      final options = [
        'Добрый день',
        'Работаем под бит',
        'Продолжаем движение',
      ];
      greeting = options[random.nextInt(options.length)];
    } else if (hour >= 18 && hour < 23) {
      final options = [
        'Добрый вечер',
        'Пора расслабиться',
        'Вечерний чилл',
      ];
      greeting = options[random.nextInt(options.length)];
    } else {
      final options = [
        'Доброй ночи',
        'Не спишь?',
        'Ночной ритм',
        'Музыка в темноте',
      ];
      greeting = options[random.nextInt(options.length)];
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(32 * scale, 48 * scale, 32 * scale, 24 * scale),
              child: Text(
                greeting,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32 * scale,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(left: 32 * scale, right: 32 * scale, bottom: 16 * scale),
              child: Text(
                'Недавно добавленные',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20 * scale,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 32 * scale),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 280 * scale,
                mainAxisSpacing: 16 * scale,
                crossAxisSpacing: 16 * scale,
                childAspectRatio: 2.8,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = recentTracks[index];
                  return _RecentTrackCard(track: track, scale: scale);
                },
                childCount: recentTracks.length,
              ),
            ),
          ),
          SliverPadding(padding: EdgeInsets.only(bottom: 32 * scale)),
        ],
      ),
    );
  }
}

class _RecentTrackCard extends ConsumerStatefulWidget {
  const _RecentTrackCard({required this.track, required this.scale});

  final dynamic track; // LibraryTrack
  final double scale;

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
                width: 64 * widget.scale,
                height: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image(
                      image: widget.track.toTrackModel().coverImage,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.white10,
                        child: Icon(
                          Icons.music_note_rounded,
                          color: Colors.white24,
                          size: 24 * widget.scale,
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
                            size: 32 * widget.scale,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(width: 16 * widget.scale),
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
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14 * widget.scale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4 * widget.scale),
                    Text(
                      widget.track.toTrackModel().artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12 * widget.scale,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 16 * widget.scale),
            ],
          ),
        ),
      ),
    );
  }
}
