import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/haptic_patterns.dart';
import '../../domain/track_model.dart';
import '../../domain/player_state.dart' as ps;
import '../providers/palette_provider.dart';
import '../providers/player_provider.dart';
import '../../../library/presentation/playlist_provider.dart';
import 'waveform_progress_bar.dart';

class DesktopBottomPlayer extends ConsumerWidget {
  const DesktopBottomPlayer({
    super.key,
    required this.onExpand,
    required this.onToggleRightPanel,
    required this.isRightPanelOpen,
  });

  final VoidCallback onExpand;
  final VoidCallback onToggleRightPanel;
  final bool isRightPanelOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final scale = (width / 1400).clamp(0.9, 1.2);

    final player = ref.watch(playerProvider);
    final palette = ref.watch(paletteProvider);
    final notifier = ref.read(playerProvider.notifier);

    final track = player.currentTrack as TrackModel?;
    if (track == null) return const SizedBox.shrink();

    return Container(
      height: 112,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          // ── Левая зона: Обложка и инфо (ширина ~300) ──────────────
          Expanded(
            flex: 3,
            child: Row(
              children: [
                SizedBox(width: 24 * scale),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8 * scale),
                  child: Image(
                    image: track.coverImage,
                    width: 64 * scale,
                    height: 64 * scale,
                    fit: BoxFit.cover,
                  ),
                ),
                SizedBox(width: 16 * scale),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14 * scale,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4 * scale),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12 * scale,
                        ),
                      ),
                    ],
                  ),
                ),
                // Like Button
                Consumer(
                  builder: (context, ref, _) {
                    final isFav = ref.watch(isFavoriteProvider(track.id));
                    return IconButton(
                      iconSize: 24 * scale,
                      icon: Icon(
                        isFav
                            ? Icons.favorite_rounded
                            : Icons.favorite_outline_rounded,
                        color: isFav ? Colors.redAccent : Colors.white54,
                      ),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        ref.read(favoritesProvider.notifier).toggle(track.id);
                      },
                    );
                  },
                ),
                SizedBox(width: 16 * scale),
              ],
            ),
          ),

          // ── Центральная зона: Контролы и Waveform ──────────────
          Expanded(
            flex: 4,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16 * scale),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Кнопки
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        iconSize: 24 * scale,
                        icon: const Icon(Icons.shuffle_rounded),
                        color:
                            player.isShuffle ? palette.primary : Colors.white54,
                        onPressed: () {
                          player.isShuffle
                              ? HapticPatterns.shuffleOff()
                              : HapticPatterns.shuffleOn();
                          notifier.toggleShuffle();
                        },
                      ),
                      SizedBox(width: 16 * scale),
                      IconButton(
                        iconSize: 24 * scale,
                        icon: const Icon(Icons.skip_previous_rounded),
                        color: Colors.white,
                        onPressed: () {
                          HapticPatterns.previous();
                          notifier.previous();
                        },
                      ),
                      SizedBox(width: 16 * scale),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () {
                            HapticPatterns.playPause();
                            notifier.playPause();
                          },
                          child: Container(
                            width: 48 * scale,
                            height: 48 * scale,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: palette.primary,
                            ),
                            child: Icon(
                              player.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 28 * scale,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 16 * scale),
                      IconButton(
                        iconSize: 24 * scale,
                        icon: const Icon(Icons.skip_next_rounded),
                        color: Colors.white,
                        onPressed: () {
                          HapticPatterns.next();
                          notifier.next();
                        },
                      ),
                      SizedBox(width: 16 * scale),
                      IconButton(
                        iconSize: 24 * scale,
                        icon: Icon(
                          player.repeatMode == ps.RepeatMode.none
                              ? Icons.repeat_rounded
                              : player.repeatMode == ps.RepeatMode.all
                                  ? Icons.repeat_rounded
                                  : Icons.repeat_one_rounded,
                        ),
                        color: player.repeatMode != ps.RepeatMode.none
                            ? palette.primary
                            : Colors.white54,
                        onPressed: () {
                          HapticPatterns.repeat();
                          notifier.toggleRepeat();
                        },
                      ),
                    ],
                  ),
                  SizedBox(height: 8 * scale),
                  // Waveform
                  SizedBox(
                    height: 44 * scale,
                    child: LiveWaveformProgressBar(
                      progress: player.progress,
                      position: player.position,
                      total: player.total,
                      accentColor: palette.primary,
                      height: 28 * scale,
                      barCount: 100,
                      onSeek: (p) => notifier.seekToProgress(p),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Правая зона: Громкость, Lyrics, Expand (ширина ~300) ──────────────
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  width: 140 * scale,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8 * scale),
                    child: _VolumeSlider(
                      volume: player.volume,
                      accentColor: palette.primary,
                      onChanged: (val) => notifier.setVolume(val),
                    ),
                  ),
                ),
                IconButton(
                  iconSize: 24 * scale,
                  icon: Icon(isRightPanelOpen
                      ? Icons.menu_open_rounded
                      : Icons.view_sidebar_rounded),
                  color: isRightPanelOpen ? palette.primary : Colors.white54,
                  onPressed: onToggleRightPanel,
                ),
                IconButton(
                  iconSize: 24 * scale,
                  icon: const Icon(Icons.open_in_full_rounded),
                  color: Colors.white54,
                  onPressed: onExpand,
                ),
                SizedBox(width: 24 * scale),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VolumeSlider extends StatelessWidget {
  const _VolumeSlider({
    required this.volume,
    required this.accentColor,
    required this.onChanged,
  });

  final double volume;
  final Color accentColor;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final IconData volIcon = volume == 0
        ? Icons.volume_off_rounded
        : volume < 0.4
            ? Icons.volume_down_rounded
            : Icons.volume_up_rounded;

    return Row(
      children: [
        Icon(volIcon, color: Colors.white38, size: 16),
        const SizedBox(width: 4),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: accentColor.withValues(alpha: 0.8),
              inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
              thumbColor: Colors.white,
              overlayColor: accentColor.withValues(alpha: 0.15),
            ),
            child: Slider(
              value: volume.clamp(0.0, 1.0),
              onChanged: onChanged,
            ),
          ),
        ),
        const Icon(Icons.volume_up_rounded, color: Colors.white24, size: 16),
      ],
    );
  }
}
