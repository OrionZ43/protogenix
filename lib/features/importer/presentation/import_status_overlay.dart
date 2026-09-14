// lib/features/importer/presentation/import_status_overlay.dart
//
// Плашка фонового импорта поверх всего приложения (MaterialApp.builder —
// над экранами и шторками): откуда импорт, что сейчас происходит, прогресс,
// «Остановить». Нажатие сворачивает её в одну строку. После запуска
// предлагает продолжить импорт, оборвавшийся при закрытии приложения.
//
// Вид — как у баннера обновления (update_banner.dart): тёмное стекло, рамка и
// иконка в цвет обложки, подпись капсом. Tooltip здесь не использовать:
// плашка лежит над Navigator, своего Overlay у неё нет, и подсказка при
// наведении падает с ошибкой.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/chip_button.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../player/presentation/providers/palette_provider.dart';
import '../data/importer_service.dart';
import 'import_manager.dart';

class ImportStatusOverlay extends ConsumerStatefulWidget {
  const ImportStatusOverlay({super.key});

  @override
  ConsumerState<ImportStatusOverlay> createState() =>
      _ImportStatusOverlayState();
}

class _ImportStatusOverlayState extends ConsumerState<ImportStatusOverlay> {
  String? _interruptedUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final url =
          await ref.read(importManagerProvider.notifier).interruptedUrl();
      if (mounted && url != null) setState(() => _interruptedUrl = url);
    });
  }

  void _resume() {
    final url = _interruptedUrl;
    setState(() => _interruptedUrl = null);
    if (url != null) ref.read(importManagerProvider.notifier).importUrl(url);
  }

  void _forget() {
    setState(() => _interruptedUrl = null);
    ref.read(importManagerProvider.notifier).forgetInterrupted();
  }

  @override
  Widget build(BuildContext context) {
    final job = ref.watch(importManagerProvider);
    final Widget card;
    if (job != null) {
      card = _JobCard(job: job);
    } else if (_interruptedUrl != null) {
      card = _ResumeCard(onResume: _resume, onForget: _forget);
    } else {
      return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
    }

    final desktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final width = math.min(420.0, screenWidth - 24);
    return Positioned(
      // На ПК — справа под строкой заголовка, на телефоне — сверху по центру
      top: desktop ? 52 : MediaQuery.paddingOf(context).top + 6,
      left: desktop ? null : (screenWidth - width) / 2,
      right: desktop ? 16 : null,
      width: width,
      child: Material(type: MaterialType.transparency, child: card),
    );
  }
}

class _JobCard extends ConsumerStatefulWidget {
  const _JobCard({required this.job});

  final ImportJob job;

  @override
  ConsumerState<_JobCard> createState() => _JobCardState();
}

class _JobCardState extends ConsumerState<_JobCard> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final progress = job.progress;
    final error = progress.status == ImportStatus.error;
    // Остановлен ограничением YouTube — ссылку предложат продолжить
    final paused = !job.running && progress.resumable;
    final accent = ref.watch(paletteProvider.select((p) => p.primary));
    final color = error ? Colors.redAccent : accent;
    final manager = ref.read(importManagerProvider.notifier);
    final value = progress.progress.clamp(0.0, 1.0).toDouble();

    final (IconData icon, String caption) = job.running
        ? (
            Icons.downloading_rounded,
            job.stopping
                ? 'ОСТАНАВЛИВАЮ…'
                : job.queue.isEmpty
                    ? 'ИМПОРТ'
                    : 'ИМПОРТ · ЕЩЁ ${job.queue.length} В ОЧЕРЕДИ',
          )
        : error
            ? (Icons.error_outline_rounded, 'НЕ ПОЛУЧИЛОСЬ')
            : paused
                ? (Icons.pause_rounded, 'ИМПОРТ НА ПАУЗЕ')
                : (Icons.check_rounded, 'ИМПОРТ ЗАВЕРШЁН');

    return GestureDetector(
      onTap: () => setState(() => _collapsed = !_collapsed),
      child: GlassPanel(
        borderColor: color.withAlpha(80),
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _StatusIcon(icon: icon, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: _Heading(
                    caption: caption,
                    title: progress.label ?? job.title,
                    color: color,
                  ),
                ),
                const SizedBox(width: 8),
                if (job.running)
                  // Останавливает и очередь (import_manager.dart)
                  ChipButton(
                    icon: Icons.stop_rounded,
                    label: job.queue.isEmpty ? 'Остановить' : 'Остановить всё',
                    onTap: job.stopping ? null : manager.stop,
                  )
                else
                  GestureDetector(
                    onTap: manager.dismiss,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.close_rounded,
                          color: Colors.white38, size: 18),
                    ),
                  ),
              ],
            ),
            if (!_collapsed || !job.running) ...[
              const SizedBox(height: 10),
              Text(
                importText(progress),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: error
                      ? Colors.redAccent.withAlpha(230)
                      : Colors.white.withAlpha(170),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
            if (job.running) ...[
              const SizedBox(height: 10),
              // Процентов рядом нет: в тексте уже «37 из 500», а проценты
              // текущего трека рядом с общими только путали
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: value > 0 ? value : null,
                  minHeight: 4,
                  color: accent,
                  backgroundColor: Colors.white12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResumeCard extends ConsumerWidget {
  const _ResumeCard({required this.onResume, required this.onForget});

  final VoidCallback onResume;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(paletteProvider.select((p) => p.primary));
    return GlassPanel(
      borderColor: accent.withAlpha(80),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _StatusIcon(icon: Icons.history_rounded, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: _Heading(
                  caption: 'ИМПОРТ ПРЕРВАЛСЯ',
                  title: 'Продолжить с того же места?',
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Приложение закрылось, пока шёл импорт по ссылке. '
            'Уже скачанные треки пропустятся.',
            style: TextStyle(
              color: Colors.white.withAlpha(170),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ChipButton(label: 'Не нужно', onTap: onForget),
              const SizedBox(width: 8),
              ChipButton(
                icon: Icons.play_arrow_rounded,
                label: 'Продолжить',
                accent: accent,
                onTap: onResume,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Иконка состояния в круге — как у баннера обновления.
class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withAlpha(40),
      ),
      child: Icon(icon, color: color, size: 16),
    );
  }
}

/// Подпись капсом над заголовком.
class _Heading extends StatelessWidget {
  const _Heading({
    required this.caption,
    required this.title,
    required this.color,
  });

  final String caption;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          caption,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
