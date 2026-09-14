// lib/features/library/presentation/screens/info_screen.dart
//
// Страница «О приложении»: кнопка «i» на главной и пункт «Инфо» в боковой
// панели на десктопе. Версия и обновления, медиатека, где лежат данные,
// благодарности и лицензии, ссылки Z43 Studios.
//
// Карточки без BackdropFilter: страница прокручивается, а размытие под
// прокручиваемым содержимым пересчитывается каждый кадр (performance.md,
// правило 5). Фон и так мягкий — полупрозрачной заливки хватает.

import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/services/app_paths.dart';
import '../../../../core/widgets/app_license_page.dart';
import '../../../../core/widgets/chip_button.dart';
import '../../../../core/widgets/glass_back_button.dart';
import '../../../../core/widgets/neon_logo.dart';
import '../../../../core/widgets/section_card.dart';
import '../../../../core/widgets/z43_branding.dart';
import '../../../player/presentation/providers/palette_provider.dart';
import '../../../player/presentation/widgets/protogenix_background.dart';
import '../../../updater/update_checker.dart';
import '../../../updater/update_provider.dart';
import '../library_provider.dart';

const _releasesUrl = 'https://github.com/OrionZ43/protogenix/releases';

final _packageInfoProvider =
    FutureProvider<PackageInfo>((ref) => PackageInfo.fromPlatform());

/// Сколько места занимает медиатека: аудио, обложки и тексты треков плюс кэш
/// потоков. Считается по путям из базы, а не по папке: файлы, скачанные до
/// переноса данных, остались на старом месте (data.md). Обход файлов — в
/// отдельном изоляте.
final _storageBytesProvider = FutureProvider.autoDispose<int>((ref) {
  final tracks = ref.watch(libraryProvider);
  final paths = <String>{
    for (final t in tracks) ...[
      t.filePath,
      if (t.coverPath != null) t.coverPath!,
      if (t.lrcPath != null) t.lrcPath!,
    ],
  }.toList();
  final cacheDir = AppPaths.audioCacheDir;
  return Isolate.run(() => _bytesOnDisk(paths, cacheDir));
});

int _bytesOnDisk(List<String> paths, String cacheDir) {
  var total = 0;
  for (final path in paths) {
    try {
      final file = File(path);
      if (file.existsSync()) total += file.lengthSync();
    } catch (_) {}
  }
  try {
    final dir = Directory(cacheDir);
    if (dir.existsSync()) {
      for (final entry in dir.listSync(recursive: true, followLinks: false)) {
        if (entry is File) total += entry.lengthSync();
      }
    }
  } catch (_) {}
  return total;
}

String _plural(int n, String one, String few, String many) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
  return many;
}

String _formatDuration(int totalMs) {
  final minutes = totalMs ~/ 60000;
  final hours = minutes ~/ 60;
  return hours == 0 ? '$minutes мин' : '$hours ч ${minutes % 60} мин';
}

String _formatBytes(int bytes) {
  const units = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = unit == 0 || value >= 100
      ? value.round().toString()
      : value.toStringAsFixed(1).replaceAll('.', ',');
  return '$text ${units[unit]}';
}

String get _platformName {
  if (Platform.isAndroid) return 'Android';
  if (Platform.isWindows) return 'Windows';
  if (Platform.isLinux) return 'Linux';
  if (Platform.isMacOS) return 'macOS';
  return Platform.operatingSystem;
}

Future<void> _openUrl(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('[Info] Не удалось открыть $url: $e');
  }
}

Future<void> _openDataFolder() async {
  final dir = AppPaths.dataDir;
  try {
    if (Platform.isWindows) {
      await Process.start('explorer.exe', [dir]);
    } else if (Platform.isMacOS) {
      await Process.start('open', [dir]);
    } else {
      await Process.start('xdg-open', [dir]);
    }
  } catch (e) {
    debugPrint('[Info] Не удалось открыть папку $dir: $e');
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class InfoScreen extends ConsumerWidget {
  const InfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(paletteProvider.select((p) => p.primary));

    return Scaffold(
      backgroundColor: Colors.transparent,
      // SizedBox.expand: фон (AnimatedBackground — Stack) берёт размер
      // содержимого, и на высоком окне под короткой страницей оставалась
      // чёрная полоса.
      body: ProtogenixBackground(
        child: SizedBox.expand(
          child: SafeArea(
            child: Stack(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 720;
                    final library = _LibraryCard(accent: accent);
                    final data = _DataCard(accent: accent);
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 64, 20, 32),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 820),
                          child: Column(
                            children: [
                              _Hero(accent: accent),
                              const SizedBox(height: 32),
                              if (wide)
                                IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(child: library),
                                      const SizedBox(width: 16),
                                      Expanded(child: data),
                                    ],
                                  ),
                                )
                              else ...[
                                library,
                                const SizedBox(height: 16),
                                data,
                              ],
                              const SizedBox(height: 16),
                              _CreditsCard(accent: accent),
                              const SizedBox(height: 32),
                              const Z43BrandingBadge(),
                            ]
                                .animate(interval: 60.ms)
                                .fadeIn(duration: 420.ms)
                                .slideY(
                                    begin: 0.04, curve: Curves.easeOutCubic),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const Positioned(top: 12, left: 12, child: GlassBackButton()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Шапка: логотип, версия, обновления ──────────────────────────────────────

class _Hero extends ConsumerWidget {
  const _Hero({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(_packageInfoProvider).valueOrNull;

    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFCE93D8).withAlpha(55),
                blurRadius: 48,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const NeonLogo(size: 128),
        ),
        const SizedBox(height: 20),
        // letterSpacing добавляет отступ и после последней буквы — сдвигаем
        // на столько же, чтобы слово стояло ровно по центру
        const Padding(
          padding: EdgeInsets.only(left: 8),
          child: Text(
            'PROTOGENIX',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 8,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Плеер нового поколения',
          style: TextStyle(
            color: Colors.white.withAlpha(140),
            fontSize: 13,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(20),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withAlpha(24)),
          ),
          child: Text(
            info == null
                ? '…'
                : 'v${info.version} · сборка ${info.buildNumber} · $_platformName',
            style: TextStyle(
              color: Colors.white.withAlpha(200),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _UpdateStatus(accent: accent),
      ],
    );
  }
}

class _UpdateStatus extends ConsumerWidget {
  const _UpdateStatus({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(updateProvider);
    final notifier = ref.read(updateProvider.notifier);
    final update = s.update;

    final Widget icon;
    final String title;
    String? caption;
    ChipButton? action;
    double? progress;

    if (update != null && s.phase == UpdatePhase.downloading) {
      icon = Icon(Icons.downloading_rounded, color: accent);
      title = 'Скачиваем v${update.manifest.version}… '
          '${(s.progress * 100).round()}%';
      progress = s.progress;
    } else if (update != null && s.phase == UpdatePhase.installing) {
      icon = Icon(Icons.install_desktop_rounded, color: accent);
      title = 'Запускаем установку…';
    } else if (update != null && s.phase == UpdatePhase.failed) {
      icon = const Icon(Icons.error_outline_rounded, color: Colors.redAccent);
      title = s.error ?? 'Не удалось обновиться';
      action = ChipButton(
        label: 'Повторить',
        icon: Icons.refresh_rounded,
        onTap: notifier.downloadAndInstall,
      );
    } else if (update != null) {
      icon = Icon(Icons.system_update_rounded, color: accent);
      title = 'Доступна версия ${update.manifest.version}';
      caption = update.isMandatory
          ? 'Обязательное обновление'
          : 'Скачается и установится само';
      action = update.asset != null
          ? ChipButton(
              label: 'Обновить',
              icon: Icons.download_rounded,
              accent: accent,
              onTap: notifier.downloadAndInstall,
            )
          : ChipButton(
              label: 'Открыть',
              icon: Icons.open_in_new_rounded,
              accent: accent,
              onTap: () => _openUrl(
                  (update.manifest.releaseUrl ?? Uri.parse(_releasesUrl))
                      .toString()),
            );
    } else if (s.checking) {
      icon = SizedBox(
        width: 22,
        height: 22,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: CircularProgressIndicator(strokeWidth: 2, color: accent),
        ),
      );
      title = 'Проверяем обновления…';
    } else {
      switch (s.outcome) {
        case UpdateCheckOutcome.upToDate:
          icon = Icon(Icons.check_circle_rounded, color: accent);
          title = 'Установлена последняя версия';
        case UpdateCheckOutcome.failed:
          icon = const Icon(Icons.cloud_off_rounded, color: Colors.white54);
          title = 'Не удалось проверить обновления';
          caption = 'Сервер обновлений не ответил';
        case UpdateCheckOutcome.disabled:
          icon =
              const Icon(Icons.update_disabled_rounded, color: Colors.white54);
          title = 'Проверка обновлений выключена';
        case UpdateCheckOutcome.available:
        case null:
          icon = const Icon(Icons.update_rounded, color: Colors.white54);
          title = 'Обновления ещё не проверялись';
      }
      if (s.outcome != UpdateCheckOutcome.disabled) {
        action = ChipButton(
          label: s.outcome == UpdateCheckOutcome.failed
              ? 'Повторить'
              : 'Проверить',
          icon: Icons.refresh_rounded,
          onTap: notifier.checkNow,
        );
        final at = s.checkedAt;
        if (at != null) {
          String two(int v) => v.toString().padLeft(2, '0');
          caption ??= 'Проверено в ${two(at.hour)}:${two(at.minute)}';
        }
      }
    }

    final notes = update != null && s.phase == UpdatePhase.available
        ? update.manifest.notes.trim()
        : '';
    // Неизменяемые копии для замыкания LayoutBuilder ниже
    final captionText = caption;
    final actionButton = action;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(16),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: update != null
                    ? accent.withAlpha(120)
                    : Colors.white.withAlpha(30),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final text = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (captionText != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              captionText,
                              style: TextStyle(
                                color: Colors.white.withAlpha(130),
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    );
                    // На узком экране кнопка — под текстом, иначе текст
                    // рвётся на четыре строки
                    if (actionButton != null && constraints.maxWidth < 400) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              icon,
                              const SizedBox(width: 12),
                              Expanded(child: text),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: actionButton,
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        icon,
                        const SizedBox(width: 12),
                        Expanded(child: text),
                        if (actionButton != null) ...[
                          const SizedBox(width: 12),
                          actionButton,
                        ],
                      ],
                    );
                  },
                ),
                if (progress != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        color: accent,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                  ),
                if (notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      notes,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withAlpha(170),
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => _openUrl(_releasesUrl),
            icon: const Icon(Icons.history_rounded, size: 16),
            label: const Text('Все версии и что нового'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withAlpha(150),
              textStyle: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Карточки ─────────────────────────────────────────────────────────────────

const _bodyStyle = TextStyle(color: Colors.white70, fontSize: 13, height: 1.45);

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style:
                  TextStyle(color: Colors.white.withAlpha(140), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryCard extends ConsumerWidget {
  const _LibraryCard({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(libraryProvider);
    final totalMs = tracks.fold<int>(0, (sum, t) => sum + t.durationMs);
    final storage = ref.watch(_storageBytesProvider);

    // Исполнитель, которого в медиатеке больше всего (от двух треков)
    final counts = <String, int>{};
    for (final t in tracks) {
      final artist = t.artist.trim();
      if (artist.isEmpty || artist.toLowerCase().startsWith('unknown')) {
        continue;
      }
      counts[artist] = (counts[artist] ?? 0) + 1;
    }
    MapEntry<String, int>? top;
    for (final entry in counts.entries) {
      if (entry.value >= 2 && (top == null || entry.value > top.value)) {
        top = entry;
      }
    }

    return SectionCard(
      icon: Icons.library_music_rounded,
      title: 'МЕДИАТЕКА',
      accent: accent,
      children: [
        if (tracks.isEmpty)
          const Text(
            'Пока пусто. Добавь трек по ссылке с YouTube, Spotify или '
            'Яндекс Музыки — кнопка «Добавить» в плеере.',
            style: _bodyStyle,
          )
        else ...[
          _Stat('${tracks.length}',
              _plural(tracks.length, 'трек', 'трека', 'треков')),
          _Stat(_formatDuration(totalMs), 'музыки'),
          _Stat(
            storage.when(
              data: _formatBytes,
              loading: () => '…',
              error: (_, __) => '—',
            ),
            'на диске',
          ),
          if (top != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Чаще всего: ',
                      style: TextStyle(color: Colors.white.withAlpha(130)),
                    ),
                    TextSpan(
                      text: top.key,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: ' · ${top.value} '
                          '${_plural(top.value, 'трек', 'трека', 'треков')}',
                      style: TextStyle(color: Colors.white.withAlpha(130)),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            ),
        ],
      ],
    );
  }
}

class _DataCard extends StatelessWidget {
  const _DataCard({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final desktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    return SectionCard(
      icon: Icons.folder_rounded,
      title: 'ДАННЫЕ',
      accent: accent,
      children: [
        if (desktop) ...[
          const Text('Медиатека, обложки и тексты — в папке',
              style: _bodyStyle),
          const SizedBox(height: 4),
          SelectableText(
            AppPaths.dataDir,
            style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 12),
          ),
          const SizedBox(height: 10),
          const ChipButton(
            label: 'Открыть папку',
            icon: Icons.folder_open_rounded,
            onTap: _openDataFolder,
          ),
        ] else
          const Text(
            'Медиатека, обложки и тексты хранятся в памяти приложения и '
            'удаляются вместе с ним.',
            style: _bodyStyle,
          ),
        const SizedBox(height: 18),
        Row(
          children: [
            Icon(Icons.shield_rounded, size: 16, color: accent),
            const SizedBox(width: 8),
            const Text(
              'Телеметрии нет',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Приложение не собирает статистику и ничего не сообщает о тебе. '
          'В сеть уходят только поиск текстов по названию трека, скачивание '
          'с YouTube и проверка обновлений'
          '${Platform.isWindows ? ', а при включённом статусе в Discord — '
              'название играющего трека в сам Discord' : ''}.',
          style: _bodyStyle,
        ),
      ],
    );
  }
}

class _CreditsCard extends ConsumerWidget {
  const _CreditsCard({required this.accent});
  final Color accent;

  static const _credits = [
    ('Тексты песен', 'LRCLIB · NetEase · Kugou'),
    ('YouTube', 'youtube_explode_dart'),
    ('Звук', 'just_audio · audio_service · media_kit'),
    ('Интерфейс', 'Flutter · Riverpod'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SectionCard(
      icon: Icons.favorite_rounded,
      title: 'БЛАГОДАРНОСТИ',
      accent: accent,
      children: [
        for (final (label, value) in _credits)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 112,
                  child: Text(
                    label,
                    style: TextStyle(
                        color: Colors.white.withAlpha(130), fontSize: 13),
                  ),
                ),
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        ChipButton(
          label: 'Лицензии открытого ПО',
          icon: Icons.description_outlined,
          onTap: () {
            final version = ref.read(_packageInfoProvider).valueOrNull?.version;
            showAppLicenses(context, version: version);
          },
        ),
      ],
    );
  }
}

