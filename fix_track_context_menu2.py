import re

with open('lib/features/library/presentation/widgets/track_context_menu.dart', 'r') as f:
    content = f.read()

# Fix showCreatePlaylistSheet call. It expects (BuildContext context, WidgetRef ref, {String? initialName, String? playlistId})
# Since we are in a widget without WidgetRef (actually _AddToPlaylistSheet is a ConsumerWidget, so we have ref!), let's just pass ref!
# Wait, let's see _AddToPlaylistSheet signature:
# class _AddToPlaylistSheet extends ConsumerWidget { ... build(BuildContext context, WidgetRef ref) { ... } }
# It has `ref`. But in the replacement we wrote: showCreatePlaylistSheet(context, container.read(playlistsProvider.notifier), track.id) which is wrong.

replace_old = """                  onTap: () {
                    Navigator.of(context).pop();
                    showCreatePlaylistSheet(context, container.read(playlistsProvider.notifier), track.id);
                  },"""

replace_new = """                  onTap: () {
                    Navigator.of(context).pop();
                    showCreatePlaylistSheet(context, ref).then((_) {
                      // Note: We can't easily wait for it if showCreatePlaylistSheet doesn't return the new playlist.
                      // The new playlist is created via ref.read(playlistsProvider.notifier).create(name).
                    });
                  },"""

content = content.replace(replace_old, replace_new)

with open('lib/features/library/presentation/widgets/track_context_menu.dart', 'w') as f:
    f.write(content)
