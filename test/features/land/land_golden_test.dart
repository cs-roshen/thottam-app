@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/screen_golden.dart';
import '../../helpers/session.dart';
import 'land_screens_test.dart' show anExpense;

void main() {
  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> toLand(WidgetTester tester) =>
      tap(tester, find.byIcon(Icons.landscape_outlined).last);

  final screens = <String, Future<void> Function(WidgetTester)>{
    'land': toLand,
    'plot_detail': (tester) async {
      await toLand(tester);
      await tap(tester, find.text('Riverside'));
    },
    'plot_costs': (tester) async {
      await toLand(tester);
      await tap(tester, find.text('Riverside'));
      await tap(tester, find.byKey(const Key('plot.tabs')));
      final tabs = tester.getRect(find.byKey(const Key('plot.tabs')));
      await tester.tapAt(tabs.center);
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
    },
    'plot_form': (tester) async {
      await toLand(tester);
      await tap(tester, find.byKey(const Key('land.add')));
    },
    'cycle_form': (tester) async {
      await toLand(tester);
      await tap(tester, find.text('Riverside'));
      await tester.ensureVisible(find.byKey(const Key('plot.addCrop')));
      await tap(tester, find.byKey(const Key('plot.addCrop')));
      await tap(tester, find.byKey(const Key('cycle.crop.Coconut')));
    },
  };

  for (final MapEntry(key: variant, value: prefs) in goldenVariants.entries) {
    for (final MapEntry(key: name, value: go) in screens.entries) {
      testWidgets('$name $variant', (tester) async {
        final (db, farm) = await farmDatabase(
          crops: const ['Coconut', 'Pepper'],
          seed: anExpense,
        );
        await expectScreenGolden(
          tester,
          name,
          variant,
          farmOverrides(db, farm, prefs),
          go,
        );
      });
    }
  }

  testWidgets('land empty', (tester) async {
    final (db, farm) = await farmDatabase();
    await db.customStatement('UPDATE plots SET deleted_at = 1');
    await expectScreenGolden(
      tester,
      'land',
      'empty',
      farmOverrides(db, farm, goldenVariants['ml']!),
      toLand,
    );
  });
}
