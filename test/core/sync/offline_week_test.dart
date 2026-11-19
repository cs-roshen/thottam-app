import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/db/synced_tables.dart';
import 'package:thottam/core/history/write_with_history.dart';
import 'package:thottam/core/sync/bundled_templates.dart';
import 'package:thottam/core/sync/sync_engine.dart';
import 'package:thottam/core/sync/sync_server.dart';
import 'package:thottam/features/expenses/data/expense_repository.dart';
import 'package:thottam/features/harvest/data/harvest_repository.dart';
import 'package:thottam/features/harvest/domain/harvest_math.dart';
import 'package:thottam/features/home/data/home_repository.dart';
import 'package:thottam/features/labour/data/labour_repository.dart';
import 'package:thottam/features/labour/domain/wages.dart';
import 'package:thottam/features/land/data/land_repository.dart';
import 'package:thottam/features/onboarding/data/onboarding_repository.dart';
import 'package:thottam/features/onboarding/domain/setup.dart';
import 'package:thottam/features/sales/data/sales_repository.dart';

import '../../helpers/session.dart';
import 'fake_server.dart';

const owner = 'user-owner';
const manager = 'user-manager';

/// A phone with its own database, clock and the app's own repositories.
class _Phone {
  _Phone(FakeServer server, this.user, int seed) : db = memoryDatabase() {
    DateTime clock() => now = now.add(const Duration(milliseconds: 10));
    history = History(db, userId: user, clock: clock, random: Random(seed));
    engine = SyncEngine(
      db,
      server.as(user),
      userId: user,
      clock: clock,
      random: Random(seed + 100),
      pageSize: 50,
      batchRows: 40,
    );
  }

  final String user;
  final AppDatabase db;
  DateTime now = DateTime.utc(2026, 11, 10, 8);
  late final History history;
  late final SyncEngine engine;
  late String farm;

  ExpenseRepository get expenses => ExpenseRepository(db, history, farm);
  HarvestRepository get harvests => HarvestRepository(db, history, farm);
  HomeRepository get home => HomeRepository(db, history, farm);
  LabourRepository get labour => LabourRepository(db, history, farm);
  SalesRepository get sales => SalesRepository(db, history, farm);

  Future<void> installTemplates() => installBundledTemplates(
    db,
    File(bundledTemplatesAsset).readAsStringSync(),
  );

  /// Every row of the farm in [table], by id.
  Future<Map<String, Map<String, Object?>>> rows(
    String table,
    String col,
  ) async => {
    for (final r
        in await db
            .customSelect(
              'SELECT * FROM $table WHERE "$col" = ?',
              variables: [Variable.withString(farm)],
            )
            .get())
      r.data['id']! as String: r.data,
  };

  Future<int> count(String sql) async =>
      (await db.customSelect(sql).getSingle()).data.values.first! as int;

  Future<String> one(String sql) async =>
      (await db.customSelect(sql).getSingle()).data.values.first! as String;
}

/// The farm tables, with the column that holds the farm.
final farmTables = [
  for (final (t, c) in syncedTables)
    if (c != null) (t, c),
];

/// D1 (implementation plan section 10): seven days of entries on two phones
/// in flight mode, then sync. Row counts and totals match on both phones and
/// the server: nothing lost, nothing doubled.
void main() {
  test('a week offline on two phones, then sync: no loss, no duplicates', () async {
    final server = FakeServer();
    final a = _Phone(server, owner, 1);
    final b = _Phone(server, manager, 2);
    addTearDown(a.db.close);
    addTearDown(b.db.close);

    // ---- before the week: the owner sets up, the manager joins ----
    await a.installTemplates();
    final setup = OnboardingRepository(a.db, a.history);
    final crops = {for (final c in await setup.standardCrops()) c.nameEn: c.id};
    a.farm = await setup.createFarm(
      owner,
      SetupInput(
        name: 'Ravi',
        farmName: 'Riverside',
        area: 50000,
        areaUnit: 'cent',
        cropIds: [crops['Coconut']!, crops['Pepper']!],
      ),
    );
    final plot = (await LandRepository(
      a.db,
      a.history,
      a.farm,
    ).watchPlots().first).single;
    final cycles = [for (final c in plot.cycles) c.id];
    final (biju, _) = await a.labour.createWorker(
      'Biju',
      defaultRatePaise: 90000,
    );
    await a.expenses.save(
      ExpenseInput(
        day: '2026-11-10',
        categoryCode: 'fertiliser',
        amountPaise: 360000,
        plotId: plot.id,
        parts: [(cycles[0], 180000), (cycles[1], 180000)],
      ),
    );
    final e0 = await a.one('SELECT id FROM expenses');
    final (firstHarvest, _) = await a.harvests.save(
      HarvestInput(
        day: '2026-11-10',
        plotId: plot.id,
        cycleId: cycles[1],
        unit: 'kg',
        teams: const [HarvestTeam(ratePaise: 80000, heads: 3)],
        perTeam: false,
        total: 100000,
      ),
      canWriteMoney: true,
    );
    final lot = await a.one(
      "SELECT id FROM lots WHERE harvest_id = '$firstHarvest'",
    );
    await a.engine.sync();
    final m = server.tables['farm_members']!.values.first;
    server.put('farm_members', {
      ...m,
      'id': 'm-manager',
      'user_id': manager,
      'role': 'manager',
    });
    b.farm = a.farm;
    await b.installTemplates();
    await b.engine.sync();
    expect(await b.count("SELECT COUNT(*) FROM lots WHERE id = '$lot'"), 1);

    // ---- seven days in flight mode ----
    server.down = true;
    for (var d = 0; d < 7; d++) {
      final day = '2026-11-${11 + d}';
      // the owner: a worker's day split across both crops, a fertiliser
      // bill split the same way, a pepper harvest with a team, a note
      await a.labour.saveWorkersDay(
        day: day,
        plotId: plot.id,
        taskCode: 'weeding',
        target: WageTarget.split(cycles, const [1, 1]),
        workers: [WorkerDay(biju, Attendance.full, ratePaise: 90000)],
      );
      final amount = 100000 + d * 1000;
      await a.expenses.save(
        ExpenseInput(
          day: day,
          categoryCode: 'fertiliser',
          amountPaise: amount,
          plotId: plot.id,
          parts: [(cycles[0], amount ~/ 2), (cycles[1], amount - amount ~/ 2)],
        ),
      );
      await a.harvests.save(
        HarvestInput(
          day: day,
          plotId: plot.id,
          cycleId: cycles[1],
          unit: 'kg',
          teams: const [HarvestTeam(ratePaise: 80000, heads: 2)],
          perTeam: false,
          total: 20000 + d * 1000,
        ),
        canWriteMoney: true,
      );
      await a.home.saveNote(NoteInput(day: day, text: 'A $day'));

      // the manager: an unnamed group's day, a part payment to Biju, a sale
      // from the lot picked before the week, a note
      await b.labour.saveGroupDay(
        day: day,
        plotId: plot.id,
        lines: const [GroupLine('general', 4, 80000)],
        target: WageTarget.one(cycles[0]),
      );
      await b.labour.addPayment(
        workerId: biju,
        kind: PaymentKind.part,
        amountPaise: 50000,
        day: day,
      );
      await b.sales.save(
        SaleInput(
          day: day,
          quantity: 5000,
          unit: 'kg',
          ratePaise: 70000,
          takes: [(lot, 5000)],
        ),
      );
      await b.home.saveNote(NoteInput(day: day, text: 'B $day'));

      // corrections, as farmers make them
      if (d == 2) {
        // the first day's bill was entered twice: deleted
        await a.expenses.delete(
          await a.one("SELECT id FROM expenses WHERE spent_on = '2026-11-11'"),
        );
      }
      if (d == 3) {
        // a note saved by mistake and undone at once
        await a.history.undo(
          await a.home.saveNote(NoteInput(day: day, text: 'oops')),
        );
      }
      if (d == 4) {
        // both phones correct the bill from before the week, in different
        // fields: they merge
        await a.history.writeWithHistory([
          UpdateRow('expenses', e0, const {'notes': 'neem cake'}),
        ]);
        await b.history.writeWithHistory([
          UpdateRow('expenses', e0, const {'mode': 'upi'}),
        ]);
      }

      // every try to sync fails quietly and keeps everything
      for (final p in [a, b]) {
        await expectLater(p.engine.sync(), throwsA(isA<SyncUnavailable>()));
        p.now = p.now.add(const Duration(days: 1));
      }
    }

    // what the two phones hold between them before the network returns
    final expected = <String, Set<String>>{
      for (final (t, c) in farmTables)
        t: {...(await a.rows(t, c)).keys, ...(await b.rows(t, c)).keys},
    };
    final waiting =
        (await a.engine.watchStatus().first).waiting +
        (await b.engine.watchStatus().first).waiting;
    expect(waiting, greaterThan(100));

    // ---- back online; the first reply is lost on the way ----
    server.down = false;
    server.loseNextReply = true;
    await expectLater(a.engine.sync(), throwsA(isA<SyncUnavailable>()));
    final watch = Stopwatch()..start();
    await a.engine.sync();
    await b.engine.sync();
    await a.engine.sync();
    await b.engine.sync();
    // ignore: avoid_print
    print(
      'D1: $waiting changes synced in ${watch.elapsedMilliseconds} ms; '
      '${server.pushes.length} batches',
    );

    for (final p in [a, b]) {
      final status = await p.engine.watchStatus().first;
      expect(status.waiting, 0, reason: p.user);
      expect(status.rejected, 0, reason: p.user);
      expect(status.conflicts, 0, reason: p.user);
      expect(await p.count('SELECT COUNT(*) FROM outbox'), 0, reason: p.user);
    }

    // the same rows everywhere, each once, and the same values on both phones
    for (final (t, c) in farmTables) {
      final onA = await a.rows(t, c);
      final onB = await b.rows(t, c);
      final onServer = {
        for (final r
            in server.tables[t]?.values ?? const <Map<String, Object?>>[])
          if (r[c] == a.farm) r['id']! as String: r,
      };
      expect(onA.keys.toSet(), expected[t], reason: '$t on A');
      expect(onB.keys.toSet(), expected[t], reason: '$t on B');
      expect(onServer.keys.toSet(), expected[t], reason: '$t on the server');
      for (final id in expected[t]!) {
        expect(onB[id], onA[id], reason: '$t $id');
      }
      // and the same totals, live rows only
      for (final col in const ['amount_paise', 'net_paise', 'quantity']) {
        if (onA.isEmpty || !onA.values.first.containsKey(col)) continue;
        int total(Iterable<Map> rows) => rows
            .where((r) => r['deleted_at'] == null)
            .fold(0, (s, r) => s + (r[col]! as int));
        expect(total(onServer.values), total(onA.values), reason: '$t $col');
      }
    }

    // hand-worked totals: the bill from before the week plus days 2 to 7
    // (day 1 deleted): 3,600 + 6 × 1,000 + (1 + … + 6) × 10 rupees
    expect(
      await a.count(
        'SELECT SUM(amount_paise) FROM expenses WHERE deleted_at IS NULL',
      ),
      360000 + 600000 + 21000,
    );
    // each bill's split still sums to the bill
    expect(
      await a.count(
        'SELECT COUNT(*) FROM expenses e WHERE deleted_at IS NULL AND '
        'amount_paise <> (SELECT SUM(amount_paise) FROM expense_allocations '
        'WHERE expense_id = e.id AND deleted_at IS NULL)',
      ),
      0,
    );
    expect(
      await b.count('SELECT COUNT(*) FROM harvests WHERE deleted_at IS NULL'),
      8,
    );
    // seven sales of 5 kg from the 100 kg lot: 65 kg left
    expect(
      await b.count(
        "SELECT SUM(quantity) FROM sale_lots WHERE lot_id = '$lot' "
        'AND deleted_at IS NULL',
      ),
      35000,
    );
    expect(
      await a.count(
        "SELECT SUM(amount_paise) FROM labour_payments WHERE worker_id = '$biju'",
      ),
      7 * 50000,
    );
    // the undone note stays in history, deleted, on both phones
    expect(
      await b.count(
        "SELECT COUNT(*) FROM notes WHERE body = 'oops' AND deleted_at IS NOT NULL",
      ),
      1,
    );
    // both corrections to the old bill arrived
    for (final p in [a, b]) {
      final e = (await p.rows('expenses', 'farm_id'))[e0]!;
      expect(e['notes'], 'neem cake', reason: p.user);
      expect(e['mode'], 'upi', reason: p.user);
    }
  });
}
