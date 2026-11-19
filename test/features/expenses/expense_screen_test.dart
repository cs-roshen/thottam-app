import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/app.dart';
import 'package:thottam/app/router.dart';
import 'package:thottam/core/db/database.dart';

import '../../helpers/screen_golden.dart';
import '../../helpers/session.dart';

void main() {
  late ProviderContainer container;

  Future<AppDatabase> pumpApp(
    WidgetTester tester, {
    List<String> crops = const ['Coconut', 'Pepper', 'Banana'],
    String role = 'owner',
    String? path = '/add/expense',
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final (db, farm) = await farmDatabase(crops: crops, role: role);
    container = ProviderContainer(overrides: farmOverrides(db, farm));
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ThottamApp(),
      ),
    );
    await settle(tester);
    if (path != null) {
      container.read(routerProvider).push(path);
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
    }
    return db;
  }

  Finder key(String k) => find.byKey(Key(k));

  Future<void> reveal(WidgetTester tester, Finder f) async {
    if (f.evaluate().isEmpty) {
      final list = find.byType(Scrollable).first;
      try {
        await tester.scrollUntilVisible(
          f,
          200,
          scrollable: list,
          maxScrolls: 20,
        );
      } on StateError {
        await tester.scrollUntilVisible(f, -200, scrollable: list);
      }
    }
    await tester.ensureVisible(f);
    await tester.pump();
  }

  Future<void> type(WidgetTester tester, String k, String text) async {
    await reveal(tester, key(k));
    await tester.enterText(key(k), text);
    await settle(tester);
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await reveal(tester, f);
    await tester.tap(f);
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
  }

  Future<List<Map<String, Object?>>> rows(AppDatabase db, String sql) async => [
    for (final r in await db.customSelect(sql).get()) r.data,
  ];

  testWidgets('a typical expense in four taps from the add button: ₹3,600 '
      'splits 2,160 / 1,080 / 360', (tester) async {
    final db = await pumpApp(tester, path: null);
    var taps = 0;
    Future<void> tapCounted(Finder f) async {
      taps++;
      await tap(tester, f);
    }

    await tapCounted(
      find.descendant(of: key('shell.nav'), matching: find.byIcon(Icons.add)),
    );
    await tapCounted(find.text('Expense'));
    // the amount field opens focused, with the number keypad
    await type(tester, 'expense.amount', '3600');
    expect(find.text('₹2,160'), findsOneWidget);
    expect(find.text('₹1,080'), findsOneWidget);
    expect(find.text('₹360'), findsOneWidget);
    await tapCounted(key('expense.category.fertiliser'));
    await tapCounted(key('expense.save'));
    expect(taps, lessThanOrEqualTo(6));
    expect(find.text('Saved'), findsOneWidget);
    final parts = await rows(
      db,
      'SELECT a.amount_paise FROM expense_allocations a '
      'JOIN crop_cycles c ON c.id = a.crop_cycle_id '
      'JOIN crops k ON k.id = c.crop_id ORDER BY a.amount_paise DESC',
    );
    expect(parts.map((p) => p['amount_paise']), [216000, 108000, 36000]);
  });

  testWidgets('edit the split by hand, then change the amount: the parts '
      'still sum to it', (tester) async {
    final db = await pumpApp(tester);
    await type(tester, 'expense.amount', '3600');
    await tap(tester, key('split.edit'));
    await type(tester, 'split.part.0', '2000');
    await type(tester, 'expense.amount', '4000');
    await tap(tester, key('expense.category.seeds'));
    await tap(tester, key('expense.save'));
    final parts = await rows(
      db,
      'SELECT amount_paise, is_manual FROM expense_allocations',
    );
    expect(
      parts.fold<int>(0, (s, p) => s + (p['amount_paise']! as int)),
      400000,
    );
    expect(parts.map((p) => p['amount_paise']), contains(200000));
    expect(parts.every((p) => p['is_manual'] == 1), isTrue);
  });

  testWidgets('split equally from the split choices: ₹100 → 33.34, 33.33, '
      '33.33', (tester) async {
    final db = await pumpApp(tester);
    await type(tester, 'expense.amount', '100');
    await tap(tester, key('split.edit'));
    await tap(tester, key('split.mode.equal'));
    await tap(tester, key('expense.category.seeds'));
    await tap(tester, key('expense.save'));
    final parts = await rows(
      db,
      'SELECT amount_paise FROM expense_allocations ORDER BY created_at',
    );
    expect(parts.map((p) => p['amount_paise']), [3334, 3333, 3333]);
  });

  testWidgets('credit asks who from, and leaves a payable', (tester) async {
    final db = await pumpApp(tester, crops: const ['Pepper']);
    await type(tester, 'expense.amount', '1200');
    await tap(tester, key('expense.category.fertiliser'));
    await tap(tester, key('expense.mode.credit'));
    expect(
      find.text('Bought on credit: kept as a payable until it is paid'),
      findsOneWidget,
    );
    await type(tester, 'expense.vendor', 'Kerala Agro');
    await tap(tester, key('expense.save'));
    final e = (await rows(db, 'SELECT * FROM expenses')).single;
    expect(e['mode'], 'credit');
    expect(e['vendor_party_id'], isNotNull);
    // one crop: the whole amount goes to it
    expect(
      (await rows(db, 'SELECT amount_paise FROM expense_allocations')).single,
      {'amount_paise': 120000},
    );
  });

  testWidgets('an amount and a category are needed', (tester) async {
    await pumpApp(tester);
    container.read(routerProvider).pop();
    await settle(tester);
    container.read(routerProvider).push('/add/expense');
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    await tap(tester, key('expense.save'));
    expect(find.text('Enter the amount'), findsOneWidget);
  });

  testWidgets('a supervisor cannot save an expense', (tester) async {
    await pumpApp(tester, role: 'supervisor');
    expect(
      find.text(
        'Only the owner, a manager or an accountant can record expenses.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(
              of: key('expense.save'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('the expense screen fits a small phone at the largest text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester);
    tester.view.physicalSize = const Size(720, 1480);
    tester.view.devicePixelRatio = 2;
    await settle(tester);
    await type(tester, 'expense.amount', '3600');
    await tap(tester, key('split.edit'));
    await tap(tester, key('expense.mode.credit'));
    await reveal(tester, key('expense.vendor'));
    expect(key('expense.vendor'), findsOneWidget);
  });
}
