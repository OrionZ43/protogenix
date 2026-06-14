import re

with open('lib/features/library/presentation/screens/playlists_screen.dart', 'r') as f:
    content = f.read()

# Fix const constructor where it has `widget.playlist.id` which is not constant
content = content.replace(
    "child: const FractionallySizedBox(\n                              heightFactor: 0.8,\n                              child: _AddTrackToPlaylistSheet(\n                                playlistId: widget.playlist.id,",
    "child: FractionallySizedBox(\n                              heightFactor: 0.8,\n                              child: _AddTrackToPlaylistSheet(\n                                playlistId: widget.playlist.id,"
)

# And fix line 890 missing const
content = content.replace("physics: NeverScrollableScrollPhysics(),", "physics: const NeverScrollableScrollPhysics(),")

with open('lib/features/library/presentation/screens/playlists_screen.dart', 'w') as f:
    f.write(content)
