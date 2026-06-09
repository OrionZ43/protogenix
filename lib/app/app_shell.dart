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
//
// Desktop (Windows / Linux / macOS):
//   WindowTitleBar поверх любого режима — кнопки закрыть/свернуть/развернуть
//
// ── Исправленные баги ──────────────────────────────────────────────────────
//   Bug 2: Убрана дублирующая кнопка «вниз» из _FullPlayerSheet.
//          Теперь _TopBar в PlayerScreen единолично отвечает за закрытие.
//   Bug 3: useSafeArea: true — контент не заползает под статус-бар.
//   Bug 4: _CompactShell стал StatefulWidget и следит за шириной экрана.
//          При складывании/раскладывании в планшетный режим открытый
//          модальный плеер принудительно закрывается.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/fold_layout.dart';
import '../core/widgets/window_title_bar.dart';
import '../features/library/presentation/screens/info_screen.dart';
import '../features/library/presentation/screens/library_screen.dart';
import '../features/library/presentation/screens/playlists_screen.dart';
import '../features/library/presentation/screens/favorites_screen.dart';
import '../features/player/presentation/widgets/mini_player.dart';
import '../features/player/presentation/screens/player_screen.dart';
import 'package:flutter/services.dart';
import '../core/widgets/z43_branding.dart';
import '../features/player/presentation/screens/expanded_player_screen.dart';
import '../features/player/presentation/providers/player_provider.dart';
import '../features/player/presentation/providers/palette_provider.dart';
import '../features/player/domain/track_model.dart';
import '../features/player/domain/player_state.dart';
import '../features/updater/update_banner.dart';

// ── Провайдер текущей вкладки ─────────────────────────────────────────────────

final _tabIndexProvider = StateProvider<int>((ref) => 0);

// ── Экраны вкладок ────────────────────────────────────────────────────────────

const _tabs = [
  _TabItem(
      icon: Icons.library_music_outlined,
      activeIcon: Icons.library_music_rounded,
      label: 'Треки'),
  _TabItem(
      icon: Icons.queue_music_outlined,
      activeIcon: Icons.queue_music_rounded,
      label: 'Плейлисты'),
  _TabItem(
      icon: Icons.favorite_outline_rounded,
      activeIcon: Icons.favorite_rounded,
      label: 'Избранное'),
  _TabItem(
      icon: Icons.info_outline_rounded,
      activeIcon: Icons.info_rounded,
      label: 'Инфо'),
];

final _screens = <Widget>[
  const LibraryScreen(),
  const PlaylistsScreen(),
  const FavoritesScreen(),
  const InfoScreen(),
];

// ── Хелпер: десктопная платформа? ────────────────────────────────────────────

bool get _isDesktop =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC
// ─────────────────────────────────────────────────────────────────────────────

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shell = FoldLayout(
      compactBuilder: (ctx, _) => const _CompactShell(),
      expandedBuilder: (ctx, _) => const _ExpandedShell(),
    );

    // На десктопе оборачиваем в колонку: тайтлбар + контент
    if (_isDesktop) {
      return const Column(
        children: [
          WindowTitleBar(),
          Expanded(child: _DesktopShell()),
        ],
      );
    }

    return shell;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMPACT — телефон
// ─────────────────────────────────────────────────────────────────────────────

/// Bug 4 fix: StatefulWidget вместо StatelessWidget.
/// didChangeDependencies() отслеживает ширину экрана.
/// При переходе compact→expanded принудительно закрывает модальный плеер.
class _CompactShell extends ConsumerStatefulWidget {
  const _CompactShell();

  @override
  ConsumerState<_CompactShell> createState() => _CompactShellState();
}

class _CompactShellState extends ConsumerState<_CompactShell> {
  // Ширина экрана на прошлом вызове didChangeDependencies
  double _prevWidth = 0.0;

  /// Bug 3 fix: useSafeArea: true — BottomSheet не заползает под статус-бар.
  /// Bug 2 fix: _FullPlayerSheet больше не добавляет Positioned-кнопку «вниз»,
  ///            т.к. PlayerScreen._TopBar теперь сам обрабатывает навигацию.
  void _openPlayer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true, // ← Bug 3: было false
      builder: (_) => const _FullPlayerSheet(),
    );
  }

  /// Bug 4 fix: при разложении телефона в планшетный режим (compact→expanded)
  /// закрываем открытый модальный плеер через addPostFrameCallback.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final width = MediaQuery.sizeOf(context).width;
    if (_prevWidth > 0 &&
        _prevWidth < kFoldBreakpoint &&
        width >= kFoldBreakpoint) {
      // Экран пересёк порог — закрываем модалку в следующем кадре
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
    _prevWidth = width;
  }

  @override
  Widget build(BuildContext context) {
    final tabIndex = ref.watch(_tabIndexProvider);
    final hasTrack = ref.watch(
      playerProvider.select((s) => s.currentTrack != null),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      body: Column(
        children: [
          const UpdateBanner(),
          Expanded(
            child: IndexedStack(
              index: tabIndex,
              children: _screens,
            ),
          ),
        ],
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
              curve: Curves.easeInOutCubic,
            ),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
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
            width: 72,
            color: Colors.white.withAlpha(6),
            child: Column(
              children: [
                const SizedBox(height: 24),

                // Лого (скрыто на десктопе — уже есть в тайтлбаре)
                if (!_isDesktop)
                  const Text(
                    'PX',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),

                if (!_isDesktop) const SizedBox(height: 32),

                // Иконки вкладок
                ...List.generate(_tabs.length, (i) {
                  final selected = tabIndex == i;
                  return _RailIcon(
                    tab: _tabs[i],
                    selected: selected,
                    onTap: () => ref.read(_tabIndexProvider.notifier).state = i,
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
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withAlpha(15),
                          border: Border.all(color: Colors.white.withAlpha(30)),
                        ),
                        child: const Icon(
                          Icons.music_note_rounded,
                          color: Colors.white70,
                          size: 22,
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
            child: Column(
              children: [
                const UpdateBanner(),
                Expanded(
                  child: IndexedStack(
                    index: tabIndex,
                    children: _screens,
                  ),
                ),
              ],
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
        color: const Color(0xFF0D0D1A),
        border: Border(top: BorderSide(color: Colors.white.withAlpha(18))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: List.generate(_tabs.length, (i) {
              final selected = currentIndex == i;
              final tab = _tabs[i];
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
                          color: selected ? Colors.white : Colors.white38,
                          size: 22,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          tab.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                            color: selected ? Colors.white : Colors.white38,
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

class _RailIcon extends StatefulWidget {
  const _RailIcon({
    required this.tab,
    required this.selected,
    required this.onTap,
  });
  final _TabItem tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_RailIcon> createState() => _RailIconState();
}

class _RailIconState extends State<_RailIcon> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _isHovered ? 1.1 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              border: widget.selected
                  ? const Border(
                      left: BorderSide(
                        color: Colors.white,
                        width: 2,
                      ),
                    )
                  : null,
            ),
            child: Icon(
              widget.selected ? widget.tab.activeIcon : widget.tab.icon,
              color: widget.selected ? Colors.white : Colors.white38,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FULL PLAYER SHEET — только для compact, 100% высоты modal
// ─────────────────────────────────────────────────────────────────────────────

/// Bug 2 fix: убрана дублирующая кнопка «вниз» из Stack.
/// PlayerScreen теперь сам содержит кнопку закрытия в _TopBar.
/// Это устраняет наложение кнопок друг на друга на складных экранах.
class _FullPlayerSheet extends StatelessWidget {
  const _FullPlayerSheet();

  @override
  Widget build(BuildContext context) {
    // Просто возвращаем PlayerScreen — без дополнительных Positioned-слоёв.
    // SafeArea внутри PlayerScreen корректно обрабатывает отступы.
    return const PlayerScreen();
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
  final String label;
}

class PlayPauseIntent extends Intent {
  const PlayPauseIntent();
  static const key = Key('play_pause');
}

class NextTrackIntent extends Intent {
  const NextTrackIntent();
  static const key = Key('next_track');
}

class PreviousTrackIntent extends Intent {
  const PreviousTrackIntent();
  static const key = Key('previous_track');
}

// ─────────────────────────────────────────────────────────────────────────────
// DESKTOP SHELL — широкий сайдбар + контентная зона с ограниченной шириной
// ─────────────────────────────────────────────────────────────────────────────
class _DesktopShell extends ConsumerWidget {
  const _DesktopShell();

  void _openPlayer(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => const ExpandedPlayerScreen(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity:
              CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabIndex = ref.watch(_tabIndexProvider);
    final hasTrack =
        ref.watch(playerProvider.select((s) => s.currentTrack != null));
    final player = ref.watch(playerProvider);
    final palette = ref.watch(paletteProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      body: Row(
        children: [
          // ── Широкий сайдбар (220px) ────────────────────────────────────────
          _DesktopSidebar(
            tabIndex: tabIndex,
            hasTrack: hasTrack,
            player: player,
            palette: palette,
            onTabChange: (i) => ref.read(_tabIndexProvider.notifier).state = i,
            onPlayerTap: () => _openPlayer(context),
            onPlayPause: () => ref.read(playerProvider.notifier).playPause(),
          ),

          // Разделитель
          Container(width: 1, color: Colors.white.withAlpha(12)),

          // ── Контентная зона с ограниченной шириной ─────────────────────────
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  children: [
                    const UpdateBanner(),
                    Expanded(
                      child: IndexedStack(
                        index: tabIndex,
                        children: _screens,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.tabIndex,
    required this.hasTrack,
    required this.player,
    required this.palette,
    required this.onTabChange,
    required this.onPlayerTap,
    required this.onPlayPause,
  });

  final int tabIndex;
  final bool hasTrack;
  final ProtogenixPlayerState player;
  final PaletteState palette;
  final ValueChanged<int> onTabChange;
  final VoidCallback onPlayerTap;
  final VoidCallback onPlayPause;

  @override
  Widget build(BuildContext context) {
    final track = player.currentTrack as TrackModel?;

    return Container(
      width: 220,
      color: Colors.white.withAlpha(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Логотип ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            child: Text(
              'PROTOGENIX',
              style: TextStyle(
                color: Colors.white.withAlpha(80),
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
              ),
            ),
          ),

          // ── Навигация ──────────────────────────────────────────────────────
          ...List.generate(_tabs.length, (i) {
            final selected = tabIndex == i;
            final tab = _tabs[i];
            return _DesktopNavItem(
              tab: tab,
              selected: selected,
              onTap: () => onTabChange(i),
            );
          }),

          const Spacer(),

          // ── Мини-плеер в сайдбаре ─────────────────────────────────────────
          if (hasTrack && track != null)
            GestureDetector(
              onTap: onPlayerTap,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.white.withAlpha(12),
                  border: Border.all(color: Colors.white.withAlpha(20)),
                ),
                child: Row(
                  children: [
                    // Обложка
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image(
                        image: track.coverImage,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      ),
                    ),

                    const SizedBox(width: 10),

                    // Название и исполнитель
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Кнопка play/pause
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        onPlayPause();
                      },
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: palette.primary.withAlpha(200),
                        ),
                        child: Icon(
                          player.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Z43 Branding ───────────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.fromLTRB(0, 0, 0, 16),
            child: Z43BrandingBadge(),
          ),
        ],
      ),
    );
  }
}

class _DesktopNavItem extends StatefulWidget {
  const _DesktopNavItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });
  final _TabItem tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_DesktopNavItem> createState() => _DesktopNavItemState();
}

class _DesktopNavItemState extends State<_DesktopNavItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: widget.selected
                ? Colors.white.withAlpha(18)
                : _isHovered
                    ? Colors.white.withAlpha(10)
                    : Colors.transparent,
            border: widget.selected
                ? Border.all(color: Colors.white.withAlpha(25))
                : null,
          ),
          child: Row(
            children: [
              Icon(
                widget.selected ? widget.tab.activeIcon : widget.tab.icon,
                color: widget.selected ? Colors.white : Colors.white38,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                widget.tab.label,
                style: TextStyle(
                  color: widget.selected ? Colors.white : Colors.white38,
                  fontSize: 13,
                  fontWeight:
                      widget.selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
