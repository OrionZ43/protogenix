import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/core/widgets/sheet_cover.dart';

// Под раскрытой шторкой ничего не рисуется: Impeller перерисовывает закрытое
// каждый кадр целиком, на слабых телефонах это больше половины кадра
// (`performance.md`, «Слабые телефоны»). Важно, чтобы закрытое возвращалось,
// как только шторку тянут или закрывают.

void main() {
  late SheetCover cover;

  setUp(() => cover = SheetCover());
  tearDown(() => cover.dispose());

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: HiddenUnderSheet(
            covered: cover,
            child: Center(
              child: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => CoveringSheet(
                    cover: cover,
                    child: const SizedBox.expand(child: Text('шторка')),
                  ),
                ),
                child: const Text('под шторкой'),
              ),
            ),
          ),
        ),
      ),
    ));
  }

  bool hidden(WidgetTester tester) => !tester
      .widget<Visibility>(find.ancestor(
        of: find.text('под шторкой'),
        matching: find.byType(Visibility),
      ))
      .visible;

  testWidgets('раскрытая шторка прячет то, что под ней', (tester) async {
    await pumpApp(tester);
    expect(hidden(tester), isFalse);

    await tester.tap(find.text('под шторкой'));
    await tester.pump(); // шторка только поехала
    expect(cover.value, isFalse, reason: 'пока едет — под ней видно');

    await tester.pumpAndSettle();
    expect(cover.value, isTrue);
    expect(hidden(tester), isTrue);
  });

  testWidgets('потянули шторку — содержимое под ней снова рисуется',
      (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('под шторкой'));
    await tester.pumpAndSettle();
    expect(cover.value, isTrue);

    final gesture =
        await tester.startGesture(tester.getCenter(find.text('шторка')));
    // Первое движение уходит на распознавание жеста, тянет второе
    await gesture.moveBy(const Offset(0, 30));
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    expect(cover.value, isFalse, reason: 'шторку тянут — под ней видно');
    expect(hidden(tester), isFalse);

    // Отпустили недалеко — шторка вернулась на место и снова всё закрыла
    await gesture.up();
    await tester.pumpAndSettle();
    expect(cover.value, isTrue);
  });

  testWidgets('закрыли шторку — всё на месте', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('под шторкой'));
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.text('шторка'))).pop();
    await tester.pumpAndSettle();
    expect(cover.value, isFalse);
    expect(hidden(tester), isFalse);
    expect(find.text('шторка'), findsNothing);
  });

  testWidgets('шторку убрали без анимации — экран под ней вернулся',
      (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('под шторкой'));
    await tester.pumpAndSettle();
    expect(cover.value, isTrue);

    final navigator = Navigator.of(tester.element(find.text('шторка')));
    final route = ModalRoute.of(tester.element(find.text('шторка')))!;
    navigator.removeRoute(route);
    await tester.pump();
    await tester.pump();
    expect(cover.value, isFalse,
        reason: 'иначе экран под шторкой остался бы невидимым навсегда');
    expect(hidden(tester), isFalse);
  });

  testWidgets('под закрытым экраном нажатия не проходят', (tester) async {
    await pumpApp(tester);
    cover.value = true;
    await tester.pump();
    final ignoring = tester.widget<Visibility>(find.ancestor(
      of: find.text('под шторкой'),
      matching: find.byType(Visibility),
    ));
    expect(ignoring.maintainInteractivity, isFalse);
    expect(ignoring.maintainSize, isTrue,
        reason: 'раскладка не должна меняться, пока спрятано');
  });
}
