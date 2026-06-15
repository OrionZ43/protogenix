import re

with open('lib/features/library/presentation/screens/library_screen.dart', 'r') as f:
    content = f.read()

content = content.replace("import 'dart:ui';\n", "")
content = content.replace("import 'package:flutter/services.dart';\n", "")
content = content.replace("import '../../data/playlist_database.dart';\n", "")

with open('lib/features/library/presentation/screens/library_screen.dart', 'w') as f:
    f.write(content)

with open('lib/features/library/presentation/screens/playlists_screen.dart', 'r') as f:
    content = f.read()
content = content.replace("physics: NeverScrollableScrollPhysics(),", "physics: const NeverScrollableScrollPhysics(),")
with open('lib/features/library/presentation/screens/playlists_screen.dart', 'w') as f:
    f.write(content)
