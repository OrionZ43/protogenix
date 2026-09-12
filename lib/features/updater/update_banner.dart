// lib/features/updater/update_banner.dart
//
// Баннер обновления вверху экрана.
//   «Обновить» → скачивание с прогрессом → установка (update_provider.dart).
//   Нет файла для этой платформы → «Открыть» ведёт на страницу релиза.
//   Крестик → скрыть до следующего запуска. Обязательное обновление
//   (сборка ниже minSupportedBuild) скрыть нельзя.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../player/presentation/providers/palette_provider.dart';
import 'update_checker.dart';
import 'update_installer.dart';
import 'update_provider.dart';

class UpdateBanner extends ConsumerStatefulWidget {
  const UpdateBanner({super.key});

  @override
  ConsumerState<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends ConsumerState<UpdateBanner>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  late final Animation<double> _expandAnim =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  Future<void> _openRelease(AvailableUpdate update) async {
    final url = update.manifest.releaseUrl ??
        Uri.parse('https://github.com/OrionZ43/protogenix/releases/latest');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Widget _buildAction(UpdateState state, Color accent) {
    final update = state.update!;
    final notifier = ref.read(updateProvider.notifier);

    // Файла для этой платформы нет — только страница релиза.
    if (update.asset == null || !UpdateInstaller.isSupported) {
      return GestureDetector(
        onTap: () => _openRelease(update),
        child: _pillButton('Открыть', accent),
      );
    }

    return switch (state.phase) {
      UpdatePhase.available => GestureDetector(
          onTap: notifier.downloadAndInstall,
          child: _pillButton('Обновить', accent),
        ),
      UpdatePhase.downloading => SizedBox(
          width: 90,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: state.progress,
                  backgroundColor: Colors.white12,
                  color: accent,
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${(state.progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      UpdatePhase.installing =>
        _pillButton('Установка...', accent, enabled: false),
      UpdatePhase.failed => GestureDetector(
          onTap: notifier.downloadAndInstall,
          child: _pillButton('Повторить', Colors.redAccent),
        ),
    };
  }

  Widget _pillButton(String label, Color color, {bool enabled = true}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: enabled ? color.withAlpha(220) : color.withAlpha(80),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(updateProvider);
    if (!state.isVisible) return const SizedBox.shrink();

    final update = state.update!;
    final manifest = update.manifest;
    final accent = ref.watch(paletteProvider).primary;
    final details = [
      if (manifest.message != null) manifest.message!,
      if (manifest.notes.isNotEmpty) manifest.notes,
    ].join('\n\n');

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(180),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withAlpha(80)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Основная строка ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withAlpha(40),
                      ),
                      child: Icon(
                        Icons.system_update_alt_rounded,
                        color: accent,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            update.isMandatory
                                ? 'НУЖНО ОБНОВИТЬСЯ'
                                : 'ДОСТУПНО ОБНОВЛЕНИЕ',
                            style: TextStyle(
                              color: accent,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Protogenix ${manifest.version}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // «Что нового»
                    if (details.isNotEmpty)
                      GestureDetector(
                        onTap: _toggleExpanded,
                        child: AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: const Icon(
                            Icons.expand_more_rounded,
                            color: Colors.white38,
                            size: 20,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),

                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _buildAction(state, accent),
                        if (state.phase == UpdatePhase.failed &&
                            state.error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: SizedBox(
                              width: 160,
                              child: Text(
                                state.error!,
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),

                    if (!update.isMandatory) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () =>
                            ref.read(updateProvider.notifier).dismiss(),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white24,
                          size: 18,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Что нового (раскрываемый блок) ─────────────────────────
              if (details.isNotEmpty)
                SizeTransition(
                  sizeFactor: _expandAnim,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(color: Colors.white.withAlpha(15), height: 16),
                        const Text(
                          'ЧТО НОВОГО',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          details.length > 500
                              ? '${details.substring(0, 500)}...'
                              : details,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            height: 1.5,
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
    );
  }
}
