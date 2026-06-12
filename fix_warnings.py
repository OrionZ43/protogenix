import re

with open('lib/features/library/presentation/screens/library_screen.dart', 'r') as f:
    content = f.read()

# remove _EmptyPlaylists
start_idx = content.find('class _EmptyPlaylists extends StatelessWidget {')
end_idx = content.find('// ── Track tile')
if start_idx != -1 and end_idx != -1:
    content = content[:start_idx] + content[end_idx:]

# remove _createPlaylistDialog
start_idx2 = content.find('Future<void> _createPlaylistDialog(BuildContext context, WidgetRef ref) {')
end_idx2 = content.find('// ── Переименование плейлиста')
if start_idx2 != -1 and end_idx2 != -1:
    content = content[:start_idx2] + content[end_idx2:]

# remove _renameDialog
start_idx3 = content.find('Future<void> _renameDialog(')
end_idx3 = content.find('class _GlassDialog extends StatelessWidget {')
if start_idx3 != -1 and end_idx3 != -1:
    content = content[:start_idx3] + content[end_idx3:]

# remove _GlassDialog
start_idx4 = content.find('class _GlassDialog extends StatelessWidget {')
end_idx4 = len(content) # Assuming this is at the end of the file
if start_idx4 != -1:
    content = content[:start_idx4]

with open('lib/features/library/presentation/screens/library_screen.dart', 'w') as f:
    f.write(content)
