import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protogenix/features/library/domain/library_track.dart';
import 'package:protogenix/features/library/data/library_database.dart';
import 'package:protogenix/features/library/presentation/library_provider.dart';
import 'package:protogenix/features/player/presentation/providers/player_provider.dart';
import 'package:protogenix/features/player/presentation/providers/palette_provider.dart';

void showTrackEditSheet(
    BuildContext context, WidgetRef ref, LibraryTrack track) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _TrackEditSheet(track: track),
  );
}

class _TrackEditSheet extends ConsumerStatefulWidget {
  const _TrackEditSheet({required this.track});
  final LibraryTrack track;

  @override
  ConsumerState<_TrackEditSheet> createState() => _TrackEditSheetState();
}

class _TrackEditSheetState extends ConsumerState<_TrackEditSheet> {
  late TextEditingController _titleController;
  late TextEditingController _artistController;
  late TextEditingController _albumController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.track.title);
    _artistController = TextEditingController(text: widget.track.artist);
    _albumController = TextEditingController(text: widget.track.album);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    HapticFeedback.lightImpact();
    final updatedTrack = widget.track.copyWith(
      title: _titleController.text.trim(),
      artist: _artistController.text.trim(),
      album: _albumController.text.trim(),
    );

    await LibraryDatabase.instance.updateTrack(updatedTrack);
    await ref.read(libraryProvider.notifier).reload();
    await ref.read(playerProvider.notifier).reloadFromLibrary();

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = ref.watch(paletteProvider).primary;
    final viewInsets = MediaQuery.of(context).viewInsets;
    final paddingBottom = MediaQuery.of(context).padding.bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(200),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: Colors.white.withAlpha(20))),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              bottom: viewInsets.bottom > 0
                  ? viewInsets.bottom + 20
                  : paddingBottom + 40,
              top: 0,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 24),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(40),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Text(
                    'РЕДАКТОР',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildTextField('Название', _titleController, accentColor),
                  const SizedBox(height: 16),
                  _buildTextField(
                      'Исполнитель', _artistController, accentColor),
                  const SizedBox(height: 16),
                  _buildTextField('Альбом', _albumController, accentColor),
                  const SizedBox(height: 32),
                  GestureDetector(
                    onTap: _save,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(20),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withAlpha(30)),
                      ),
                      child: const Center(
                        child: Text(
                          'Сохранить',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
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

  Widget _buildTextField(
      String label, TextEditingController controller, Color accentColor) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      cursorColor: accentColor,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withAlpha(15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withAlpha(30)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accentColor.withAlpha(180)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withAlpha(30)),
        ),
      ),
    );
  }
}
