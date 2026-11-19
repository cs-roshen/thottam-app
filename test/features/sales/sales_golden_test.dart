@Tags(['golden'])
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/router.dart';

import '../../helpers/screen_golden.dart';
import '../../helpers/session.dart';
import 'sales_repository_test.dart' show twoLots;

void main() {
  Future<void> go(WidgetTester tester, String path) async {
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
        .read(routerProvider)
        .push(path);
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
  }

  final screens = <String, Future<void> Function(WidgetTester)>{
    'sell': (tester) async {
      await go(tester, '/add/sale');
      await tester.enterText(find.byKey(const Key('sale.quantity')), '50');
      await tester.enterText(find.byKey(const Key('sale.rate')), '705');
      await settle(tester);
    },
    'sell_empty': (tester) => go(tester, '/add/sale'),
  };

  for (final MapEntry(key: variant, value: prefs) in goldenVariants.entries) {
    for (final MapEntry(key: name, value: steps) in screens.entries) {
      testWidgets('$name $variant', (tester) async {
        final (db, farm) = await farmDatabase(
          crops: const ['Pepper'],
          seed: name == 'sell_empty' ? null : twoLots,
        );
        await expectScreenGolden(
          tester,
          name,
          variant,
          farmOverrides(db, farm, prefs),
          steps,
        );
      });
    }
  }
}
