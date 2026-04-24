// lib/features/player/presentation/screens/expanded_player_screen.dart
//
// Полноэкранный плеер для Fold / планшета.
//
// Макет:
//   [← кнопка назад]
//   ┌─────────────── 42% ─────────────────┬──────────── 58% ──────────────┐
//   │  MusicVisualizerControls            │  BeautifulLyricsView          │
//   │  (обложка + сердечко + кнопки)      │  (текст / karaoke)            │
//   └─────────────────────────────────────┴───────────────────────────────┘

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/palette_provider.dart';
import '../providers/karaoke_provider.dart';
import '../providers/player_provider.dart';
import '../../domain/track_model.dart';
import '../widgets/protogenix_background.dart';
import '../widgets/music_visualizer_controls.dart';
import '../widgets/beautiful_lyrics_view.dart';
import '../widgets/lyrics_search_sheet.dart';
import '../../../importer/presentation/importer_sheet.dart';

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
              _TopBar(track: track),

              // ── Основной контент ──────────────────────────────────────────
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Левая колонка — плеер (42%), сердечко включено
                    Expanded(
                      flex: 42,
                      child: MusicVisualizerControls(
                        compact: true,
                        showFavorite: true, // ← сердечко рядом с названием
                        onAddTrack: () => showImporterSheet(context),
                        onChangeLyrics: track != null
                            ? () => showLyricsSearchSheet(context, ref, track)
                            : null,
                      ),
                    ),

                    VerticalDivider(
                      color: Colors.white.withAlpha(18),
                      width: 1,
                      thickness: 1,
                    ),

                    // Правая колонка — текст песни (58%)
                    const Expanded(flex: 58, child: BeautifulLyricsView()),
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

// ─────────────────────────────────────────────────────────────────────────────
// TOP BAR
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.track});
  final TrackModel? track;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          // Левая часть: кнопка «Назад»
          SizedBox(
            width: 120,
            child: Navigator.canPop(context)
                ? Center(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withAlpha(15),
                        ),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white70,
                          size: 24,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // Центр: Логотип
          const Expanded(
            child: Text(
              'PROTOGENIX',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 2.5,
              ),
            ),
          ),

          // Правая часть: название трека
          SizedBox(
            width: 120,
            child: track != null
                ? Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text(
                      track!.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
