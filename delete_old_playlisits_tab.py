import re

with open('lib/features/library/presentation/screens/library_screen.dart', 'r') as f:
    content = f.read()

# Replace _PlaylistsTab() inside TabBarView with PlaylistsScreen()
content = content.replace('_PlaylistsTab(),', 'PlaylistsScreen(),')

# Delete everything after _FavoritesTab because we want to remove the old _PlaylistCard, _createPlaylistDialog, etc.
# We will do this carefully.
import io
lines = io.StringIO(content).readlines()

new_lines = []
in_playlists_tab = False
in_old_widgets = False

for line in lines:
    if line.startswith('class _PlaylistsTab extends'):
        in_playlists_tab = True
    elif in_playlists_tab and line.startswith('class _FavoritesTab extends'):
        in_playlists_tab = False

    if line.startswith('class _PlaylistCard extends ConsumerStatefulWidget'):
        in_old_widgets = True

    if not in_playlists_tab and not in_old_widgets:
        new_lines.append(line)

with open('lib/features/library/presentation/screens/library_screen.dart', 'w') as f:
    f.writelines(new_lines)
