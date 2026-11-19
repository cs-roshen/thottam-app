import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/history/write_with_history.dart';
import 'package:thottam/core/sync/bundled_templates.dart';
import 'package:thottam/features/land/data/land_repository.dart';
import 'package:thottam/features/land/domain/land.dart';
import 'package:thottam/features/onboarding/data/onboarding_repository.dart';
import 'package:thottam/features/onboarding/domain/setup.dart';

import 'package:thottam/core/db/queries.dart';

const user = 'user-owner';

void main() {
  late AppDatabase db;
  late History history;
  late LandRepository land;
  late String farm;
  late Map<String, String> crop;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    var now = DateTime(2026, 11, 19, 8);
    history = History(
      db,
      userId: user,
      clock: () => now = now.add(const Duration(milliseconds: 10)),
      random: Random(1),
    );
    await installBundledTemplates(
      db,
      File(bundledTemplatesAsset).readAsStringSync(),
    );
    farm = await OnboardingRepository(db, history).createFarm(
      user,
      const SetupInput(name: 'Ravi', farmName: 'Home', areaUnit: 'cent'),
    );
    land = LandRepository(db, history, farm);
    crop = {for (final c in await land.crops()) c.nameEn: c.id};
  });
  tearDown(() => db.close());

  Future<int> scalar(String sql) async =>
      (await db.customSelect(sql).getSingle()).data.values.first as int? ?? 0;

  /// A plot with coconut and pepper, and entries on both.
  Future<(String, String, String)> mixedPlot() async {
    final (plot, _) = await land.createPlot(
      const PlotInput(name: 'Hill', area: 2500, areaUnit: 'acre'),
    );
    final (coconut, _) = await land.createCycle(
      plot,
      CycleInput(cropId: crop['Coconut']!, plantCount: 60),
    );
    final (pepper, _) = await land.createCycle(
      plot,
      CycleInput(cropId: crop['Pepper']!, areaShare: 30000),
    );
    // ₹3,600 of fertiliser split 2,400 / 1,200
    await history.writeWithHistory([
      CreateRow(
        'expenses',
        {
          'id': 'e1',
          'farm_id': farm,
          'spent_on': '2026-11-10',
          'category_code': 'fertiliser',
          'amount_paise': 360000,
          'plot_id': plot,
        },
        summary: {'plot_id': plot, 'amount_paise': 360000},
      ),
      CreateRow('expense_allocations', {
        'farm_id': farm,
        'expense_id': 'e1',
        'crop_cycle_id': coconut,
        'amount_paise': 240000,
      }),
      CreateRow('expense_allocations', {
        'farm_id': farm,
        'expense_id': 'e1',
        'crop_cycle_id': pepper,
        'amount_paise': 120000,
      }),
      // ₹900 of wages on coconut alone, and a family member's day
      CreateRow('workers', {'id': 'w1', 'farm_id': farm, 'name': 'Biju'}),
      CreateRow('workers', {
        'id': 'w2',
        'farm_id': farm,
        'name': 'Amma',
        'is_family': true,
      }),
      CreateRow(
        'labour_entries',
        {
          'farm_id': farm,
          'work_date': '2026-11-11',
          'worker_id': 'w1',
          'crop_cycle_id': coconut,
          'plot_id': plot,
          'amount_paise': 90000,
        },
        summary: {'plot_id': plot, 'amount_paise': 90000},
      ),
      CreateRow('labour_entries', {
        'farm_id': farm,
        'work_date': '2026-11-11',
        'worker_id': 'w2',
        'crop_cycle_id': coconut,
        'plot_id': plot,
        'amount_paise': 50000,
      }),
      // a group's ₹1,000 split across both crops
      CreateRow('labour_groups', {'id': 'g1', 'farm_id': farm, 'label': 'A'}),
      CreateRow('labour_entries', {
        'id': 'l3',
        'farm_id': farm,
        'work_date': '2026-11-12',
        'group_id': 'g1',
        'plot_id': plot,
        'amount_paise': 100000,
      }),
      CreateRow('labour_allocations', {
        'farm_id': farm,
        'labour_entry_id': 'l3',
        'crop_cycle_id': coconut,
        'amount_paise': 70000,
      }),
      CreateRow('labour_allocations', {
        'farm_id': farm,
        'labour_entry_id': 'l3',
        'crop_cycle_id': pepper,
        'amount_paise': 30000,
      }),
      CreateRow('harvests', {
        'farm_id': farm,
        'crop_cycle_id': pepper,
        'plot_id': plot,
        'harvested_on': '2026-11-15',
        'quantity': 120000,
      }),
    ]);
    return (plot, coconut, pepper);
  }

  test('a new plot is listed with its area, tenure and crops; two crops '
      'make it mixed', () async {
    final (plot, _, _) = await mixedPlot();
    final plots = await land.watchPlots().first;
    final hill = plots.firstWhere((p) => p.id == plot);
    expect(hill.area, 2500);
    expect(hill.areaUnit, 'acre');
    expect(hill.tenure, 'owned');
    expect(hill.cycles.map((c) => c.nameEn), ['Coconut', 'Pepper']);
    expect(hill.cycles.first.plantCount, 60);
    expect(hill.cycles.last.areaShare, 30000);
    expect(hill.mixed, isTrue);
    // the set-up plot has no crops
    expect(plots.firstWhere((p) => p.name == 'Home').mixed, isFalse);
  });

  test('plot totals equal the sum of its crop cycles; family labour stays '
      'out', () async {
    final (plot, coconut, pepper) = await mixedPlot();
    final cycles = await land.watchCycleTotals(plot).first;
    final c = cycles.firstWhere((x) => x.cycleId == coconut);
    final p = cycles.firstWhere((x) => x.cycleId == pepper);
    expect(c.expensePaise, 240000);
    expect(c.labourPaise, 90000 + 70000);
    expect(p.expensePaise, 120000);
    expect(p.labourPaise, 30000);
    expect(p.yields, {'kg': 120000});
    final total = plotTotals(plot, cycles);
    expect(total.costPaise, 360000 + 90000 + 100000);
    expect(total.costPaise, c.costPaise + p.costPaise);
    expect(total.yields, {'kg': 120000});
  });

  test('costs by category, wages included, largest first', () async {
    final (plot, _, _) = await mixedPlot();
    expect(await land.watchCostsByCategory(plot).first, [
      ('fertiliser', 360000),
      ('wages', 190000),
    ]);
  });

  test('deleting a plot keeps every entry and leaves profit and loss '
      'unchanged; undo restores the plot and its crops', () async {
    final (plot, coconut, _) = await mixedPlot();
    Future<List<Object?>> profitAndLoss() async => [
      for (final name in [
        'profit and loss for a season, expenses by crop cycle',
        'profit and loss for a season, labour by crop cycle',
      ])
        for (final r
            in await db
                .customSelect(
                  listQueries
                      .firstWhere((q) => q.name == name)
                      .sql
                      .replaceAll(':farm', "'$farm'")
                      .replaceAll(':from', "'2026-01-01'")
                      .replaceAll(':to', "'2026-12-31'"),
                )
                .get())
          r.data.values.toList(),
    ];
    final before = await profitAndLoss();
    final entries = await scalar(
      'SELECT COUNT(*) FROM expenses WHERE deleted_at IS NULL',
    );
    expect(await land.entryCount(plotId: plot), 5);

    final events = await land.deletePlot(plot);
    expect((await land.watchPlots().first).where((p) => p.id == plot), isEmpty);
    expect(await land.watchPlot(plot).first, isNull);
    expect(
      await scalar(
        "SELECT COUNT(*) FROM crop_cycles WHERE plot_id = '$plot' "
        'AND deleted_at IS NULL',
      ),
      0,
    );
    expect(await profitAndLoss(), before);
    expect(
      await scalar('SELECT COUNT(*) FROM expenses WHERE deleted_at IS NULL'),
      entries,
    );
    expect(
      await scalar(
        'SELECT COUNT(*) FROM labour_entries WHERE deleted_at IS NULL',
      ),
      3,
    );

    await land.undo(events);
    final back = await land.watchPlot(plot).first;
    expect(back, isNotNull);
    expect(back!.cycles.map((c) => c.id), contains(coconut));
  });

  test(
    'deleting a crop cycle asks with its own entry count and keeps them',
    () async {
      final (plot, coconut, pepper) = await mixedPlot();
      // pepper: its share of the expense, the group's day and the harvest
      expect(await land.entryCount(cycleId: pepper), 3);
      final cycle = (await land.watchPlot(plot).first)!.cycles.firstWhere(
        (c) => c.id == pepper,
      );
      final events = await land.deleteCycle(cycle);
      expect((await land.watchPlot(plot).first)!.cycles.map((c) => c.id), [
        coconut,
      ]);
      expect(
        await scalar('SELECT COUNT(*) FROM harvests WHERE deleted_at IS NULL'),
        1,
      );
      await land.undo(events);
      expect((await land.watchPlot(plot).first)!.cycles, hasLength(2));
    },
  );

  test('closing a season takes the crop off the plot\'s current crops and '
      'its costs out of this season; reopening brings both back', () async {
    final (plot, _, pepper) = await mixedPlot();
    final cycle = (await land.watchPlot(plot).first)!.cycles.firstWhere(
      (c) => c.id == pepper,
    );
    await land.setCycleClosed(cycle, closed: true);
    final closed = (await land.watchPlot(plot).first)!.cycles.firstWhere(
      (c) => c.id == pepper,
    );
    expect(closed.closed, isTrue);
    expect(
      (await land.watchPlots().first)
          .firstWhere((p) => p.id == plot)
          .cycles
          .map((c) => c.id),
      isNot(contains(pepper)),
    );
    expect(await land.watchCostsByCategory(plot).first, [
      ('fertiliser', 240000),
      ('wages', 160000),
    ]);
    await land.setCycleClosed(closed, closed: false);
    expect(
      (await land.watchPlots().first).firstWhere((p) => p.id == plot).mixed,
      isTrue,
    );
  });

  test('editing a plot and a crop cycle writes history', () async {
    final (plot, coconut, _) = await mixedPlot();
    await land.updatePlot(
      plot,
      const PlotInput(name: 'Hill top', areaUnit: 'acre', tenure: 'leased'),
    );
    await land.updateCycle(
      plot,
      coconut,
      CycleInput(cropId: crop['Coconut']!, plantCount: 65, variety: 'WCT'),
    );
    final p = (await land.watchPlot(plot).first)!;
    expect(p.name, 'Hill top');
    expect(p.area, isNull);
    expect(p.tenure, 'leased');
    expect(p.cycles.first.plantCount, 65);
    expect(p.cycles.first.variety, 'WCT');
    expect(
      await scalar(
        "SELECT COUNT(*) FROM event_log WHERE \"action\" = 'update' "
        "AND entity IN ('plots', 'crop_cycles')",
      ),
      2,
    );
  });

  test('recent history of a plot shows the plot, its crops and its entries, '
      'newest first', () async {
    final (plot, _, _) = await mixedPlot();
    final events = await land.watchRecentHistory(plot, limit: 10).first;
    expect(events.map((e) => e.entity).toSet(), {
      'plots',
      'crop_cycles',
      'expenses',
      'labour_entries',
    });
    // the set-up plot's history is not this plot's
    expect(events.where((e) => e.summary['plot'] == 'Home'), isEmpty);
    expect(events.first.action, 'create');
    expect(await land.watchRecentHistory(plot).first, hasLength(5));
  });

  test('the farm\'s land is totalled in the unit most plots use', () {
    PlotView p(int? area, String unit) => PlotView(
      id: unit,
      name: unit,
      area: area,
      areaUnit: unit,
      tenure: 'owned',
    );
    int? convert(int q, String from, String to) =>
        {('acre', 'cent'): q * 100, ('cent', 'acre'): q ~/ 100}[(from, to)] ??
        (from == to ? q : null);
    expect(
      totalArea([p(50000, 'cent'), p(2500, 'acre'), p(10000, 'cent')], convert),
      (310000, 'cent'),
    );
    expect(totalArea([p(null, 'cent')], convert), isNull);
    expect(totalArea([p(2500, 'acre'), p(50000, 'cent')], convert), (
      3000,
      'acre',
    ));
  });

  test('percents and planting years are checked', () {
    expect(parsePercent(60000), 60000);
    expect(parsePercent(100001), isNull);
    expect(parsePercent(null), isNull);
    expect(plantedOnForYear('2015', 2026), '2015-01-01');
    expect(plantedOnForYear('2030', 2026), isNull);
    expect(plantedOnForYear('15', 2026), isNull);
  });
}
