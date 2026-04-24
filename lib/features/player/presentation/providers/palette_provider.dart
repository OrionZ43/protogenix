import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

class PaletteState {
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final bool isLoading;

  const PaletteState({
    required this.primary,
    required this.secondary,
    required this.tertiary,
    this.isLoading = false,
  });

  static const defaultState = PaletteState(
    primary: Color(0xFF7B5EA7),
    secondary: Color(0xFF4A3580),
    tertiary: Color(0xFF1A0D40),
  );

  PaletteState copyWith({
    Color? primary,
    Color? secondary,
    Color? tertiary,
    bool? isLoading,
  }) {
    return PaletteState(
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      tertiary: tertiary ?? this.tertiary,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class PaletteNotifier extends StateNotifier<PaletteState> {
  PaletteNotifier() : super(PaletteState.defaultState);

  Future<void> extractFromImage(ImageProvider imageProvider) async {
    state = state.copyWith(isLoading: true);

    try {
      final generator = await PaletteGenerator.fromImageProvider(
        imageProvider,
        size: const Size(200, 200),
        maximumColorCount: 16,
      );
      debugPrint('=== PALETTE DEBUG ===');
      debugPrint('dominant: ${generator.dominantColor?.color}');
      debugPrint('vibrant: ${generator.vibrantColor?.color}');
      debugPrint('lightVibrant: ${generator.lightVibrantColor?.color}');
      debugPrint('darkVibrant: ${generator.darkVibrantColor?.color}');
      debugPrint('muted: ${generator.mutedColor?.color}');
      debugPrint('darkMuted: ${generator.darkMutedColor?.color}');

      final primary = generator.vibrantColor?.color ??
          generator.lightVibrantColor?.color ??
          generator.dominantColor?.color ??
          PaletteState.defaultState.primary;

      final secondary = generator.darkVibrantColor?.color ??
          generator.mutedColor?.color ??
          generator.dominantColor?.color ??
          PaletteState.defaultState.secondary;

      final tertiary = generator.darkMutedColor?.color ??
          generator.dominantColor?.color ??
          PaletteState.defaultState.tertiary;

      HSLColor boost(Color c) => HSLColor.fromColor(c);

      final boostedPrimary = boost(primary)
          .withSaturation((boost(primary).saturation * 1.4).clamp(0.0, 1.0))
          .withLightness((boost(primary).lightness * 1.2).clamp(0.2, 0.8))
          .toColor();

      final boostedSecondary = boost(secondary)
          .withSaturation((boost(secondary).saturation * 1.3).clamp(0.0, 1.0))
          .withLightness((boost(secondary).lightness * 0.7).clamp(0.05, 0.5))
          .toColor();

      final boostedTertiary = boost(tertiary)
          .withSaturation((boost(tertiary).saturation * 1.2).clamp(0.0, 1.0))
          .withLightness((boost(tertiary).lightness * 0.4).clamp(0.02, 0.3))
          .toColor();

      state = PaletteState(
        primary: boostedPrimary,
        secondary: boostedSecondary,
        tertiary: boostedTertiary,
        isLoading: false,
      );
    } catch (e, stack) {
      debugPrint('PaletteGenerator ERROR: $e');
      debugPrint('Stack: $stack');
      state = PaletteState.defaultState;
    }
  }
// ← здесь закрывается класс PaletteNotifier
}

// ← провайдер снаружи класса
final paletteProvider =
    StateNotifierProvider<PaletteNotifier, PaletteState>((ref) {
  return PaletteNotifier();
});
