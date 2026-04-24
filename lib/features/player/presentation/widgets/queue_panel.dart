import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/track_model.dart';
import '../providers/palette_provider.dart';
import '../providers/player_provider.dart';

class QueuePanel extends ConsumerWidget {
  const QueuePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final palette = ref.watch(paletteProvider);
    final queue = player.queue.cast<TrackModel>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 16),
          child: Text(
            'UP NEXT',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white54,
              letterSpacing: 4,
            ),
          ).animate().fadeIn(duration: 600.ms),
        ),

        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: queue.length,
            itemBuilder: (context, index) {
              final track = queue[index];
              final isCurrent = index == player.currentIndex;

              return _QueueItem(
                    track: track,
                    isCurrent: isCurrent,
                    index: index,
                    palette: palette,
                    onTap: () {
                      ref
                          .read(playerProvider.notifier)
                          .loadPlaylist(queue, initialIndex: index);
                    },
                  )
                  .animate(delay: Duration(milliseconds: 80 * index))
                  .fadeIn(duration: 400.ms)
                  .slideX(begin: 0.2, end: 0);
            },
          ),
        ),
      ],
    );
  }
}

class _QueueItem extends StatelessWidget {
  const _QueueItem({
    required this.track,
    required this.isCurrent,
    required this.index,
    required this.palette,
    required this.onTap,
  });

  final TrackModel track;
  final bool isCurrent;
  final int index;
  final PaletteState palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: isCurrent
                ? palette.primary.withAlpha(50)
                : Colors.white.withAlpha(10),
            border: Border.all(
              color: isCurrent
                  ? palette.primary.withAlpha(120)
                  : Colors.white.withAlpha(20),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Обложка
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image(
                    image: track.coverImage,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 14),

                // Инфо
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        style: TextStyle(
                          color: isCurrent ? Colors.white : Colors.white70,
                          fontWeight: isCurrent
                              ? FontWeight.w600
                              : FontWeight.normal,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        track.artist,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                // Индикатор текущего трека
                if (isCurrent)
                  _PlayingIndicator(color: palette.primary)
                else
                  Text(
                    _formatDuration(track.duration),
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// Анимированные полоски "сейчас играет"
class _PlayingIndicator extends StatefulWidget {
  const _PlayingIndicator({required this.color});
  final Color color;

  @override
  State<_PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<_PlayingIndicator>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (i) {
      return AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 400 + i * 120),
      )..repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _controllers[i],
            builder: (context, _) {
              return Container(
                width: 4,
                height: 6 + (_controllers[i].value * 14),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
