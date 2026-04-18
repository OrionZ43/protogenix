import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/track_model.dart';
import '../../domain/player_state.dart' as ps;
import '../providers/palette_provider.dart';
import '../providers/player_provider.dart';
import 'glass_card.dart';

/// Компактная версия плеера для левой колонки Fold
class PlayerControlsCompact extends ConsumerStatefulWidget {
  const PlayerControlsCompact({super.key});

  @override
  ConsumerState<PlayerControlsCompact> createState() =>
      _PlayerControlsCompactState();
}

class _PlayerControlsCompactState
    extends ConsumerState<PlayerControlsCompact> {
  bool _isLiked = false;

  @override
  Widget build(BuildContext context) {
    final player   = ref.watch(playerProvider);
    final palette  = ref.watch(paletteProvider);
    final notifier = ref.read(playerProvider.notifier);
    final track    = player.currentTrack as TrackModel? ?? mockTrack;
    final size     = MediaQuery.of(context).size;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Заголовок
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'NOW PLAYING',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white54,
                    letterSpacing: 3,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert_rounded),
                  color: Colors.white54,
                  onPressed: () {},
                ),
              ],
            ),

            const Spacer(),

            // Обложка — чуть меньше чем на компактном экране
            GlassCard(
              padding: const EdgeInsets.all(10),
              borderRadius: 28,
              opacity: 0.08,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image(
                  image: track.coverImage,
                  width: size.width * 0.35,
                  height: size.width * 0.35,
                  fit: BoxFit.cover,
                ),
              ),
            ),

            const Spacer(),

            // Название + лайк
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        track.artist,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withAlpha(165),
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _isLiked = !_isLiked),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Icon(
                      _isLiked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      key: ValueKey(_isLiked),
                      color: _isLiked ? palette.primary : Colors.white54,
                      size: 26,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Прогресс-бар
            _buildProgressBar(player, notifier),

            const SizedBox(height: 12),

            // Кнопки управления
            _buildControls(player, notifier, palette),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar(
      ps.ProtogenixPlayerState player,
      PlayerNotifier notifier,
      ) {
    String fmt(Duration d) {
      final m = d.inMinutes.toString().padLeft(2, '0');
      final s = (d.inSeconds % 60).toString().padLeft(2, '0');
      return '$m:$s';
    }

    return Column(
      children: [
        Slider(value: player.progress, onChanged: notifier.seekToProgress),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(fmt(player.position),
                style:
                const TextStyle(color: Colors.white54, fontSize: 11)),
            Text(fmt(player.total),
                style:
                const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ),
      ],
    );
  }

  Widget _buildControls(
      ps.ProtogenixPlayerState player,
      PlayerNotifier notifier,
      PaletteState palette,
      ) {
    return GlassCard(
      borderRadius: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: const Icon(Icons.shuffle_rounded),
            color: player.isShuffle ? palette.primary : Colors.white60,
            iconSize: 20,
            onPressed: notifier.toggleShuffle,
          ),
          IconButton(
            icon: const Icon(Icons.skip_previous_rounded),
            color: Colors.white,
            iconSize: 32,
            onPressed: notifier.previous,
          ),
          GestureDetector(
            onTap: notifier.playPause,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.primary,
                boxShadow: [
                  BoxShadow(
                    color: palette.primary.withAlpha(120),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: player.isLoading || player.isBuffering
                  ? const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
                  : AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  player.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  key: ValueKey(player.isPlaying),
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.skip_next_rounded),
            color: Colors.white,
            iconSize: 32,
            onPressed: notifier.next,
          ),
          IconButton(
            icon: Icon(
              player.repeatMode == ps.RepeatMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
            ),
            color: player.repeatMode != ps.RepeatMode.none
                ? palette.primary
                : Colors.white60,
            iconSize: 20,
            onPressed: notifier.toggleRepeat,
          ),
        ],
      ),
    );
  }
}