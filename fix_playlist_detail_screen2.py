import re

with open('lib/features/library/presentation/screens/playlists_screen.dart', 'r') as f:
    content = f.read()

# Replace the TODO comment inside the "Add track" ActionButton
add_track_old = """                  Expanded(
                    child: _ActionButton(
                      icon: Icons.add_rounded,
                      label: 'Добавить',
                      onTap: () {
                        // TODO: Implement open library sheet
                      },
                    ),
                  ),"""

add_track_new = """                  Expanded(
                    child: _ActionButton(
                      icon: Icons.add_rounded,
                      label: 'Добавить',
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          barrierColor: Colors.black.withValues(alpha: 0.5),
                          builder: (ctx) => UncontrolledProviderScope(
                            container: ProviderScope.containerOf(context),
                            child: FractionallySizedBox(
                              heightFactor: 0.8,
                              child: _AddTrackToPlaylistSheet(
                                playlistId: widget.playlist.id,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),"""

content = content.replace(add_track_old, add_track_new)

with open('lib/features/library/presentation/screens/playlists_screen.dart', 'w') as f:
    f.write(content)
