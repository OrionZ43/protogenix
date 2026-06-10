import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/karaoke_provider.dart';
import '../providers/palette_provider.dart';
import '../providers/player_provider.dart';
import '../../domain/track_model.dart';
import '../widgets/protogenix_background.dart';
import '../widgets/player_main_controls.dart';
import '../../../importer/presentation/importer_sheet.dart';

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    ref.watch(karaokeProvider);
    ref.watch(paletteProvider);

    final track = player.currentTrack as TrackModel?;

    return Scaffold(
      backgroundColor: Colors.black,
      body: ProtogenixBackground(
        child: track != null
            ? (Platform.isWindows || Platform.isLinux || Platform.isMacOS
                ? DragToMoveArea(
                    child: PlayerMainControls(track: track, compact: true))
                : PlayerMainControls(track: track, compact: true))
            : const _EmptyLibraryScreen(),
      ),
    );
  }
}

// ── Empty Library ─────────────────────────────────────────────────────────────

class _EmptyLibraryScreen extends StatelessWidget {
  const _EmptyLibraryScreen();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
    );
  }
}
