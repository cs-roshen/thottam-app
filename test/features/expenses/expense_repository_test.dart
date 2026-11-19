import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/history/write_with_history.dart';
import 'package:thottam/core/split/split.dart';
import 'package:thottam/core/sync/bundled_templates.dart';
import 'package:thottam/features/expenses/data/expense_repository.dart';
import 'package:thottam/features/land/data/land_repository.dart';
import 'package:thottam/features/onboarding/data/onboarding_repository.dart';
import 'package:thottam/features/onboarding/domain/setup.dart';

import '../../helpers/session.dart';

void main() {
  late AppDatabase db;
  late String farm;
  late ExpenseRepository expenses;
  late LandRepository land;
  late String plot;
  late List<String> cycles;

  setUp(() async {
    final (d, f) = await farmDatabase(
      crops: const ['Coconut', 'Pepper', 'Banana'],
    );
    db = d;
    farm = f;
    var now = DateTime(2026, 11, 19, 10);
    final history = History(
      db,
      userId: testUser,
      clock: () => now = now.add(const Duration(milliseconds: 10)),
    );
    expenses = ExpenseRepository(db, history, farm);
    land = LandRepository(db, history, farm);
    final p = (await land.watchPlots().first).single;
    plot = p.id;
    // coconut, pepper, banana in set-up order
    cycles = [
      for (final name in ['Coconut', 'Pepper', 'Banana'])
        p.cycles.firstWhere((c) => c.nameEn == name).id,
    ];
  });
  tearDown(() => db.close());

  Future<List<Map<String, Object?>>> rows(String sql) async => [
    for (final r in await db.customSelect(sql).get()) r.data,
  ];

  ExpenseInput input(
    int paise,
    List<int> parts, {
    String mode = 'cash',
    String? vendor,
    String day = '2026-11-19',
    String category = 'fertiliser',
  }) => ExpenseInput(
    day: day,
    categoryCode: category,
    amountPaise: paise,
    plotId: plot,
    parts: [for (var i = 0; i < parts.length; i++) (cycles[i], parts[i])],
    mode: mode,
    vendor: vendor,
  );

  test('₹3,600 on coconut 60%, pepper 30%, banana 10% → ₹2,160, ₹1,080, '
      '₹360, saved with the expense', () async {
    final parts = splitAmount(360000, [
      const SplitTarget('c', templateWeight: 60),
      const SplitTarget('p', templateWeight: 30),
      const SplitTarget('b', templateWeight: 10),
    ], SplitMode.templateShare);
    await expenses.save(input(360000, parts));
    final saved = await rows(
      'SELECT crop_cycle_id, amount_paise FROM expense_allocations '
      'ORDER BY created_at',
    );
    expect(saved.map((r) => r['amount_paise']), [216000, 108000, 36000]);
    expect(saved.map((r) => r['crop_cycle_id']), cycles);
    final totals = await land.watchCycleTotals(plot).first;
    expect(
      totals.firstWhere((t) => t.cycleId == cycles[0]).expensePaise,
      216000,
    );
    expect(
      await rows("SELECT * FROM event_log WHERE entity = 'expenses'"),
      hasLength(1),
    );
  });

  test('credit leaves a payable, from a shop named once', () async {
    await expenses.save(
      input(120000, [120000, 0, 0], mode: 'credit', vendor: 'Kerala Agro'),
    );
    await expenses.save(
      input(30000, [30000, 0, 0], mode: 'credit', vendor: 'Kerala Agro '),
    );
    await expenses.save(input(50000, [50000, 0, 0]));
    final owed = await expenses.payables();
    expect(owed.map((p) => p.owedPaise), [30000, 120000]); // newest first
    expect(
      await rows("SELECT * FROM parties WHERE kind = 'vendor'"),
      hasLength(1),
    );
    // paying part of it leaves the rest owed
    final history = History(db, userId: testUser);
    await history.writeWithHistory([
      CreateRow('expense_payments', {
        'farm_id': farm,
        'expense_id': owed.last.expenseId,
        'paid_on': '2026-11-20',
        'amount_paise': 100000,
      }),
    ]);
    expect((await expenses.payables()).map((p) => p.owedPaise), [30000, 20000]);
  });

  test(
    'deleting an expense takes its split with it; undo brings both back',
    () async {
      await expenses.save(input(360000, [216000, 108000, 36000]));
      final id =
          (await rows('SELECT id FROM expenses')).single['id']! as String;
      final events = await expenses.delete(id);
      Future<int> cost() async => (await land.watchCycleTotals(plot).first)
          .fold<int>(0, (s, t) => s + t.expensePaise);
      expect(await cost(), 0);
      expect(
        await rows(
          'SELECT * FROM expense_allocations WHERE deleted_at IS NULL',
        ),
        isEmpty,
      );
      await expenses.undo(events);
      expect(await cost(), 360000);
    },
  );

  test('categories come most used first; the last plot and mode are '
      'remembered', () async {
    await expenses.save(input(10000, [10000, 0, 0], category: 'transport'));
    await expenses.save(input(10000, [10000, 0, 0], category: 'seeds'));
    await expenses.save(
      input(10000, [10000, 0, 0], category: 'seeds', mode: 'upi'),
    );
    // too old to count
    await expenses.save(
      input(10000, [10000, 0, 0], category: 'repairs', day: '2026-01-02'),
    );
    expect(await expenses.categoriesByUse('2026-11-19'), [
      'seeds',
      'transport',
    ]);
    final (lastPlot, _, mode) = await expenses.last();
    expect(lastPlot, plot);
    expect(mode, 'upi');
  });

  test('saving a typical expense to a database file takes well under the '
      '150 ms budget', () async {
    final dir = await Directory.systemTemp.createTemp('thottam_save');
    addTearDown(() => dir.delete(recursive: true));
    final file = AppDatabase(
      NativeDatabase(File('${dir.path}/save.db'), setup: applyPragmas),
    );
    addTearDown(file.close);
    var now = DateTime(2026, 11, 19, 10);
    final history = History(
      file,
      userId: testUser,
      clock: () => now = now.add(const Duration(milliseconds: 10)),
      random: Random(3),
    );
    await installBundledTemplates(
      file,
      File(bundledTemplatesAsset).readAsStringSync(),
    );
    final onboarding = OnboardingRepository(file, history);
    final crops = await onboarding.standardCrops();
    final f = await onboarding.createFarm(
      testUser,
      SetupInput(
        name: 'Ravi',
        farmName: 'Riverside',
        areaUnit: 'cent',
        cropIds: [for (final c in crops.take(3)) c.id],
      ),
    );
    final repo = ExpenseRepository(file, history, f);
    final p = (await LandRepository(
      file,
      history,
      f,
    ).watchPlots().first).single;
    final times = <int>[];
    for (var i = 0; i < 20; i++) {
      final w = Stopwatch()..start();
      await repo.save(
        ExpenseInput(
          day: '2026-11-19',
          categoryCode: 'fertiliser',
          amountPaise: 360000,
          plotId: p.id,
          parts: [
            (p.cycles[0].id, 216000),
            (p.cycles[1].id, 108000),
            (p.cycles[2].id, 36000),
          ],
        ),
      );
      times.add(w.elapsedMicroseconds);
    }
    times.sort();
    // ignore: avoid_print
    print(
      'save an expense with a 3-crop split: median '
      '${(times[10] / 1000).toStringAsFixed(1)} ms, slowest '
      '${(times.last / 1000).toStringAsFixed(1)} ms (budget 150)',
    );
    expect(times[10] / 1000, lessThan(150));
  });
}
