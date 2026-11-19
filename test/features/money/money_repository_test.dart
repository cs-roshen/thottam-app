import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/history/write_with_history.dart';
import 'package:thottam/features/expenses/data/expense_repository.dart';
import 'package:thottam/features/harvest/data/harvest_repository.dart';
import 'package:thottam/features/harvest/domain/harvest_math.dart';
import 'package:thottam/features/land/data/land_repository.dart';
import 'package:thottam/features/money/data/money_repository.dart';
import 'package:thottam/features/money/domain/profit.dart';
import 'package:thottam/features/sales/data/sales_repository.dart';

import '../../helpers/session.dart';
import 'money_test_farm.dart';

void main() {
  late AppDatabase db;
  late String farm;
  late History history;
  late MoneyRepository money;

  setUp(() async {
    final (d, f) = await farmDatabase(
      crops: const ['Coconut', 'Pepper', 'Banana'],
      seed: specExample,
    );
    db = d;
    farm = f;
    var now = DateTime(2026, 11, 19, 12);
    history = History(
      db,
      userId: testUser,
      clock: () => now = now.add(const Duration(milliseconds: 10)),
      random: Random(7),
    );
    money = MoneyRepository(db, farm);
  });
  tearDown(() => db.close());

  Future<ProfitAndLoss> report({
    bool family = false,
    String plot = '',
    String from = '2026-04-01',
    String to = '2027-03-31',
  }) async {
    final rows = await money
        .watchCycles(from: from, to: to, plotId: plot)
        .first;
    final crop = {for (final r in rows) r.money.cycleId: r.nameEn};
    return profitByCrop(
      [for (final r in rows) r.money],
      (c) => crop[c],
      includeFamily: family,
    );
  }

  test('the spec example from real entries: income ₹1,84,500, '
      'expense ₹96,200, profit ₹88,300', () async {
    final p = await report();
    expect(p.incomePaise, 18450000);
    expect(p.expensePaise, 9620000);
    expect(p.profitPaise, 8830000);
    expect(p.familyPaise, 1200000);
    expect(p.rows.map((r) => r.key), ['Coconut', 'Pepper', 'Banana']);
    expect(p.rows.map((r) => r.expensePaise), [3100000, 4420000, 2100000]);
  });

  test('with family labour: expense ₹1,08,200, profit ₹76,300', () async {
    final p = await report(family: true);
    expect(p.expensePaise, 10820000);
    expect(p.profitPaise, 7630000);
    expect(p.rows.map((r) => r.expensePaise), [3600000, 4820000, 2400000]);
  });

  test('only the period counts', () async {
    final p = await report(from: '2026-09-03', to: '2026-09-30');
    expect(p.incomePaise, 0);
    expect(p.expensePaise, 0);
    expect(p.familyPaise, 1200000);
  });

  test('a sale from two lots splits its net amount by quantity, the paise '
      'adding up to the sale', () async {
    final plot = (await LandRepository(
      db,
      history,
      farm,
    ).watchPlots().first).single;
    final harvests = HarvestRepository(db, history, farm);
    final lots = <String>[];
    for (final c in plot.cycles.take(2)) {
      final (h, _) = await harvests.save(
        HarvestInput(
          day: '2026-11-01',
          plotId: plot.id,
          cycleId: c.id,
          unit: 'kg',
          teams: const [HarvestTeam(heads: 1, ratePaise: 0)],
          perTeam: false,
          total: 1000,
        ),
        canWriteMoney: true,
      );
      lots.add((await harvests.watchHarvest(h).first)!.lotId);
    }
    final before = await report();
    // 2 kg at ₹50 less 1 paisa: ₹99.99, half each is 4999.5 paise
    await SalesRepository(db, history, farm).save(
      SaleInput(
        day: '2026-11-02',
        quantity: 2000,
        unit: 'kg',
        ratePaise: 5000,
        takes: [(lots[0], 1000), (lots[1], 1000)],
        deductions: const [('Weighing', 1)],
      ),
    );
    final after = await report();
    expect(after.incomePaise - before.incomePaise, 9999);
    final gained = [
      for (var i = 0; i < 2; i++)
        after.rows[i].incomePaise - before.rows[i].incomePaise,
    ]..sort();
    expect(gained, [4999, 5000]);
  });

  test('money on no crop has its own row and stays with its plot', () async {
    final land = LandRepository(db, history, farm);
    final (bare, _) = await land.createPlot(
      const PlotInput(name: 'Hill', areaUnit: 'cent', area: 10000),
    );
    await ExpenseRepository(db, history, farm).save(
      ExpenseInput(
        day: '2026-11-03',
        categoryCode: 'fertiliser',
        amountPaise: 100000,
        plotId: bare,
      ),
    );
    final all = await report();
    expect(all.rows.last.key, isNull);
    expect(all.rows.last.expensePaise, 100000);
    expect(all.expensePaise, 9620000 + 100000);

    final hill = await report(plot: bare);
    expect(hill.rows.map((r) => r.key), [null]);
    expect(hill.incomePaise, 0);

    final riverside = (await land.watchPlots().first)
        .firstWhere((p) => p.id != bare)
        .id;
    expect((await report(plot: riverside)).expensePaise, 9620000);
  });

  test(
    'deleting an entry takes it out; totals are the sum of the rows',
    () async {
      final first = await money
          .watchCycles(from: '2026-04-01', to: '2027-03-31')
          .first;
      expect(first, isNotEmpty);
      final expense =
          (await db.customSelect('SELECT id FROM expenses LIMIT 1').getSingle())
              .read<String>('id');
      await ExpenseRepository(db, history, farm).delete(expense);
      final p = await report();
      expect(p.expensePaise, 9620000 - 7420000);
      expect(p.incomePaise, p.rows.fold<int>(0, (s, r) => s + r.incomePaise));
      expect(p.expensePaise, p.rows.fold<int>(0, (s, r) => s + r.expensePaise));
    },
  );
}
