// lib/features/player/presentation/widgets/music_visualizer_controls.dart
//
// MusicVisualizerControls v5.1 — доработано с тактильной отдачей и улучшенными зонами тапа.
//   • showFavorite: true → сердечко слева от названия трека
//   • Реактивно через isFavoriteProvider — мгновенный отклик без перезагрузки
//   • Интегрирован HapticFeedback для премиального ощущения

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/track_model.dart';
import '../../domain/player_state.dart' as ps;
import '../providers/palette_provider.dart';
import '../providers/player_provider.dart';
import '../../../library/presentation/playlist_provider.dart';
import '../../../library/presentation/widgets/add_to_playlist_sheet.dart';
import '../../../../core/utils/haptic_patterns.dart';
import 'waveform_progress_bar.dart';

// ═════════════════════════════════════════════════════════════════════════════
// PUBLIC WIDGET
// ═════════════════════════════════════════════════════════════════════════════

class MusicVisualizerControls extends ConsumerWidget {
  const MusicVisualizerControls({
    super.key,
    this.compact = false,
    this.showFavorite = false,
    this.onAddTrack,
    this.onChangeLyrics,
  });

  final bool compact;

  /// Показывать ли кнопку «Избранное» рядом с названием трека
  final bool showFavorite;
  final VoidCallback? onAddTrack;
  final VoidCallback? onChangeLyrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    final palette = ref.watch(paletteProvider);

    final track = player.currentTrack as TrackModel?;
    if (track == null) return const SizedBox.shrink();

    if (compact) {
      return _CompactLayout(
        track: track,
        player: player,
        notifier: notifier,
        palette: palette,
        showFavorite: showFavorite,
        onAddTrack: onAddTrack,
        onChangeLyrics: onChangeLyrics,
      );
    }

    return _FullLayout(
      track: track,
      player: player,
      notifier: notifier,
      palette: palette,
      showFavorite: showFavorite,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FULL LAYOUT
// ─────────────────────────────────────────────────────────────────────────────

class _FullLayout extends StatelessWidget {
  const _FullLayout({
    required this.track,
    required this.player,
    required this.notifier,
    required this.palette,
    required this.showFavorite,
  });

  final TrackModel track;
  final ps.ProtogenixPlayerState player;
  final PlayerNotifier notifier;
  final PaletteState palette;
  final bool showFavorite;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(child: _CoverArt(track: track)),
          const SizedBox(height: 28),
          _TrackInfo(
            track: track,
            palette: palette,
            showFavorite: showFavorite,
          ),
          const SizedBox(height: 20),
          Flexible(
            child: LiveWaveformProgressBar(
              progress: player.progress,
              accentColor: palette.primary,
              onSeek: notifier.seekToProgress,
              position: player.position,
              total: player.total,
            ),
          ),
          const SizedBox(height: 16),
          _Controls(player: player, notifier: notifier, palette: palette),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMPACT LAYOUT
// ─────────────────────────────────────────────────────────────────────────────

class _CompactLayout extends StatelessWidget {
  const _CompactLayout({
    required this.track,
    required this.player,
    required this.notifier,
    required this.palette,
    required this.showFavorite,
    this.onAddTrack,
    this.onChangeLyrics,
  });

  final TrackModel track;
  final ps.ProtogenixPlayerState player;
  final PlayerNotifier notifier;
  final PaletteState palette;
  final bool showFavorite;
  final VoidCallback? onAddTrack;
  final VoidCallback? onChangeLyrics;

  @override
  Widget build(BuildContext context) {
    final hasButtons = onAddTrack != null || onChangeLyrics != null;

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CoverArt(track: track, size: 200),
                const SizedBox(height: 16),
                _TrackInfo(
                  track: track,
                  palette: palette,
                  compact: true,
                  showFavorite: showFavorite,
                ),
                const SizedBox(height: 16),
                LiveWaveformProgressBar(
                  progress: player.progress,
                  accentColor: palette.primary,
                  onSeek: notifier.seekToProgress,
                  position: player.position,
                  total: player.total,
                  height: 40,
                  barCount: 60,
                ),
                const SizedBox(height: 12),
                _Controls(
                  player: player,
                  notifier: notifier,
                  palette: palette,
                  compact: true,
                ),
                const SizedBox(height: 10),
                _VolumeSlider(
                  volume: player.volume,
                  accentColor: palette.primary,
                  onChanged: notifier.setVolume,
                ),
              ],
            ),
          ),
        ),
        if (hasButtons)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Flexible: на узком телефоне подписи сокращаются многоточием,
                // а не выталкивают кнопки за край экрана
                if (onAddTrack != null) ...[
                  Flexible(
                    child: _CapsuleButton(
                      icon: Icons.add_rounded,
                      label: 'Добавить трек',
                      color: palette.primary,
                      onTap: onAddTrack!,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                if (onChangeLyrics != null)
                  Flexible(
                    child: _CapsuleButton(
                      icon: Icons.manage_search_rounded,
                      label: 'Другой текст',
                      color: palette.secondary,
                      onTap: onChangeLyrics!,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CAPSULE BUTTON
// ─────────────────────────────────────────────────────────────────────────────

class _CapsuleButton extends StatefulWidget {
  const _CapsuleButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_CapsuleButton> createState() => _CapsuleButtonState();
}

class _CapsuleButtonState extends State<_CapsuleButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _isHovered ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: _isHovered
                  ? Colors.white.withAlpha(25)
                  : Colors.white.withAlpha(18),
              border: Border.all(color: Colors.white.withAlpha(35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, color: widget.color, size: 17),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 13)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COVER ART
// ─────────────────────────────────────────────────────────────────────────────

class _CoverArt extends StatelessWidget {
  const _CoverArt({required this.track, this.size});
  final TrackModel track;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final sz =
        size ?? (MediaQuery.of(context).size.width - 48).clamp(180.0, 320.0);

    return Container(
      width: sz,
      height: sz,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(100),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image(
        image: track.coverImage,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: Colors.white10,
          child: const Icon(
            Icons.music_note_rounded,
            color: Colors.white24,
            size: 80,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TRACK INFO  — ConsumerWidget, чтобы напрямую читать favoritesProvider
// ─────────────────────────────────────────────────────────────────────────────

class _TrackInfo extends ConsumerWidget {
  const _TrackInfo({
    required this.track,
    required this.palette,
    this.compact = false,
    this.showFavorite = false,
  });
  final TrackModel track;
  final PaletteState palette;
  final bool compact;
  final bool showFavorite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav =
        showFavorite ? ref.watch(isFavoriteProvider(track.id)) : false;

    final titleStyle = TextStyle(
      color: Colors.white,
      fontSize: compact ? 18 : 22,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
    );
    final artistStyle = TextStyle(
      color: Colors.white60,
      fontSize: compact ? 13 : 15,
    );

    return Row(
      children: [
        // Сердечко слева (занимает 40px → текст остаётся по центру)
        if (showFavorite)
          SizedBox(
            width: 40,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                ref.read(favoritesProvider.notifier).toggle(track.id);
              },
              behavior: HitTestBehavior.opaque,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(
                  isFav
                      ? Icons.favorite_rounded
                      : Icons.favorite_outline_rounded,
                  key: ValueKey(isFav),
                  color: isFav ? Colors.redAccent : Colors.white38,
                  size: 22,
                ),
              ),
            ),
          )
        else
          const SizedBox(width: 40),

        // Название + артист — центрированы
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                track.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: titleStyle,
              ),
              const SizedBox(height: 4),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: artistStyle,
              ),
            ],
          ),
        ),

        // Справа — «в плейлист», симметрично сердечку (раньше тут был пустой
        // противовес). Просили в отзывах: без «⋮» и выбора пунктов
        if (showFavorite)
          SizedBox(
            width: 40,
            child: Tooltip(
              message: 'В плейлист',
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  showAddToPlaylistSheet(context, [track.id]);
                },
                behavior: HitTestBehavior.opaque,
                child: const Icon(Icons.playlist_add_rounded,
                    color: Colors.white38, size: 24),
              ),
            ),
          )
        else
          const SizedBox(width: 40),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CONTROLS ROW
// ─────────────────────────────────────────────────────────────────────────────

class _Controls extends StatelessWidget {
  const _Controls({
    required this.player,
    required this.notifier,
    required this.palette,
    this.compact = false,
  });

  final ps.ProtogenixPlayerState player;
  final PlayerNotifier notifier;
  final PaletteState palette;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final playing = player.isPlaying;
    final iconSize = compact ? 20.0 : 24.0;
    final playSize = compact ? 52.0 : 64.0;

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _CtrlButton(
            tooltip: 'Shuffle',
            icon: Icons.shuffle_rounded,
            color: player.isShuffle ? palette.primary : Colors.white38,
            size: iconSize,
            onTap: () {
              player.isShuffle
                  ? HapticPatterns.shuffleOff()
                  : HapticPatterns.shuffleOn();
              notifier.toggleShuffle();
            },
          ),
          const SizedBox(width: 16),
          _CtrlButton(
            tooltip: 'Previous',
            icon: Icons.skip_previous_rounded,
            color: Colors.white,
            size: iconSize + 4,
            onTap: () {
              HapticPatterns.previous();
              notifier.previous();
            },
          ),
          const SizedBox(width: 16),
          Tooltip(
            message: playing ? 'Pause' : 'Play',
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(200),
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(color: Colors.white70, fontSize: 12),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  HapticPatterns.playPause();
                  notifier.playPause();
                },
                child: Container(
                  width: playSize,
                  height: playSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.primary,
                    boxShadow: [
                      BoxShadow(
                        color: palette.primary.withAlpha(80),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: playSize * 0.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          _CtrlButton(
            tooltip: 'Next',
            icon: Icons.skip_next_rounded,
            color: Colors.white,
            size: iconSize + 4,
            onTap: () {
              HapticPatterns.next();
              notifier.next();
            },
          ),
          const SizedBox(width: 16),
          _CtrlButton(
            tooltip: 'Repeat',
            icon: switch (player.repeatMode) {
              ps.RepeatMode.none => Icons.repeat_rounded,
              ps.RepeatMode.all => Icons.repeat_rounded,
              ps.RepeatMode.one => Icons.repeat_one_rounded,
            },
            color: player.repeatMode != ps.RepeatMode.none
                ? palette.primary
                : Colors.white38,
            size: iconSize,
            onTap: () {
              HapticPatterns.repeat();
              notifier.toggleRepeat();
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VOLUME SLIDER — десктопный ползунок громкости
// ─────────────────────────────────────────────────────────────────────────────

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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(volIcon, color: Colors.white38, size: 16),
          const SizedBox(width: 4),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: accentColor.withAlpha(200),
                inactiveTrackColor: Colors.white.withAlpha(20),
                thumbColor: Colors.white,
                overlayColor: accentColor.withAlpha(30),
              ),
              child: Slider(
                value: volume.clamp(0.0, 1.0),
                onChanged: onChanged,
              ),
            ),
          ),
          const Icon(Icons.volume_up_rounded, color: Colors.white24, size: 16),
        ],
      ),
    );
  }
}

class _CtrlButton extends StatefulWidget {
  const _CtrlButton({
    required this.icon,
    required this.color,
    required this.size,
    required this.onTap,
    this.tooltip,
  });
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  State<_CtrlButton> createState() => _CtrlButtonState();
}

class _CtrlButtonState extends State<_CtrlButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    Widget child = GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _isHovered ? 1.1 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(widget.icon, color: widget.color, size: widget.size),
        ),
      ),
    );

    child = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: child,
    );

    if (widget.tooltip != null) {
      child = Tooltip(
        message: widget.tooltip!,
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(200),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: Colors.white70, fontSize: 12),
        child: child,
      );
    }

    return child;
  }
}
