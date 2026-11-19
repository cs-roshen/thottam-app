@Tags(['golden'])
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/router.dart';
import 'package:thottam/core/history/write_with_history.dart';

import '../../helpers/screen_golden.dart';
import '../../helpers/session.dart';
import 'labour_screens_test.dart' show fourWorkers;

void main() {
  Future<void> go(WidgetTester tester, String path) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    container.read(routerProvider).push(path);
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final f = find.byKey(Key(key));
    if (f.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        f,
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await settle(tester);
  }

  final screens = <String, Future<void> Function(WidgetTester)>{
    'labour_named': (tester) async {
      await go(tester, '/add/labour');
      await tap(tester, 'worker.w4.overtime'); // Anu, listed first
    },
    'labour_group': (tester) async {
      await go(tester, '/add/labour');
      await tap(tester, 'labour.mode');
      final mode = tester.getRect(find.byKey(const Key('labour.mode')));
      await tester.tapAt(mode.centerRight - const Offset(40, 0));
      await settle(tester);
    },
    'labour_team': (tester) => go(tester, '/labour/team'),
    'labour_ledger': (tester) => go(tester, '/labour/worker/w1'),
  };

  for (final MapEntry(key: variant, value: prefs) in goldenVariants.entries) {
    for (final MapEntry(key: name, value: steps) in screens.entries) {
      testWidgets('$name $variant', (tester) async {
        final (db, farm) = await farmDatabase(
          crops: const ['Coconut', 'Pepper'],
          seed: (db, history, farm) async {
            await fourWorkers(db, history, farm);
            await history.writeWithHistory([
              CreateRow('labour_entries', {
                'farm_id': farm,
                'work_date': '2026-11-18',
                'worker_id': 'w1',
                'rate_paise': 90000,
                'amount_paise': 90000,
              }),
              CreateRow('labour_payments', {
                'farm_id': farm,
                'paid_on': '2026-11-18',
                'worker_id': 'w1',
                'kind': 'advance',
                'amount_paise': 20000,
              }),
            ]);
          },
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
