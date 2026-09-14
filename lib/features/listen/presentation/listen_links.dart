// lib/features/listen/presentation/listen_links.dart
//
// Приём ссылок «Слушать в Protogenix» (listen_link.dart) и вопрос перед
// скачиванием.
//   Windows: установщик прописывает схему protogenix:// в реестр, ссылка
//   приходит аргументом запуска. Если приложение уже открыто, второй запуск
//   пересылает её первому (windows/runner/main.cpp → flutter_window.cpp →
//   канал z43.studios.protogenix/links, метод open).
//   Android: intent-filter в манифесте; ссылку запуска Dart забирает методом
//   initialLink, пока приложение открыто — open из MainActivity.onNewIntent.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/glass_dialog.dart';
import '../../importer/presentation/import_manager.dart';
import '../../library/data/library_database.dart';
import '../../player/presentation/providers/palette_provider.dart';
import '../../player/presentation/providers/player_provider.dart';
import '../domain/listen_link.dart';

const _channel = MethodChannel('z43.studios.protogenix/links');

List<String> _launchArguments = const [];

/// Аргументы запуска (Windows): среди них может быть ссылка protogenix://….
/// Вызывается из main().
void setLaunchArguments(List<String> args) => _launchArguments = args;

/// Пришла ссылка — ждёт вопроса «добавить в медиатеку?».
final pendingListenLinkProvider = StateProvider<ListenLink?>((ref) => null);

/// Подключает приём ссылок. Живёт вместе с приложением (ProtogenixApp).
final listenLinksProvider = Provider<void>((ref) {
  if (!Platform.isWindows && !Platform.isAndroid) return;

  void deliver(Object? raw) {
    final link = raw is String ? ListenLink.parse(raw) : null;
    if (link != null) {
      ref.read(pendingListenLinkProvider.notifier).state = link;
    }
  }

  _channel.setMethodCallHandler((call) async {
    if (call.method == 'open') deliver(call.arguments);
  });
  ref.onDispose(() => _channel.setMethodCallHandler(null));

  // Ссылка, с которой приложение запустили. Позже, а не сразу: провайдеру
  // нельзя менять другие провайдеры, пока он сам создаётся
  Future<void>(() async {
    if (Platform.isWindows) {
      for (final arg in _launchArguments) {
        if (arg.startsWith('protogenix:')) deliver(arg);
      }
    } else {
      try {
        deliver(await _channel.invokeMethod<String>('initialLink'));
      } catch (e) {
        debugPrint('[Links] Не удалось получить ссылку запуска: $e');
      }
    }
  });
});

/// Вопрос перед скачиванием. [navigator] — ключ Navigator приложения:
/// ссылка может прийти, пока открыт любой экран.
Future<void> handleListenLink(
  WidgetRef ref,
  GlobalKey<NavigatorState> navigator,
  ListenLink link,
) async {
  ref.read(pendingListenLinkProvider.notifier).state = null;
  // Ссылка запуска приходит раньше первого кадра
  while (navigator.currentContext == null) {
    await WidgetsBinding.instance.endOfFrame;
  }
  final accent = ref.read(paletteProvider).primary;
  final videoId = link.videoId;

  final existing =
      videoId == null ? null : await LibraryDatabase.instance.getTrackById(videoId);
  if (existing != null) {
    final context = navigator.currentContext;
    if (context == null || !context.mounted) return;
    final play = await showGlassConfirm(
      context,
      title: 'Уже в медиатеке',
      message: '«${existing.title}» — ${existing.artist}. Включить сейчас?',
      confirmLabel: 'Включить',
      icon: Icons.play_arrow_rounded,
      color: accent,
    );
    if (play) {
      await ref.read(playerProvider.notifier).playNext(existing.toTrackModel());
    }
    return;
  }

  final context = navigator.currentContext;
  if (context == null || !context.mounted) return;
  final add = await showGlassConfirm(
    context,
    title: 'Добавить в медиатеку?',
    message: videoId != null
        ? '${link.label}. Трек скачается с YouTube.'
        : '${link.label}. Запись найдётся на YouTube по названию и '
            'исполнителю — только та же версия, без каверов и концертов.',
    confirmLabel: 'Добавить',
    icon: Icons.playlist_add_rounded,
    color: accent,
  );
  if (!add) return;

  final manager = ref.read(importManagerProvider.notifier);
  if (videoId != null) {
    unawaited(manager.importUrl(
      'https://www.youtube.com/watch?v=$videoId',
      title: link.title.isEmpty ? null : link.title,
    ));
  } else {
    unawaited(manager.importSearchedTrack(
      title: link.title,
      artist: link.artist,
      duration: link.duration,
    ));
  }
}
