// lib/features/player/presentation/widgets/music_visualizer_controls.dart
//
// MusicVisualizerControls v4 — чистый UI без привязки к аудио.
//   • _FullLayout:    обложка + контролы вертикально центрированы
//   • _CompactLayout: капсульные кнопки внизу через [onAddTrack] / [onChangeLyrics]
//   • Обложка и кнопки статичны — без скейла от bass/beatDrop
//   • Убраны: VisualizerEngine, VisualizerSnapshot, bass, highs, beatDrop, Ticker-реакции

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/track_model.dart';
import '../../domain/player_state.dart' as ps;
import '../providers/palette_provider.dart';
import '../providers/player_provider.dart';
import 'waveform_progress_bar.dart';

// ═════════════════════════════════════════════════════════════════════════════
// PUBLIC WIDGET
// ═════════════════════════════════════════════════════════════════════════════

class MusicVisualizerControls extends ConsumerWidget {
  const MusicVisualizerControls({
    super.key,
    this.compact        = false,
    this.onAddTrack,
    this.onChangeLyrics,
  });

  final bool          compact;
  final VoidCallback? onAddTrack;
  final VoidCallback? onChangeLyrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player   = ref.watch(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    final palette  = ref.watch(paletteProvider);

    final track = player.currentTrack as TrackModel?;
    if (track == null) return const SizedBox.shrink();

    if (compact) {
      return _CompactLayout(
        track:          track,
        player:         player,
        notifier:       notifier,
        palette:        palette,
        onAddTrack:     onAddTrack,
        onChangeLyrics: onChangeLyrics,
      );
    }

    return _FullLayout(
      track:    track,
      player:   player,
      notifier: notifier,
      palette:  palette,
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
  });

  final TrackModel               track;
  final ps.ProtogenixPlayerState player;
  final PlayerNotifier           notifier;
  final PaletteState             palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _CoverArt(track: track),
          const SizedBox(height: 28),
          _TrackInfo(track: track, palette: palette),
          const SizedBox(height: 20),
          LiveWaveformProgressBar(
            progress:    player.progress,
            accentColor: palette.primary,
            onSeek:      notifier.seekToProgress,
            position:    player.position,
            total:       player.total,
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
    this.onAddTrack,
    this.onChangeLyrics,
  });

  final TrackModel               track;
  final ps.ProtogenixPlayerState player;
  final PlayerNotifier           notifier;
  final PaletteState             palette;
  final VoidCallback?            onAddTrack;
  final VoidCallback?            onChangeLyrics;

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
                _TrackInfo(track: track, palette: palette, compact: true),
                const SizedBox(height: 16),
                LiveWaveformProgressBar(
                  progress:    player.progress,
                  accentColor: palette.primary,
                  onSeek:      notifier.seekToProgress,
                  position:    player.position,
                  total:       player.total,
                  height:      40,
                  barCount:    60,
                ),
                const SizedBox(height: 12),
                _Controls(
                  player: player, notifier: notifier,
                  palette: palette, compact: true,
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
                if (onAddTrack != null) ...[
                  _CapsuleButton(
                    icon: Icons.add_rounded, label: 'Добавить трек',
                    color: palette.primary,  onTap: onAddTrack!,
                  ),
                  const SizedBox(width: 10),
                ],
                if (onChangeLyrics != null)
                  _CapsuleButton(
                    icon: Icons.manage_search_rounded, label: 'Другой текст',
                    color: palette.secondary, onTap: onChangeLyrics!,
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

class _CapsuleButton extends StatelessWidget {
  const _CapsuleButton({
    required this.icon,  required this.label,
    required this.color, required this.onTap,
  });
  final IconData icon; final String label;
  final Color color;   final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color:  Colors.white.withAlpha(18),
        border: Border.all(color: Colors.white.withAlpha(35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// COVER ART — статичная, без реакции на bass
// ─────────────────────────────────────────────────────────────────────────────

class _CoverArt extends StatelessWidget {
  const _CoverArt({required this.track, this.size});
  final TrackModel track;
  final double?    size;

  @override
  Widget build(BuildContext context) {
    final sz = size ??
        (MediaQuery.of(context).size.width - 48).clamp(180.0, 320.0);

    return Container(
      width: sz,
      height: sz,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withAlpha(100),
            blurRadius: 40,
            offset:     const Offset(0, 16),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image(
        image: track.coverImage,
        fit:   BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: Colors.white10,
          child: const Icon(
            Icons.music_note_rounded,
            color: Colors.white24,
            size:  80,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TRACK INFO
// ─────────────────────────────────────────────────────────────────────────────

class _TrackInfo extends StatelessWidget {
  const _TrackInfo({
    required this.track,
    required this.palette,
    this.compact = false,
  });
  final TrackModel track;
  final PaletteState palette;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(
      track.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        color:       Colors.white,
        fontSize:    compact ? 18 : 22,
        fontWeight:  FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
    const SizedBox(height: 4),
    Text(
      track.artist,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        color:    Colors.white60,
        fontSize: compact ? 13 : 15,
      ),
    ),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// CONTROLS ROW — статичные кнопки, без Ticker и реакции на аудио
// ─────────────────────────────────────────────────────────────────────────────

class _Controls extends StatelessWidget {
  const _Controls({
    required this.player,
    required this.notifier,
    required this.palette,
    this.compact = false,
  });

  final ps.ProtogenixPlayerState player;
  final PlayerNotifier           notifier;
  final PaletteState             palette;
  final bool                     compact;

  @override
  Widget build(BuildContext context) {
    final playing  = player.isPlaying;
    final iconSize = compact ? 20.0 : 24.0;
    final playSize = compact ? 52.0 : 64.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _CtrlButton(
          icon:  Icons.shuffle_rounded,
          color: player.isShuffle ? palette.primary : Colors.white38,
          size:  iconSize,
          onTap: notifier.toggleShuffle,
        ),
        const Spacer(),
        _CtrlButton(
          icon: Icons.skip_previous_rounded, color: Colors.white,
          size: iconSize + 4, onTap: notifier.previous,
        ),
        const SizedBox(width: 16),

        // Play/Pause — фиксированный размер, без scale от bass
        GestureDetector(
          onTap: notifier.playPause,
          child: Container(
            width: playSize,
            height: playSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.primary,
              boxShadow: [
                BoxShadow(
                  color:      palette.primary.withAlpha(80),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size:  playSize * 0.5,
            ),
          ),
        ),

        const SizedBox(width: 16),
        _CtrlButton(
          icon: Icons.skip_next_rounded, color: Colors.white,
          size: iconSize + 4, onTap: notifier.next,
        ),
        const Spacer(),
        _CtrlButton(
          icon: switch (player.repeatMode) {
            ps.RepeatMode.none => Icons.repeat_rounded,
            ps.RepeatMode.all  => Icons.repeat_rounded,
            ps.RepeatMode.one  => Icons.repeat_one_rounded,
          },
          color: player.repeatMode != ps.RepeatMode.none
              ? palette.primary : Colors.white38,
          size:  iconSize,
          onTap: notifier.toggleRepeat,
        ),
      ],
    );
  }
}

class _CtrlButton extends StatelessWidget {
  const _CtrlButton({
    required this.icon,  required this.color,
    required this.size,  required this.onTap,
  });
  final IconData icon;
  final Color    color;
  final double   size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Icon(icon, color: color, size: size),
    ),
  );
}
