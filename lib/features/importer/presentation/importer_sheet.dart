import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/importer_service.dart';
import '../../library/presentation/library_provider.dart';
import '../../player/presentation/providers/player_provider.dart';

class ImporterSheet extends ConsumerStatefulWidget {
  const ImporterSheet({super.key});

  @override
  ConsumerState<ImporterSheet> createState() => _ImporterSheetState();
}

class _ImporterSheetState extends ConsumerState<ImporterSheet> {
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
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ручка
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

          Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              0,
              24,
              MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ИМПОРТ ТРЕКА',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white38,
                        letterSpacing: 3,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Вставь ссылку',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'YouTube, прямые ссылки на MP3/FLAC',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white38,
                      ),
                ),

                const SizedBox(height: 24),

                // Поле ввода
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.white.withAlpha(10),
                    border: Border.all(color: Colors.white.withAlpha(25)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'https://youtube.com/watch?v=...',
                            hintStyle: TextStyle(color: Colors.white24),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                          onSubmitted: (_) => _startImport(),
                        ),
                      ),
                      // Кнопка вставить
                      IconButton(
                        icon: const Icon(
                          Icons.content_paste_rounded,
                          color: Colors.white38,
                        ),
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data?.text != null) {
                            _controller.text = data!.text!;
                          }
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Прогресс
                if (_progress.status != ImportStatus.idle)
                  _buildProgress().animate().fadeIn(duration: 300.ms),

                const SizedBox(height: 16),

                // Кнопка импорт
                SizedBox(
                  width: double.infinity,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    child: ElevatedButton(
                      onPressed: _isImporting ? null : _startImport,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7B5EA7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _isImporting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
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
        ],
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
