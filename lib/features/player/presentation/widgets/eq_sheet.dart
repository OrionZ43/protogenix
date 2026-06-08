// lib/features/player/presentation/widgets/eq_sheet.dart
//
// Премиум 5-полосный эквалайзер в glassmorphism-стиле.
// Поддерживается только на Android (AndroidEqualizer из just_audio).
//
// Использование:
//   showEqSheet(context, ref);

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../data/audio_handler.dart';
import '../../domain/player_state.dart'; // <-- ИСПРАВЛЕНИЕ: Добавлен импорт
import '../providers/palette_provider.dart';
import '../providers/player_provider.dart';

// Стандартные метки 5-полосного EQ (Android может вернуть другие centerFreq,
// но будем показывать их из params.bands[i].centerFrequency).
const _kBandLabels = ['60\nHz', '230\nHz', '910\nHz', '4\nkHz', '14\nkHz'];

/// Открывает EQ BottomSheet.
void showEqSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withAlpha(100),
    builder: (_) => ProviderScope(
      parent: ProviderScope.containerOf(context),
      child: const _EqSheet(),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _EqSheet extends ConsumerStatefulWidget {
  const _EqSheet();

  @override
  ConsumerState<_EqSheet> createState() => _EqSheetState();
}

class _EqSheetState extends ConsumerState<_EqSheet> {
  AndroidEqualizerParameters? _params;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadParams();
  }

  Future<void> _loadParams() async {
    try {
      final handler = audioHandler as ProtogenixAudioHandler;
      final params = await handler.equalizer?.parameters;
      if (mounted) setState(() => _params = params);
    } catch (e) {
      debugPrint('Ошибка загрузки параметров эквалайзера: $e');
      if (mounted)
        setState(() => _loadError = 'Ошибка загрузки параметров эквалайзера');
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerProvider);
    final palette = ref.watch(paletteProvider);
    final notifier = ref.read(playerProvider.notifier);

    final accentColor = palette.primary;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(200),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(color: Colors.white.withAlpha(20)),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Drag handle ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 20),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: Colors.white.withAlpha(40),
                  ),
                ),
              ),

              // ── Заголовок + переключатель ─────────────────────────────
              Row(
                children: [
                  Icon(Icons.tune_rounded, color: accentColor, size: 20),
                  const SizedBox(width: 10),
                  const Text(
                    'EQUALIZER',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.5,
                    ),
                  ),
                  const Spacer(),
                  // On/Off toggle
                  GestureDetector(
                    onTap: () => notifier.setEqEnabled(!player.eqEnabled),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 48,
                      height: 26,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        color: player.eqEnabled
                            ? accentColor
                            : Colors.white.withAlpha(25),
                        border: Border.all(
                          color: player.eqEnabled
                              ? accentColor
                              : Colors.white.withAlpha(40),
                        ),
                      ),
                      child: Align(
                        alignment: player.eqEnabled
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // ── Слайдеры ─────────────────────────────────────────────────
              _buildSliders(player, notifier, accentColor),

              const SizedBox(height: 24),

              // ── Кнопка Reset ─────────────────────────────────────────────
              GestureDetector(
                onTap: player.eqEnabled
                    ? () async {
                        for (int i = 0; i < 5; i++) {
                          await notifier.setEqBandGain(i, 0.0);
                        }
                      }
                    : null,
                child: Opacity(
                  opacity: player.eqEnabled ? 1.0 : 0.3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: Colors.white.withAlpha(12),
                      border: Border.all(color: Colors.white.withAlpha(20)),
                    ),
                    child: const Text(
                      'СБРОСИТЬ',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // ── Скорость воспроизведения ──────────────────────────────────
              Row(
                children: [
                  Icon(Icons.speed_rounded,
                      color: player.speed != 1.0 ? accentColor : Colors.white54,
                      size: 20),
                  const SizedBox(width: 10),
                  const Text(
                    'СКОРОСТЬ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '×${player.speed.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: player.speed != 1.0 ? accentColor : Colors.white54,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor:
                      player.speed != 1.0 ? accentColor : Colors.white38,
                  inactiveTrackColor: Colors.white.withAlpha(20),
                  thumbColor: player.speed != 1.0 ? accentColor : Colors.white,
                  overlayColor:
                      (player.speed != 1.0 ? accentColor : Colors.white)
                          .withAlpha(40),
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 8),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 16),
                  valueIndicatorTextStyle: const TextStyle(color: Colors.white),
                ),
                child: Slider(
                  value: player.speed,
                  min: 0.5,
                  max: 2.0,
                  divisions: 6,
                  label: '×${player.speed.toStringAsFixed(2)}',
                  onChanged: (val) {
                    notifier.setSpeed(val);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSliders(
    ProtogenixPlayerState player,
    PlayerNotifier notifier,
    Color accentColor,
  ) {
    // Состояние загрузки
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'Эквалайзер недоступен.\nЗапустите воспроизведение и откройте снова.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withAlpha(80), fontSize: 13),
          ),
        ),
      );
    }

    if (_params == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: CircularProgressIndicator(color: accentColor, strokeWidth: 2),
      );
    }

    final bandCount = _params!.bands.length.clamp(0, 5);

    // ИСПРАВЛЕНИЕ: minDecibels и maxDecibels находятся прямо у параметров,
    // а не у конкретной полосы.
    final minDb = _params!.minDecibels;
    final maxDb = _params!.maxDecibels;

    return Opacity(
      opacity: player.eqEnabled ? 1.0 : 0.35,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(bandCount, (i) {
          final gain =
              i < player.eqBandGains.length ? player.eqBandGains[i] : 0.0;
          final freqHz = _params!.bands[i].centerFrequency;
          final freqLabel = _formatFreq(freqHz);

          return _BandColumn(
            freqLabel: freqLabel,
            gain: gain,
            minDb: minDb,
            maxDb: maxDb,
            accentColor: accentColor,
            enabled: player.eqEnabled,
            onChanged: (v) => notifier.setEqBandGain(i, v),
          );
        }),
      ),
    );
  }

  String _formatFreq(double hz) {
    if (hz >= 1000) {
      final k = (hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1);
      return '$k\nkHz';
    }
    return '${hz.round()}\nHz';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BAND COLUMN — один столбец с вертикальным слайдером
// ─────────────────────────────────────────────────────────────────────────────

class _BandColumn extends StatelessWidget {
  const _BandColumn({
    required this.freqLabel,
    required this.gain,
    required this.minDb,
    required this.maxDb,
    required this.accentColor,
    required this.enabled,
    required this.onChanged,
  });

  final String freqLabel;
  final double gain;
  final double minDb;
  final double maxDb;
  final Color accentColor;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final showPositive = gain > 0.5;
    final showNegative = gain < -0.5;
    final gainLabel =
        gain >= 0 ? '+${gain.toStringAsFixed(1)}' : gain.toStringAsFixed(1);

    return Column(
      children: [
        // Значение gain
        Text(
          gainLabel,
          style: TextStyle(
            color: showPositive
                ? accentColor
                : showNegative
                    ? Colors.white38
                    : Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),

        const SizedBox(height: 8),

        // Вертикальный слайдер через RotatedBox
        SizedBox(
          width: 44,
          height: 140,
          child: RotatedBox(
            quarterTurns: 3, // -90° → вертикальный
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: accentColor.withAlpha(enabled ? 255 : 100),
                inactiveTrackColor: Colors.white.withAlpha(30),
                thumbColor: accentColor,
                thumbShape: RoundSliderThumbShape(
                  enabledThumbRadius: enabled ? 8 : 6,
                ),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                overlayColor: accentColor.withAlpha(30),
              ),
              child: SizedBox(
                width: 140,
                child: Slider(
                  value: gain.clamp(minDb, maxDb),
                  min: minDb,
                  max: maxDb,
                  divisions: ((maxDb - minDb) * 2).round(), // шаг 0.5 dB
                  onChanged: enabled ? onChanged : null,
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Центральный маркер (0 dB)
        Container(
          width: 1,
          height: 8,
          color: Colors.white.withAlpha(25),
        ),

        const SizedBox(height: 6),

        // Частотная метка
        Text(
          freqLabel,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withAlpha(70),
            fontSize: 9.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
