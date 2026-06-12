import re

with open('lib/features/library/presentation/screens/library_screen.dart', 'r') as f:
    content = f.read()

# Make sure we import playlists_screen.dart
if "import 'playlists_screen.dart';" not in content:
    content = content.replace(
        "import '../widgets/track_context_menu.dart';",
        "import '../widgets/track_context_menu.dart';\nimport 'playlists_screen.dart';"
    )

# Instead of modifying the massive library_screen.dart piece by piece and risking syntax errors,
# let's just make the _PlaylistsTab widget return PlaylistsScreen directly.
# Wait, PlaylistsScreen is a Scaffold. TabBarView children should ideally not be Scaffolds (though they can be).
# Actually, the user's issue is that the text "PROTOGENIX" overflowed!
