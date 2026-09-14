import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/library_track.dart';
import '../library_provider.dart';
import '../playlist_provider.dart';
import '../widgets/track_context_menu.dart';
import '../widgets/add_to_playlist_sheet.dart';
import 'playlists_screen.dart';
import '../../../importer/presentation/importer_sheet.dart';
import '../../../player/presentation/providers/palette_provider.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../../player/presentation/widgets/protogenix_background.dart';
import '../../../player/presentation/widgets/glass_card.dart';
import '../../../../core/theme/cover_placeholder.dart';
import '../../../../core/widgets/chip_button.dart';
import '../../../../core/widgets/glass_dialog.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ProtogenixBackground(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Медиатека',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _GlassTabBar(),
                Expanded(
                  child: TabBarView(
                    children: [
                      _TracksTab(),
                      PlaylistsScreen(),
                      _FavoritesTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassTabBar extends StatelessWidget {
  const _GlassTabBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: GlassCard(
        borderRadius: 14,
        padding: const EdgeInsets.all(4),
        opacity: 0.08,
        child: TabBar(
          tabs: const [
            Tab(text: 'Треки'),
            Tab(text: 'Плейлисты'),
            Tab(text: 'Избранное'),
          ],
          indicator: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: Colors.white.withAlpha(46),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withAlpha(128),
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          dividerColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          splashBorderRadius: BorderRadius.circular(10),
          overlayColor: WidgetStateProperty.all(Colors.white.withAlpha(20)),
        ),
      ),
    );
  }
}

class _TracksTab extends ConsumerWidget {
  const _TracksTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(libraryProvider);
    return tracks.isEmpty
        ? _EmptyState(onImport: () => showImporterSheet(context))
        : _TrackList(tracks: tracks);
  }
}

class _FavoritesTab extends ConsumerWidget {
  const _FavoritesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allTracks = ref.watch(libraryProvider);
    final favoriteIds = ref.watch(favoritesProvider);

    final favorites = allTracks.where((t) => favoriteIds.contains(t.id)).toList();

    return CustomScrollView(
      slivers: [
        if (favorites.isEmpty)
          const SliverFillRemaining(
            child: _EmptyFavorites(),
          )
        else ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: _PlayAllButton(tracks: favorites),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _FavoriteTile(
                track: favorites[i],
                index: i,
                allTracks: favorites,
              ),
              childCount: favorites.length,
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 140)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onImport});
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.library_music_rounded,
              size: 80,
              color: Colors.white12,
            ),
            const SizedBox(height: 24),
            const Text(
              'Библиотека пуста',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Добавь треки, чтобы начать',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
            const SizedBox(height: 32),
            _ImportButton(onTap: onImport),
          ],
        ).animate().fadeIn(duration: 600.ms).scale(
              begin: const Offset(0.9, 0.9),
              curve: Curves.easeOutCubic,
            ),
      ),
    );
  }
}

class _ImportButton extends StatelessWidget {
  const _ImportButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withAlpha(20),
          border: Border.all(color: Colors.white24),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, color: Colors.white70),
            SizedBox(width: 8),
            Text(
              'Импортировать',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TRACK LIST
// ─────────────────────────────────────────────────────────────────────────────

class _TrackList extends ConsumerStatefulWidget {
  const _TrackList({required this.tracks});
  final List<LibraryTrack> tracks;

  @override
  ConsumerState<_TrackList> createState() => _TrackListState();
}

void _showSortSheet(BuildContext context, WidgetRef ref) {
  final currentMode = ref.read(librarySortModeProvider);
  final palette = ref.read(paletteProvider);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(200),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 16),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'СОРТИРОВКА',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 13,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  _SortOptionTile(
                    label: 'По дате добавления',
                    isSelected: currentMode == LibrarySortMode.dateAdded,
                    accentColor: palette.primary,
                    onTap: () {
                      ref.read(librarySortModeProvider.notifier).state =
                          LibrarySortMode.dateAdded;
                      Navigator.pop(ctx);
                    },
                  ),
                  _SortOptionTile(
                    label: 'По названию',
                    isSelected: currentMode == LibrarySortMode.title,
                    accentColor: palette.primary,
                    onTap: () {
                      ref.read(librarySortModeProvider.notifier).state =
                          LibrarySortMode.title;
                      Navigator.pop(ctx);
                    },
                  ),
                  _SortOptionTile(
                    label: 'По исполнителю',
                    isSelected: currentMode == LibrarySortMode.artist,
                    accentColor: palette.primary,
                    onTap: () {
                      ref.read(librarySortModeProvider.notifier).state =
                          LibrarySortMode.artist;
                      Navigator.pop(ctx);
                    },
                  ),
                  _SortOptionTile(
                    label: 'По длительности',
                    isSelected: currentMode == LibrarySortMode.duration,
                    accentColor: palette.primary,
                    onTap: () {
                      ref.read(librarySortModeProvider.notifier).state =
                          LibrarySortMode.duration;
                      Navigator.pop(ctx);
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _SortOptionTile extends StatelessWidget {
  const _SortOptionTile({
    required this.label,
    required this.isSelected,
    required this.accentColor,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? accentColor : Colors.white70,
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_rounded, color: accentColor, size: 22),
          ],
        ),
      ),
    );
  }
}

class _TrackListState extends ConsumerState<_TrackList> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Выделение нескольких треков — чтобы добавить их в плейлист разом
  // (из отзывов: 400 треков по одному не накидаешь)
  bool _selecting = false;
  final Set<String> _selected = {};

  void _startSelection([String? trackId]) {
    HapticFeedback.selectionClick();
    setState(() {
      _selecting = true;
      if (trackId != null) _selected.add(trackId);
    });
  }

  void _toggle(String trackId) {
    setState(() {
      if (!_selected.remove(trackId)) _selected.add(trackId);
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  /// В порядке, в котором треки сейчас показаны; выделенные, но скрытые
  /// поиском, — следом.
  Future<void> _addSelectedToPlaylist(List<LibraryTrack> shown) async {
    final shownIds = {for (final t in shown) t.id};
    final ids = [
      for (final t in shown)
        if (_selected.contains(t.id)) t.id,
      for (final t in widget.tracks)
        if (_selected.contains(t.id) && !shownIds.contains(t.id)) t.id,
    ];
    if (await showAddToPlaylistSheet(context, ids) && mounted) {
      _exitSelection();
    }
  }

  /// Удаление пачкой — например, неправильно скачанных треков. Своя музыка
  /// с телефона остаётся на месте (library_provider.dart).
  Future<void> _deleteSelected() async {
    final tracks = [
      for (final t in widget.tracks)
        if (_selected.contains(t.id)) t,
    ];
    if (tracks.isEmpty) return;
    final fromPhone = tracks.where((t) => t.source == 'device').length;
    final confirmed = await showGlassConfirm(
      context,
      title: 'Удалить ${tracks.length} ${tracksWord(tracks.length)}?',
      message:
          'Треки пропадут из медиатеки, скачанные файлы удалятся с устройства.'
          '${fromPhone == 0 ? '' : ' Музыка с телефона останется на месте — '
              '$fromPhone ${tracksWord(fromPhone)} уйдут только из медиатеки.'}',
      confirmLabel: 'Удалить',
    );
    if (!confirmed || !mounted) return;

    final currentId = ref.read(playerProvider).currentTrack?.id;
    await ref.read(libraryProvider.notifier).removeTracksWithFiles(tracks);
    // Плейлисты хранят id отдельно (data.md): перечитать, чтобы удалённые
    // пропали и там
    ref.invalidate(playlistTracksProvider);
    ref.invalidate(playlistTracksNotifierProvider);
    if (tracks.any((t) => t.id == currentId)) {
      await ref.read(playerProvider.notifier).reloadFromLibrary();
    }
    if (!mounted) return;
    _exitSelection();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Удалено: ${tracks.length} ${tracksWord(tracks.length)}')));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(paletteProvider);

    var filteredTracks = widget.tracks.where((t) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return t.title.toLowerCase().contains(q) ||
          t.artist.toLowerCase().contains(q);
    }).toList();

    final sortMode = ref.watch(librarySortModeProvider);
    switch (sortMode) {
      case LibrarySortMode.title:
        filteredTracks.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case LibrarySortMode.artist:
        filteredTracks.sort(
            (a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        break;
      case LibrarySortMode.duration:
        filteredTracks.sort((a, b) => a.durationMs.compareTo(b.durationMs));
        break;
      case LibrarySortMode.dateAdded:
        // already sorted by date desc in DB
        break;
    }

    final allSelected = filteredTracks.isNotEmpty &&
        filteredTracks.every((t) => _selected.contains(t.id));

    return PopScope(
      // «Назад» сначала снимает выделение
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitSelection();
      },
      child: SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          // ── Заголовок ────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: _selecting
                  ? _SelectionBar(
                      count: _selected.length,
                      allSelected: allSelected,
                      accent: palette.primary,
                      onClose: _exitSelection,
                      onToggleAll: () => setState(() {
                        final ids = filteredTracks.map((t) => t.id);
                        if (allSelected) {
                          _selected.removeAll(ids);
                        } else {
                          _selected.addAll(ids);
                        }
                      }),
                      onAddToPlaylist: () =>
                          _addSelectedToPlaylist(filteredTracks),
                      onDelete: _deleteSelected,
                    )
                  : Row(
                children: [
                  const Text(
                    'Треки',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${widget.tracks.length}',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Выделить несколько треков: на ПК до долгого нажатия
                  // не догадаться
                  if (widget.tracks.isNotEmpty) ...[
                    _GlassIconButton(
                      icon: Icons.checklist_rounded,
                      isActive: false,
                      activeColor: palette.primary,
                      onTap: _startSelection,
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Кнопка сортировки — круглая стеклянная с hover-эффектом
                  _GlassIconButton(
                    icon: Icons.sort_rounded,
                    isActive: sortMode != LibrarySortMode.dateAdded,
                    activeColor: palette.primary,
                    onTap: () => _showSortSheet(context, ref),
                  ),
                  const SizedBox(width: 8),
                  // Кнопка импорта
                  GestureDetector(
                    onTap: () => showImporterSheet(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withAlpha(15),
                        border: Border.all(color: Colors.white.withAlpha(30)),
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Поиск ────────────────────────────────────────────────────────
          if (widget.tracks.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withAlpha(25)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    cursorColor: palette.primary,
                    decoration: InputDecoration(
                      hintText: 'Поиск треков и исполнителей...',
                      hintStyle:
                          const TextStyle(color: Colors.white38, fontSize: 15),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: Colors.white38, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  color: Colors.white54, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ),
            ),

          // ── Список ───────────────────────────────────────────────────────
          if (filteredTracks.isEmpty && _searchQuery.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 60),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.search_off_rounded,
                          size: 48, color: Colors.white24),
                      const SizedBox(height: 16),
                      Text(
                        'Ничего не найдено',
                        style: TextStyle(
                            color: Colors.white.withAlpha(150), fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = filteredTracks[index];
                  return _TrackTile(
                    track: track,
                    index: index,
                    tracks: filteredTracks,
                    selecting: _selecting,
                    selected: _selected.contains(track.id),
                    onSelect: () => _toggle(track.id),
                    onLongPress: () => _selecting
                        ? _toggle(track.id)
                        : _startSelection(track.id),
                  );
                },
                childCount: filteredTracks.length,
              ),
            ),

          // Отступ снизу (под мини-плеер + навбар)
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TRACK TILE
// ─────────────────────────────────────────────────────────────────────────────

/// Шапка списка в режиме выделения: сколько выбрано, «Все», корзина,
/// «В плейлист». Кнопки — те же стеклянные, что в обычной шапке.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.allSelected,
    required this.accent,
    required this.onClose,
    required this.onToggleAll,
    required this.onAddToPlaylist,
    required this.onDelete,
  });

  final int count;
  final bool allSelected;
  final Color accent;
  final VoidCallback onClose;
  final VoidCallback onToggleAll;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    // На узком телефоне у «В плейлист» только иконка — иначе не влезает
    final narrow = MediaQuery.sizeOf(context).width < 400;
    return Row(
      children: [
        _GlassIconButton(icon: Icons.close_rounded, onTap: onClose),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            count == 0 ? 'Выбери треки' : 'Выбрано: $count',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        ChipButton(label: allSelected ? 'Снять' : 'Все', onTap: onToggleAll),
        const SizedBox(width: 8),
        // Корзина — красная, как «Удалить трек» в меню «⋮»
        Opacity(
          opacity: count == 0 ? 0.4 : 1,
          child: IgnorePointer(
            ignoring: count == 0,
            child: _GlassIconButton(
              icon: Icons.delete_outline_rounded,
              isActive: true,
              activeColor: Colors.redAccent,
              onTap: onDelete,
            ),
          ),
        ),
        const SizedBox(width: 8),
        ChipButton(
          icon: Icons.playlist_add_rounded,
          label: narrow ? null : 'В плейлист',
          accent: accent,
          onTap: count == 0 ? null : onAddToPlaylist,
        ),
      ],
    );
  }
}

class _TrackTile extends ConsumerWidget {
  const _TrackTile({
    required this.track,
    required this.index,
    required this.tracks,
    this.selecting = false,
    this.selected = false,
    this.onSelect,
    this.onLongPress,
  });

  final LibraryTrack track;
  final int index;
  final List<LibraryTrack> tracks;

  /// Режим выделения: нажатие отмечает трек, а не включает его.
  final bool selecting;
  final bool selected;
  final VoidCallback? onSelect;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTrackId =
        ref.watch(playerProvider.select((s) => s.currentTrack?.id));
    final isPlaying = currentTrackId == track.id;
    final palette = ref.watch(paletteProvider);

    return InkWell(
      onLongPress: onLongPress,
      onTap: selecting
          ? onSelect
          : () {
        // Оптимизация производительности: используем Iterable (map) без toList(),
        // чтобы избежать блокировки UI-потока перед запуском плеера.
        final models = tracks.map((t) => t.toTrackModel());
        ref.read(playerProvider.notifier).loadPlaylist(
              models,
              initialIndex: index,
            );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: isPlaying
              ? Border(
                  left: BorderSide(
                    // Цвет обложки, как и значок эквалайзера на обложке
                    color: palette.primary,
                    width: 3,
                  ),
                )
              : null,
          color: selected
              ? palette.primary.withAlpha(34)
              : isPlaying
                  ? Colors.white.withAlpha(8)
                  : Colors.transparent,
        ),
        child: Row(
          children: [
            // Обложка / playing indicator
            Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image(
                    image: track.coverPath != null
                        ? FileImage(File(track.coverPath!)) as ImageProvider
                        : kCoverPlaceholder,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                  ),
                ),
                if (isPlaying)
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.black.withAlpha(120),
                    ),
                    child: Icon(
                      Icons.equalizer_rounded,
                      color: palette.primary,
                      size: 22,
                    ),
                  ),
                // Раньше в else здесь было затемнение с динамиком: это прежний
                // индикатор «играет», который при добавлении эквалайзера уехал
                // в ветку для всех остальных треков
                // Режим выделения — отметка поверх обложки
                if (selecting)
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.black.withAlpha(150),
                    ),
                    child: Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: selected ? palette.primary : Colors.white70,
                      size: 24,
                    ),
                  ),
              ],
            ),

            const SizedBox(width: 14),

            // Название + артист
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isPlaying ? Colors.white : Colors.white70,
                      fontSize: 15,
                      fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isPlaying ? Colors.white : Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Длительность
            Text(
              _fmtDuration(track.duration),
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 12,
              ),
            ),

            const SizedBox(width: 4),

            // Три точки → контекстное меню (при выделении не нужны; место
            // остаётся, чтобы строка не прыгала)
            if (selecting)
              const SizedBox(width: 36)
            else
              IconButton(
                icon: const Icon(Icons.more_vert_rounded),
                color: Colors.white38,
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () => showTrackContextMenu(context, ref, track),
              ),
          ],
        ),
      ),
    );
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ── Кнопка играть всё ─────────────────────────────────────────────────────────

class _PlayAllButton extends ConsumerWidget {
  const _PlayAllButton({required this.tracks});
  final List<LibraryTrack> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        final models = tracks.map((t) => t.toTrackModel());
        ref.read(playerProvider.notifier).loadPlaylist(models);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withAlpha(15),
          border: Border.all(color: Colors.white.withAlpha(25)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_rounded, color: Colors.redAccent, size: 18),
            SizedBox(width: 8),
            Text(
              'Слушать избранное',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyFavorites extends StatelessWidget {
  const _EmptyFavorites();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.favorite_outline_rounded,
            size: 80,
            color: Colors.white12,
          ),
          SizedBox(height: 20),
          Text(
            'Нет избранных треков',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Нажми ♥ у трека, чтобы добавить',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ── Track tile ────────────────────────────────────────────────────────────────

class _FavoriteTile extends ConsumerWidget {
  const _FavoriteTile({
    required this.track,
    required this.index,
    required this.allTracks,
  });

  final LibraryTrack track;
  final int index;
  final List<LibraryTrack> allTracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final isPlaying = player.currentTrack?.id == track.id;

    return InkWell(
      onTap: () {
        final models = allTracks.map((t) => t.toTrackModel());
        ref.read(playerProvider.notifier).loadPlaylist(
              models,
              initialIndex: index,
            );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: isPlaying ? Colors.white.withAlpha(8) : Colors.transparent,
        child: Row(
          children: [
            // Сердечко
            GestureDetector(
              onTap: () =>
                  ref.read(favoritesProvider.notifier).toggle(track.id),
              child: const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(
                  Icons.favorite_rounded,
                  color: Colors.redAccent,
                  size: 18,
                ),
              ),
            ),

            // Обложка
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image(
                image: track.coverPath != null
                    ? FileImage(File(track.coverPath!)) as ImageProvider
                    : kCoverPlaceholder,
                width: 50,
                height: 50,
                fit: BoxFit.cover,
              ),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            IconButton(
              icon: const Icon(Icons.more_vert_rounded),
              color: Colors.white38,
              iconSize: 20,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () => showTrackContextMenu(context, ref, track),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Круглая стеклянная кнопка-иконка (с hover-эффектом) ─────────────────────

class _GlassIconButton extends StatefulWidget {
  const _GlassIconButton({
    required this.icon,
    required this.onTap,
    this.isActive = false,
    this.activeColor,
    this.size = 38,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isActive;
  final Color? activeColor;
  final double size;

  @override
  State<_GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<_GlassIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.activeColor ?? Colors.white;
    final iconColor = widget.isActive ? accent : Colors.white70;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isActive
                    ? accent.withAlpha(_isHovered ? 45 : 30)
                    : Colors.white.withAlpha(_isHovered ? 26 : 15),
                border: Border.all(
                  color: widget.isActive
                      ? accent.withAlpha(_isHovered ? 130 : 100)
                      : Colors.white.withAlpha(_isHovered ? 55 : 30),
                  width: 1,
                ),
              ),
              child: Icon(
                widget.icon,
                color: iconColor,
                size: widget.size * 0.45,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
