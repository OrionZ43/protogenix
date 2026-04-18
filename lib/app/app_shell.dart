// lib/app/app_shell.dart
//
// Главный навигационный каркас приложения.
//
// Compact (телефон):
//   BottomNavigationBar  ← вкладки
//   MiniPlayer           ← плавает над BottomBar
//   Свайп/тап мини-плеера → PlayerScreen как fullscreen modal
//
// Expanded (планшет / Fold):
//   NavigationRail слева + контент справа
//   MiniPlayer встроен в нижнюю часть Rail
//   Тап мини-плеера → ExpandedPlayerScreen через Navigator.push (НЕ modal)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/fold_layout.dart';
import '../features/library/presentation/screens/library_screen.dart';
import '../features/library/presentation/screens/playlists_screen.dart';
import '../features/library/presentation/screens/favorites_screen.dart';
import '../features/player/presentation/widgets/mini_player.dart';
import '../features/player/presentation/screens/player_screen.dart';
import '../features/player/presentation/screens/expanded_player_screen.dart';
import '../features/player/presentation/providers/player_provider.dart';

// ── Провайдер текущей вкладки ─────────────────────────────────────────────────

final _tabIndexProvider = StateProvider<int>((ref) => 0);

// ── Экраны вкладок ────────────────────────────────────────────────────────────

const _tabs = [
  _TabItem(icon: Icons.library_music_outlined,  activeIcon: Icons.library_music_rounded,  label: 'Треки'),
  _TabItem(icon: Icons.queue_music_outlined,     activeIcon: Icons.queue_music_rounded,    label: 'Плейлисты'),
  _TabItem(icon: Icons.favorite_outline_rounded, activeIcon: Icons.favorite_rounded,       label: 'Избранное'),
];

final _screens = <Widget>[
  LibraryScreen(),
  const PlaylistsScreen(),
  const FavoritesScreen(),
];

// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC
// ─────────────────────────────────────────────────────────────────────────────

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FoldLayout(
      compactBuilder:  (ctx, _) => const _CompactShell(),
      expandedBuilder: (ctx, _) => const _ExpandedShell(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMPACT — телефон
// ─────────────────────────────────────────────────────────────────────────────

class _CompactShell extends ConsumerWidget {
  const _CompactShell();

  /// Компактный плеер открывается как fullscreen modal снизу.
  void _openPlayer(BuildContext context) {
    showModalBottomSheet(
      context:            context,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      useSafeArea:        false,
      builder: (_) => const _FullPlayerSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabIndex = ref.watch(_tabIndexProvider);
    final hasTrack = ref.watch(
      playerProvider.select((s) => s.currentTrack != null),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      body: IndexedStack(
        index: tabIndex,
        children: _screens,
      ),

      // MiniPlayer + BottomNavigationBar в одной колонке
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Мини-плеер (виден только если есть трек)
          if (hasTrack)
            GestureDetector(
              onTap: () => _openPlayer(context),
              onVerticalDragEnd: (d) {
                if (d.primaryVelocity != null && d.primaryVelocity! < -200) {
                  _openPlayer(context);
                }
              },
              child: MiniPlayer(onTap: () => _openPlayer(context)),
            ),

          // Нижняя навигация
          _BottomBar(
            currentIndex: tabIndex,
            onTap: (i) => ref.read(_tabIndexProvider.notifier).state = i,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EXPANDED — планшет / Fold
// ─────────────────────────────────────────────────────────────────────────────

class _ExpandedShell extends ConsumerWidget {
  const _ExpandedShell();

  /// Широкий плеер открывается как обычный экран (push),
  /// а не modal — чтобы занять всю ширину Fold без чёрных полей.
  void _openPlayer(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => const ExpandedPlayerScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve:  Curves.easeInOutCubic,
            ),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end:   Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve:  Curves.easeOutCubic,
              )),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabIndex = ref.watch(_tabIndexProvider);
    final hasTrack = ref.watch(
      playerProvider.select((s) => s.currentTrack != null),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      body: Row(
        children: [
          // ── NavigationRail слева ──────────────────────────────────────────
          Container(
            width:       72,
            color:       Colors.white.withAlpha(6),
            child: Column(
              children: [
                const SizedBox(height: 24),

                // Лого
                const Text(
                  'PX',
                  style: TextStyle(
                    color:         Colors.white54,
                    fontSize:      13,
                    fontWeight:    FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),

                const SizedBox(height: 32),

                // Иконки вкладок
                ...List.generate(_tabs.length, (i) {
                  final selected = tabIndex == i;
                  return _RailIcon(
                    tab:      _tabs[i],
                    selected: selected,
                    onTap: () =>
                        ref.read(_tabIndexProvider.notifier).state = i,
                  );
                }),

                const Spacer(),

                // Мини-плеер встроен снизу Rail — тап → ExpandedPlayerScreen
                if (hasTrack)
                  GestureDetector(
                    onTap: () => _openPlayer(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 12),
                      child: Container(
                        width:  52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withAlpha(15),
                          border: Border.all(
                              color: Colors.white.withAlpha(30)),
                        ),
                        child: const Icon(
                          Icons.music_note_rounded,
                          color: Colors.white70,
                          size:  22,
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 16),
              ],
            ),
          ),

          // Разделитель
          Container(width: 1, color: Colors.white.withAlpha(12)),

          // ── Контент справа ────────────────────────────────────────────────
          Expanded(
            child: IndexedStack(
              index: tabIndex,
              children: _screens,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM BAR
// ─────────────────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.currentIndex, required this.onTap});
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:  const Color(0xFF0D0D1A),
        border: Border(top: BorderSide(color: Colors.white.withAlpha(18))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: List.generate(_tabs.length, (i) {
              final selected = currentIndex == i;
              final tab      = _tabs[i];
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          selected ? tab.activeIcon : tab.icon,
                          color: selected
                              ? Colors.white
                              : Colors.white38,
                          size: 22,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          tab.label,
                          style: TextStyle(
                            fontSize:   10,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: selected
                                ? Colors.white
                                : Colors.white38,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RAIL ICON
// ─────────────────────────────────────────────────────────────────────────────

class _RailIcon extends StatelessWidget {
  const _RailIcon({
    required this.tab,
    required this.selected,
    required this.onTap,
  });
  final _TabItem tab;
  final bool     selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration:   const Duration(milliseconds: 200),
        width:      double.infinity,
        padding:    const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: selected
              ? const Border(
                  left: BorderSide(
                    color: Colors.white,
                    width: 2,
                  ),
                )
              : null,
        ),
        child: Icon(
          selected ? tab.activeIcon : tab.icon,
          color: selected ? Colors.white : Colors.white38,
          size:  22,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FULL PLAYER SHEET — только для compact, 100% высоты modal
// ─────────────────────────────────────────────────────────────────────────────

class _FullPlayerSheet extends StatelessWidget {
  const _FullPlayerSheet();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height,
      child: Stack(
        children: [
          const PlayerScreen(),

          // Кнопка "вниз"
          Positioned(
            top:  MediaQuery.of(context).padding.top + 8,
            left: 16,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width:  36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha(18),
                ),
                child: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white70,
                  size:  24,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA
// ─────────────────────────────────────────────────────────────────────────────

class _TabItem {
  const _TabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
  final IconData icon;
  final IconData activeIcon;
  final String   label;
}
