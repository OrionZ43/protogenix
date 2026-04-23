// lib/features/library/presentation/widgets/track_context_menu.dart
//
// Контекстное меню трека (BottomSheet).
// Действия: избранное, добавить в плейлист, найти текст, удалить.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/library_track.dart';
import '../../data/playlist_database.dart';
import '../library_provider.dart';
import '../playlist_provider.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../../player/presentation/widgets/lyrics_search_sheet.dart';

// ── Точка входа ───────────────────────────────────────────────────────────────

void showTrackContextMenu(
  BuildContext context,
  WidgetRef ref,
  LibraryTrack track,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => UncontrolledProviderScope(
      container: ProviderScope.containerOf(context),
      child: _TrackContextMenu(track: track),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _TrackContextMenu extends ConsumerWidget {
  const _TrackContextMenu({required this.track});
  final LibraryTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = ref.watch(isFavoriteProvider(track.id));

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
            // Ручка
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Заголовок — обложка + название
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image(
                      image: track.coverPath != null
                          ? FileImage(File(track.coverPath!)) as ImageProvider
                          : const AssetImage('assets/images/mock_cover.jpg'),
                      width: 48,
                      height: 48,
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
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Divider(color: Colors.white.withAlpha(20), height: 1),
            const SizedBox(height: 8),

            // ── Действия ──────────────────────────────────────────────────────

            // Избранное
            _MenuItem(
              icon: isFav
                  ? Icons.favorite_rounded
                  : Icons.favorite_outline_rounded,
              iconColor: isFav ? Colors.redAccent : Colors.white70,
              label: isFav ? 'Убрать из избранного' : 'В избранное',
              onTap: () {
                ref.read(favoritesProvider.notifier).toggle(track.id);
                Navigator.of(context).pop();
              },
            ),

            // Добавить в плейлист
            _MenuItem(
              icon: Icons.playlist_add_rounded,
              label: 'Добавить в плейлист',
              onTap: () {
                Navigator.of(context).pop();
                _showAddToPlaylistSheet(context, ref, track);
              },
            ),

            // Найти текст
            _MenuItem(
              icon: Icons.manage_search_rounded,
              label: 'Найти текст вручную',
              onTap: () {
                Navigator.of(context).pop();
                showLyricsSearchSheet(context, ref, track.toTrackModel());
              },
            ),

            // Удалить трек
            _MenuItem(
              icon: Icons.delete_outline_rounded,
              iconColor: Colors.redAccent,
              label: 'Удалить трек',
              labelColor: Colors.redAccent,
              onTap: () {
                Navigator.of(context).pop();
                _confirmDelete(context, ref, track);
              },
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// ── Добавить в плейлист ───────────────────────────────────────────────────────

void _showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  LibraryTrack track,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => UncontrolledProviderScope(
      container: ProviderScope.containerOf(context),
      child: _AddToPlaylistSheet(track: track),
    ),
  );
}

class _AddToPlaylistSheet extends ConsumerWidget {
  const _AddToPlaylistSheet({required this.track});
  final LibraryTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);

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
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Добавить в плейлист',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            // Создать новый
            _MenuItem(
              icon: Icons.add_circle_outline_rounded,
              label: 'Создать новый плейлист',
              onTap: () async {
                Navigator.of(context).pop();
                final name = await _promptPlaylistName(context);
                if (name != null && name.isNotEmpty) {
                  final pl =
                      await ref.read(playlistsProvider.notifier).create(name);
                  await PlaylistDatabase.instance.addTrackToPlaylist(
                    playlistId: pl.id,
                    trackId: track.id,
                  );
                }
              },
            ),

            if (playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Нет плейлистов',
                  style: TextStyle(color: Colors.white38, fontSize: 14),
                ),
              )
            else
              ...playlists.map(
                (pl) => _MenuItem(
                  icon: Icons.queue_music_rounded,
                  label: pl.name,
                  onTap: () async {
                    await PlaylistDatabase.instance.addTrackToPlaylist(
                      playlistId: pl.id,
                      trackId: track.id,
                    );
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Добавлено в «${pl.name}»'),
                          backgroundColor: const Color(0xFF1A1A2E),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// ── Диалог имени плейлиста ────────────────────────────────────────────────────

Future<String?> _promptPlaylistName(BuildContext context) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF13131F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Новый плейлист',
        style: TextStyle(color: Colors.white, fontSize: 17),
      ),
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
          child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
          child: const Text('Создать', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

// ── Подтверждение удаления — удаляет из БД + с диска ─────────────────────────

void _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  LibraryTrack track,
) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF13131F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Удалить трек?',
        style: TextStyle(color: Colors.white, fontSize: 17),
      ),
      content: Text(
        '«${track.title}» будет удалён из библиотеки и с диска.',
        style: const TextStyle(color: Colors.white54, fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () async {
            Navigator.of(ctx).pop();

            final isCurrentTrack =
                ref.read(playerProvider).currentTrack?.id == track.id;

            // Удаляем из БД + физические файлы с диска
            await ref
                .read(libraryProvider.notifier)
                .removeTrackWithFiles(track);

            // Если удалённый трек сейчас играл — перезагружаем плеер
            if (isCurrentTrack) {
              await ref.read(playerProvider.notifier).reloadFromLibrary();
            }
          },
          child:
              const Text('Удалить', style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    ),
  );
}

// ── Вспомогательный виджет пункта меню ───────────────────────────────────────

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.labelColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? labelColor;

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
              style: TextStyle(
                color: labelColor ?? Colors.white,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
