// lib/app/app.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import '../core/theme/app_theme.dart';
import 'app_shell.dart';
import '../features/discord/presentation/discord_presence.dart';
import '../features/importer/presentation/import_status_overlay.dart';
import '../features/listen/domain/listen_link.dart';
import '../features/listen/presentation/listen_links.dart';
import '../core/widgets/window_title_bar.dart';

/// Navigator приложения: вопрос «добавить в медиатеку?» по ссылке «Слушать в
/// Protogenix» показывается поверх любого открытого экрана.
final _navigatorKey = GlobalKey<NavigatorState>();

class ProtogenixApp extends ConsumerWidget {
  const ProtogenixApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    // Статус «Слушает…» в Discord (только Windows) — живёт вместе с приложением
    ref.watch(discordPresenceProvider);
    // «Слушать в Protogenix»: ссылки со страницы сайта (кнопка в Discord)
    ref.watch(listenLinksProvider);
    ref.listen<ListenLink?>(pendingListenLinkProvider, (_, link) {
      if (link != null) handleListenLink(ref, _navigatorKey, link);
    });

    return MaterialApp(
      navigatorKey: _navigatorKey,
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
