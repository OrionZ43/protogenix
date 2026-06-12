import re

with open('lib/features/library/presentation/screens/library_screen.dart', 'r') as f:
    content = f.read()

# Make sure we import playlists_screen.dart
if "import 'playlists_screen.dart';" not in content:
    content = content.replace(
        "import '../widgets/track_context_menu.dart';",
        "import '../widgets/track_context_menu.dart';\nimport 'playlists_screen.dart';"
    )

content = content.replace('_PlaylistsTab(),', 'PlaylistsScreen(),')

# Find start of _PlaylistsTab
start = content.find('class _PlaylistsTab extends ConsumerWidget {')
end = content.find('class _FavoritesTab extends ConsumerWidget {')
if start != -1 and end != -1:
    content = content[:start] + content[end:]

# Find start of _EmptyPlaylists
start2 = content.find('class _EmptyPlaylists extends StatelessWidget {')
end2 = content.find('// ── Кнопка играть всё ─────────────────────────────────────────────────────────')
if start2 != -1 and end2 != -1:
    content = content[:start2] + content[end2:]

# Find start of _createPlaylistDialog
start3 = content.find('Future<void> _createPlaylistDialog(')
end3 = content.find('class _GlassDialog extends StatelessWidget {')
if start3 != -1 and end3 != -1:
    content = content[:start3] + content[end3:]

# Find start of _GlassDialog
start4 = content.find('class _GlassDialog extends StatelessWidget {')
end4 = len(content)
if start4 != -1:
    content = content[:start4]

with open('lib/features/library/presentation/screens/library_screen.dart', 'w') as f:
    f.write(content)
