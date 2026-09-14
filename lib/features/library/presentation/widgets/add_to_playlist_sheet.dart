// lib/features/library/presentation/widgets/add_to_playlist_sheet.dart
//
// «В плейлист» — для одного трека (меню «⋮», кнопка в плеере) и для
// выделенных в медиатеке. Новый плейлист создаётся прямо здесь и сразу
// получает треки: раньше «Создать новый плейлист» открывал отдельную шторку,
// и трек в новый плейлист не попадал.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/chip_button.dart';
import '../../../player/presentation/providers/palette_provider.dart';
import '../../data/playlist_database.dart';
import '../playlist_provider.dart';

/// true — треки добавлены. [container] — если шторку открывают из уже
/// закрытой шторки (меню «⋮»): её контекст к этому моменту без ProviderScope.
Future<bool> showAddToPlaylistSheet(
  BuildContext context,
  List<String> trackIds, {
  ProviderContainer? container,
}) async {
  if (trackIds.isEmpty) return false;
  final added = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => UncontrolledProviderScope(
      container: container ?? ProviderScope.containerOf(context),
      child: _AddToPlaylistSheet(trackIds: trackIds),
    ),
  );
  return added ?? false;
}

/// «1 трек», «2 трека», «5 треков».
String tracksWord(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return 'трек';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return 'трека';
  }
  return 'треков';
}

class _AddToPlaylistSheet extends ConsumerStatefulWidget {
  const _AddToPlaylistSheet({required this.trackIds});
  final List<String> trackIds;

  @override
  ConsumerState<_AddToPlaylistSheet> createState() =>
      _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends ConsumerState<_AddToPlaylistSheet> {
  final _nameCtrl = TextEditingController();
  bool _naming = false;
  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _addTo(String playlistId, String name) async {
    if (_busy) return;
    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    final added = await PlaylistDatabase.instance.addTracksToPlaylist(
      playlistId: playlistId,
      trackIds: widget.trackIds,
    );
    ref.invalidate(playlistTracksProvider(playlistId));
    ref.invalidate(playlistTracksNotifierProvider(playlistId));
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(true);
    messenger.showSnackBar(SnackBar(content: Text(_result(name, added))));
  }

  String _result(String name, int added) {
    final total = widget.trackIds.length;
    if (total == 1) {
      return added == 1 ? 'Добавлено в «$name»' : 'Трек уже есть в «$name»';
    }
    final base = 'В «$name» добавлено $added ${tracksWord(added)}';
    return added == total ? base : '$base, остальные там уже были';
  }

  Future<void> _createAndAdd() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _busy) return;
    final playlist = await ref.read(playlistsProvider.notifier).create(name);
    await _addTo(playlist.id, playlist.name);
  }

  @override
  Widget build(BuildContext context) {
    final playlists = ref.watch(playlistsProvider);
    final count = widget.trackIds.length;
    final accent = ref.watch(paletteProvider.select((p) => p.primary));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(200),
              border:
                  Border(top: BorderSide(color: Colors.white.withAlpha(30))),
            ),
            child: SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.75),
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
                    // Подпись капсом и заголовок — как у остальных шторок
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'В ПЛЕЙЛИСТ',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              count == 1
                                  ? 'Куда добавить трек?'
                                  : 'Куда добавить $count ${tracksWord(count)}?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_naming)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: Colors.white.withAlpha(10),
                                  border: Border.all(
                                      color: Colors.white.withAlpha(25)),
                                ),
                                child: TextField(
                                  controller: _nameCtrl,
                                  autofocus: true,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _createAndAdd(),
                                  cursorColor: accent,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 15),
                                  decoration: const InputDecoration(
                                    hintText: 'Название нового плейлиста',
                                    hintStyle:
                                        TextStyle(color: Colors.white38),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 13),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ChipButton(
                              label: 'Создать',
                              accent: accent,
                              onTap: _busy ? null : _createAndAdd,
                            ),
                          ],
                        ),
                      )
                    else
                      _SheetItem(
                        icon: Icons.add_circle_outline_rounded,
                        iconColor: accent,
                        label: 'Новый плейлист',
                        onTap: () => setState(() => _naming = true),
                      ),
                    if (playlists.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Плейлистов пока нет',
                          style: TextStyle(color: Colors.white38, fontSize: 14),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          children: [
                            for (final playlist in playlists)
                              _SheetItem(
                                icon: Icons.queue_music_rounded,
                                label: playlist.name,
                                onTap: () => _addTo(playlist.id, playlist.name),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
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

class _SheetItem extends StatelessWidget {
  const _SheetItem({
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
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
