import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protogenix/app/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  testWidgets('App smoke test', skip: true, (WidgetTester tester) async {
    tester.binding.window.physicalSizeTestValue = const Size(800, 600);
    tester.binding.window.devicePixelRatioTestValue = 1.0;
    await tester.pumpWidget(const ProviderScope(child: ProtogenixApp()));
    // await tester.pumpAndSettle();
    expect(find.byType(ProtogenixApp), findsOneWidget);
  });
}
