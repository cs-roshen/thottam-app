@Tags(['golden'])
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/router.dart';

import '../../helpers/screen_golden.dart';
import '../../helpers/session.dart';
import 'history_test.dart' show aDayOfWork;

void main() {
  Future<void> go(WidgetTester tester) async {
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
        .read(routerProvider)
        .push('/history');
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
  }

  for (final MapEntry(key: variant, value: prefs) in goldenVariants.entries) {
    testWidgets('history $variant', (tester) async {
      final (db, farm) = await farmDatabase(
        crops: const ['Pepper'],
        seed: aDayOfWork,
      );
      await expectScreenGolden(
        tester,
        'history',
        variant,
        farmOverrides(db, farm, prefs),
        go,
      );
    });
  }
}
