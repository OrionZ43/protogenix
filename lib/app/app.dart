// lib/app/app.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import '../core/theme/app_theme.dart';
import 'app_shell.dart';
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
        if (!isDesktop) return child!;
        return Column(
          children: [
            const WindowTitleBar(),
            Expanded(child: child!),
          ],
        );
      },
      home: const AppShell(),
    );
  }
}
