import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/app.dart';
import 'package:thottam/app/router.dart';
import 'package:thottam/app/session.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/history/write_with_history.dart';
import 'package:thottam/features/expenses/data/expense_repository.dart';
import 'package:thottam/features/land/data/land_repository.dart';

import '../../helpers/screen_golden.dart';
import '../../helpers/session.dart';
import 'money_test_farm.dart';

/// The spec example, and a second plot with only a ₹1,000 bill on it.
Future<void> withHill(AppDatabase db, History history, String farm) async {
  await specExample(db, history, farm);
  final (hill, _) = await LandRepository(
    db,
    history,
    farm,
  ).createPlot(const PlotInput(name: 'Hill', areaUnit: 'cent', area: 10000));
  await ExpenseRepository(db, history, farm).save(
    ExpenseInput(
      day: '2026-11-03',
      categoryCode: 'fertiliser',
      amountPaise: 100000,
      plotId: hill,
    ),
  );
}

void main() {
  late ProviderContainer container;

  Future<void> pumpMoney(
    WidgetTester tester, {
    bool hill = false,
    bool small = false,
    Map<String, Object?> prefs = const {'settings.language': 'english'},
  }) async {
    // 412 dp wide, or 360 dp, the narrowest phones in use
    tester.view.physicalSize = small
        ? const Size(720, 1480)
        : const Size(1080, 2400);
    tester.view.devicePixelRatio = small ? 2 : 2.625;
    addTearDown(tester.view.reset);
    final (db, farm) = await farmDatabase(
      crops: const ['Coconut', 'Pepper', 'Banana'],
      seed: hill ? withHill : specExample,
    );
    container = ProviderContainer(overrides: farmOverrides(db, farm, prefs));
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ThottamApp(),
      ),
    );
    await settle(tester);
    container.read(routerProvider).go('/money');
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(
      f,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(f);
    await settle(tester);
  }

  String textOf(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  testWidgets('the spec example: profit ₹88,300 from ₹1,84,500 in and '
      '₹96,200 out, by crop, family labour left out', (tester) async {
    await pumpMoney(tester);
    expect(find.text('Profit and loss'), findsWidgets);
    expect(
      textOf(tester, 'money.scope'),
      'April 2026 – March 2027 · All plots',
    );
    expect(textOf(tester, 'money.profit'), '₹88,300');
    expect(textOf(tester, 'money.income'), 'Income ₹1,84,500');
    expect(textOf(tester, 'money.expense'), 'Expense ₹96,200');
    for (final (crop, profit, income, expense) in [
      ('Coconut', '₹61,000', 'Income ₹92,000', 'Expense ₹31,000'),
      ('Pepper', '₹24,300', 'Income ₹68,500', 'Expense ₹44,200'),
      ('Banana', '₹3,000', 'Income ₹24,000', 'Expense ₹21,000'),
    ]) {
      final row = find.ancestor(
        of: find.text(crop),
        matching: find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('money.crop.'),
        ),
      );
      for (final t in [profit, income, expense]) {
        expect(
          find.descendant(of: row, matching: find.text(t)),
          findsOneWidget,
          reason: '$crop $t',
        );
      }
    }
    await tester.scrollUntilVisible(
      find.text('Value of own work ₹12,000'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Value of own work ₹12,000'), findsOneWidget);
  });

  testWidgets('switching family labour in: expense ₹1,08,200, profit '
      '₹76,300; and out again', (tester) async {
    await pumpMoney(tester);
    await tap(tester, find.byKey(const Key('money.family')));
    expect(textOf(tester, 'money.expense'), 'Expense ₹1,08,200');
    expect(textOf(tester, 'money.profit'), '₹76,300');
    expect(find.text('Expense ₹36,000'), findsOneWidget);
    await tap(tester, find.byKey(const Key('money.family')));
    expect(textOf(tester, 'money.profit'), '₹88,300');
  });

  testWidgets('last year has nothing yet', (tester) async {
    await pumpMoney(tester);
    await tap(tester, find.text('Last year'));
    expect(
      textOf(tester, 'money.scope'),
      'April 2025 – March 2026 · All plots',
    );
    expect(textOf(tester, 'money.profit'), '₹0');
    expect(
      find.text('Nothing sold or spent in this period yet.'),
      findsOneWidget,
    );
  });

  testWidgets('one plot at a time; a loss says so in words', (tester) async {
    await pumpMoney(tester, hill: true);
    expect(textOf(tester, 'money.profit'), '₹87,300');
    expect(find.text('Not on a crop'), findsOneWidget);
    expect(find.text('Loss ₹1,000'), findsOneWidget);

    await tap(tester, find.widgetWithText(ChoiceChip, 'Hill'));
    expect(textOf(tester, 'money.scope'), 'April 2026 – March 2027 · Hill');
    expect(find.text('Loss'), findsOneWidget);
    expect(textOf(tester, 'money.profit'), '₹1,000');
    expect(find.text('Coconut'), findsNothing);

    await tap(tester, find.widgetWithText(ChoiceChip, 'Riverside'));
    expect(textOf(tester, 'money.profit'), '₹88,300');
    expect(find.text('Not on a crop'), findsNothing);
  });

  testWidgets('share copies the report as text', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    await pumpMoney(tester);
    await tap(tester, find.byKey(const Key('money.family')));
    await tap(tester, find.byKey(const Key('money.share')));
    expect(
      find.text('Report copied. Paste it into a message.'),
      findsOneWidget,
    );
    expect(copied, '''
Profit and loss
April 2026 – March 2027 · All plots
Income ₹1,84,500
Expense ₹1,08,200
Profit ₹76,300

Coconut: income ₹92,000, expense ₹36,000, profit ₹56,000
Pepper: income ₹68,500, expense ₹48,200, profit ₹20,300
Banana: income ₹24,000, expense ₹24,000, profit ₹0

Family labour included: ₹12,000''');
  });

  testWidgets('a new entry shows at once', (tester) async {
    await pumpMoney(tester);
    final db = container.read(databaseProvider);
    final farm = container.read(farmIdProvider);
    final history = History(db, userId: testUser);
    final plot = (await LandRepository(
      db,
      history,
      farm,
    ).watchPlots().first).single;
    await ExpenseRepository(db, history, farm).save(
      ExpenseInput(
        day: '2026-11-19',
        categoryCode: 'fertiliser',
        amountPaise: 30000,
        plotId: plot.id,
        parts: [(plot.cycles.first.id, 30000)],
      ),
    );
    await settle(tester);
    expect(textOf(tester, 'money.expense'), 'Expense ₹96,500');
  });

  testWidgets('Malayalam, large text, on a 360 dp phone: nothing overflows', (
    tester,
  ) async {
    await pumpMoney(
      tester,
      hill: true,
      small: true,
      prefs: const {
        'settings.language': 'malayalam',
        'settings.large_text': true,
      },
    );
    await tap(tester, find.byKey(const Key('money.share')));
    expect(tester.takeException(), isNull);
    expect(find.text('ലാഭ നഷ്ടം'), findsWidgets);
  });
}
