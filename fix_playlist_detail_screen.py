import re

with open('lib/features/library/presentation/screens/playlists_screen.dart', 'r') as f:
    content = f.read()

# Replace the Action Buttons row
action_buttons_old = """                  Expanded(
                    child: _ActionButton(
                      icon: Icons.play_arrow_rounded,
                      label: 'Слушать',
                      onTap: () {
                        ref.read(playerProvider.notifier).loadPlaylist(
                              tracks.map((t) => t.toTrackModel()).toList(),
                            );
                        ref.read(playerProvider.notifier).play();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.shuffle_rounded,
                      label: 'Перемешать',
                      onTap: () {
                        final shuffled = List.of(tracks)..shuffle();
                        ref.read(playerProvider.notifier).loadPlaylist(
                              shuffled.map((t) => t.toTrackModel()).toList(),
                            );
                        ref.read(playerProvider.notifier).play();
                      },
                    ),
                  ),"""

action_buttons_new = """                  Expanded(
                    child: _ActionButton(
                      icon: Icons.play_arrow_rounded,
                      label: 'Слушать',
                      onTap: () {
                        ref.read(playerProvider.notifier).loadPlaylist(
                              tracks.map((t) => t.toTrackModel()).toList(),
                            );
                        ref.read(playerProvider.notifier).play();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.shuffle_rounded,
                      label: 'Перемешать',
                      onTap: () {
                        final shuffled = List.of(tracks)..shuffle();
                        ref.read(playerProvider.notifier).loadPlaylist(
                              shuffled.map((t) => t.toTrackModel()).toList(),
                            );
                        ref.read(playerProvider.notifier).play();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.add_rounded,
                      label: 'Добавить',
                      onTap: () {
                        // TODO: Implement open library sheet
                      },
                    ),
                  ),"""

content = content.replace(action_buttons_old, action_buttons_new)

# Replace the Reorder text with a glass capsule
reorder_text_old = """                  GestureDetector(
                    onTap: () => setState(() => _isReordering = !_isReordering),
                    child: Text(
                      _isReordering ? 'Готово' : 'Изменить порядок',
                      style: const TextStyle(
                        color: AppColors.neonPurple,
                        fontSize: 13,
                      ),
                    ),
                  ),"""

reorder_text_new = """                  GestureDetector(
                    onTap: () => setState(() => _isReordering = !_isReordering),
                    child: GlassCard(
                      borderRadius: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Text(
                        _isReordering ? 'Готово' : 'Изменить порядок',
                        style: const TextStyle(
                          color: AppColors.neonPurple,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),"""

content = content.replace(reorder_text_old, reorder_text_new)

with open('lib/features/library/presentation/screens/playlists_screen.dart', 'w') as f:
    f.write(content)
