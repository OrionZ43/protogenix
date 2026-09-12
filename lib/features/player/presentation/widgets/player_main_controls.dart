import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/palette_provider.dart';
import '../providers/player_provider.dart';
import '../../domain/track_model.dart';
import 'music_visualizer_controls.dart';
import 'beautiful_lyrics_view.dart';
import 'lyrics_search_sheet.dart';
import '../../../importer/presentation/importer_sheet.dart';
import 'sleep_timer_sheet.dart';
import 'eq_sheet.dart';

class PlayerMainControls extends ConsumerWidget {
  const PlayerMainControls({
    super.key,
    required this.track,
    this.compact = true,
    this.onClose,
  });

  final TrackModel? track;
  final bool compact;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _TopBar(track: track, compact: compact, onClose: onClose),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: MusicVisualizerControls(
              compact: compact,
              showFavorite: true,
              onAddTrack: () => showImporterSheet(context),
              onChangeLyrics: track != null
                  ? () => showLyricsSearchSheet(context, ref, track!)
                  : null,
            ),
          ),
        ),
        _BottomRow(track: track, compact: compact),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.track, required this.compact, this.onClose});
  final TrackModel? track;
  final bool compact;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final canClose = onClose != null || Navigator.canPop(context);
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 56,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Слева: Кнопка закрытия
            if (canClose)
              Positioned(
                left: 16,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    if (onClose != null) {
                      onClose!();
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withAlpha(20),
                    ),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ),

            // Центр: Логотип
            const Text(
              'PROTOGENIX',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 3.5,
              ),
            ),

            // Справа: эквалайзер (только Android) и текст
            Positioned(
              right: 16,
              child: Row(
                children: [
                  if (Platform.isAndroid)
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        showEqSheet(context);
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: _EqIcon(),
                      ),
                    ),
                  if (compact && track != null)
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _showLyricsSheet(context, track!);
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Icon(Icons.lyrics_outlined,
                            color: Colors.white54, size: 22),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLyricsSheet(BuildContext context, TrackModel track) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, child) {
             return Scaffold(
              backgroundColor: Colors.transparent,
              body: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(160),
                    ),
                    child: Column(
                      children: [
                        // Pull indicator
                        Center(
                          child: Container(
                            margin: const EdgeInsets.only(top: 12, bottom: 12),
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(50),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        // Search button inside lyrics view
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const SizedBox(width: 40),
                              const Text(
                                'LYRICS',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.manage_search_rounded,
                                    color: Colors.white54),
                                onPressed: () {
                                  showLyricsSearchSheet(context, ref, track);
                                },
                              ),
                            ],
                          ),
                        ),
                        const Expanded(child: BeautifulLyricsView()),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
        );
      },
    );
  }
}

/// Иконка эквалайзера: окрашена в цвет обложки, когда он включён.
class _EqIcon extends ConsumerWidget {
  const _EqIcon();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(playerProvider.select((s) => s.eqEnabled));
    final accent = ref.watch(paletteProvider.select((p) => p.primary));
    return Icon(Icons.tune_rounded,
        color: enabled ? accent : Colors.white54, size: 22);
  }
}

class _BottomRow extends ConsumerWidget {
  const _BottomRow({required this.track, required this.compact});
  final TrackModel? track;
  final bool compact;

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(paletteProvider);
    final timerActive = ref.watch(playerProvider.select((s) => s.sleepTimerActive));
    final stopAfterTrack = ref.watch(playerProvider.select((s) => s.stopAfterTrack));
    final sleepTimerRemaining = ref.watch(playerProvider.select((s) => s.sleepTimerRemaining));

    return Padding(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 8, bottom: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _CapsuleBtn(
                icon: Icons.add_rounded,
                label: 'Добавить',
                onTap: () {
                  HapticFeedback.lightImpact();
                  showImporterSheet(context);
                },
              ),
            ),
          ),
          _CapsuleBtn(
            icon: Icons.bedtime_rounded,
            label: !timerActive
                ? 'Таймер'
                : stopAfterTrack
                    ? 'До конца трека'
                    : (sleepTimerRemaining != null
                        ? _formatDuration(sleepTimerRemaining)
                        : 'Таймер активен'),
            isActive: timerActive,
            accentColor: palette.primary,
            onTap: () {
              HapticFeedback.lightImpact();
              showSleepTimerSheet(context, ref);
            },
          ),
          Expanded(
            child: compact
                ? Align(
                    alignment: Alignment.centerRight,
                    child: _CapsuleBtn(
                      icon: Icons.lyrics_outlined,
                      label: 'Текст',
                      onTap: track != null
                          ? () {
                              HapticFeedback.lightImpact();
                              _showLyricsSheet(context, ref, track!);
                            }
                          : null,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  void _showLyricsSheet(BuildContext context, WidgetRef ref, TrackModel track) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(160),
                ),
                child: Column(
                  children: [
                    // Pull indicator
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(50),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Search button inside lyrics view
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const SizedBox(width: 40),
                          const Text(
                            'LYRICS',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.manage_search_rounded,
                                color: Colors.white54),
                            onPressed: () {
                              showLyricsSearchSheet(context, ref, track);
                            },
                          ),
                        ],
                      ),
                    ),
                    const Expanded(child: BeautifulLyricsView()),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CapsuleBtn extends StatelessWidget {
  const _CapsuleBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.accentColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isActive;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? (accentColor ?? Colors.white) : Colors.white60;

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap != null ? 1.0 : 0.4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: isActive ? color.withAlpha(30) : Colors.white.withAlpha(12),
            border: Border.all(
              color:
                  isActive ? color.withAlpha(100) : Colors.white.withAlpha(25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
