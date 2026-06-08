import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../player/presentation/widgets/glass_card.dart';
import 'package:file_picker/file_picker.dart';
import '../data/importer_service.dart';
import '../../library/presentation/library_provider.dart';
import '../../player/presentation/providers/player_provider.dart';

class ImporterSheet extends ConsumerStatefulWidget {
  const ImporterSheet({super.key});

  @override
  ConsumerState<ImporterSheet> createState() => _ImporterSheetState();
}

enum _ImportMode { selection, input, local }

enum _Service { none, youtube, spotify, yandex }

class _ImporterSheetState extends ConsumerState<ImporterSheet> {
  _ImportMode _mode = _ImportMode.selection;
  _Service _selectedService = _Service.none;

  final _controller = TextEditingController();
  ImportProgress _progress = ImportProgress.idle;
  bool _isImporting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _startImport() async {
    final url = _controller.text.trim();
    if (url.isEmpty) return;

    setState(() => _isImporting = true);
    FocusScope.of(context).unfocus();

    await ImporterService.instance.importFromUrl(
      url: url,
      onProgress: (progress) {
        if (mounted) setState(() => _progress = progress);
      },
    );

    if (_progress.status == ImportStatus.done) {
      // Обновляем библиотеку и перезагружаем плеер
      ref.read(libraryProvider.notifier).reload();
      ref.read(playerProvider.notifier).reloadFromLibrary();
      _controller.clear();
    }

    if (mounted) setState(() => _isImporting = false);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(200),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withAlpha(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ручка (Drag handle)
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 20),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              Flexible(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      0,
                      24,
                      MediaQuery.of(context).viewInsets.bottom +
                          MediaQuery.of(context).padding.bottom +
                          24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ИМПОРТ ТРЕКА',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Colors.white38,
                                    letterSpacing: 3,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (_mode != _ImportMode.selection)
                              IconButton(
                                icon: const Icon(Icons.arrow_back_rounded,
                                    color: Colors.white),
                                onPressed: () {
                                  setState(() {
                                    _mode = _ImportMode.selection;
                                    _selectedService = _Service.none;
                                    _progress = ImportProgress.idle;
                                    _controller.clear();
                                  });
                                },
                              ),
                            Expanded(
                              child: Text(
                                _mode == _ImportMode.selection
                                    ? 'Выбери источник'
                                    : _selectedService == _Service.youtube
                                        ? 'Импорт из YouTube'
                                        : _selectedService == _Service.spotify
                                            ? 'Импорт из Spotify'
                                            : 'Импорт из Яндекс.Музыки',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      color: Colors.white,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Поле ввода
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: _mode == _ImportMode.selection
                              ? _buildSelectionGrid()
                              : Column(
                                  key: const ValueKey('input_mode'),
                                  children: [
                                    // Поле ввода
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        color: Colors.white.withAlpha(10),
                                        border: Border.all(
                                            color: Colors.white.withAlpha(25)),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: _controller,
                                              style: const TextStyle(
                                                  color: Colors.white),
                                              decoration: InputDecoration(
                                                hintText: _selectedService ==
                                                        _Service.youtube
                                                    ? 'https://youtube.com/watch?v=...'
                                                    : _selectedService ==
                                                            _Service.spotify
                                                        ? 'https://open.spotify.com/track/...'
                                                        : 'https://music.yandex.ru/album/...',
                                                hintStyle: const TextStyle(
                                                    color: Colors.white24),
                                                border: InputBorder.none,
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 14,
                                                ),
                                              ),
                                              onSubmitted: (_) =>
                                                  _startImport(),
                                            ),
                                          ),
                                          // Кнопка вставить
                                          IconButton(
                                            icon: const Icon(
                                              Icons.content_paste_rounded,
                                              color: Colors.white38,
                                            ),
                                            onPressed: () async {
                                              final data =
                                                  await Clipboard.getData(
                                                'text/plain',
                                              );
                                              if (data?.text != null) {
                                                _controller.text = data!.text!;
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 16),

// Кнопка импорт
                                    SizedBox(
                                      width: double.infinity,
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 300),
                                        child: ElevatedButton(
                                          onPressed: _isImporting
                                              ? null
                                              : _startImport,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _selectedService ==
                                                    _Service.youtube
                                                ? Colors.redAccent
                                                : _selectedService ==
                                                        _Service.spotify
                                                    ? const Color(0xFF1DB954)
                                                    : const Color(0xFFFFCC00),
                                            foregroundColor: _selectedService ==
                                                    _Service.yandex
                                                ? Colors.black
                                                : Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 16),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                            elevation: 0,
                                          ),
                                          child: _isImporting
                                              ? SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                    color: _selectedService ==
                                                            _Service.yandex
                                                        ? Colors.black
                                                        : Colors.white,
                                                    strokeWidth: 2,
                                                  ),
                                                )
                                              : const Text(
                                                  'Импортировать',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),

                        if (_progress.status != ImportStatus.idle) ...[
                          const SizedBox(height: 16),
                          _buildProgress().animate().fadeIn(duration: 300.ms),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickLocalFiles() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.any,
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final paths = result.files
            .where((f) => f.path != null)
            .map((f) => f.path!)
            .where((p) =>
                p.endsWith('.mp3') ||
                p.endsWith('.flac') ||
                p.endsWith('.m4a') ||
                p.endsWith('.wav'))
            .toList();

        if (paths.isNotEmpty) {
          setState(() => _isImporting = true);

          await ImporterService.instance.importLocalFiles(
            paths: paths,
            onProgress: (progress) {
              if (mounted) setState(() => _progress = progress);
            },
          );

          if (_progress.status == ImportStatus.done) {
            ref.read(libraryProvider.notifier).reload();
            ref.read(playerProvider.notifier).reloadFromLibrary();
          }

          if (mounted) setState(() => _isImporting = false);
        }
      }
    } catch (e) {
      debugPrint('Ошибка выбора файлов: $e');
      if (mounted) {
        setState(() {
          _progress = const ImportProgress(
            status: ImportStatus.error,
            message: 'Ошибка выбора файлов',
            error: 'Произошла ошибка при обработке файлов',
          );
        });
      }
    }
  }

  Widget _buildSelectionGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.3,
      padding: EdgeInsets.zero,
      children: [
        _buildServiceCard('YouTube', Icons.play_arrow_rounded, Colors.redAccent,
            () {
          setState(() {
            _mode = _ImportMode.input;
            _selectedService = _Service.youtube;
          });
        }),
        _buildServiceCard(
            'Spotify', Icons.music_note_rounded, const Color(0xFF1DB954), () {
          setState(() {
            _mode = _ImportMode.input;
            _selectedService = _Service.spotify;
          });
        }),
        _buildServiceCard(
            'Yandex', Icons.library_music_rounded, const Color(0xFFFFCC00), () {
          setState(() {
            _mode = _ImportMode.input;
            _selectedService = _Service.yandex;
          });
        }),
        _buildServiceCard(
            'Локальные', Icons.folder_rounded, const Color(0xFF7B5EA7), () {
          _pickLocalFiles();
        }),
      ],
    );
  }

  Widget _buildServiceCard(
      String title, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha(15),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: GlassCard(
          borderRadius: 20.0,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withAlpha(10),
              border: Border.all(color: color.withAlpha(40)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 36),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgress() {
    final isError = _progress.status == ImportStatus.error;
    final isDone = _progress.status == ImportStatus.done;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isError
            ? Colors.red.withAlpha(20)
            : isDone
                ? Colors.green.withAlpha(20)
                : Colors.white.withAlpha(8),
        border: Border.all(
          color: isError
              ? Colors.red.withAlpha(60)
              : isDone
                  ? Colors.green.withAlpha(60)
                  : Colors.white.withAlpha(15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : isDone
                        ? Icons.check_circle_outline_rounded
                        : Icons.downloading_rounded,
                color: isError
                    ? Colors.redAccent
                    : isDone
                        ? Colors.greenAccent
                        : Colors.white60,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isError
                      ? (_progress.error ?? _progress.message)
                      : _progress.message,
                  style: TextStyle(
                    color: isError
                        ? Colors.redAccent
                        : isDone
                            ? Colors.greenAccent
                            : Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          if (!isError && !isDone) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress.progress,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation(Color(0xFF7B5EA7)),
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Открыть импортёр как bottom sheet
void showImporterSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const ImporterSheet(),
  );
}
