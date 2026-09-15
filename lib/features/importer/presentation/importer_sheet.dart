import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../data/device_music.dart';
import '../data/importer_service.dart';
import '../data/local_tags.dart';
import 'import_manager.dart';
import '../../../core/services/android_permissions.dart';
import '../../../core/widgets/accent_button.dart';
import '../../../core/widgets/chip_button.dart';
import '../../player/presentation/providers/palette_provider.dart';

class ImporterSheet extends ConsumerStatefulWidget {
  const ImporterSheet({super.key});

  @override
  ConsumerState<ImporterSheet> createState() => _ImporterSheetState();
}

class _ImporterSheetState extends ConsumerState<ImporterSheet> {
  final _controller = TextEditingController();
  /// Сообщение до начала импорта: нет доступа, нечего импортировать. Сам
  /// импорт идёт в фоне, его прогресс — у ImportManager (import_manager.dart).
  ImportProgress? _notice;
  bool _scanning = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startImport() {
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    FocusScope.of(context).unfocus();
    _controller.clear();
    setState(() => _notice = null);
    // Импорт идёт в фоне: шторку можно закрыть, прогресс останется на плашке
    ref.read(importManagerProvider.notifier).importUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(paletteProvider).primary;
    final job = ref.watch(importManagerProvider);
    final running = job?.running ?? false;
    // Пока идёт импорт, новый встаёт в очередь (import_manager.dart)
    final queued = job?.queue.length ?? 0;

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
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white38, letterSpacing: 3),
                        ),
                        const SizedBox(height: 8),
                        Text('Добавить трек', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white)),
                        const SizedBox(height: 24),

                        // Поле ввода ссылки
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
                                  cursorColor: accent,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: const InputDecoration(
                                    hintText: 'Вставь ссылку: YouTube, Spotify, Яндекс.Музыка...',
                                    hintStyle: TextStyle(color: Colors.white24),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  ),
                                  onSubmitted: (_) => _startImport(),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.content_paste_rounded, color: Colors.white38),
                                onPressed: () async {
                                  final data = await Clipboard.getData('text/plain');
                                  if (data?.text != null) _controller.text = data!.text!;
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Кнопка импорта — единый акцентный цвет
                        AccentButton(
                          label: running
                              ? 'Добавить в очередь'
                              : 'Импортировать',
                          icon: running ? Icons.playlist_add_rounded : null,
                          accent: accent,
                          onTap: _startImport,
                        ),

                        const SizedBox(height: 24),
                        Divider(color: Colors.white.withAlpha(15)),
                        const SizedBox(height: 12),

                        // Локальные файлы — обычный пункт списка, без цветных карточек
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: _pickLocalFiles,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withAlpha(15),
                                  ),
                                  child: const Icon(Icons.folder_rounded, color: Colors.white70, size: 20),
                                ),
                                const SizedBox(width: 14),
                                const Text('Добавить локальные файлы', style: TextStyle(color: Colors.white, fontSize: 15)),
                              ],
                            ),
                          ),
                        ),

                        // Вся музыка телефона — только Android (MediaStore)
                        if (Platform.isAndroid)
                          InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: _scanning ? null : _scanDevice,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white.withAlpha(15),
                                    ),
                                    child: const Icon(Icons.phone_android_rounded, color: Colors.white70, size: 20),
                                  ),
                                  const SizedBox(width: 14),
                                  const Expanded(
                                    child: Text('Найти музыку на телефоне', style: TextStyle(color: Colors.white, fontSize: 15)),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        if (job != null) ...[
                          const SizedBox(height: 16),
                          _buildProgress(job.progress, accent).animate().fadeIn(duration: 300.ms),
                          if (job.running) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    queued == 0
                                        ? 'Импорт идёт в фоне — шторку можно закрыть'
                                        : 'Импорт идёт в фоне, ещё $queued в очереди — '
                                            'шторку можно закрыть',
                                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ChipButton(
                                  icon: Icons.keyboard_arrow_down_rounded,
                                  label: 'Свернуть',
                                  onTap: () => Navigator.of(context).pop(),
                                ),
                              ],
                            ),
                          ],
                        ] else if (_notice != null) ...[
                          const SizedBox(height: 16),
                          _buildProgress(_notice!, accent).animate().fadeIn(duration: 300.ms),
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

  /// Вся музыка телефона (Android): список из MediaStore, файлы не копируются.
  /// Сам импорт идёт в фоне — через ImportManager, как и остальные.
  Future<void> _scanDevice() async {
    setState(() => _notice = null);
    final status = await DeviceMusic.requestPermission();
    if (!status.isGranted && !status.isLimited) {
      if (status.isPermanentlyDenied) await openAndroidAppSettings();
      if (mounted) {
        setState(() => _notice = const ImportProgress(
              status: ImportStatus.error,
              message: 'Нет доступа к музыке на телефоне',
              error: 'Разреши Protogenix доступ к аудио в настройках '
                  'телефона, раздел «Разрешения».',
            ));
      }
      return;
    }

    setState(() => _scanning = true);
    try {
      final tracks = await DeviceMusic.query();
      if (!mounted) return;
      if (tracks.isEmpty) {
        setState(() => _notice = const ImportProgress(
              status: ImportStatus.error,
              message: 'Музыки на телефоне не нашлось',
              error: 'Ищется всё, что Android считает музыкой, '
                  'не короче 30 секунд.',
            ));
        return;
      }
      ref.read(importManagerProvider.notifier).importDeviceTracks(tracks);
    } catch (e) {
      debugPrint('Ошибка поиска музыки на телефоне: $e');
      if (mounted) {
        setState(() => _notice = const ImportProgress(
              status: ImportStatus.error,
              message: 'Не удалось найти музыку',
              error: 'Не получилось прочитать медиатеку телефона.',
            ));
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _pickLocalFiles() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.any,
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;

      final paths = result.files
          .where((f) => f.path != null)
          .map((f) => f.path!)
          // Регистр не важен (.MP3), форматы — все, что умеет плеер
          .where((path) => kLocalAudioExtensions
              .any((ext) => path.toLowerCase().endsWith(ext)))
          .toList();
      if (paths.isEmpty) {
        setState(() => _notice = const ImportProgress(
              status: ImportStatus.error,
              message: 'Среди выбранных нет аудиофайлов',
              error: 'Подойдут mp3, m4a, flac, ogg, opus, aac и wav.',
            ));
        return;
      }
      setState(() => _notice = null);
      ref.read(importManagerProvider.notifier).importLocalFiles(paths);
    } catch (e) {
      debugPrint('Ошибка выбора файлов: $e');
      if (mounted) {
        setState(() => _notice = const ImportProgress(
              status: ImportStatus.error,
              message: 'Ошибка выбора файлов',
              error: 'Произошла ошибка при обработке файлов',
            ));
      }
    }
  }
  Widget _buildProgress(ImportProgress progress, Color accent) {
    final isError = progress.status == ImportStatus.error;
    final isDone = progress.status == ImportStatus.done;
    // Успех — в цвет обложки, как везде в приложении (было зелёным);
    // ошибка — красным
    final color = isError ? Colors.redAccent : accent;
    final tinted = isError || isDone;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: tinted ? color.withAlpha(24) : Colors.white.withAlpha(8),
        border: Border.all(
          color: tinted ? color.withAlpha(80) : Colors.white.withAlpha(15),
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
                color: tinted ? color : Colors.white60,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  importText(progress),
                  style: TextStyle(
                    color: isError
                        ? Colors.redAccent
                        : Colors.white.withAlpha(isDone ? 230 : 180),
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
                value: progress.progress,
                backgroundColor: Colors.white12,
                color: accent,
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
