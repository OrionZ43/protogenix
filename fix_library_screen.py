import re

with open('lib/features/library/presentation/screens/library_screen.dart', 'r') as f:
    content = f.read()

# Replace sorting icon button
sort_btn_old = """                  GestureDetector(
                    onTap: () => _showSortSheet(context, ref),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withAlpha(0),
                      ),
                      child: Icon(
                        Icons.sort_rounded,
                        size: 20,
                        color: sortMode != LibrarySortMode.dateAdded
                            ? palette.primary
                            : Colors.white24,
                      ),
                    ),
                  ),"""

sort_btn_new = """                  GestureDetector(
                    onTap: () => _showSortSheet(context, ref),
                    child: GlassCard(
                      borderRadius: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.sort_rounded,
                            size: 16,
                            color: sortMode != LibrarySortMode.dateAdded
                                ? palette.primary
                                : Colors.white54,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Сортировка',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: sortMode != LibrarySortMode.dateAdded
                                  ? palette.primary
                                  : Colors.white54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),"""

content = content.replace(sort_btn_old, sort_btn_new)

with open('lib/features/library/presentation/screens/library_screen.dart', 'w') as f:
    f.write(content)
