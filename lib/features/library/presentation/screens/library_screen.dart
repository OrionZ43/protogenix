// lib/features/library/presentation/screens/library_screen.dart
//
// Экран "Треки" — список всей библиотеки.
// Пусто → заглушка с кнопкой импорта.
// Трек → тап запускает воспроизведение, три точки → TrackContextMenu.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/library_track.dart';
import '../library_provider.dart';
import '../playlist_provider.dart';
import '../widgets/track_context_menu.dart';
import '../../../importer/presentation/importer_sheet.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../../player/presentation/widgets/protogenix_background.dart';

class LibraryScreen extends ConsumerWidget {
  LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(libraryProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ProtogenixBackground(
        child: tracks.isEmpty
            ? _EmptyState(onImport: () => showImporterSheet(context))
            : _TrackList(tracks: tracks),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY STATE
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onImport});
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.library_music_rounded,
              size:  80,
              color: Colors.white12,
            ),
            const SizedBox(height: 24),
            const Text(
              'Библиотека пуста',
              style: TextStyle(
                color:      Colors.white70,
                fontSize:   22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Добавь треки, чтобы начать',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
            const SizedBox(height: 32),
            _ImportButton(onTap: onImport),
          ],
        ),
      ),
    );
  }
}

class _ImportButton extends StatelessWidget {
  const _ImportButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
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
            Text(
              'Импортировать',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TRACK LIST
// ─────────────────────────────────────────────────────────────────────────────

class _TrackList extends ConsumerWidget {
  const _TrackList({required this.tracks});
  final List<LibraryTrack> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          // ── Заголовок ────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Text(
                    'Треки',
                    style: TextStyle(
                      color:      Colors.white,
                      fontSize:   26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${tracks.length}',
                    style: const TextStyle(
                      color:    Colors.white38,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Кнопка импорта
                  GestureDetector(
                    onTap: () => showImporterSheet(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withAlpha(15),
                        border:
                            Border.all(color: Colors.white.withAlpha(30)),
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        color: Colors.white70,
                        size:  20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Список ───────────────────────────────────────────────────────
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _TrackTile(
                track:  tracks[index],
                index:  index,
                tracks: tracks,
              ),
              childCount: tracks.length,
            ),
          ),

          // Отступ снизу (под мини-плеер + навбар)
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TRACK TILE
// ─────────────────────────────────────────────────────────────────────────────

class _TrackTile extends ConsumerWidget {
  const _TrackTile({
    required this.track,
    required this.index,
    required this.tracks,
  });

  final LibraryTrack       track;
  final int                index;
  final List<LibraryTrack> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player    = ref.watch(playerProvider);
    final isPlaying = player.currentTrack?.id == track.id;

    return InkWell(
      onTap: () {
        final models = tracks.map((t) => t.toTrackModel()).toList();
        ref.read(playerProvider.notifier).loadPlaylist(
              models,
              initialIndex: index,
            );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: isPlaying
              ? Border(
                  left: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                )
              : null,
          color: isPlaying
              ? Colors.white.withAlpha(8)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            // Обложка / playing indicator
            Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image(
                    image: track.coverPath != null
                        ? FileImage(File(track.coverPath!)) as ImageProvider
                        : const AssetImage('assets/images/mock_cover.jpg'),
                    width:  50,
                    height: 50,
                    fit:    BoxFit.cover,
                  ),
                ),
                if (isPlaying)
                  Container(
                    width:  50,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.black.withAlpha(120),
                    ),
                    child: const Icon(
                      Icons.volume_up_rounded,
                      color: Colors.white,
                      size:  22,
                    ),
                  ),
              ],
            ),

            const SizedBox(width: 14),

            // Название + артист
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color:      isPlaying ? Colors.white : Colors.white,
                      fontSize:   15,
                      fontWeight:
                          isPlaying ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color:    Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Длительность
            Text(
              _fmtDuration(track.duration),
              style: const TextStyle(
                color:    Colors.white38,
                fontSize: 12,
              ),
            ),

            const SizedBox(width: 4),

            // Три точки → контекстное меню
            IconButton(
              icon: const Icon(Icons.more_vert_rounded),
              color: Colors.white38,
              iconSize: 20,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () => showTrackContextMenu(context, ref, track),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
