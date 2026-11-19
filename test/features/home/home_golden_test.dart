@Tags(['golden'])
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/router.dart';

import '../../helpers/screen_golden.dart';
import '../../helpers/session.dart';
import 'home_test_farm.dart';

void main() {
  Future<void> stay(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
  }

  for (final MapEntry(key: variant, value: prefs) in goldenVariants.entries) {
    testWidgets('home $variant', (tester) async {
      final (db, farm) = await farmDatabase(
        crops: const ['Coconut', 'Pepper', 'Banana'],
        seed: homeFarm,
      );
      await expectScreenGolden(
        tester,
        'home',
        variant,
        farmOverrides(db, farm, prefs),
        stay,
      );
    });
  }

  testWidgets('home empty', (tester) async {
    final (db, farm) = await farmDatabase(crops: const ['Pepper']);
    await expectScreenGolden(
      tester,
      'home',
      'empty',
      farmOverrides(db, farm, goldenVariants['ml']!),
      stay,
    );
  });

  testWidgets('note ml', (tester) async {
    final (db, farm) = await farmDatabase(
      crops: const ['Coconut', 'Pepper', 'Banana'],
    );
    await expectScreenGolden(
      tester,
      'note',
      'ml',
      farmOverrides(db, farm, goldenVariants['ml']!),
      (tester) async {
        ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
            .read(routerProvider)
            .push('/add/note');
        await settle(tester);
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.text('Riverside'));
        await settle(tester);
      },
    );
  });
}
