import re

with open('lib/features/library/presentation/screens/library_screen.dart', 'r') as f:
    content = f.read()

# Let's fix the broken PlaylistCard stuff in library_screen.dart
# The script replaced _PlaylistCard with PlaylistCard but messed up the syntax
content = content.replace("class _PlaylistCard extends ConsumerStatefulWidget {\n  const PlaylistCard({", "class _PlaylistCard extends ConsumerStatefulWidget {\n  const _PlaylistCard({")
with open('lib/features/library/presentation/screens/library_screen.dart', 'w') as f:
    f.write(content)
