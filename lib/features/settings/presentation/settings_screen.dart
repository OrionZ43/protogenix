// lib/features/settings/presentation/settings_screen.dart
//
// «Настройки» — всё, что переключается, в одном месте, и вход в «О
// приложении». Открывается шестерёнкой на главной (телефон) и пунктом внизу
// боковой панели (ПК). Карточки — те же, что на странице «О приложении»
// (SectionCard), и тоже без размытия: страница прокручивается
// (performance.md, правило 5).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/chip_button.dart';
import '../../../core/widgets/glass_back_button.dart';
import '../../../core/widgets/section_card.dart';
import '../../discord/presentation/discord_presence.dart';
import '../../library/presentation/screens/info_screen.dart';
import '../../player/presentation/providers/lyrics_display_provider.dart';
import '../../player/presentation/providers/palette_provider.dart';
import '../../player/presentation/providers/player_provider.dart';
import '../../player/presentation/widgets/eq_sheet.dart';
import '../../player/presentation/widgets/protogenix_background.dart';
import '../../updater/update_provider.dart';

const _bodyStyle = TextStyle(color: Colors.white70, fontSize: 13, height: 1.45);
const _hintStyle =
    TextStyle(color: Color(0x82FFFFFF), fontSize: 12, height: 1.4);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(paletteProvider.select((p) => p.primary));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ProtogenixBackground(
        child: SizedBox.expand(
          child: SafeArea(
            child: Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 72, 20, 32),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Настройки',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 24),
                          _LyricsCard(accent: accent),
                          if (Platform.isWindows) ...[
                            const SizedBox(height: 16),
                            _DiscordCard(accent: accent),
                          ],
                          if (Platform.isAndroid) ...[
                            const SizedBox(height: 16),
                            _EqualizerCard(accent: accent),
                          ],
                          const SizedBox(height: 16),
                          _AboutCard(accent: accent),
                        ],
                      ),
                    ),
                  ),
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

/// «Слоги / Строки» — то же, что кнопка в самом тексте
/// (lyrics_display_provider.dart).
class _LyricsCard extends ConsumerWidget {
  const _LyricsCard({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linesOnly = ref.watch(lyricsLinesOnlyProvider);
    final notifier = ref.read(lyricsLinesOnlyProvider.notifier);
    return SectionCard(
      icon: Icons.lyrics_rounded,
      title: 'ТЕКСТЫ',
      accent: accent,
      children: [
        const Text(
          'Текст с таймингами по словам можно показывать караоке по слогам '
          'или просто строками — строками легче слабому телефону.',
          style: _bodyStyle,
        ),
        const SizedBox(height: 4),
        const Text(
          'То же переключается кнопкой в правом верхнем углу текста.',
          style: _hintStyle,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChipButton(
              label: 'Слоги',
              icon: Icons.graphic_eq_rounded,
              accent: linesOnly ? null : accent,
              onTap: linesOnly ? notifier.toggle : () {},
            ),
            ChipButton(
              label: 'Строки',
              icon: Icons.segment_rounded,
              accent: linesOnly ? accent : null,
              onTap: linesOnly ? () {} : notifier.toggle,
            ),
          ],
        ),
      ],
    );
  }
}

/// Статус «Слушает…» в Discord — только Windows (discord_presence.dart).
class _DiscordCard extends ConsumerWidget {
  const _DiscordCard({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(discordPresenceEnabledProvider);
    return SectionCard(
      icon: Icons.headphones_rounded,
      title: 'DISCORD',
      accent: accent,
      children: [
        Text(
          enabled
              ? 'Пока играет трек, друзья видят в Discord «Слушает»: название, '
                  'исполнителя и сколько осталось. На паузе статус пропадает.'
              : 'Статус в Discord выключен — друзья не видят, что играет.',
          style: _bodyStyle,
        ),
        const SizedBox(height: 4),
        const Text(
          'Работает, когда запущен Discord для ПК.',
          style: _hintStyle,
        ),
        const SizedBox(height: 12),
        ChipButton(
          label: enabled ? 'Выключить' : 'Включить',
          icon: enabled
              ? Icons.visibility_off_rounded
              : Icons.visibility_rounded,
          accent: enabled ? null : accent,
          onTap: ref.read(discordPresenceEnabledProvider.notifier).toggle,
        ),
      ],
    );
  }
}

/// Эквалайзер есть только на Android (known-issues.md, «Эквалайзер»).
class _EqualizerCard extends ConsumerWidget {
  const _EqualizerCard({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(playerProvider.select((s) => s.eqEnabled));
    return SectionCard(
      icon: Icons.tune_rounded,
      title: 'ЭКВАЛАЙЗЕР',
      accent: accent,
      children: [
        Text(
          enabled ? 'Эквалайзер включён.' : 'Эквалайзер выключен.',
          style: _bodyStyle,
        ),
        const SizedBox(height: 4),
        const Text(
          'Та же шторка открывается кнопкой в верхней панели плеера.',
          style: _hintStyle,
        ),
        const SizedBox(height: 12),
        ChipButton(
          label: 'Открыть эквалайзер',
          icon: Icons.tune_rounded,
          accent: accent,
          onTap: () => showEqSheet(context),
        ),
      ],
    );
  }
}

/// Вход в «О приложении»; если вышла новая версия — видно и здесь.
class _AboutCard extends ConsumerWidget {
  const _AboutCard({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(updateProvider.select((s) => s.update));
    return SectionCard(
      icon: Icons.info_rounded,
      title: 'О ПРИЛОЖЕНИИ',
      accent: accent,
      children: [
        Text(
          update != null
              ? 'Вышла версия ${update.manifest.version} — обновиться можно '
                  'на странице «О приложении».'
              : 'Версия и обновления, медиатека, где лежат данные, '
                  'благодарности и лицензии.',
          style: update != null
              ? TextStyle(
                  color: accent,
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                )
              : _bodyStyle,
        ),
        const SizedBox(height: 12),
        ChipButton(
          label: 'О приложении',
          icon: Icons.chevron_right_rounded,
          accent: accent,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const InfoScreen()),
          ),
        ),
      ],
    );
  }
}
