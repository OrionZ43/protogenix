// lib/features/player/presentation/widgets/mini_player.dart
//
// Глобальный Mini-Player.
// Показывается поверх контента когда пользователь «смахивает вниз» на плеере
// или переходит в другой раздел.
//
// Использование в app.dart:
//   Scaffold(
//     body: ...,
//     bottomNavigationBar: const MiniPlayer(),
//   )
//
// Или через Stack + AnimatedPositioned если нужно поверх bottomNavBar.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/player_provider.dart';
import '../providers/palette_provider.dart';
import '../../domain/track_model.dart';
import '../../domain/player_state.dart';

class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key, this.onTap});

  /// Коллбэк при нажатии — открывает полный плеер
  final VoidCallback? onTap;

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerProvider);
    final palette = ref.watch(paletteProvider);

    // Если очередь пуста — ничего не показываем
    if (player.queue.isEmpty || player.currentTrack == null) {
      _slideCtrl.reverse();
      return const SizedBox.shrink();
    }

    _slideCtrl.forward();

    final track = player.currentTrack as TrackModel;

    return SlideTransition(
      position: _slideAnim,
      child: _MiniPlayerContent(
        track: track,
        player: player,
        palette: palette,
        onTap: widget.onTap,
        notifier: ref.read(playerProvider.notifier),
      ),
    );
  }
}

class _MiniPlayerContent extends StatelessWidget {
  const _MiniPlayerContent({
    required this.track,
    required this.player,
    required this.palette,
    required this.notifier,
    this.onTap,
  });

  final TrackModel track;
  final ProtogenixPlayerState player;
  final PaletteState palette;
  final PlayerNotifier notifier;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 72,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.black.withAlpha(220),
          border: Border.all(color: Colors.white.withAlpha(25)),
          boxShadow: [
            BoxShadow(
              color: palette.primary.withAlpha(60),
              blurRadius: 20,
              spreadRadius: 1,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              // Прогресс-полоска снизу
              Positioned(
                bottom: 0,
                left: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 2,
                  width: MediaQuery.of(context).size.width * player.progress,
                  color: palette.primary.withAlpha(180),
                ),
              ),

              // Контент
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    // Обложка
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image(
                        image: track.coverImage,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Название / артист
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Предыдущий
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded),
                      color: Colors.white70,
                      iconSize: 26,
                      onPressed: notifier.previous,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),

                    const SizedBox(width: 4),

                    // Play / Pause
                    GestureDetector(
                      onTap: notifier.playPause,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: palette.primary,
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            player.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            key: ValueKey(player.isPlaying),
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 4),

                    // Следующий
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded),
                      color: Colors.white70,
                      iconSize: 26,
                      onPressed: notifier.next,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
