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
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/fold_layout.dart';
import '../features/library/presentation/screens/library_screen.dart';
import '../features/search/presentation/screens/search_screen.dart';
import '../features/player/presentation/widgets/mini_player.dart';
import '../features/player/presentation/screens/player_screen.dart';
import 'package:flutter/services.dart';

import '../features/player/presentation/screens/expanded_player_screen.dart';
import '../features/player/presentation/providers/player_provider.dart';

import '../features/updater/update_banner.dart';
import '../features/home/presentation/screens/home_screen.dart';
import '../features/player/presentation/widgets/desktop_bottom_player.dart';
import '../features/player/presentation/widgets/queue_panel.dart';
import '../features/player/presentation/widgets/beautiful_lyrics_view.dart';
import '../features/player/presentation/widgets/protogenix_background.dart';
import '../features/library/presentation/screens/info_screen.dart';
import '../core/widgets/neon_logo.dart';

// ── Провайдер текущей вкладки ─────────────────────────────────────────────────

final _tabIndexProvider = StateProvider<int>((ref) => 0);

// ── Экраны вкладок ────────────────────────────────────────────────────────────

const _tabs = [
  _TabItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Главная'),
  _TabItem(
      icon: Icons.search_outlined,
      activeIcon: Icons.search_rounded,
      label: 'Поиск'),
  _TabItem(
      icon: Icons.library_music_outlined,
      activeIcon: Icons.library_music_rounded,
      label: 'Медиатека'),
];

final _screens = <Widget>[
  const HomeScreen(),
  const SearchScreen(),
  const LibraryScreen(),
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

    // На десктопе возвращаем только _DesktopShell (WindowTitleBar вынесен в app.dart)
    if (_isDesktop) {
      return const _DesktopShell();
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
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(160),
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
class _DesktopShell extends ConsumerStatefulWidget {
  const _DesktopShell();

  @override
  ConsumerState<_DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<_DesktopShell> {
  bool _isRightPanelOpen = false;
  bool _showQueue = false;
  bool _isPlayerExpanded = false;
  double _rightPanelWidth = 400.0;
  bool _isDragging = false;

  void _openPlayer(BuildContext context) {
    setState(() => _isPlayerExpanded = true);
  }

  void _closePlayer() {
    setState(() => _isPlayerExpanded = false);
  }

  void _toggleRightPanel() {
    setState(() {
      _isRightPanelOpen = !_isRightPanelOpen;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tabIndex = ref.watch(_tabIndexProvider);
    final hasTrack =
        ref.watch(playerProvider.select((s) => s.currentTrack != null));

    if (_isPlayerExpanded && hasTrack) {
      return ExpandedPlayerScreen(onClose: _closePlayer);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      body: ProtogenixBackground(
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  // ── Широкий сайдбар (240px) ────────────────────────────────────────
                  _DesktopSidebar(
                    tabIndex: tabIndex,
                    onTabChange: (i) =>
                        ref.read(_tabIndexProvider.notifier).state = i,
                  ),

                  Container(
                      width: 1, color: Colors.white.withValues(alpha: 0.1)),

                  // ── Контентная зона ────────────────────────────────────────────────
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

                  // ── Выезжающая панель (Lyrics / Queue) ─────────────────────────────
                  if (hasTrack) ...[
                    if (_isRightPanelOpen)
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeLeftRight,
                        child: GestureDetector(
                          onPanStart: (_) => setState(() => _isDragging = true),
                          onPanEnd: (_) => setState(() => _isDragging = false),
                          onPanCancel: () => setState(() => _isDragging = false),
                          onPanUpdate: (details) {
                            setState(() {
                              _rightPanelWidth -= details.delta.dx;
                              _rightPanelWidth = _rightPanelWidth.clamp(300.0, 800.0);
                            });
                          },
                          child: Container(
                            width: 6,
                            color: Colors.transparent,
                            alignment: Alignment.center,
                            child: Container(
                              width: 1,
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                        ),
                      ),
                    AnimatedContainer(
                      duration: _isDragging ? Duration.zero : const Duration(milliseconds: 350), // 0 duration only while dragging for smooth resize
                      curve: Curves.easeOutCubic,
                      width: _isRightPanelOpen ? _rightPanelWidth : 0,
                      child: ClipRect(
                        child: OverflowBox(
                          minWidth: _rightPanelWidth,
                          maxWidth: _rightPanelWidth,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            children: [
                              Expanded(
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  child: Column(
                                    children: [
                                      // Toggle for Lyrics / Queue
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 12),
                                        decoration: BoxDecoration(
                                          border: Border(
                                            bottom: BorderSide(
                                                color: Colors.white
                                                    .withValues(alpha: 0.1)),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceEvenly,
                                          children: [
                                            _PanelTabButton(
                                              icon: Icons.lyrics_outlined,
                                              label: 'Текст',
                                              isSelected: !_showQueue,
                                              onTap: () => setState(
                                                  () => _showQueue = false),
                                            ),
                                            _PanelTabButton(
                                              icon: Icons.queue_music_rounded,
                                              label: 'Очередь',
                                              isSelected: _showQueue,
                                              onTap: () => setState(
                                                  () => _showQueue = true),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Panel Content
                                      Expanded(
                                        child: AnimatedSwitcher(
                                          duration:
                                              const Duration(milliseconds: 200),
                                          child: _showQueue
                                              ? const QueuePanel()
                                              : const BeautifulLyricsView(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Нижний плеер ──────────────────────────────────────────────────────────
            if (hasTrack)
              DesktopBottomPlayer(
                onExpand: () => _openPlayer(context),
                onToggleRightPanel: _toggleRightPanel,
                isRightPanelOpen: _isRightPanelOpen,
              ),
          ],
        ),
      ),
    );
  }
}

class _PanelTabButton extends StatelessWidget {
  const _PanelTabButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : Colors.white54,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white54,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.tabIndex,
    required this.onTabChange,
  });

  final int tabIndex;
  final ValueChanged<int> onTabChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: Colors.black.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Логотип ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
            child: Row(
              children: [
                const NeonLogo(size: 46),
                const SizedBox(width: 12),
                Text(
                  'PROTOGENIX',
                  style: TextStyle(
                    color: Colors.white.withAlpha(200),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                  ),
                ),
              ],
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

          const Spacer(), // Прижимает "Инфо" книзу

          // Пункт "Инфо"
          _DesktopNavItem(
            tab: const _TabItem(
              icon: Icons.info_outline_rounded,
              activeIcon: Icons.info_rounded,
              label: 'Инфо',
            ),
            selected: false,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const InfoScreen()),
            ),
          ),

          const SizedBox(height: 16),
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
