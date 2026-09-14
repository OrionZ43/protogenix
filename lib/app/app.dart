// lib/app/app.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import '../core/theme/app_theme.dart';
import 'app_shell.dart';
import '../features/importer/presentation/import_status_overlay.dart';
import '../core/widgets/window_title_bar.dart';

class ProtogenixApp extends ConsumerWidget {
  const ProtogenixApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    return MaterialApp(
      title: 'Protogenix',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      builder: (context, child) {
        final content = isDesktop
            ? Column(
                children: [
                  const WindowTitleBar(),
                  Expanded(child: child!),
                ],
              )
            : child!;
        // Плашка фонового импорта — поверх всех экранов и шторок
        return Stack(
          fit: StackFit.expand,
          children: [content, const ImportStatusOverlay()],
        );
      },
      home: const AppShell(),
    );
  }
}
