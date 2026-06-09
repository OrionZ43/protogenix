// lib/features/updater/update_banner.dart
//
// Glassmorphism-баннер обновления. Показывается вверху любого экрана.
// «Обновить» → открывает страницу релиза на GitHub.
// «Позже» → скрывает до следующего запуска.

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../player/presentation/providers/palette_provider.dart';
import 'update_provider.dart';

class UpdateBanner extends ConsumerStatefulWidget {
  const UpdateBanner({super.key});

  @override
  ConsumerState<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends ConsumerState<UpdateBanner>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _controller;
  late Animation<double> _expandAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _expandAnim =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  }

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

  Future<void> _openRelease(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final update = ref.watch(updateProvider);
    if (update == null) return const SizedBox.shrink();

    final palette = ref.watch(paletteProvider);
    final accent = palette.primary;

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
                    // Иконка
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

                    // Текст
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'ДОСТУПНО ОБНОВЛЕНИЕ',
                            style: TextStyle(
                              color: accent,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Protogenix ${update.version}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Кнопка «Что нового»
                    if (update.releaseNotes.isNotEmpty)
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

                    // Кнопка «Обновить»
                    GestureDetector(
                      onTap: () => _openRelease(update.releaseUrl),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: accent.withAlpha(220),
                        ),
                        child: const Text(
                          'Обновить',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Кнопка закрытия
                    GestureDetector(
                      onTap: () => ref.read(updateProvider.notifier).dismiss(),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white24,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Что нового (раскрываемый блок) ─────────────────────────
              if (update.releaseNotes.isNotEmpty)
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
                        // Release notes: показываем как простой текст (markdown)
                        Text(
                          update.releaseNotes.length > 500
                              ? '${update.releaseNotes.substring(0, 500)}...'
                              : update.releaseNotes,
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
