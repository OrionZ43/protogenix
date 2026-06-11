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

import '../providers/palette_provider.dart';
import '../providers/karaoke_provider.dart';
import '../providers/player_provider.dart';
import '../../domain/track_model.dart';
import '../widgets/protogenix_background.dart';
import '../widgets/beautiful_lyrics_view.dart';
import '../widgets/player_main_controls.dart';

class ExpandedPlayerScreen extends ConsumerWidget {
  const ExpandedPlayerScreen({super.key, this.onClose});

  /// Если задан — кнопка "вниз"/"назад" вызывает этот callback вместо Navigator.pop.
  /// Используется на десктопе, где экран не является отдельным route.
  final VoidCallback? onClose;

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
                          flex: isWideDesktop ? 4 : 1,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                                vertical: isWideDesktop ? 24.0 : 0.0),
                            child: PlayerMainControls(
                              track: track,
                              compact: false, // Обязательно false, чтобы использовать большие шрифты
                              onClose: onClose,
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
                          flex: isWideDesktop ? 6 : 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(100),
                                  blurRadius: 40,
                                  spreadRadius: -10,
                                  offset: const Offset(-20, 0),
                                ),
                              ],
                            ),
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
