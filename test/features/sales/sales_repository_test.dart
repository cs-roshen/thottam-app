import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/history/write_with_history.dart';
import 'package:thottam/features/harvest/data/harvest_repository.dart';
import 'package:thottam/features/harvest/domain/harvest_math.dart';
import 'package:thottam/features/land/data/land_repository.dart';
import 'package:thottam/features/sales/data/sales_repository.dart';
import 'package:thottam/features/sales/domain/sale_math.dart';

import '../../helpers/session.dart';

/// Two pepper lots: 120 kg at ₹28,560 (₹238 a kg) and 100 kg at ₹25,000
/// (₹250 a kg), each sold from by [SalesRepository].
Future<(String, String)> twoLots(
  AppDatabase db,
  History history,
  String farm,
) async {
  final harvests = HarvestRepository(db, history, farm);
  final p = (await LandRepository(db, history, farm).watchPlots().first).single;
  final cycle = p.cycles.single.id;
  Future<String> lot(String day, int quantity, int cost) async {
    final (id, _) = await harvests.save(
      HarvestInput(
        day: day,
        plotId: p.id,
        cycleId: cycle,
        unit: 'kg',
        teams: const [HarvestTeam(heads: 1, ratePaise: 0)],
        perTeam: false,
        total: quantity,
      ),
      canWriteMoney: true,
    );
    final lotId = (await harvests.watchHarvest(id).first)!.lotId;
    await harvests.setCost(lotId, cost);
    return lotId;
  }

  return (
    await lot('2026-11-01', 120000, 2856000),
    await lot('2026-11-10', 100000, 2500000),
  );
}

void main() {
  late AppDatabase db;
  late SalesRepository sales;
  late String older;
  late String newer;

  setUp(() async {
    final (d, farm) = await farmDatabase(crops: const ['Pepper']);
    db = d;
    var now = DateTime(2026, 11, 19, 10);
    final history = History(
      db,
      userId: testUser,
      clock: () => now = now.add(const Duration(milliseconds: 10)),
      random: Random(4),
    );
    sales = SalesRepository(db, history, farm);
    (older, newer) = await twoLots(db, history, farm);
  });
  tearDown(() => db.close());

  SaleInput sale(
    int quantity,
    List<(String, int)> takes, {
    int rate = 70500,
    List<(String, int)> deductions = const [('Commission', 17000)],
    PaymentStatus status = PaymentStatus.paid,
    int? received,
    String? newBuyer = 'Joseph Traders',
    String? buyerId,
    String unit = 'kg',
  }) => SaleInput(
    day: '2026-11-19',
    quantity: quantity,
    unit: unit,
    ratePaise: rate,
    takes: takes,
    deductions: deductions,
    status: status,
    receivedPaise: received,
    newBuyer: buyerId == null ? newBuyer : null,
    buyerId: buyerId,
  );

  test('the sale example: 50 kg at ₹705 less ₹170 → net ₹35,080; the lot '
      'keeps the rest', () async {
    await sales.save(sale(50000, [(older, 50000)]));
    final row = (await db.customSelect('SELECT * FROM sales').getSingle()).data;
    expect(row['net_paise'], 3508000);
    expect(row['rate_paise'], 70500);
    final stock = {
      for (final l in await sales.watchLotsInStock().first) l.id: l.stock,
    };
    expect(stock[older], 70000);
    expect(stock[newer], 100000);
    // paid in full: nothing owed
    expect((await sales.watchBuyers().first).single.duePaise, 0);
  });

  test('cannot sell more than a lot holds', () async {
    await expectLater(
      sales.save(sale(130000, [(older, 130000)])),
      throwsStateError,
    );
    expect(await db.customSelect('SELECT * FROM sales').get(), isEmpty);
  });

  test('a sold-out lot leaves the stock list', () async {
    await sales.save(sale(120000, [(older, 120000)]));
    expect((await sales.watchLotsInStock().first).map((l) => l.id), [newer]);
  });

  test('a sale from two lots takes from each and keeps their costs', () async {
    final lots = await sales.watchLotsInStock().first;
    expect(lots.map((l) => l.costPaise), [2856000, 2500000]);
    final takes = takeFrom([
      for (final l in lots) StockLot(l.id, l.stock),
    ], 130000)!;
    expect(takes, [(older, 120000), (newer, 10000)]);
    await sales.save(sale(130000, takes));
    final rows = await db
        .customSelect(
          'SELECT lot_id, quantity FROM sale_lots ORDER BY created_at',
        )
        .get();
    expect(rows.map((r) => (r.data['lot_id'], r.data['quantity'])), [
      (older, 120000),
      (newer, 10000),
    ]);
  });

  test('part paid and due leave what the buyer owes; money received later '
      'brings it down', () async {
    await sales.save(
      sale(
        50000,
        [(older, 50000)],
        status: PaymentStatus.part,
        received: 2000000,
      ),
    );
    var buyer = (await sales.watchBuyers().first).single;
    expect(buyer.duePaise, 1508000);
    await sales.save(
      sale(
        10000,
        [(older, 10000)],
        status: PaymentStatus.due,
        buyerId: buyer.id,
      ),
    );
    buyer = (await sales.watchBuyers().first).single;
    expect(buyer.duePaise, 1508000 + 705000 - 17000);
    final owed = await sales.watchBuyerSales(buyer.id).first;
    expect(owed, hasLength(2));
    final undo = await sales.receive(owed.last.id, 1508000, '2026-11-20');
    expect((await sales.watchBuyers().first).single.duePaise, 688000);
    await sales.undo(undo);
    expect((await sales.watchBuyers().first).single.duePaise, 2196000);
    // a due sale is a credit sale
    final modes = await db.customSelect('SELECT mode FROM sales').get();
    expect(modes.map((m) => m.data['mode']), containsAll(['cash', 'credit']));
  });

  test('undo of a sale puts the stock back', () async {
    final events = await sales.save(sale(50000, [(older, 50000)]));
    await sales.undo(events);
    final stock = {
      for (final l in await sales.watchLotsInStock().first) l.id: l.stock,
    };
    expect(stock[older], 120000);
  });
}
