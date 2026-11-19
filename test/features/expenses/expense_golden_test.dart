@Tags(['golden'])
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/router.dart';

import '../../helpers/screen_golden.dart';
import '../../helpers/session.dart';

void main() {
  for (final MapEntry(key: variant, value: prefs) in goldenVariants.entries) {
    testWidgets('expense $variant', (tester) async {
      final (db, farm) = await farmDatabase(
        crops: const ['Coconut', 'Pepper', 'Banana'],
      );
      await expectScreenGolden(
        tester,
        'expense',
        variant,
        farmOverrides(db, farm, prefs),
        (tester) async {
          ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
              .read(routerProvider)
              .push('/add/expense');
          await settle(tester);
          await tester.pump(const Duration(seconds: 1));
          await tester.enterText(
            find.byKey(const Key('expense.amount')),
            '3600',
          );
          await tester.tap(
            find.byKey(const Key('expense.category.fertiliser')),
          );
          await settle(tester);
        },
      );
    });
  }
}
