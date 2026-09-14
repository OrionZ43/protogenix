import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/features/updater/update_banner.dart';
import 'package:protogenix/features/updater/update_checker.dart';
import 'package:protogenix/features/updater/update_manifest.dart';
import 'package:protogenix/features/updater/update_provider.dart';

// Состояние задаётся сразу. Своя проверка UpdateNotifier в тесте падает на
// плагинах платформы и тихо ловится — заданное обновление при этом остаётся.
class _Updates extends UpdateNotifier {
  _Updates({required bool found}) {
    state = found
        ? const UpdateState(
            update: AvailableUpdate(
              manifest: UpdateManifest(
                version: '1.1.1',
                build: 4,
                minSupportedBuild: 1,
                notes: '',
                assets: {},
              ),
              asset: null,
              isMandatory: false,
            ),
          )
        : const UpdateState();
  }
}

void main() {
  // Строка состояния телефона — 40 точек сверху, как при edge-to-edge
  Future<EdgeInsets> pumpShell(WidgetTester tester,
      {required bool found}) async {
    tester.view.padding = const FakeViewPadding(top: 40);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late EdgeInsets tabsPadding;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        updateProvider.overrideWith((ref) => _Updates(found: found)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: UpdateBannerLayout(
            child: Builder(builder: (context) {
              tabsPadding = MediaQuery.paddingOf(context);
              return const SizedBox.expand();
            }),
          ),
        ),
      ),
    ));
    await tester.pump();
    return tabsPadding;
  }

  testWidgets(
      'баннер — ниже строки состояния, вкладки под ним без второго отступа',
      (tester) async {
    final tabsPadding = await pumpShell(tester, found: true);

    // Раньше надпись стояла на 20 точках — под часами и значками
    expect(tester.getTopLeft(find.text('ДОСТУПНО ОБНОВЛЕНИЕ')).dy,
        greaterThan(40));
    expect(tabsPadding.top, 0);
  });

  testWidgets('без баннера вкладки сами отступают от строки состояния',
      (tester) async {
    final tabsPadding = await pumpShell(tester, found: false);

    expect(find.text('ДОСТУПНО ОБНОВЛЕНИЕ'), findsNothing);
    expect(tabsPadding.top, 40);
  });
}
