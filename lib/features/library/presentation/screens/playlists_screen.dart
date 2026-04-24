// lib/features/library/presentation/screens/playlists_screen.dart
//
// Экран плейлистов + детальный экран плейлиста.

import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/playlist_database.dart';
import '../../domain/library_track.dart';
import '../playlist_provider.dart';
import '../widgets/track_context_menu.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../../player/presentation/widgets/protogenix_background.dart';
import '../../../player/presentation/widgets/glass_card.dart';

// ═════════════════════════════════════════════════════════════════════════════
// PLAYLISTS SCREEN
// ═════════════════════════════════════════════════════════════════════════════

class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _CreateFab(
        onTap: () => _createPlaylistDialog(context, ref),
      ),
      body: ProtogenixBackground(
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Row(
                    children: [
                      const Text(
                        'Плейлисты',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const Spacer(),
                      if (playlists.isNotEmpty)
                        Text(
                          '${playlists.length}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 16,
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              if (playlists.isEmpty)
                SliverFillRemaining(
                  child: _EmptyPlaylists(
                    onTap: () => _createPlaylistDialog(context, ref),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.1,
                        ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _PlaylistCard(
                        playlist: playlists[i],
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PlaylistDetailScreen(playlist: playlists[i]),
                          ),
                        ),
                        onDelete: () => ref
                            .read(playlistsProvider.notifier)
                            .delete(playlists[i].id),
                        onRename: () =>
                            _renameDialog(context, ref, playlists[i]),
                      ),
                      childCount: playlists.length,
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── FAB ───────────────────────────────────────────────────────────────────────

class _CreateFab extends StatelessWidget {
  const _CreateFab({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white.withAlpha(20),
          border: Border.all(color: Colors.white.withAlpha(40)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(
              'Создать',
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

class _EmptyPlaylists extends StatelessWidget {
  const _EmptyPlaylists({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.queue_music_rounded,
            size: 80,
            color: Colors.white12,
          ),
          const SizedBox(height: 20),
          const Text(
            'Нет плейлистов',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Создай первый плейлист',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
          const SizedBox(height: 28),
          GestureDetector(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white.withAlpha(18),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, color: Colors.white70, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Создать плейлист',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              )
              .animate()
              .fadeIn(duration: 600.ms)
              .scale(begin: const Offset(0.9, 0.9), curve: Curves.easeOutCubic),
        ],
      ),
    );
  }
}

// ── Playlist card ─────────────────────────────────────────────────────────────

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.playlist,
    required this.onTap,
    required this.onDelete,
    required this.onRename,
  });

  final Playlist playlist;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        borderRadius: 18,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withAlpha(15),
              ),
              child: const Icon(
                Icons.queue_music_rounded,
                color: Colors.white60,
                size: 22,
              ),
            ),

            const Spacer(),

            Text(
              playlist.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 6),

            Row(
              children: [
                GestureDetector(
                  onTap: onRename,
                  child: const Icon(
                    Icons.edit_outlined,
                    color: Colors.white38,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: onDelete,
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.white38,
                    size: 16,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Диалоги ───────────────────────────────────────────────────────────────────

Future<void> _createPlaylistDialog(BuildContext context, WidgetRef ref) async {
  final ctrl = TextEditingController();
  final name = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '',
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, anim1, anim2) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim1, anim2, child) {
      return Transform.scale(
        scale: anim1.value,
        child: Opacity(
          opacity: anim1.value,
          child: _GlassDialog(
            title: 'Новый плейлист',
            content: TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              cursorColor: Colors.white70,
              decoration: InputDecoration(
                hintText: 'Название...',
                hintStyle: const TextStyle(color: Colors.white38),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white60),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text(
                  'Отмена',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
                child: const Text(
                  'Создать',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (name != null && name.isNotEmpty) {
    ref.read(playlistsProvider.notifier).create(name);
  }
}

Future<void> _renameDialog(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final ctrl = TextEditingController(text: playlist.name);
  final name = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '',
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, anim1, anim2) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim1, anim2, child) {
      return Transform.scale(
        scale: anim1.value,
        child: Opacity(
          opacity: anim1.value,
          child: _GlassDialog(
            title: 'Переименовать',
            content: TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              cursorColor: Colors.white70,
              decoration: InputDecoration(
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white60),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text(
                  'Отмена',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
                child: const Text(
                  'Сохранить',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (name != null && name.isNotEmpty) {
    ref.read(playlistsProvider.notifier).rename(playlist.id, name);
  }
}

class _GlassDialog extends StatelessWidget {
  const _GlassDialog({
    required this.title,
    required this.content,
    required this.actions,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(200),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withAlpha(30)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    content,
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: actions,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PLAYLIST DETAIL SCREEN
// ═════════════════════════════════════════════════════════════════════════════

class PlaylistDetailScreen extends ConsumerWidget {
  const PlaylistDetailScreen({super.key, required this.playlist});
  final Playlist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTracks = ref.watch(playlistTracksProvider(playlist.id));

    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      body: ProtogenixBackground(
        child: SafeArea(
          child: asyncTracks.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: Colors.white24),
            ),
            error: (e, _) => Center(
              child: Text(
                'Ошибка загрузки',
                style: const TextStyle(color: Colors.white54),
              ),
            ),
            data: (tracks) =>
                _PlaylistContent(playlist: playlist, tracks: tracks),
          ),
        ),
      ),
    );
  }
}

class _PlaylistContent extends ConsumerWidget {
  const _PlaylistContent({required this.playlist, required this.tracks});

  final Playlist playlist;
  final List<LibraryTrack> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomScrollView(
      slivers: [
        // Заголовок
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white70,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    playlist.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                Text(
                  '${tracks.length} треков',
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ],
            ),
          ),
        ),

        // Кнопка "Играть всё"
        if (tracks.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: GestureDetector(
                onTap: () {
                  final models = tracks.map((t) => t.toTrackModel()).toList();
                  ref.read(playerProvider.notifier).loadPlaylist(models);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white.withAlpha(18),
                    border: Border.all(color: Colors.white.withAlpha(30)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Слушать всё',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Треки
        if (tracks.isEmpty)
          const SliverFillRemaining(
            child: Center(
              child: Text(
                'Плейлист пуст',
                style: TextStyle(color: Colors.white38, fontSize: 15),
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _PlaylistTrackTile(
                track: tracks[i],
                index: i,
                allTracks: tracks,
                playlistId: playlist.id,
              ),
              childCount: tracks.length,
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }
}

class _PlaylistTrackTile extends ConsumerWidget {
  const _PlaylistTrackTile({
    required this.track,
    required this.index,
    required this.allTracks,
    required this.playlistId,
  });

  final LibraryTrack track;
  final int index;
  final List<LibraryTrack> allTracks;
  final String playlistId;

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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Text(
              '${index + 1}',
              style: TextStyle(
                color: isPlaying ? Colors.white : Colors.white24,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(width: 14),

            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image(
                image: track.coverPath != null
                    ? FileImage(File(track.coverPath!)) as ImageProvider
                    : const AssetImage('assets/images/mock_cover.jpg'),
                width: 44,
                height: 44,
                fit: BoxFit.cover,
              ),
            ),

            const SizedBox(width: 12),

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
                      fontSize: 14,
                      fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),

            // Меню: убрать из плейлиста + другие действия
            IconButton(
              icon: const Icon(Icons.more_vert_rounded),
              color: Colors.white38,
              iconSize: 20,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () =>
                  _showPlaylistTrackOptions(context, ref, track, playlistId),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Меню трека внутри плейлиста ───────────────────────────────────────────────

void _showPlaylistTrackOptions(
  BuildContext context,
  WidgetRef ref,
  LibraryTrack track,
  String playlistId,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => UncontrolledProviderScope(
      container: ProviderScope.containerOf(context),
      child: _PlaylistTrackOptionsSheet(track: track, playlistId: playlistId),
    ),
  );
}

class _PlaylistTrackOptionsSheet extends ConsumerWidget {
  const _PlaylistTrackOptionsSheet({
    required this.track,
    required this.playlistId,
  });

  final LibraryTrack track;
  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0E0E1C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Заголовок
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Divider(color: Colors.white.withAlpha(20), height: 1),
            const SizedBox(height: 8),

            // Убрать из плейлиста
            _OptionTile(
              icon: Icons.remove_circle_outline_rounded,
              iconColor: Colors.orangeAccent,
              label: 'Убрать из плейлиста',
              onTap: () async {
                Navigator.of(context).pop();
                await PlaylistDatabase.instance.removeTrackFromPlaylist(
                  playlistId: playlistId,
                  trackId: track.id,
                );
                // Инвалидируем кэш FutureProvider для этого плейлиста
                ref.invalidate(playlistTracksProvider(playlistId));
              },
            ),

            // Другие действия (открывает общее меню трека)
            _OptionTile(
              icon: Icons.more_horiz_rounded,
              label: 'Другие действия',
              onTap: () {
                Navigator.of(context).pop();
                showTrackContextMenu(context, ref, track);
              },
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? Colors.white70, size: 22),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
