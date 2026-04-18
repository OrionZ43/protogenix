import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/fold_layout.dart';
import '../features/player/presentation/screens/player_screen.dart';
import '../features/player/presentation/screens/expanded_player_screen.dart';

class ProtogenixApp extends ConsumerWidget {
  const ProtogenixApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Protogenix',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const _AppShell(),
    );
  }
}

class _AppShell extends StatelessWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context) {
    return FoldLayout(
      // Сложенный экран — классический плеер
      compactBuilder: (context, data) => const PlayerScreen(),
      // Разложенный экран — два столбца
      expandedBuilder: (context, data) => const ExpandedPlayerScreen(),
    );
  }
}