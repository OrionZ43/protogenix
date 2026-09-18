import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/core/services/app_paths.dart';
import 'package:protogenix/features/importer/presentation/importer_sheet.dart';

// Плеера в тестах нет (known-issues.md, «Тесты»), но шторке импорта он и не
// нужен: она смотрит только палитру и менеджер импорта. Пути — во временную
// папку, чтобы менеджер не полез в настоящие данные.
void main() {
  setUpAll(() async {
    final tmp = await Directory.systemTemp.createTemp('protogenix_sheet_');
    AppPaths.databasesDir = tmp.path;
    AppPaths.dataDir = tmp.path;
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: ImporterSheet())),
    ));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> paste(WidgetTester tester, String url) async {
    await tester.enterText(find.byType(TextField), url);
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('плейлист Spotify: предупреждение про 99 и «Почему?»',
      (tester) async {
    await pumpSheet(tester);
    expect(find.textContaining('только первые'), findsNothing);

    await paste(tester,
        'https://open.spotify.com/playlist/3qDD9XgaWAKwMaQ89uzcIc?si=abc');
    expect(find.textContaining('только первые 99 треков'), findsOneWidget);

    await tester.tapOnText(find.textRange.ofSubstring('Почему?'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Войти за тебя приложение не может'),
        findsOneWidget);
  });

  testWidgets('альбом и трек приходят целиком — предупреждения нет',
      (tester) async {
    await pumpSheet(tester);

    await paste(
        tester, 'https://open.spotify.com/intl-ru/album/3T4tUhGYeRNVUGevb0wThu');
    expect(find.textContaining('только первые'), findsNothing);

    await paste(
        tester, 'https://open.spotify.com/track/4u7EnebtmKWzUH433cf5Qv');
    expect(find.textContaining('только первые'), findsNothing);
  });

  testWidgets('поле очистили — предупреждение исчезает', (tester) async {
    await pumpSheet(tester);
    await paste(tester,
        'https://open.spotify.com/playlist/3qDD9XgaWAKwMaQ89uzcIc');
    expect(find.textContaining('только первые 99 треков'), findsOneWidget);

    await paste(tester, '');
    expect(find.textContaining('только первые'), findsNothing);
  });
}
