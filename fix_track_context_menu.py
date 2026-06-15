import re

with open('lib/features/library/presentation/widgets/track_context_menu.dart', 'r') as f:
    content = f.read()

if "import '../screens/playlists_screen.dart';" not in content:
    content = "import '../screens/playlists_screen.dart';\n" + content

if "import '../playlist_provider.dart';" not in content:
    content = "import '../playlist_provider.dart';\n" + content

# Replace _promptPlaylistName with _CreatePlaylistSheet wrapper
create_playlist_old = """                // Создать новый
                _MenuItem(
                  icon: Icons.add_circle_outline_rounded,
                  label: 'Создать новый плейлист',
                  onTap: () async {
                    Navigator.of(context).pop();
                    final name = await _promptPlaylistName(context);
                    if (name != null && name.isNotEmpty) {
                      final pl =
                          await container.read(playlistsProvider.notifier).create(name);
                      await PlaylistDatabase.instance.addTrackToPlaylist(
                        playlistId: pl.id,
                        trackId: track.id,
                      );
                    }
                  },
                ),"""

create_playlist_new = """                // Создать новый
                _MenuItem(
                  icon: Icons.add_circle_outline_rounded,
                  label: 'Создать новый плейлист',
                  onTap: () {
                    Navigator.of(context).pop();
                    showCreatePlaylistSheet(context, container.read(playlistsProvider.notifier), track.id);
                  },
                ),"""

content = content.replace(create_playlist_old, create_playlist_new)


# Fix the prompt function entirely since it is removed (or leave it out)
# Remove _promptPlaylistName function
prompt_func = re.compile(r'// ── Диалог имени плейлиста ────────────────────────────────────────────────────.*?// ── Подтверждение удаления', re.DOTALL)
content = prompt_func.sub('// ── Подтверждение удаления', content)

# Update cache invalidation inside the playlist mapping inside _AddToPlaylistSheet
add_to_existing_old = """                  onTap: () async {
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
                  },"""

add_to_existing_new = """                  onTap: () async {
                    await PlaylistDatabase.instance.addTrackToPlaylist(
                      playlistId: pl.id,
                      trackId: track.id,
                    );

                    container.invalidate(playlistTracksProvider(pl.id));
                    final notifier = container.read(playlistTracksNotifierProvider(pl.id).notifier);
                    notifier.add(track.id);

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
                  },"""

content = content.replace(add_to_existing_old, add_to_existing_new)

with open('lib/features/library/presentation/widgets/track_context_menu.dart', 'w') as f:
    f.write(content)
