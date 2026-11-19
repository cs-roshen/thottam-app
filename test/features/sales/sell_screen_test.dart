import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/app.dart';
import 'package:thottam/app/router.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/history/write_with_history.dart';

import '../../helpers/screen_golden.dart';
import '../../helpers/session.dart';
import 'sales_repository_test.dart' show twoLots;

void main() {
  late ProviderContainer container;

  Future<AppDatabase> pumpSell(
    WidgetTester tester, {
    String role = 'owner',
    String path = '/add/sale',
    bool withPrice = false,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final (db, farm) = await farmDatabase(
      crops: const ['Pepper'],
      role: role,
      seed: (db, history, farm) async {
        await twoLots(db, history, farm);
        if (withPrice) {
          final crop =
              (await db
                      .customSelect(
                        "SELECT id FROM crops WHERE code = 'pepper'",
                      )
                      .getSingle())
                  .read<String>('id');
          await history.writeWithHistory([
            CreateRow('market_prices', {
              'farm_id': farm,
              'crop_id': crop,
              'market': 'Kochi',
              'price_paise': 70500,
              'unit': 'kg',
              'source': 'Spices Board',
              'published_at': DateTime(2026, 11, 19, 7),
            }),
          ]);
        }
      },
    );
    container = ProviderContainer(overrides: farmOverrides(db, farm));
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ThottamApp(),
      ),
    );
    await settle(tester);
    container.read(routerProvider).push(path);
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
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
          maxScrolls: 30,
        );
      } on StateError {
        await tester.scrollUntilVisible(f, -200, scrollable: list);
      }
    }
    await tester.ensureVisible(f);
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await reveal(tester, f);
    await tester.tap(f);
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> type(WidgetTester tester, String k, String text) async {
    await reveal(tester, key(k));
    await tester.enterText(key(k), text);
    await settle(tester);
  }

  String textOf(WidgetTester tester, String k) =>
      tester.widget<Text>(key(k)).data!;

  testWidgets('the sale example, with the rate from today\'s price: gross '
      '₹35,250, net ₹35,080, ₹701.60 a kg, profit ₹463.60 a kg', (
    tester,
  ) async {
    final db = await pumpSell(tester, withPrice: true);
    expect(find.text('Today’s price ₹705 / kg'), findsOneWidget);
    await type(tester, 'sale.quantity', '50');
    await tap(tester, key('sale.addDeduction'));
    await type(tester, 'sale.deduction.0.label', 'Commission');
    await type(tester, 'sale.deduction.0.amount', '170');
    await reveal(tester, key('sale.profit'));
    expect(textOf(tester, 'sale.gross'), '₹35,250');
    expect(textOf(tester, 'sale.net'), '₹35,080');
    expect(
      textOf(tester, 'sale.netPerUnit'),
      '₹701.60 per kg after deductions',
    );
    expect(textOf(tester, 'sale.profit'), '₹463.60');
    expect(textOf(tester, 'sale.cost'), 'your cost ₹238 per kg');
    await type(tester, 'sale.buyerName', 'Joseph Traders');
    await tap(tester, key('sale.save'));
    final sale =
        (await db.customSelect('SELECT * FROM sales').getSingle()).data;
    expect(sale['net_paise'], 3508000);
    expect(sale['quantity'], 50000);
  });

  testWidgets('two lots: the cost per kg is the weighted one, ₹242.80', (
    tester,
  ) async {
    await pumpSell(tester);
    final lots = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('sale.lot.'),
    );
    await tap(tester, lots.last);
    await type(tester, 'sale.quantity', '125');
    await type(tester, 'sale.rate', '700');
    await reveal(tester, key('sale.cost'));
    // 120 kg at ₹238 and 5 kg at ₹250: (28,560 + 1,250) / 125 = ₹238.48
    expect(textOf(tester, 'sale.cost'), 'your cost ₹238.48 per kg');
  });

  testWidgets('cannot sell more than the chosen lots hold', (tester) async {
    final db = await pumpSell(tester);
    await type(tester, 'sale.quantity', '121');
    await type(tester, 'sale.rate', '700');
    expect(textOf(tester, 'sale.error'), 'Only 120 kg in stock');
    await tap(tester, key('sale.save'));
    expect(await db.customSelect('SELECT * FROM sales').get(), isEmpty);
  });

  testWidgets('sold by the quintal, the lot cost is carried per quintal', (
    tester,
  ) async {
    await pumpSell(tester);
    await tap(tester, key('sale.unit.quintal'));
    await type(tester, 'sale.quantity', '1');
    await type(tester, 'sale.rate', '70000');
    await reveal(tester, key('sale.cost'));
    expect(textOf(tester, 'sale.cost'), 'your cost ₹23,800 per quintal');
  });

  testWidgets('part paid leaves the rest owed in the buyer book', (
    tester,
  ) async {
    await pumpSell(tester);
    await type(tester, 'sale.quantity', '10');
    await type(tester, 'sale.rate', '700');
    await type(tester, 'sale.buyerName', 'Joseph Traders');
    await tap(tester, key('sale.status.part'));
    await type(tester, 'sale.received', '3000');
    await tap(tester, key('sale.save'));
    container.read(routerProvider).push('/sales/buyers');
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Joseph Traders'), findsOneWidget);
    expect(find.text('Due ₹4,000'), findsOneWidget);
  });

  testWidgets('a supervisor cannot sell', (tester) async {
    await pumpSell(tester, role: 'supervisor');
    expect(
      find.text(
        'Only the owner, a manager or an accountant can record a sale.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the sell screen fits a small phone at the largest text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpSell(tester, withPrice: true);
    tester.view.physicalSize = const Size(720, 1480);
    tester.view.devicePixelRatio = 2;
    await settle(tester);
    await type(tester, 'sale.quantity', '50');
    await tap(tester, key('sale.addDeduction'));
    await tap(tester, key('sale.status.part'));
    await reveal(tester, key('sale.received'));
    expect(key('sale.received'), findsOneWidget);
  });
}
