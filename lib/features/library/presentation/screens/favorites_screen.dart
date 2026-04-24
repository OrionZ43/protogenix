// lib/features/library/presentation/screens/favorites_screen.dart
//
// Экран "Избранное" — фильтрует треки библиотеки по favoritesProvider.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/library_track.dart';
import '../library_provider.dart';
import '../playlist_provider.dart';
import '../widgets/track_context_menu.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../../player/presentation/widgets/protogenix_background.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allTracks = ref.watch(libraryProvider);
    final favoriteIds = ref.watch(favoritesProvider);

    final favorites = allTracks
        .where((t) => favoriteIds.contains(t.id))
        .toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ProtogenixBackground(
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              // Заголовок
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      const Text(
                        'Избранное',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const Spacer(),
                      if (favorites.isNotEmpty)
                        Text(
                          '${favorites.length}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 16,
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              if (favorites.isEmpty)
                const SliverFillRemaining(child: _EmptyFavorites())
              else ...[
                // Кнопка "Играть всё"
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: _PlayAllButton(tracks: favorites),
                  ),
                ),

                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _FavoriteTile(
                      track: favorites[i],
                      index: i,
                      allTracks: favorites,
                    ),
                    childCount: favorites.length,
                  ),
                ),
              ],

              const SliverToBoxAdapter(child: SizedBox(height: 140)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Кнопка играть всё ─────────────────────────────────────────────────────────

class _PlayAllButton extends ConsumerWidget {
  const _PlayAllButton({required this.tracks});
  final List<LibraryTrack> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        final models = tracks.map((t) => t.toTrackModel()).toList();
        ref.read(playerProvider.notifier).loadPlaylist(models);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withAlpha(15),
          border: Border.all(color: Colors.white.withAlpha(25)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_rounded, color: Colors.redAccent, size: 18),
            SizedBox(width: 8),
            Text(
              'Слушать избранное',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyFavorites extends StatelessWidget {
  const _EmptyFavorites();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.favorite_outline_rounded,
            size: 80,
            color: Colors.white12,
          ),
          const SizedBox(height: 20),
          const Text(
            'Нет избранных треков',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Нажми ♥ у трека, чтобы добавить',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ── Track tile ────────────────────────────────────────────────────────────────

class _FavoriteTile extends ConsumerWidget {
  const _FavoriteTile({
    required this.track,
    required this.index,
    required this.allTracks,
  });

  final LibraryTrack track;
  final int index;
  final List<LibraryTrack> allTracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final isPlaying = player.currentTrack?.id == track.id;

    return InkWell(
      onTap: () {
        final models = allTracks.map((t) => t.toTrackModel()).toList();
        ref
            .read(playerProvider.notifier)
            .loadPlaylist(models, initialIndex: index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: isPlaying ? Colors.white.withAlpha(8) : Colors.transparent,
        child: Row(
          children: [
            // Сердечко
            GestureDetector(
              onTap: () =>
                  ref.read(favoritesProvider.notifier).toggle(track.id),
              child: const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(
                  Icons.favorite_rounded,
                  color: Colors.redAccent,
                  size: 18,
                ),
              ),
            ),

            // Обложка
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image(
                image: track.coverPath != null
                    ? FileImage(File(track.coverPath!)) as ImageProvider
                    : const AssetImage('assets/images/mock_cover.jpg'),
                width: 50,
                height: 50,
                fit: BoxFit.cover,
              ),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),

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
}
