@Tags(['golden'])
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/router.dart';

import '../../helpers/screen_golden.dart';
import '../../helpers/session.dart';
import 'money_screen_test.dart' show withHill;

void main() {
  Future<void> go(WidgetTester tester) async {
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
        .read(routerProvider)
        .go('/money');
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
  }

  for (final MapEntry(key: variant, value: prefs) in goldenVariants.entries) {
    testWidgets('profit and loss $variant', (tester) async {
      final (db, farm) = await farmDatabase(
        crops: const ['Coconut', 'Pepper', 'Banana'],
        seed: withHill,
      );
      await expectScreenGolden(
        tester,
        'money',
        variant,
        farmOverrides(db, farm, prefs),
        go,
      );
    });
  }

  testWidgets('profit and loss empty', (tester) async {
    final (db, farm) = await farmDatabase(crops: const ['Pepper']);
    await expectScreenGolden(
      tester,
      'money',
      'empty',
      farmOverrides(db, farm, goldenVariants['ml']!),
      go,
    );
  });
}
