import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/history/write_with_history.dart';
import 'package:thottam/features/labour/data/labour_repository.dart';
import 'package:thottam/features/labour/domain/wages.dart';
import 'package:thottam/features/land/data/land_repository.dart';

import '../../helpers/session.dart';

void main() {
  late AppDatabase db;
  late String farm;
  late LabourRepository labour;
  late LandRepository land;
  late String plot;
  late List<String> cycles;

  setUp(() async {
    final (d, f) = await farmDatabase(crops: const ['Coconut', 'Pepper']);
    db = d;
    farm = f;
    var now = DateTime(2026, 11, 19, 10);
    final history = History(
      db,
      userId: testUser,
      clock: () => now = now.add(const Duration(milliseconds: 10)),
    );
    labour = LabourRepository(db, history, farm);
    land = LandRepository(db, history, farm);
    final p = (await land.watchPlots().first).single;
    plot = p.id;
    cycles = [for (final c in p.cycles) c.id];
  });
  tearDown(() => db.close());

  Future<List<Map<String, Object?>>> rows(String sql) async => [
    for (final r in await db.customSelect(sql).get()) r.data,
  ];

  Future<List<String>> fourWorkers() async => [
    for (final (name, rate) in [
      ('Biju', 90000),
      ('Sali', 90000),
      ('Raju', 70000),
      ('Anu', 90000),
    ])
      (await labour.createWorker(name, defaultRatePaise: rate)).$1,
  ];

  test('rates 900, 900, 700, 900 with full, full, half, absent → ₹2,150, '
      'posted to the one crop chosen; the absent day is recorded', () async {
    final w = await fourWorkers();
    await labour.saveWorkersDay(
      day: '2026-11-19',
      plotId: plot,
      taskCode: 'weeding',
      target: WageTarget.one(cycles.first),
      workers: [
        WorkerDay(w[0], Attendance.full, ratePaise: 90000),
        WorkerDay(w[1], Attendance.full, ratePaise: 90000),
        WorkerDay(w[2], Attendance.half, ratePaise: 70000),
        WorkerDay(w[3], Attendance.absent, ratePaise: 90000),
      ],
    );
    final entries = await rows(
      'SELECT * FROM labour_entries ORDER BY created_at',
    );
    expect(entries.map((e) => e['amount_paise']), [90000, 90000, 35000, 0]);
    expect(entries.map((e) => e['attendance']), [1000, 1000, 500, 0]);
    expect(
      entries.fold<int>(0, (s, e) => s + (e['amount_paise']! as int)),
      215000,
    );
    expect(entries.every((e) => e['crop_cycle_id'] == cycles.first), isTrue);
    expect(entries.every((e) => e['task_code'] == 'weeding'), isTrue);
    expect(await rows('SELECT * FROM labour_allocations'), isEmpty);
    // each worker's history has the day
    expect(
      await rows(
        "SELECT * FROM event_log WHERE entity = 'labour_entries' "
        "AND json_extract(summary, '\$.worker_id') = '${w[2]}'",
      ),
      hasLength(1),
    );
    // and the crop's cost has it
    final totals = await land.watchCycleTotals(plot).first;
    expect(
      totals.firstWhere((t) => t.cycleId == cycles.first).labourPaise,
      215000,
    );
  });

  test('overtime: ₹900 full day plus 2 hours at ₹150 → ₹1,200, with the '
      'hours and rate kept on the entry', () async {
    final (id, _) = await labour.createWorker('Biju', defaultRatePaise: 90000);
    await labour.saveWorkersDay(
      day: '2026-11-19',
      target: WageTarget.one(cycles.first),
      workers: [
        WorkerDay(
          id,
          Attendance.overtime,
          ratePaise: 90000,
          overtimeHours: 2000,
          overtimeRatePaise: 15000,
        ),
      ],
    );
    final e = (await rows('SELECT * FROM labour_entries')).single;
    expect(e['amount_paise'], 120000);
    expect(e['attendance'], 1000);
    expect(e['overtime_hours'], 2000);
    expect(e['overtime_rate_paise'], 15000);
  });

  test('a group of 5 at ₹800 and 1 at ₹1,200 → ₹5,200, with no names '
      'needed; the group is made in the same save', () async {
    await labour.saveGroupDay(
      day: '2026-11-19',
      lines: const [
        GroupLine('general', 5, 80000),
        GroupLine('climber', 1, 120000),
      ],
      hours: 8000,
      target: WageTarget.one(cycles.first),
    );
    final group = (await rows('SELECT * FROM labour_groups')).single;
    expect(group['is_named'], 0);
    expect(group['label'], '');
    final entries = await rows(
      'SELECT * FROM labour_entries ORDER BY created_at',
    );
    expect(entries.map((e) => e['head_count']), [5, 1]);
    expect(entries.map((e) => e['rate_class']), ['general', 'climber']);
    expect(entries.map((e) => e['amount_paise']), [400000, 120000]);
    expect(entries.every((e) => e['group_id'] == group['id']), isTrue);
    expect(entries.every((e) => e['hours'] == 8000), isTrue);
  });

  test('a group paid one lump sum', () async {
    await labour.saveGroupDay(
      day: '2026-11-19',
      label: 'Thomas team',
      lines: const [GroupLine('general', 6, 80000)],
      lumpSumPaise: 450000,
      target: WageTarget.one(cycles.first),
    );
    final e = (await rows('SELECT * FROM labour_entries')).single;
    expect(e['amount_paise'], 450000);
    expect(e['head_count'], 6);
    expect(e['amount_overridden'], 1);
    final g = (await labour.watchGroups().first).single;
    expect(g.isNamed, isTrue);
    expect(g.label, 'Thomas team');
  });

  test('on a mixed plot each entry splits across the crops by the day\'s '
      'parts, and its parts sum to it', () async {
    final w = await fourWorkers();
    await labour.saveWorkersDay(
      day: '2026-11-19',
      target: WageTarget.split(cycles, const [60, 30]),
      manualSplit: true,
      workers: [
        WorkerDay(w[0], Attendance.full, ratePaise: 90000),
        WorkerDay(w[2], Attendance.half, ratePaise: 70001),
      ],
    );
    final entries = await rows(
      'SELECT * FROM labour_entries ORDER BY created_at',
    );
    expect(entries.every((e) => e['crop_cycle_id'] == null), isTrue);
    for (final e in entries) {
      final parts = await rows(
        "SELECT * FROM labour_allocations WHERE labour_entry_id = '${e['id']}' "
        'ORDER BY created_at',
      );
      expect(parts.map((p) => p['crop_cycle_id']), cycles);
      expect(
        parts.fold<int>(0, (s, p) => s + (p['amount_paise']! as int)),
        e['amount_paise'],
      );
      expect(parts.every((p) => p['is_manual'] == 1), isTrue);
    }
    // ₹900 by 60 / 30 → ₹600 / ₹300
    expect(
      (await rows(
        "SELECT amount_paise FROM labour_allocations WHERE labour_entry_id = "
        "'${entries.first['id']}' ORDER BY created_at",
      )).map((r) => r['amount_paise']),
      [60000, 30000],
    );
    // the plot's totals hold the whole wage
    final totals = await land.watchCycleTotals(plot).first;
    expect(totals.fold<int>(0, (s, t) => s + t.labourPaise), 90000 + 35001);
  });

  test('an unnamed group named later keeps its days and its balance', () async {
    await labour.saveGroupDay(
      day: '2026-11-18',
      lines: const [GroupLine('general', 4, 80000)],
      target: WageTarget.one(cycles.first),
    );
    final before = (await labour.watchGroups().first).single;
    await labour.updateGroup(
      before,
      label: 'Thomas team',
      usualSize: 4,
      defaultRates: const {'general': 85000},
    );
    final after = (await labour.watchGroups().first).single;
    expect(after.id, before.id);
    expect(after.isNamed, isTrue);
    expect(after.defaultRates, {'general': 85000});
    expect(after.balancePaise, 320000);
    expect(await labour.watchLedger(groupId: after.id).first, hasLength(1));
  });

  test('members can be added to a group and taken off again', () async {
    final w = await fourWorkers();
    await labour.saveGroupDay(
      day: '2026-11-18',
      lines: const [GroupLine('general', 2, 80000)],
      target: WageTarget.one(cycles.first),
    );
    var g = (await labour.watchGroups().first).single;
    await labour.updateGroup(g, label: 'A', memberIds: [w[0], w[1]]);
    g = (await labour.watchGroups().first).single;
    expect(g.memberIds, [w[0], w[1]]);
    await labour.updateGroup(g, label: 'A', memberIds: [w[1]]);
    expect((await labour.watchGroups().first).single.memberIds, [w[1]]);
  });

  test('balances: wages less money paid and deductions; a bonus is paid on '
      'top and leaves the balance', () async {
    final (id, _) = await labour.createWorker('Biju', defaultRatePaise: 90000);
    await labour.saveWorkersDay(
      day: '2026-11-18',
      target: WageTarget.one(cycles.first),
      workers: [WorkerDay(id, Attendance.full, ratePaise: 90000)],
    );
    await labour.saveWorkersDay(
      day: '2026-11-19',
      target: WageTarget.one(cycles.first),
      workers: [WorkerDay(id, Attendance.full, ratePaise: 90000)],
    );
    Future<int> owed() async =>
        (await labour.watchWorkers().first).single.balancePaise;
    expect(await owed(), 180000);
    await labour.addPayment(
      workerId: id,
      kind: PaymentKind.advance,
      amountPaise: 50000,
      day: '2026-11-19',
    );
    expect(await owed(), 130000);
    await labour.addPayment(
      workerId: id,
      kind: PaymentKind.bonus,
      amountPaise: 10000,
      day: '2026-11-19',
    );
    expect(await owed(), 130000);
    await labour.addPayment(
      workerId: id,
      kind: PaymentKind.deduction,
      amountPaise: 30000,
      day: '2026-11-19',
    );
    expect(await owed(), 100000);
    final undo = await labour.addPayment(
      workerId: id,
      kind: PaymentKind.settlement,
      amountPaise: 100000,
      day: '2026-11-19',
      mode: 'upi',
    );
    expect(await owed(), 0);
    await labour.undo(undo);
    expect(await owed(), 100000);
    final ledger = await labour.watchLedger(workerId: id).first;
    expect(ledger.where((l) => l.kind == null), hasLength(2));
    expect(ledger.where((l) => l.kind != null), hasLength(3));
  });

  test('"same as yesterday" brings back the last day\'s attendance', () async {
    final w = await fourWorkers();
    await labour.saveWorkersDay(
      day: '2026-11-17',
      target: WageTarget.one(cycles.first),
      workers: [WorkerDay(w[3], Attendance.full, ratePaise: 90000)],
    );
    await labour.saveWorkersDay(
      day: '2026-11-18',
      target: WageTarget.one(cycles.first),
      workers: [
        WorkerDay(w[0], Attendance.full, ratePaise: 95000),
        WorkerDay(w[2], Attendance.half, ratePaise: 70000),
        WorkerDay(
          w[1],
          Attendance.overtime,
          ratePaise: 90000,
          overtimeHours: 2000,
          overtimeRatePaise: 15000,
        ),
      ],
    );
    final last = {
      for (final d in await labour.lastDay('2026-11-19')) d.workerId: d,
    };
    expect(last.keys.toSet(), {w[0], w[1], w[2]});
    expect(last[w[0]]!.ratePaise, 95000);
    expect(last[w[2]]!.attendance, Attendance.half);
    expect(last[w[1]]!.attendance, Attendance.overtime);
    expect(last[w[1]]!.overtimeHours, 2000);
    expect(await labour.lastDay('2026-11-17'), isEmpty);
  });

  test('undo of a day takes back every entry of it', () async {
    final w = await fourWorkers();
    final events = await labour.saveWorkersDay(
      day: '2026-11-19',
      target: WageTarget.split(cycles, const [1, 1]),
      workers: [
        WorkerDay(w[0], Attendance.full, ratePaise: 90000),
        WorkerDay(w[1], Attendance.full, ratePaise: 90000),
      ],
    );
    await labour.undo(events);
    expect(
      await rows('SELECT * FROM labour_entries WHERE deleted_at IS NULL'),
      isEmpty,
    );
    expect(
      await rows('SELECT * FROM labour_allocations WHERE deleted_at IS NULL'),
      isEmpty,
    );
  });

  test(
    'family work is shown in labour but left out of the plot\'s costs',
    () async {
      final (id, _) = await labour.createWorker(
        'Amma',
        defaultRatePaise: 50000,
        isFamily: true,
      );
      await labour.saveWorkersDay(
        day: '2026-11-19',
        target: WageTarget.one(cycles.first),
        workers: [WorkerDay(id, Attendance.full, ratePaise: 50000)],
      );
      expect((await labour.watchWorkers().first).single.isFamily, isTrue);
      final totals = await land.watchCycleTotals(plot).first;
      expect(totals.fold<int>(0, (s, t) => s + t.labourPaise), 0);
    },
  );
}
