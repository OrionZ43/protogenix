import 'dart:io';

// lib/features/player/presentation/screens/expanded_player_screen.dart
//
// Полноэкранный плеер для Fold / планшета.
//
// Макет:
//   [← кнопка назад]
//   ┌─────────────── 50% ─────────────────┬──────────── 50% ──────────────┐
//   │  PlayerMainControls                 │  BeautifulLyricsView          │
//   │  (обложка + сердечко + кнопки)      │  (текст / karaoke)            │
//   └─────────────────────────────────────┴───────────────────────────────┘

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/palette_provider.dart';
import '../providers/karaoke_provider.dart';
import '../providers/player_provider.dart';
import '../../domain/track_model.dart';
import '../widgets/protogenix_background.dart';
import '../widgets/beautiful_lyrics_view.dart';
import '../widgets/player_main_controls.dart';

class ExpandedPlayerScreen extends ConsumerWidget {
  const ExpandedPlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    ref.watch(karaokeProvider);
    ref.watch(paletteProvider);

    final track = player.currentTrack as TrackModel?;

    return Scaffold(
      backgroundColor: Colors.black,
      body: ProtogenixBackground(
        child: SafeArea(
          child: Column(
            children: [
              // ── Топ-бар с кнопкой "назад" ─────────────────────────────────
              if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                const DragToMoveArea(child: SizedBox(height: 16)) // Small padding for drag area, PlayerMainControls has its own TopBar
              else
                const SizedBox.shrink(),

              // ── Основной контент ──────────────────────────────────────────
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = Platform.isWindows ||
                        Platform.isLinux ||
                        Platform.isMacOS;
                    final isWideDesktop =
                        isDesktop && constraints.maxWidth > 900;

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Левая колонка — плеер (PlayerMainControls)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                                vertical: isWideDesktop ? 24.0 : 0.0),
                            child: PlayerMainControls(
                              track: track,
                              compact: false, // Обязательно false, чтобы использовать большие шрифты
                            ),
                          ),
                        ),

                        VerticalDivider(
                          color: Colors.white.withAlpha(18),
                          width: 1,
                          thickness: 1,
                        ),

                        // Правая колонка — текст песни
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                                top: isWideDesktop ? 48.0 : 24.0,
                                right: isWideDesktop ? 48.0 : 32.0,
                                bottom: isWideDesktop ? 48.0 : 24.0),
                            child: const BeautifulLyricsView(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
