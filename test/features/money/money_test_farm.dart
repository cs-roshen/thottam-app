import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/history/write_with_history.dart';
import 'package:thottam/features/expenses/data/expense_repository.dart';
import 'package:thottam/features/harvest/data/harvest_repository.dart';
import 'package:thottam/features/harvest/domain/harvest_math.dart';
import 'package:thottam/features/labour/data/labour_repository.dart';
import 'package:thottam/features/labour/domain/wages.dart';
import 'package:thottam/features/land/data/land_repository.dart';
import 'package:thottam/features/sales/data/sales_repository.dart';

/// The spec's profit and loss example entered through the app's own
/// repositories on a farm set up with coconut, pepper and banana:
/// sales of ₹92,000, ₹68,500 and ₹24,000; one fertiliser bill of ₹74,200
/// split ₹20,000, ₹44,200 and ₹10,000; a paid worker's ₹22,000 day split
/// across coconut and banana; family work of ₹5,000, ₹4,000 and ₹3,000.
Future<void> specExample(AppDatabase db, History history, String farm) async {
  final plot = (await LandRepository(
    db,
    history,
    farm,
  ).watchPlots().first).single;
  final cycle = {for (final c in plot.cycles) c.nameEn: c.id};
  final (coconut, pepper, banana) = (
    cycle['Coconut']!,
    cycle['Pepper']!,
    cycle['Banana']!,
  );

  final harvests = HarvestRepository(db, history, farm);
  final sales = SalesRepository(db, history, farm);
  for (final (c, rate) in [
    (coconut, 92000),
    (pepper, 68500),
    (banana, 24000),
  ]) {
    final (h, _) = await harvests.save(
      HarvestInput(
        day: '2026-10-01',
        plotId: plot.id,
        cycleId: c,
        unit: 'kg',
        teams: const [HarvestTeam(heads: 1, ratePaise: 0)],
        perTeam: false,
        total: 100000,
      ),
      canWriteMoney: true,
    );
    final lot = (await harvests.watchHarvest(h).first)!.lotId;
    await sales.save(
      SaleInput(
        day: '2026-10-02',
        quantity: 100000,
        unit: 'kg',
        ratePaise: rate,
        takes: [(lot, 100000)],
      ),
    );
  }

  await ExpenseRepository(db, history, farm).save(
    ExpenseInput(
      day: '2026-09-01',
      categoryCode: 'fertiliser',
      amountPaise: 7420000,
      plotId: plot.id,
      parts: [(coconut, 2000000), (pepper, 4420000), (banana, 1000000)],
    ),
  );

  final labour = LabourRepository(db, history, farm);
  final (biju, _) = await labour.createWorker(
    'Biju',
    defaultRatePaise: 2200000,
  );
  await labour.saveWorkersDay(
    day: '2026-09-02',
    workers: [WorkerDay(biju, Attendance.full, ratePaise: 2200000)],
    target: WageTarget.split([coconut, banana], const [1, 1]),
    plotId: plot.id,
  );
  final (amma, _) = await labour.createWorker('Amma', isFamily: true);
  for (final (day, c, rate) in [
    ('2026-09-03', coconut, 500000),
    ('2026-09-04', pepper, 400000),
    ('2026-09-05', banana, 300000),
  ]) {
    await labour.saveWorkersDay(
      day: day,
      workers: [WorkerDay(amma, Attendance.full, ratePaise: rate)],
      target: WageTarget.one(c),
      plotId: plot.id,
    );
  }
}
