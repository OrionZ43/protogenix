import re

with open('lib/features/library/presentation/screens/playlists_screen.dart', 'r') as f:
    content = f.read()

content = content.replace('class _PlaylistCard extends ConsumerWidget', 'class PlaylistCard extends ConsumerWidget')
content = content.replace('const _PlaylistCard({', 'const PlaylistCard({')
content = content.replace('_PlaylistCard(', 'PlaylistCard(')

content = content.replace('Future<void> _showCreatePlaylistSheet(', 'Future<void> showCreatePlaylistSheet(')
content = content.replace('_showCreatePlaylistSheet(', 'showCreatePlaylistSheet(')

with open('lib/features/library/presentation/screens/playlists_screen.dart', 'w') as f:
    f.write(content)
