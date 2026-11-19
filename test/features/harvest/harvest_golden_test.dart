@Tags(['golden'])
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/router.dart';

import '../../helpers/screen_golden.dart';
import '../../helpers/session.dart';
import 'harvest_screen_test.dart' show biju;

void main() {
  Future<void> go(WidgetTester tester) async {
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
        .read(routerProvider)
        .push('/add/harvest');
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pump();
    await tester.tap(find.byKey(Key(key)));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
  }

  final screens = <String, Future<void> Function(WidgetTester)>{
    'harvest': (tester) async {
      await go(tester);
      await tester.enterText(find.byKey(const Key('harvest.total')), '120');
      await tap(tester, 'harvest.addGroup');
      await tester.scrollUntilVisible(
        find.byKey(const Key('harvest.team.0.heads')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
    },
    'lot': (tester) async {
      await go(tester);
      await tester.enterText(find.byKey(const Key('harvest.total')), '120');
      await tap(tester, 'harvest.addGroup');
      await tap(tester, 'harvest.save');
    },
  };

  for (final MapEntry(key: variant, value: prefs) in goldenVariants.entries) {
    for (final MapEntry(key: name, value: steps) in screens.entries) {
      testWidgets('$name $variant', (tester) async {
        final (db, farm) = await farmDatabase(
          crops: const ['Pepper'],
          seed: biju,
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
