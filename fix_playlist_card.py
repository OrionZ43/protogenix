import re

with open('lib/features/library/presentation/screens/playlists_screen.dart', 'r') as f:
    content = f.read()

new_card = """class PlaylistCard extends ConsumerWidget {
  const PlaylistCard({
    super.key,
    required this.playlist,
    required this.onTap,
    required this.onDelete,
    required this.onRename,
  });

  final Playlist playlist;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistAsync = ref.watch(playlistTracksProvider(playlist.id));
    final tracks = playlistAsync.valueOrNull ?? [];

    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        borderRadius: 20,
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 16),
                _PlaylistCoverCollage(
                  tracks: tracks,
                  diameter: 100,
                  animate: true,
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${tracks.length} треков',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_rounded, color: Colors.white38, size: 16),
                    onPressed: onRename,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 16),
                    onPressed: onDelete,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}"""

start_idx = content.find('class PlaylistCard extends ConsumerWidget {')
end_idx = content.find('// ── Create/Rename Playlist Sheet')
if start_idx != -1 and end_idx != -1:
    content = content[:start_idx] + new_card + '\n\n' + content[end_idx:]
    with open('lib/features/library/presentation/screens/playlists_screen.dart', 'w') as f:
        f.write(content)
