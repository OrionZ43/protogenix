// lib/features/importer/presentation/desktop_drop_import.dart
//
// Перетаскивание своих файлов и папок из Проводника в окно (ПК) — просили
// в отзывах вместо выбора через диалог. desktop_drop на Windows — один C++
// файл без Rust (dependencies.md). Импорт идёт в фоне через ImportManager,
// прогресс показывает общая плашка (import_status_overlay.dart).

import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/glass_panel.dart';
import '../../player/presentation/providers/palette_provider.dart';
import '../data/local_tags.dart';
import 'import_manager.dart';

class DesktopDropImport extends ConsumerStatefulWidget {
  const DesktopDropImport({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DesktopDropImport> createState() => _DesktopDropImportState();
}

class _DesktopDropImportState extends ConsumerState<DesktopDropImport> {
  bool _hover = false;

  Future<void> _onDrop(List<String> paths) async {
    setState(() => _hover = false);
    final messenger = ScaffoldMessenger.of(context);
    // Пока идёт другой импорт, этот встанет в очередь (import_manager.dart)
    final manager = ref.read(importManagerProvider.notifier);
    final files = await collectAudioFiles(paths);
    if (!mounted) return;
    if (files.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Здесь нет аудиофайлов — подойдут mp3, m4a, flac, '
              'ogg, opus, wav')));
      return;
    }
    unawaited(manager.importLocalFiles(files));
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _hover = true),
      onDragExited: (_) => setState(() => _hover = false),
      onDragDone: (details) =>
          _onDrop([for (final item in details.files) item.path]),
      child: Stack(
        children: [
          widget.child,
          if (_hover)
            const Positioned.fill(child: IgnorePointer(child: _DropHint())),
        ],
      ),
    );
  }
}

/// Подсказка поверх окна, пока над ним держат файлы: тёмное стекло с рамкой
/// в цвет обложки.
class _DropHint extends ConsumerWidget {
  const _DropHint();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(paletteProvider.select((p) => p.primary));
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GlassPanel(
        borderRadius: 28,
        alpha: 170,
        borderColor: accent.withAlpha(160),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withAlpha(40),
                ),
                child:
                    Icon(Icons.file_download_outlined, color: accent, size: 34),
              ),
              const SizedBox(height: 18),
              const Text(
                'ОТПУСТИ, ЧТОБЫ ДОБАВИТЬ',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'В медиатеку',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Файлы и папки: mp3, m4a, flac, ogg, opus, wav',
                style: TextStyle(
                  color: Colors.white.withAlpha(130),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
