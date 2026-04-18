// lib/features/player/presentation/widgets/protogenix_background.dart
//
// ProtogenixBackground — DRY-обёртка над AnimatedBackground.
// Берёт цвета из paletteProvider, больше не зависит от VisualizerEngine.
//
// Использование:
//   ProtogenixBackground(child: ...)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/palette_provider.dart';
import 'animated_background.dart';

class ProtogenixBackground extends ConsumerWidget {
  const ProtogenixBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(paletteProvider);

    return AnimatedBackground(
      primaryColor:   palette.primary,
      secondaryColor: palette.secondary,
      tertiaryColor:  palette.tertiary,
      child: child,
    );
  }
}
