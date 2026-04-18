// lib/features/player/presentation/screens/player_screen.dart
// Компактный плеер (телефон / узкий режим)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/track_model.dart';
import '../providers/player_provider.dart';
import '../providers/karaoke_provider.dart';
import '../widgets/protogenix_background.dart';
import '../widgets/music_visualizer_controls.dart';
import '../widgets/lyrics_search_sheet.dart';
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
        child: SafeArea(
          child: Column(
            children: [
              _TopBar(track: track),
              Expanded(
                child: MusicVisualizerControls(
                  compact:      false,
                  showFavorite: true,   // ← сердечко рядом с названием
                ),
              ),
              _BottomRow(track: track),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Top Bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.track});
  final TrackModel? track;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          const Text(
            'PROTOGENIX',
            style: TextStyle(
              color:         Colors.white70,
              fontSize:      11,
              fontWeight:    FontWeight.w600,
              letterSpacing: 2.5,
            ),
          ),
          const Spacer(),
          if (track != null)
            const Icon(Icons.lyrics_outlined, color: Colors.white54, size: 22),
        ],
      ),
    );
  }
}

// ── Bottom Row — кнопки «Добавить трек» и «Текст» ────────────────────────────

class _BottomRow extends ConsumerWidget {
  const _BottomRow({required this.track});
  final TrackModel? track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _CapsuleBtn(
            icon:  Icons.add_rounded,
            label: 'Добавить',
            onTap: () => showImporterSheet(context),
          ),
          _CapsuleBtn(
            icon:  Icons.manage_search_rounded,
            label: 'Текст',
            // Открывает ручной поиск текста (ранее был пустой () {})
            onTap: track != null
                ? () => showLyricsSearchSheet(context, ref, track!)
                : null,
          ),
        ],
      ),
    );
  }
}

class _CapsuleBtn extends StatelessWidget {
  const _CapsuleBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData     icon;
  final String       label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Opacity(
      opacity: onTap != null ? 1.0 : 0.4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color:  Colors.white.withAlpha(12),
          border: Border.all(color: Colors.white.withAlpha(25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white60, size: 15),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ],
        ),
      ),
    ),
  );
}

// ── Empty Library ─────────────────────────────────────────────────────────────

class _EmptyLibraryScreen extends ConsumerWidget {
  const _EmptyLibraryScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                const Text('Библиотека пуста',
                    style: TextStyle(color: Colors.white70, fontSize: 22,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text('Добавь треки, чтобы начать',
                    style: TextStyle(color: Colors.white38, fontSize: 14)),
                const SizedBox(height: 32),
                GestureDetector(
                  onTap: () => showImporterSheet(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color:  Colors.white.withAlpha(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, color: Colors.white70),
                        SizedBox(width: 8),
                        Text('Добавить трек',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 16)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
