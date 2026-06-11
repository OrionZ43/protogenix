import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/playlist_database.dart';
import '../../domain/library_track.dart';
import '../library_provider.dart';
import '../playlist_provider.dart';
import '../widgets/track_context_menu.dart';
import '../../../importer/presentation/importer_sheet.dart';
import '../../../player/presentation/providers/palette_provider.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../../player/presentation/widgets/protogenix_background.dart';
import '../../../player/presentation/widgets/glass_card.dart';

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
                      _PlaylistsTab(),
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

class _PlaylistsTab extends ConsumerWidget {
  const _PlaylistsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                const Text(
                  'Плейлисты',
                  style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5),
                ),
                const Spacer(),
                Text(
                  '${playlists.length}',
                  style: const TextStyle(color: Colors.white38, fontSize: 16),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _createPlaylistDialog(context, ref),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withAlpha(15),
                      border: Border.all(color: Colors.white.withAlpha(30)),
                    ),
                    child: const Icon(Icons.add_rounded, color: Colors.white70, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),

        if (playlists.isEmpty)
          SliverFillRemaining(
            child: _EmptyPlaylists(
              onTap: () => _createPlaylistDialog(context, ref),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.1,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _PlaylistCard(
                  playlist: playlists[i],
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlaylistDetailScreen(playlist: playlists[i]),
                    ),
                  ),
                  onDelete: () => ref.read(playlistsProvider.notifier).delete(playlists[i].id),
                  onRename: () => _renameDialog(context, ref, playlists[i]),
                ),
                childCount: playlists.length,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
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
    backgroundColor: const Color(0xFF13131F),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return SafeArea(
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
              padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Сортировка',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
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
            const SizedBox(height: 16),
          ],
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
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      title: Text(
        label,
        style: TextStyle(
          color: isSelected ? accentColor : Colors.white70,
          fontSize: 16,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check_rounded, color: accentColor, size: 24)
          : null,
    );
  }
}

class _TrackListState extends ConsumerState<_TrackList> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

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

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          // ── Заголовок ────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
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
                  // Кнопка сортировки
                  GestureDetector(
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
                  ),
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
                (context, index) => _TrackTile(
                  track: filteredTracks[index],
                  index: index,
                  tracks: filteredTracks,
                ),
                childCount: filteredTracks.length,
              ),
            ),

          // Отступ снизу (под мини-плеер + навбар)
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TRACK TILE
// ─────────────────────────────────────────────────────────────────────────────

class _TrackTile extends ConsumerWidget {
  const _TrackTile({
    required this.track,
    required this.index,
    required this.tracks,
  });

  final LibraryTrack track;
  final int index;
  final List<LibraryTrack> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTrackId =
        ref.watch(playerProvider.select((s) => s.currentTrack?.id));
    final isPlaying = currentTrackId == track.id;
    final palette = ref.watch(paletteProvider);

    return InkWell(
      onTap: () {
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
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                )
              : null,
          color: isPlaying ? Colors.white.withAlpha(8) : Colors.transparent,
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
                        : const AssetImage('assets/images/mock_cover.jpg'),
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
                  )
                else
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.black.withAlpha(120),
                    ),
                    child: const Icon(
                      Icons.volume_up_rounded,
                      color: Colors.white,
                      size: 22,
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

            // Три точки → контекстное меню
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

class _EmptyPlaylists extends StatelessWidget {
  const _EmptyPlaylists({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.queue_music_rounded,
            size: 80,
            color: Colors.white12,
          ),
          const SizedBox(height: 20),
          const Text(
            'Нет плейлистов',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Создай первый плейлист',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Colors.white.withAlpha(18),
                border: Border.all(color: Colors.white24),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_rounded,
                    color: Colors.white70,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Создать плейлист',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      )
          .animate()
          .fadeIn(duration: 600.ms)
          .scale(begin: const Offset(0.9, 0.9), curve: Curves.easeOutCubic),
    );
  }
}

// ── Playlist card ─────────────────────────────────────────────────────────────

class _PlaylistCard extends ConsumerStatefulWidget {
  const _PlaylistCard({
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
  ConsumerState<_PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends ConsumerState<_PlaylistCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playlistAsync = ref.watch(playlistTracksProvider(widget.playlist.id));

    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
      },
      onExit: (_) {
        setState(() => _isHovered = false);
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: GlassCard(
          borderRadius: 18,
          padding: EdgeInsets.zero,
          child: Stack(
            children: [
              // Анимированные обложки (фон)
              if (playlistAsync is AsyncData)
                Positioned.fill(
                  child: _AnimatedCoversBackground(
                    tracks: playlistAsync.value ?? [],
                    animation: _animCtrl,
                    isHovered: _isHovered,
                  ),
                ),

              // Градиентное затемнение, чтобы текст читался поверх обложек
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withAlpha(0),
                        Colors.black.withAlpha(200),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),

              // Контент карточки
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white.withAlpha(
                          30,
                        ), // чуть ярче, т.к. фон может быть тёмным
                      ),
                      child: const Icon(
                        Icons.queue_music_rounded,
                        color: Colors.white70,
                        size: 22,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      widget.playlist.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: widget.onRename,
                          child: const Icon(
                            Icons.edit_outlined,
                            color: Colors.white54,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: widget.onDelete,
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.white54,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedCoversBackground extends StatelessWidget {
  const _AnimatedCoversBackground({
    required this.tracks,
    required this.animation,
    required this.isHovered,
  });

  final List<LibraryTrack> tracks;
  final Animation<double> animation;
  final bool isHovered;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();

    // Берем до 4 обложек
    final covers = tracks
        .where((t) => t.coverPath != null)
        .map((t) => FileImage(File(t.coverPath!)))
        .take(4)
        .toList();

    if (covers.isEmpty) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: List.generate(covers.length, (i) {
              // Немного разная траектория движения для каждой обложки
              final offset = _calculateOffset(i, animation.value);

              return AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                left: offset.dx,
                top: offset.dy,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 300),
                  scale: isHovered ? 1.2 : 1.0,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: isHovered ? 0.6 : 0.3,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        image: DecorationImage(
                          image: covers[i],
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Offset _calculateOffset(int index, double animValue) {
    // Базовые позиции
    final basePositions = [
      const Offset(-10, -10),
      const Offset(80, -20),
      const Offset(-20, 70),
      const Offset(90, 80),
    ];

    if (index >= basePositions.length) return Offset.zero;

    final base = basePositions[index];

    // Амплитуда движения (туда-сюда)
    final dx = base.dx + (index % 2 == 0 ? 20 * animValue : -20 * animValue);
    final dy = base.dy + (index % 2 != 0 ? 20 * animValue : -20 * animValue);

    return Offset(dx, dy);
  }
}

// ── Диалоги ───────────────────────────────────────────────────────────────────

Future<void> _createPlaylistDialog(BuildContext context, WidgetRef ref) async {
  final ctrl = TextEditingController();
  final name = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '',
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, anim1, anim2) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim1, anim2, child) {
      return Transform.scale(
        scale: anim1.value,
        child: Opacity(
          opacity: anim1.value,
          child: _GlassDialog(
            title: 'Новый плейлист',
            content: TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              cursorColor: Colors.white70,
              decoration: InputDecoration(
                hintText: 'Название...',
                hintStyle: const TextStyle(color: Colors.white38),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white60),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text(
                  'Отмена',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
                child: const Text(
                  'Создать',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (name != null && name.isNotEmpty) {
    ref.read(playlistsProvider.notifier).create(name);
  }
}

Future<void> _renameDialog(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
) async {
  final ctrl = TextEditingController(text: playlist.name);
  final name = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '',
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, anim1, anim2) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim1, anim2, child) {
      return Transform.scale(
        scale: anim1.value,
        child: Opacity(
          opacity: anim1.value,
          child: _GlassDialog(
            title: 'Переименовать',
            content: TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              cursorColor: Colors.white70,
              decoration: InputDecoration(
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white60),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text(
                  'Отмена',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
                child: const Text(
                  'Сохранить',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (name != null && name.isNotEmpty) {
    ref.read(playlistsProvider.notifier).rename(playlist.id, name);
  }
}

class _GlassDialog extends StatelessWidget {
  const _GlassDialog({
    required this.title,
    required this.content,
    required this.actions,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(200),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withAlpha(30)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    content,
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: actions,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PLAYLIST DETAIL SCREEN
// ═════════════════════════════════════════════════════════════════════════════

class PlaylistDetailScreen extends ConsumerWidget {
  const PlaylistDetailScreen({super.key, required this.playlist});
  final Playlist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTracks = ref.watch(playlistTracksProvider(playlist.id));

    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      body: ProtogenixBackground(
        child: SafeArea(
          child: asyncTracks.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: Colors.white24),
            ),
            error: (e, _) => const Center(
              child: Text(
                'Ошибка загрузки',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            data: (tracks) =>
                _PlaylistContent(playlist: playlist, tracks: tracks),
          ),
        ),
      ),
    );
  }
}

class _PlaylistContent extends ConsumerWidget {
  const _PlaylistContent({required this.playlist, required this.tracks});

  final Playlist playlist;
  final List<LibraryTrack> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomScrollView(
      slivers: [
        // Заголовок
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white70,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    playlist.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                Text(
                  '${tracks.length} треков',
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ],
            ),
          ),
        ),

        // Кнопка "Играть всё"
        if (tracks.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: GestureDetector(
                onTap: () {
                  // ОПТИМИЗАЦИЯ ПРОИЗВОДИТЕЛЬНОСТИ: Без .toList()
                  final models = tracks.map((t) => t.toTrackModel());
                  ref.read(playerProvider.notifier).loadPlaylist(models);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white.withAlpha(18),
                    border: Border.all(color: Colors.white.withAlpha(30)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Слушать всё',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Треки
        if (tracks.isEmpty)
          const SliverFillRemaining(
            child: Center(
              child: Text(
                'Плейлист пуст',
                style: TextStyle(color: Colors.white38, fontSize: 15),
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _PlaylistTrackTile(
                track: tracks[i],
                index: i,
                allTracks: tracks,
                playlistId: playlist.id,
              ),
              childCount: tracks.length,
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }
}

class _PlaylistTrackTile extends ConsumerWidget {
  const _PlaylistTrackTile({
    required this.track,
    required this.index,
    required this.allTracks,
    required this.playlistId,
  });

  final LibraryTrack track;
  final int index;
  final List<LibraryTrack> allTracks;
  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final isPlaying = player.currentTrack?.id == track.id;

    return InkWell(
      onTap: () {
        // ОПТИМИЗАЦИЯ ПРОИЗВОДИТЕЛЬНОСТИ: Без .toList()
        final models = allTracks.map((t) => t.toTrackModel());
        ref
            .read(playerProvider.notifier)
            .loadPlaylist(models, initialIndex: index);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Text(
              '${index + 1}',
              style: TextStyle(
                color: isPlaying ? Colors.white : Colors.white24,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(width: 14),

            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image(
                image: track.coverPath != null
                    ? FileImage(File(track.coverPath!)) as ImageProvider
                    : const AssetImage('assets/images/mock_cover.jpg'),
                width: 44,
                height: 44,
                fit: BoxFit.cover,
              ),
            ),

            const SizedBox(width: 12),

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
                      fontSize: 14,
                      fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),

            // Меню: убрать из плейлиста + другие действия
            IconButton(
              icon: const Icon(Icons.more_vert_rounded),
              color: Colors.white38,
              iconSize: 20,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () =>
                  _showPlaylistTrackOptions(context, ref, track, playlistId),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Меню трека внутри плейлиста ───────────────────────────────────────────────

void _showPlaylistTrackOptions(
  BuildContext context,
  WidgetRef ref,
  LibraryTrack track,
  String playlistId,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => UncontrolledProviderScope(
      container: ProviderScope.containerOf(context),
      child: _PlaylistTrackOptionsSheet(track: track, playlistId: playlistId),
    ),
  );
}

class _PlaylistTrackOptionsSheet extends ConsumerWidget {
  const _PlaylistTrackOptionsSheet({
    required this.track,
    required this.playlistId,
  });

  final LibraryTrack track;
  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0E0E1C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Заголовок
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Divider(color: Colors.white.withAlpha(20), height: 1),
            const SizedBox(height: 8),

            // Убрать из плейлиста
            _OptionTile(
              icon: Icons.remove_circle_outline_rounded,
              iconColor: Colors.orangeAccent,
              label: 'Убрать из плейлиста',
              onTap: () async {
                Navigator.of(context).pop();
                await PlaylistDatabase.instance.removeTrackFromPlaylist(
                  playlistId: playlistId,
                  trackId: track.id,
                );
                // Инвалидируем кэш FutureProvider для этого плейлиста
                ref.invalidate(playlistTracksProvider(playlistId));
              },
            ),

            // Другие действия (открывает общее меню трека)
            _OptionTile(
              icon: Icons.more_horiz_rounded,
              label: 'Другие действия',
              onTap: () {
                Navigator.of(context).pop();
                showTrackContextMenu(context, ref, track);
              },
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? Colors.white70, size: 22),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ],
        ),
      ),
    );
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
                    : const AssetImage('assets/images/mock_cover.jpg'),
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
