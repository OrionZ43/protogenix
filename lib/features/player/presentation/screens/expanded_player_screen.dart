// lib/features/player/presentation/screens/expanded_player_screen.dart
//
// ExpandedPlayerScreen v3:
//   • Левая колонка центрирована (Expanded + mainAxisAlignment.center внутри)
//   • Кнопки «Добавить трек» / «Другой текст» — капсулы ВНИЗУ левой панели
//   • Тот же визуализатор баса что на PlayerScreen (DRY через MusicVisualizerControls)

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
          child: Row(
            children: [
              // ── Левая колонка — плеер (42%) ─────────────────────────────
              Expanded(
                flex: 42,
                child: MusicVisualizerControls(
                  compact:    true,
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

              // ── Правая колонка — текст (58%) ─────────────────────────────
              const Expanded(
                flex: 58,
                child: BeautifulLyricsView(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}