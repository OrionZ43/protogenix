import re

# 1. We should just replace the _PlaylistsTab in library_screen.dart to use PlaylistsScreen directly.
# Wait, PlaylistsScreen is a Scaffold with ProtogenixBackground.
# library_screen.dart ALSO has a Scaffold with ProtogenixBackground.
# If we put PlaylistsScreen inside a TabBarView, it will be nested Scaffolds.
# But flutter allows nested scaffolds! Let's just do it.

with open('lib/features/library/presentation/screens/library_screen.dart', 'r') as f:
    lib_content = f.read()

if "import 'playlists_screen.dart';" not in lib_content:
    lib_content = lib_content.replace(
        "import '../widgets/track_context_menu.dart';",
        "import '../widgets/track_context_menu.dart';\nimport 'playlists_screen.dart';"
    )

lib_content = lib_content.replace('_PlaylistsTab(),', 'PlaylistsScreen(),')

# we also need to delete all the _PlaylistCard, _createPlaylistDialog, _renameDialog, _GlassDialog from library_screen.dart
# To do this safely:
start_idx = lib_content.find('class _PlaylistsTab extends ConsumerWidget {')
end_idx = lib_content.find('class _FavoritesTab extends ConsumerWidget {')
lib_content = lib_content[:start_idx] + lib_content[end_idx:]

start_idx2 = lib_content.find('class _EmptyPlaylists extends StatelessWidget {')
end_idx2 = lib_content.find('// ── Player Content')
if end_idx2 == -1:
    end_idx2 = lib_content.find('class PlaylistDetailScreen')
if end_idx2 == -1:
    end_idx2 = len(lib_content) # just cut to the end if we can't find it, wait, we might cut important things
# Actually, the quickest and safest way to replace them is just replace _PlaylistsTab in TabBarView

with open('lib/features/library/presentation/screens/library_screen.dart', 'w') as f:
    f.write(lib_content)
