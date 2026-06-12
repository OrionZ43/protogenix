import re

with open('lib/features/library/presentation/screens/library_screen.dart', 'r') as f:
    lib_content = f.read()

if "import 'playlists_screen.dart';" not in lib_content:
    lib_content = lib_content.replace(
        "import '../widgets/track_context_menu.dart';",
        "import '../widgets/track_context_menu.dart';\nimport 'playlists_screen.dart';"
    )

lib_content = lib_content.replace('_PlaylistsTab(),', 'PlaylistsScreen(),')

# we also need to delete all the _PlaylistCard, _createPlaylistDialog, _renameDialog, _GlassDialog from library_screen.dart
start_idx = lib_content.find('class _PlaylistsTab extends ConsumerWidget {')
end_idx = lib_content.find('class _FavoritesTab extends ConsumerWidget {')
lib_content = lib_content[:start_idx] + lib_content[end_idx:]

start_idx2 = lib_content.find('class _EmptyPlaylists extends StatelessWidget {')
end_idx2 = lib_content.find('class _PlaylistCard extends ConsumerStatefulWidget {')

# Find exactly where _PlaylistCard ends and the next component (e.g. track tiles or something) starts.
# Wait, _PlaylistCard is the old one. We want to remove _EmptyPlaylists and _PlaylistCard and _createPlaylistDialog
# Let's just find and replace them with empty strings using regex.
import io

lines = io.StringIO(lib_content).readlines()

new_lines = []
skip = False

for line in lines:
    if line.startswith('class _EmptyPlaylists extends StatelessWidget {'):
        skip = True
    elif line.startswith('class _PlaylistCard extends ConsumerStatefulWidget {'):
        skip = True
    elif line.startswith('Future<void> _createPlaylistDialog('):
        skip = True
    elif line.startswith('Future<void> _renameDialog('):
        skip = True
    elif line.startswith('class _GlassDialog extends StatelessWidget {'):
        skip = True

    # How to know when to stop skipping?
    if skip and line.startswith('// ── '):
        if 'Track tile' in line or 'Player Content' in line or 'Кнопка играть всё' in line or 'Empty state' in line or 'Переименование плейлиста' in line:
            if 'Переименование плейлиста' in line:
                pass
            else:
                skip = False

    if skip and line.startswith('class '):
        if '_PlaylistTrackTile' in line or 'PlaylistDetailScreen' in line:
            pass # Keep skipping if it's playlist specific
        if '_FavoritesTab' in line or 'LibraryScreen' in line:
            skip = False

    if skip and line.startswith('// ── Player Content'):
         skip = False

    # Let's just do it manually by finding indices.
