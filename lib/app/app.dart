// lib/app/app.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import 'app_shell.dart';

class ProtogenixApp extends ConsumerWidget {
  const ProtogenixApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title:                    'Protogenix',
      debugShowCheckedModeBanner: false,
      theme:                    AppTheme.dark(),
      home:                     const AppShell(),
    );
  }
}
