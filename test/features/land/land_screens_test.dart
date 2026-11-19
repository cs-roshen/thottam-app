import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/app.dart';
import 'package:thottam/app/widgets/widgets.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/history/write_with_history.dart';

import '../../helpers/screen_golden.dart';
import '../../helpers/session.dart';

/// ₹3,600 of fertiliser on the set-up plot's coconut.
Future<void> anExpense(AppDatabase db, History history, String farm) async {
  final plot = (await db.customSelect('SELECT id FROM plots').getSingle())
      .read<String>('id');
  final cycle =
      (await db.customSelect('SELECT id FROM crop_cycles LIMIT 1').getSingle())
          .read<String>('id');
  await history.writeWithHistory([
    CreateRow(
      'expenses',
      {
        'id': 'e1',
        'farm_id': farm,
        'spent_on': '2026-11-18',
        'category_code': 'fertiliser',
        'amount_paise': 360000,
        'plot_id': plot,
      },
      summary: {'plot_id': plot, 'amount_paise': 360000},
    ),
    CreateRow('expense_allocations', {
      'farm_id': farm,
      'expense_id': 'e1',
      'crop_cycle_id': cycle,
      'amount_paise': 360000,
    }),
  ]);
}

void main() {
  Future<AppDatabase> pumpLand(
    WidgetTester tester, {
    List<String> crops = const ['Coconut', 'Pepper'],
    String role = 'owner',
    bool withExpense = true,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final (db, farm) = await farmDatabase(
      crops: crops,
      role: role,
      seed: withExpense ? anExpense : null,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: farmOverrides(db, farm),
        child: const ThottamApp(),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('My land').last);
    await settle(tester);
    return db;
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    if (f.evaluate().isEmpty) {
      // a lazy list builds what is near the screen only
      await tester.scrollUntilVisible(
        f,
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(f);
    await tester.pump(); // the scroll lands on the next frame
    await tester.tap(f);
    await settle(tester);
    // page transitions on Android take up to 800 ms
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('the list shows each plot with area, tenure, crops and the '
      'mixed-crop tag', (tester) async {
    await pumpLand(tester);
    expect(find.text('Riverside'), findsOneWidget);
    expect(find.text('50 cent · Owned'), findsOneWidget);
    expect(find.text('Coconut'), findsOneWidget);
    expect(find.text('Pepper'), findsOneWidget);
    expect(find.text('Mixed crop'), findsOneWidget);
    expect(find.text('1 plot · 50 cent'), findsOneWidget);
  });

  testWidgets('add a plot, then undo it', (tester) async {
    final db = await pumpLand(tester);
    await tap(tester, find.byKey(const Key('land.add')));
    expect(find.text('Add a plot'), findsWidgets);
    await tap(tester, find.byKey(const Key('plot.save')));
    expect(find.text('Enter a name for the plot'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('plot.name')), 'Paddy field');
    await tester.enterText(find.byKey(const Key('plot.area')), '1');
    await tap(tester, find.byKey(const Key('plot.unit.acre')));
    await tap(tester, find.byKey(const Key('plot.tenure.leased')));
    await tap(tester, find.byKey(const Key('plot.save')));

    expect(find.widgetWithText(ThottamCard, 'Paddy field'), findsOneWidget);
    expect(find.text('1 acre · Leased'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    await tap(tester, find.text('Undo'));
    expect(find.widgetWithText(ThottamCard, 'Paddy field'), findsNothing);
    expect(
      (await db
              .customSelect(
                'SELECT COUNT(*) AS n FROM plots WHERE deleted_at IS NULL',
              )
              .getSingle())
          .read<int>('n'),
      1,
    );
  });

  testWidgets('plot detail: stats, costs by category and recent history', (
    tester,
  ) async {
    await pumpLand(tester);
    await tap(tester, find.text('Riverside'));
    expect(find.text('Season cost'), findsOneWidget);
    expect(find.text('₹3,600'), findsOneWidget);
    expect(find.text('Spent ₹3,600'), findsOneWidget);
    expect(find.text('Spent ₹0'), findsOneWidget);
    await tap(tester, find.text('Costs'));
    expect(find.text('Fertiliser'), findsOneWidget);
    await tap(tester, find.text('History'));
    expect(find.text('Expense added'), findsOneWidget);
    expect(find.text('Plot added'), findsOneWidget);
  });

  testWidgets('deleting a plot says how many entries stay, keeps them, and '
      'undo brings the plot back', (tester) async {
    final db = await pumpLand(tester);
    await tap(tester, find.text('Riverside'));
    await tap(tester, find.byKey(const Key('plot.menu')));
    await tap(tester, find.byKey(const Key('plot.delete')));
    expect(find.text('Delete Riverside?'), findsOneWidget);
    expect(
      find.text(
        '1 entry is recorded on it. It stays in history and in profit and loss.',
      ),
      findsOneWidget,
    );
    await tap(tester, find.byKey(const Key('delete.confirm')));

    expect(find.text('No plots yet'), findsOneWidget);
    expect(find.text('Plot deleted'), findsOneWidget);
    expect(
      (await db
              .customSelect(
                'SELECT COUNT(*) AS n FROM expenses WHERE deleted_at IS NULL',
              )
              .getSingle())
          .read<int>('n'),
      1,
    );
    await tap(tester, find.text('Undo'));
    expect(find.text('Riverside'), findsOneWidget);
  });

  testWidgets('add a crop to a plot', (tester) async {
    await pumpLand(tester, crops: const [], withExpense: false);
    await tap(tester, find.text('Riverside'));
    expect(find.text('No crops on this plot yet.'), findsOneWidget);
    await tap(tester, find.byKey(const Key('plot.addCrop')));
    await tap(tester, find.byKey(const Key('cycle.save')));
    expect(find.text('Choose a crop'), findsOneWidget);
    await tap(tester, find.byKey(const Key('cycle.crop.Coconut')));
    await tester.enterText(find.byKey(const Key('cycle.plants')), '60');
    await tester.enterText(find.byKey(const Key('cycle.year')), '2015');
    await settle(tester);
    await tap(tester, find.byKey(const Key('cycle.save')));
    expect(find.text('Coconut'), findsOneWidget);
    expect(find.text('60 plants · Planted 2015'), findsOneWidget);
  });

  testWidgets('a viewer sees the land read-only', (tester) async {
    await pumpLand(tester, role: 'viewer');
    expect(find.byKey(const Key('land.add')), findsNothing);
    expect(
      find.text('Only the owner or a manager can change plots and crops.'),
      findsOneWidget,
    );
    await tap(tester, find.text('Riverside'));
    expect(find.byKey(const Key('plot.menu')), findsNothing);
    expect(find.byKey(const Key('plot.addCrop')), findsNothing);
    expect(find.byKey(const Key('plot.addExpense')), findsNothing);
  });

  testWidgets('a supervisor sees no money on a plot', (tester) async {
    await pumpLand(tester, role: 'supervisor');
    await tap(tester, find.text('Riverside'));
    expect(find.text('Season cost'), findsNothing);
    expect(find.text('Spent ₹3,600'), findsNothing);
    expect(find.byKey(const Key('plot.addExpense')), findsNothing);
    expect(find.byKey(const Key('plot.addHarvest')), findsOneWidget);
  });

  testWidgets('the land screens fit a small phone at the largest text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpLand(tester);
    tester.view.physicalSize = const Size(720, 1480);
    tester.view.devicePixelRatio = 2;
    await settle(tester);
    await tap(tester, find.text('Riverside'));
    await tap(tester, find.text('Costs'));
    await tap(tester, find.text('History'));
    await tap(tester, find.byKey(const Key('plot.menu')));
    await tap(tester, find.text('Edit'));
    expect(find.byKey(const Key('plot.save')), findsOneWidget);
  });
}
