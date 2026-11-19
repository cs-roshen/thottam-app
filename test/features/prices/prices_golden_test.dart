@Tags(['golden'])
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/router.dart';

import '../../helpers/screen_golden.dart';
import '../../helpers/session.dart';
import 'prices_test_farm.dart';

void main() {
  for (final MapEntry(key: variant, value: prefs) in goldenVariants.entries) {
    testWidgets('prices $variant', (tester) async {
      final (db, farm) = await farmDatabase(
        crops: const ['Pepper', 'Coconut'],
        seed: priceFarm,
      );
      await expectScreenGolden(
        tester,
        'prices',
        variant,
        farmOverrides(db, farm, prefs),
        (tester) async {
          ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
              .read(routerProvider)
              .push('/prices');
          await settle(tester);
          await tester.pump(const Duration(seconds: 1));
        },
      );
    });
  }
}
