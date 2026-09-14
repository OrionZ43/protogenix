import '../../data/library_database.dart';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/playlist_database.dart';
import '../../domain/library_track.dart';
import '../playlist_provider.dart';
import '../widgets/track_context_menu.dart';
import '../../../player/presentation/providers/palette_provider.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../../player/presentation/widgets/protogenix_background.dart';
import '../../../player/presentation/widgets/glass_card.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/cover_placeholder.dart';

// ═════════════════════════════════════════════════════════════════════════════
// PLAYLISTS SCREEN
// ═════════════════════════════════════════════════════════════════════════════

class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: _CreateFab(
        onTap: () => showCreatePlaylistSheet(context, ref),
      ),
      body: ProtogenixBackground(
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Row(
                    children: [
                      const Text(
                        'Плейлисты',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const Spacer(),
                      if (playlists.isNotEmpty)
                        Text(
                          '${playlists.length}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 16,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (playlists.isEmpty)
                SliverFillRemaining(
                  child: _EmptyPlaylists(
                    onTap: () => showCreatePlaylistSheet(context, ref),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.1,
                    ),
                    delegate: SliverChildBuilderDelegate(
                          (context, i) => PlaylistCard(
                        playlist: playlists[i],
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PlaylistDetailScreen(playlist: playlists[i]),
                          ),
                        ),
                        onDelete: () => ref
                            .read(playlistsProvider.notifier)
                            .delete(playlists[i].id),
                        onRename: () => showCreatePlaylistSheet(
                          context,
                          ref,
                          initialName: playlists[i].name,
                          playlistId: playlists[i].id,
                        ),
                      ),
                      childCount: playlists.length,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── FAB ───────────────────────────────────────────────────────────────────────

class _CreateFab extends StatelessWidget {
  const _CreateFab({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white.withAlpha(20),
          border: Border.all(color: Colors.white.withAlpha(40)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(
              'Создать',
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

// ── Playlist Cover Collage ────────────────────────────────────────────────────

class _PlaylistCoverCollage extends StatefulWidget {
  const _PlaylistCoverCollage({
    required this.tracks,
    required this.diameter,
    this.animate = true,
    this.glowColor,
  });

  final List<LibraryTrack> tracks;
  final double diameter;
  final bool animate;
  final Color? glowColor;

  @override
  State<_PlaylistCoverCollage> createState() => _PlaylistCoverCollageState();
}

class _PlaylistCoverCollageState extends State<_PlaylistCoverCollage>
    with SingleTickerProviderStateMixin {
  // Один общий медленный цикл (0..1, по кругу), из которого выводятся фазы
  // орбит спутников, "дыхание" главной обложки и точки соединительных линий.
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 36),
    );
    if (widget.animate) {
      _animCtrl.repeat();
    }
  }

  @override
  void didUpdateWidget(_PlaylistCoverCollage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !oldWidget.animate) {
      _animCtrl.repeat();
    } else if (!widget.animate && oldWidget.animate) {
      _animCtrl.stop();
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Widget _cover(String? path, {BoxFit fit = BoxFit.cover}) {
    final image = path == null
        ? Image(image: kCoverPlaceholder, fit: fit)
        : Image(
      image: ResizeImage(FileImage(File(path)), width: 200),
      fit: fit,
    );
    return SizedBox.expand(child: image);
  }

  Widget _emptyState() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            AppColors.neonPurple.withValues(alpha: 0.35),
            AppColors.neonCyan.withValues(alpha: 0.15),
          ],
          center: Alignment.topLeft,
          radius: 1.2,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.queue_music_rounded,
          color: Colors.white.withValues(alpha: 0.5),
          size: widget.diameter * 0.4,
        ),
      ),
    );
  }

  Widget _satelliteCover(String? coverPath, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(child: _cover(coverPath)),
    );
  }

  /// Созвездие: главная обложка в центре, спутники летают по орбитам вокруг
  /// и могут выходить за пределы блока, соединённые тонкими линиями —
  /// с главной обложкой и друг с другом.
  Widget _buildConstellation(List<String?> covers) {
    final d = widget.diameter;
    final mainSize = d * 0.56;
    final satSize = d * 0.30;
    // Орбита шире самого блока — спутники "выплывают" за края.
    final orbitRadius = d * 0.62;
    // Видимая область больше diameter, чтобы спутники не подрезались layout'ом.
    final boundsSize = d * 1.6;
    final center = boundsSize / 2;

    final satellites = covers.skip(1).take(3).toList();

    final phases = [0.0, 0.34, 0.67];
    final speeds = [0.07, -0.09, 0.05];
    final bobs = [d * 0.05, d * 0.07, d * 0.04];
    final radii = [orbitRadius, orbitRadius * 0.92, orbitRadius * 1.05];

    return SizedBox(
      width: boundsSize,
      height: boundsSize,
      child: AnimatedBuilder(
        animation: _animCtrl,
        builder: (context, _) {
          // Считаем позиции спутников один раз за кадр — используются и для
          // линий (CustomPaint), и для самих картинок (Positioned).
          final positions = <Offset>[];
          for (var i = 0; i < satellites.length; i++) {
            final t = (_animCtrl.value * speeds[i % speeds.length] +
                phases[i % phases.length]) %
                1.0;
            final angle = t * 2 * math.pi;
            final r = radii[i % radii.length];
            final dx = math.cos(angle) * r;
            final dy = math.sin(angle) * r * 0.55; // эллиптическая орбита
            final bob = math.sin(angle * 2) * bobs[i % bobs.length];
            positions.add(Offset(center + dx, center + dy + bob));
          }

          final breathe =
              1.0 + 0.035 * math.sin(_animCtrl.value * 2 * math.pi);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Линии-связи: рисуются за обложками.
              Positioned.fill(
                child: CustomPaint(
                  painter: _ConstellationPainter(
                    center: Offset(center, center),
                    satellitePositions: positions,
                    color: (widget.glowColor ?? AppColors.neonPurple),
                  ),
                ),
              ),
              // Главная обложка — крупно в центре, с лёгким "дыханием".
              Positioned(
                left: center - (mainSize * breathe) / 2,
                top: center - (mainSize * breathe) / 2,
                width: mainSize * breathe,
                height: mainSize * breathe,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (widget.glowColor ?? AppColors.neonPurple)
                            .withValues(alpha: 0.3),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipOval(child: _cover(covers[0])),
                ),
              ),
              // Спутники летают по орбитам.
              for (var i = 0; i < satellites.length; i++)
                Positioned(
                  left: positions[i].dx - satSize / 2,
                  top: positions[i].dy - satSize / 2,
                  width: satSize,
                  height: satSize,
                  child: _satelliteCover(satellites[i], satSize),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final covers = widget.tracks
        .where((t) => t.coverPath != null)
        .map((t) => t.coverPath)
        .toList();
    if (covers.isEmpty && widget.tracks.isNotEmpty) {
      covers.add(null); // Fallback to mock cover if no covers at all
    }

    final simple = covers.length <= 1;

    return RepaintBoundary(
      child: SizedBox(
        width: widget.diameter,
        height: widget.diameter,
        // OverflowBox позволяет созвездию визуально выходить за пределы
        // отведённого диаметра без изменения занимаемого места в layout'е.
        child: simple
            ? Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: widget.glowColor != null
                ? [
              BoxShadow(
                color: widget.glowColor!.withValues(alpha: 0.4),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ]
                : null,
          ),
          child: ClipOval(
            child: covers.isEmpty
                ? _emptyState()
                : AnimatedBuilder(
              animation: _animCtrl,
              builder: (context, child) {
                final breathe = 1.0 +
                    0.05 *
                        math.sin(_animCtrl.value * 2 * math.pi);
                return Transform.scale(
                    scale: breathe, child: child);
              },
              child: _cover(covers[0]),
            ),
          ),
        )
            : OverflowBox(
          maxWidth: widget.diameter * 1.6,
          maxHeight: widget.diameter * 1.6,
          child: _buildConstellation(covers),
        ),
      ),
    );
  }
}

/// Рисует тонкие соединительные линии: от центра к каждому спутнику и между
/// соседними спутниками — лёгкий эффект "созвездия".
class _ConstellationPainter extends CustomPainter {
  _ConstellationPainter({
    required this.center,
    required this.satellitePositions,
    required this.color,
  });

  final Offset center;
  final List<Offset> satellitePositions;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (satellitePositions.isEmpty) return;

    final toCenterPaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final betweenPaint = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (final pos in satellitePositions) {
      canvas.drawLine(center, pos, toCenterPaint);
    }

    for (var i = 0; i < satellitePositions.length; i++) {
      final next = satellitePositions[(i + 1) % satellitePositions.length];
      if (satellitePositions.length > 1) {
        canvas.drawLine(satellitePositions[i], next, betweenPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ConstellationPainter oldDelegate) {
    return oldDelegate.satellitePositions != satellitePositions ||
        oldDelegate.center != center ||
        oldDelegate.color != color;
  }
}

// ── Playlist card ─────────────────────────────────────────────────────────────

class PlaylistCard extends ConsumerWidget {
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
}

// ── Create/Rename Playlist Sheet ──────────────────────────────────────────────

Future<void> showCreatePlaylistSheet(
    BuildContext context,
    WidgetRef ref, {
      String? initialName,
      String? playlistId,
    }) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) => UncontrolledProviderScope(
      container: ProviderScope.containerOf(context),
      child: _CreatePlaylistSheet(
        initialName: initialName,
        onCreated: (name, description) {
          if (playlistId != null) {
            ref.read(playlistsProvider.notifier).rename(playlistId, name);
          } else {
            ref.read(playlistsProvider.notifier).create(name);
          }
          Navigator.of(ctx).pop();
        },
      ),
    ),
  );
}

class _CreatePlaylistSheet extends StatefulWidget {
  const _CreatePlaylistSheet({this.initialName, required this.onCreated});

  final String? initialName;
  final void Function(String name, String description) onCreated;

  @override
  State<_CreatePlaylistSheet> createState() => _CreatePlaylistSheetState();
}

class _CreatePlaylistSheetState extends State<_CreatePlaylistSheet> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ClipRRect(
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      widget.initialName != null
                          ? 'ПЕРЕИМЕНОВАТЬ'
                          : 'НОВЫЙ ПЛЕЙЛИСТ',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white38,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 24,
                      right: 24,
                      top: 12,
                    ),
                    child: TextField(
                      controller: _nameCtrl,
                      autofocus: true,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Название...',
                        hintStyle: TextStyle(color: Colors.white24),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 24,
                      right: 24,
                      bottom: 16,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _GlassButton(
                            label: 'Отмена',
                            onTap: () => Navigator.of(context).pop(),
                            subtle: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _GlassButton(
                            label: widget.initialName != null
                                ? 'Сохранить'
                                : 'Создать',
                            onTap: () {
                              if (_nameCtrl.text.trim().isNotEmpty) {
                                widget.onCreated(
                                  _nameCtrl.text.trim(),
                                  '',
                                );
                              }
                            },
                            primary: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.subtle = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        borderRadius: 16,
        padding: const EdgeInsets.symmetric(vertical: 14),
        opacity: primary ? 0.15 : (subtle ? 0.0 : 0.05),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: subtle ? Colors.white38 : Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Playlist Detail Screen ────────────────────────────────────────────────────

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  const PlaylistDetailScreen({super.key, required this.playlist});
  final Playlist playlist;

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  late final ScrollController _scrollCtrl;
  bool _isCollapsed = false;
  bool _isReordering = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    _scrollCtrl.addListener(() {
      final isCollapsed = _scrollCtrl.offset > 260;
      if (isCollapsed != _isCollapsed) {
        setState(() => _isCollapsed = isCollapsed);
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncTracks = ref.watch(
      playlistTracksNotifierProvider(widget.playlist.id),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      body: ProtogenixBackground(
        child: asyncTracks.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: Colors.white24),
          ),
          // Само исключение пользователю не показываем (security.md, п. 3)
          error: (_, __) => Center(
            child: Text(
              'Не удалось открыть плейлист',
              style: TextStyle(color: Colors.white.withAlpha(150)),
            ),
          ),
          data: (tracks) => _buildContent(context, tracks),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<LibraryTrack> tracks) {
    return CustomScrollView(
      controller: _scrollCtrl,
      slivers: [
        SliverAppBar(
          expandedHeight: 320,
          pinned: true,
          stretch: true,
          backgroundColor: Colors.black.withValues(alpha: 0.4),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: AnimatedOpacity(
            opacity: _isCollapsed ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Text(
              widget.playlist.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          flexibleSpace: FlexibleSpaceBar(
            collapseMode: CollapseMode.parallax,
            background: _PlaylistHeroSection(
              playlist: widget.playlist,
              tracks: tracks,
            ),
          ),
        ),
        if (tracks.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
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
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          barrierColor: Colors.black.withValues(alpha: 0.5),
                          builder: (ctx) => UncontrolledProviderScope(
                            container: ProviderScope.containerOf(context),
                            child: FractionallySizedBox(
                              heightFactor: 0.8,
                              child: _AddTrackToPlaylistSheet(
                                playlistId: widget.playlist.id,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (tracks.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  const Text(
                    'ТРЕКИ',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => _isReordering = !_isReordering);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: _isReordering
                            ? AppColors.neonPurple.withAlpha(30)
                            : Colors.white.withAlpha(12),
                        border: Border.all(
                          color: _isReordering
                              ? AppColors.neonPurple.withAlpha(100)
                              : Colors.white.withAlpha(25),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isReordering
                                ? Icons.check_rounded
                                : Icons.swap_vert_rounded,
                            color: _isReordering
                                ? AppColors.neonPurple
                                : Colors.white60,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isReordering ? 'Готово' : 'Изменить порядок',
                            style: TextStyle(
                              color: _isReordering
                                  ? AppColors.neonPurple
                                  : Colors.white60,
                              fontSize: 12,
                              fontWeight: _isReordering
                                  ? FontWeight.w600
                                  : FontWeight.normal,
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
        if (tracks.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(
                    Icons.music_off_rounded,
                    size: 60,
                    color: Colors.white12,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Плейлист пуст',
                    style: TextStyle(color: Colors.white38, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Добавь треки из библиотеки',
                    style: TextStyle(color: Colors.white24, fontSize: 13),
                  ),
                ],
              ).animate().fadeIn(duration: 400.ms),
            ),
          )
        else
          SliverToBoxAdapter(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorder: (oldIndex, newIndex) {
                ref
                    .read(
                  playlistTracksNotifierProvider(
                    widget.playlist.id,
                  ).notifier,
                )
                    .reorder(oldIndex, newIndex);
              },
              itemCount: tracks.length,
              itemBuilder: (context, i) {
                return _ReorderableTrackTile(
                  key: ValueKey(tracks[i].id),
                  track: tracks[i],
                  index: i,
                  allTracks: tracks,
                  playlistId: widget.playlist.id,
                  isReordering: _isReordering,
                  onRemove: () => ref
                      .read(
                    playlistTracksNotifierProvider(
                      widget.playlist.id,
                    ).notifier,
                  )
                      .remove(tracks[i].id),
                );
              },
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }
}

class _PlaylistHeroSection extends StatelessWidget {
  const _PlaylistHeroSection({required this.playlist, required this.tracks});
  final Playlist playlist;
  final List<LibraryTrack> tracks;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ProtogenixBackground(child: SizedBox())),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 40),
              _PlaylistCoverCollage(
                tracks: tracks,
                diameter: 160,
                animate: true,
                glowColor: AppColors.neonPurple,
              ),
              const SizedBox(height: 20),
              Text(
                playlist.name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              Text(
                '${tracks.length} треков',
                style: const TextStyle(fontSize: 13, color: Colors.white38),
              ),
            ],
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0),
                  const Color(0xFF080810)
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        borderRadius: 16,
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reorderable Track Tile ────────────────────────────────────────────────────

class _ReorderableTrackTile extends ConsumerWidget {
  const _ReorderableTrackTile({
    super.key,
    required this.track,
    required this.index,
    required this.allTracks,
    required this.playlistId,
    required this.isReordering,
    required this.onRemove,
  });

  final LibraryTrack track;
  final int index;
  final List<LibraryTrack> allTracks;
  final String playlistId;
  final bool isReordering;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final isPlaying = player.currentTrack?.id == track.id;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (isReordering)
            ReorderableDragStartListener(
              index: index,
              child: const Icon(
                Icons.drag_handle_rounded,
                color: Colors.white38,
                size: 20,
              ),
            )
          else
            SizedBox(
              width: 24,
              child: Text(
                '${index + 1}',
                style: const TextStyle(color: Colors.white24, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(width: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image(
              image: track.coverPath != null
                  ? FileImage(File(track.coverPath!)) as ImageProvider
                  : kCoverPlaceholder,
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
          if (!isReordering)
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
    );

    return Dismissible(
      key: ValueKey('dismiss_${track.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        HapticFeedback.mediumImpact();
        onRemove();
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Colors.red.withValues(alpha: 0.15),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: Colors.redAccent,
          size: 24,
        ),
      ),
      child: isReordering
          ? content
          : InkWell(
        onTap: () {
          final models = allTracks.map((t) => t.toTrackModel()).toList();
          ref
              .read(playerProvider.notifier)
              .loadPlaylist(models, initialIndex: index);
          ref.read(playerProvider.notifier).play();
        },
        child: content,
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
                    // This updates DB and cache in PlaylistTracksNotifier
                    ref
                        .read(
                        playlistTracksNotifierProvider(playlistId).notifier)
                        .remove(track.id);
                    // Also invalidate standard cache for cards
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

class _AddTrackToPlaylistSheet extends ConsumerStatefulWidget {
  const _AddTrackToPlaylistSheet({required this.playlistId});
  final String playlistId;

  @override
  ConsumerState<_AddTrackToPlaylistSheet> createState() => _AddTrackToPlaylistSheetState();
}

class _AddTrackToPlaylistSheetState extends ConsumerState<_AddTrackToPlaylistSheet> {
  List<LibraryTrack>? _allTracks;

  /// Уже в плейлисте или добавлены сейчас — с галочкой. Раньше нажатие «+»
  /// ничего не показывало, и трек добавляли по нескольку раз.
  final _added = <String>{};

  @override
  void initState() {
    super.initState();
    _loadAllTracks();
  }

  Future<void> _loadAllTracks() async {
    final db = LibraryDatabase.instance;
    final tracks = await db.getAllTracks();
    final inPlaylist = ref
            .read(playlistTracksNotifierProvider(widget.playlistId))
            .valueOrNull ??
        const <LibraryTrack>[];
    if (!mounted) return;
    setState(() {
      _allTracks = tracks;
      _added.addAll(inPlaylist.map((t) => t.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(paletteProvider.select((p) => p.primary));
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.78),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Text(
                        'ДОБАВИТЬ ТРЕКИ',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white38,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(color: Colors.white12, height: 1),
                Expanded(
                  child: _allTracks == null
                      ? const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white24,
                    ),
                  )
                      : _allTracks!.isEmpty
                      ? const Center(
                    child: Text(
                      'Библиотека пуста',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                      : ListView.builder(
                    itemCount: _allTracks!.length,
                    itemBuilder: (context, index) {
                      final track = _allTracks![index];
                      final added = _added.contains(track.id);
                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image(
                            image: track.toTrackModel().coverImage,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                          ),
                        ),
                        title: Text(
                          track.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          track.artist,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            added
                                ? Icons.check_circle_rounded
                                : Icons.add_circle_outline_rounded,
                            color: added ? accent : Colors.white38,
                          ),
                          onPressed: () {
                            if (added) return;
                            ref
                                .read(playlistTracksNotifierProvider(
                                widget.playlistId)
                                .notifier)
                                .add(track.id);
                            HapticFeedback.lightImpact();
                            setState(() => _added.add(track.id));
                          },
                        ),
                      );
                    },
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