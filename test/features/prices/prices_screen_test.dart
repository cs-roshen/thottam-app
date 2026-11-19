import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:thottam/app/app.dart';
import 'package:thottam/app/router.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/history/write_with_history.dart';
import 'package:thottam/features/prices/data/prices_repository.dart';

import '../../helpers/screen_golden.dart';
import '../../helpers/session.dart';
import 'prices_test_farm.dart';

void main() {
  group('repository', () {
    late AppDatabase db;
    late PricesRepository repo;
    late String pepper;

    setUp(() async {
      final (d, farm) = await farmDatabase(
        crops: const ['Pepper', 'Coconut'],
        seed: priceFarm,
      );
      db = d;
      var now = DateTime(2026, 11, 19, 12);
      repo = PricesRepository(
        db,
        History(
          db,
          userId: testUser,
          clock: () => now = now.add(const Duration(milliseconds: 10)),
          random: Random(13),
        ),
        farm,
        testUser,
      );
      pepper =
          (await db
                  .customSelect("SELECT id FROM crops WHERE name_en = 'Pepper'")
                  .getSingle())
              .read<String>('id');
    });
    tearDown(() => db.close());

    test('official prices and the farm\'s own rate, newest first', () async {
      await repo.addPrice(
        cropId: pepper,
        paise: 71000,
        unit: 'kg',
        market: ' Joseph Stores ',
        at: DateTime(2026, 11, 19, 11),
      );
      final p = (await repo.watch([pepper]).first)[pepper]!;
      expect(p.points.first.market, 'Joseph Stores');
      expect(p.points.first.local, isTrue);
      expect(p.points.skip(1).every((x) => !x.local), isTrue);
      final row = await db
          .customSelect(
            "SELECT source FROM market_prices WHERE market = 'Joseph Stores'",
          )
          .getSingle();
      expect(row.read<String>('source'), 'local');
    });

    test('an alert: on at a threshold, changed, off', () async {
      await repo.setAlert(pepper, 70000);
      expect((await repo.watch([pepper]).first)[pepper]!.alertPaise, 70000);
      await repo.setAlert(pepper, 72000);
      expect((await repo.watch([pepper]).first)[pepper]!.alertPaise, 72000);
      await repo.setAlert(pepper, null);
      expect((await repo.watch([pepper]).first)[pepper]!.alertPaise, isNull);
      final rows = await db
          .customSelect('SELECT COUNT(*) AS n FROM price_alerts')
          .getSingle();
      expect(rows.read<int>('n'), 1);
    });
  });

  group('screen', () {
    late ProviderContainer container;

    Future<void> pumpPrices(
      WidgetTester tester, {
      String role = 'owner',
      bool small = false,
      Map<String, Object?> prefs = const {'settings.language': 'english'},
    }) async {
      tester.view.physicalSize = small
          ? const Size(720, 1480)
          : const Size(1080, 2400);
      tester.view.devicePixelRatio = small ? 2 : 2.625;
      addTearDown(tester.view.reset);
      final (db, farm) = await farmDatabase(
        crops: const ['Pepper', 'Coconut'],
        role: role,
        seed: priceFarm,
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
      container.read(routerProvider).push('/prices');
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
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
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('each crop: price, change, source and time; a price older '
        'than one day is marked', (tester) async {
      await pumpPrices(tester);
      expect(find.text('₹705 / kg'), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(const Key('prices.change')).first,
          matching: find.text('₹5'),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
      expect(find.text('Spices Board · 19 Nov, 10:00 AM'), findsWidgets);
      // coconut's price is four days old
      expect(find.text('Old price · 15 Nov'), findsOneWidget);
      // pepper, chosen first: its line and markets
      expect(find.text('Low ₹690 · High ₹705'), findsOneWidget);
      expect(find.text('Kattappana'), findsOneWidget);
      expect(find.text('₹698 / kg'), findsOneWidget);
    });

    testWidgets('choosing another crop shows its prices', (tester) async {
      await pumpPrices(tester);
      await tap(tester, find.byKey(const Key('prices.crop.Coconut')));
      expect(find.text('Low ₹32 · High ₹32'), findsOneWidget);
    });

    testWidgets('a shop rate entered by hand shows as the farm\'s own', (
      tester,
    ) async {
      await pumpPrices(tester);
      await tap(tester, find.byKey(const Key('prices.add')));
      await tap(tester, find.byKey(const Key('price.save')));
      expect(find.text('Enter the price'), findsOneWidget);
      expect(find.text('Name the market or shop'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('price.amount')),
          matching: find.byType(TextField),
        ),
        '712',
      );
      await tester.enterText(
        find.byKey(const Key('price.market')),
        'Joseph Stores',
      );
      await tap(tester, find.byKey(const Key('price.save')));
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('₹712 / kg'), findsWidgets);
      expect(find.textContaining('Your entry · Joseph Stores'), findsWidgets);
    });

    testWidgets('a price alert: switched on with a threshold, shown when the '
        'price is above it', (tester) async {
      await pumpPrices(tester);
      await tap(tester, find.byKey(const Key('prices.alert')));
      await tester.enterText(find.byKey(const Key('alert.amount')), '700');
      await tap(tester, find.byKey(const Key('alert.save')));
      expect(find.text('Notify when above ₹700'), findsOneWidget);
      expect(find.text('Above your alert of ₹700'), findsOneWidget);
    });

    testWidgets('a supervisor reads prices but adds no rates or alerts', (
      tester,
    ) async {
      await pumpPrices(tester, role: 'supervisor');
      expect(find.text('₹705 / kg'), findsWidgets);
      expect(find.byKey(const Key('prices.add')), findsNothing);
      await tester.scrollUntilVisible(
        find.text(
          'Only the owner, a manager or the accountant can add prices and '
          'alerts.',
        ),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final alert = tester.widget<SwitchListTile>(
        find.descendant(
          of: find.byKey(const Key('prices.alert')),
          matching: find.byType(SwitchListTile),
        ),
      );
      expect(alert.onChanged, isNull);
    });

    testWidgets('Malayalam, large text, on a 360 dp phone: nothing '
        'overflows', (tester) async {
      await pumpPrices(
        tester,
        small: true,
        prefs: const {
          'settings.language': 'malayalam',
          'settings.large_text': true,
        },
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('prices.add')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tap(tester, find.byKey(const Key('prices.add')));
      expect(tester.takeException(), isNull);
    });
  });
}
