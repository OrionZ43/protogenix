// lib/features/player/presentation/screens/player_screen.dart
// Компактный плеер (телефон / узкий режим)
//
// UPDATED:
// - Фикс TopBar (Stack для идеальной центровки)
// - Адаптация под Status Bar (SafeArea/Padding)
// - Поддержка Flex Mode (Tabletop)
// - Унификация кнопок (EQ + Sleep Timer)

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../domain/track_model.dart';
import '../providers/player_provider.dart';
import '../providers/palette_provider.dart';
import '../widgets/protogenix_background.dart';
import '../widgets/music_visualizer_controls.dart';
import '../widgets/lyrics_search_sheet.dart';
import '../widgets/beautiful_lyrics_view.dart';
import '../widgets/sleep_timer_sheet.dart';
import '../../../importer/presentation/importer_sheet.dart';

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);

    if (player.queue.isEmpty) {
      return const _EmptyLibraryScreen();
    }

    final track = player.currentTrack as TrackModel?;

    return Scaffold(
      backgroundColor: Colors.black,
      body: ProtogenixBackground(
        child: Column(
          children: [
            _TopBar(track: track),
            const Expanded(
              child: MusicVisualizerControls(
                compact: false,
                showFavorite: true,
              ),
            ),
            _BottomRow(track: track),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Top Bar ───────────────────────────────────────────────────────────────────

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.track});
  final TrackModel? track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topPadding = MediaQuery.viewPaddingOf(context).top;

    return Padding(
      padding: EdgeInsets.only(top: topPadding + 8, left: 16, right: 16),
      child: SizedBox(
        height: 44,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Слева: Кнопка закрытия
            if (Navigator.canPop(context))
              Positioned(
                left: 0,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).pop();
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

            // Справа: Эквалайзер (только Android) +Lyrics
            Positioned(
              right: 0,
              child: Row(
                children: [
                  if (track != null)
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _showLyricsSheet(context, ref);
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
}

// ── Bottom Row ────────────────────────────────────────────────────────────────

class _BottomRow extends ConsumerWidget {
  const _BottomRow({required this.track});
  final TrackModel? track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(paletteProvider);
    final timerActive =
        ref.watch(playerProvider.select((s) => s.sleepTimerActive));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _CapsuleBtn(
            icon: Icons.add_rounded,
            label: 'Добавить',
            onTap: () {
              HapticFeedback.lightImpact();
              showImporterSheet(context);
            },
          ),
          _CapsuleBtn(
            icon: Icons.bedtime_rounded,
            label: 'Таймер',
            isActive: timerActive,
            accentColor: palette.primary,
            onTap: () {
              HapticFeedback.lightImpact();
              showSleepTimerSheet(context, ref);
            },
          ),
          _CapsuleBtn(
            icon: Icons.lyrics_outlined,
            label: 'Текст',
            onTap: track != null
                ? () {
                    HapticFeedback.lightImpact();
                    _showLyricsSheet(context, ref);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

void _showLyricsSheet(BuildContext context, WidgetRef ref) {
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
                            final track = ref.read(playerProvider).currentTrack;
                            if (track != null) {
                              showLyricsSearchSheet(context, ref, track);
                            }
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

// ── Empty Library ─────────────────────────────────────────────────────────────

class _EmptyLibraryScreen extends StatelessWidget {
  const _EmptyLibraryScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ProtogenixBackground(
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.library_music_rounded,
                    size: 80, color: Colors.white24),
                const SizedBox(height: 24),
                const Text(
                  'Библиотека пуста',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 22,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Добавь треки, чтобы начать',
                  style: TextStyle(color: Colors.white38, fontSize: 14),
                ),
                const SizedBox(height: 32),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    showImporterSheet(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.white.withAlpha(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, color: Colors.white70),
                        SizedBox(width: 8),
                        Text('Добавить трек',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 16)),
                      ],
                    ),
                  ),
                ),
              ],
            ).animate().fadeIn(duration: 600.ms).scale(
                begin: const Offset(0.9, 0.9), curve: Curves.easeOutCubic),
          ),
        ),
      ),
    );
  }
}
