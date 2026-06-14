import re

with open('lib/features/library/presentation/screens/playlists_screen.dart', 'r') as f:
    content = f.read()

# Fix imports in playlists_screen.dart
if "import '../../data/library_database.dart';" not in content:
    content = "import '../../data/library_database.dart';\n" + content

# Fix const constructor
content = content.replace("child: FractionallySizedBox(", "child: const FractionallySizedBox(")

with open('lib/features/library/presentation/screens/playlists_screen.dart', 'w') as f:
    f.write(content)
