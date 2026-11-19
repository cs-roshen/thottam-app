import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/history/write_with_history.dart';
import 'package:thottam/features/harvest/data/harvest_repository.dart';
import 'package:thottam/features/harvest/domain/harvest_math.dart';
import 'package:thottam/features/land/data/land_repository.dart';

import '../../helpers/session.dart';

void main() {
  late AppDatabase db;
  late String farm;
  late History history;
  late HarvestRepository owner;
  late HarvestRepository supervisor;
  late String plot;
  late String pepper;

  setUp(() async {
    final (d, f) = await farmDatabase(crops: const ['Pepper']);
    db = d;
    farm = f;
    var now = DateTime(2026, 11, 19, 10);
    DateTime clock() => now = now.add(const Duration(milliseconds: 10));
    history = History(db, userId: testUser, clock: clock, random: Random(7));
    owner = HarvestRepository(db, history, farm);
    supervisor = HarvestRepository(
      db,
      History(db, userId: 'user-sup', clock: clock, random: Random(8)),
      farm,
    );
    final p = (await LandRepository(
      db,
      history,
      farm,
    ).watchPlots().first).single;
    plot = p.id;
    pepper = p.cycles.single.id;
  });
  tearDown(() => db.close());

  Future<void> expense(String day, int paise) => history.writeWithHistory([
    CreateRow('expenses', {
      'id': 'e-$day-$paise',
      'farm_id': farm,
      'spent_on': day,
      'category_code': 'fertiliser',
      'amount_paise': paise,
      'plot_id': plot,
    }),
    CreateRow('expense_allocations', {
      'farm_id': farm,
      'expense_id': 'e-$day-$paise',
      'crop_cycle_id': pepper,
      'amount_paise': paise,
    }),
  ]);

  Future<void> wage(String day, int paise, {bool family = false}) =>
      history.writeWithHistory([
        CreateRow('workers', {
          'id': 'w-$day-$paise',
          'farm_id': farm,
          'name': 'W',
          'is_family': family,
        }),
        CreateRow('labour_entries', {
          'farm_id': farm,
          'work_date': day,
          'worker_id': 'w-$day-$paise',
          'crop_cycle_id': pepper,
          'amount_paise': paise,
        }),
      ]);

  /// The spec's teams: Group A 6 at ₹800 with 75 kg, Group B 3 at ₹900 with
  /// 30 kg, one named worker at ₹1,000 with 15 kg.
  Future<List<HarvestTeam>> specTeams({bool namedIsFamily = false}) async {
    await history.writeWithHistory([
      CreateRow('workers', {
        'id': 'w-named',
        'farm_id': farm,
        'name': 'Biju',
        'is_family': namedIsFamily,
      }),
    ]);
    return [
      const HarvestTeam(heads: 6, ratePaise: 80000, quantity: 75000),
      const HarvestTeam(heads: 3, ratePaise: 90000, quantity: 30000),
      HarvestTeam(
        ratePaise: 100000,
        quantity: 15000,
        workerId: 'w-named',
        isFamily: namedIsFamily,
      ),
    ];
  }

  HarvestInput input(String day, List<HarvestTeam> teams) => HarvestInput(
    day: day,
    plotId: plot,
    cycleId: pepper,
    unit: 'kg',
    teams: teams,
    perTeam: true,
  );

  /// ₹20,060 since the October harvest: ₹15,000 fertiliser and ₹5,060
  /// wages; ₹5,000 before it, and family work, which stay out.
  Future<void> costsSinceOctober() async {
    await expense('2026-10-01', 500000);
    await owner.save(
      input('2026-10-15', const [HarvestTeam(heads: 2, ratePaise: 80000)]),
      canWriteMoney: true,
    );
    await expense('2026-10-20', 1500000);
    await wage('2026-11-02', 506000);
    await wage('2026-11-03', 90000, family: true);
  }

  Future<Map<String, Object?>?> lotCostOf(String harvestId) async =>
      (await db
              .customSelect(
                'SELECT c.* FROM lots l JOIN lot_costs c ON c.id = l.id '
                "WHERE l.harvest_id = '$harvestId'",
              )
              .getSingleOrNull())
          ?.data;

  test('the lot stores ₹20,060 since the last harvest plus ₹8,500 wages: '
      '₹28,560, ₹238 per kg', () async {
    await costsSinceOctober();
    final (id, _) = await owner.save(
      input('2026-11-19', await specTeams()),
      canWriteMoney: true,
    );
    final h = (await owner.watchHarvest(id).first)!;
    expect(h.quantity, 120000);
    expect(h.costPaise, 2856000);
    expect(costPerUnit(h.costPaise!, h.quantity), 23800);
    expect(h.teams, hasLength(3));
    // the lot holds the stock, the teams are labour on the harvest
    final lot =
        (await db
                .customSelect("SELECT * FROM lots WHERE harvest_id = '$id'")
                .getSingle())
            .data;
    expect(lot['quantity'], 120000);
    final teams = await db
        .customSelect(
          "SELECT amount_paise FROM labour_entries WHERE harvest_id = '$id'",
        )
        .get();
    expect(teams.map((t) => t.data['amount_paise']), [480000, 270000, 100000]);
  });

  test('with the named worker as family the lot stores ₹27,560', () async {
    await costsSinceOctober();
    final (id, _) = await owner.save(
      input('2026-11-19', await specTeams(namedIsFamily: true)),
      canWriteMoney: true,
    );
    final h = (await owner.watchHarvest(id).first)!;
    expect(h.costPaise, 2756000);
    expect(costPerUnit(h.costPaise!, h.quantity), 22967);
  });

  test('a cost entered later with an earlier date changes the lot only when '
      'the farmer recalculates', () async {
    await costsSinceOctober();
    final (id, _) = await owner.save(
      input('2026-11-19', await specTeams()),
      canWriteMoney: true,
    );
    await expense('2026-11-10', 100000);
    expect((await owner.watchHarvest(id).first)!.costPaise, 2856000);
    await owner.recalculate(id);
    expect((await owner.watchHarvest(id).first)!.costPaise, 2956000);
  });

  test('an edited cost is marked and stays through team edits; reset works '
      'it out again', () async {
    await costsSinceOctober();
    final teams = await specTeams();
    final (id, _) = await owner.save(
      input('2026-11-19', teams),
      canWriteMoney: true,
    );
    final lotId = (await owner.watchHarvest(id).first)!.lotId;
    await owner.setCost(lotId, 3000000);
    var h = (await owner.watchHarvest(id).first)!;
    expect(h.costPaise, 3000000);
    expect(h.costOverridden, isTrue);
    await owner.editTeams(
      id,
      input('2026-11-19', teams.sublist(0, 2)),
      canWriteMoney: true,
    );
    h = (await owner.watchHarvest(id).first)!;
    expect(h.costPaise, 3000000);
    expect(h.quantity, 105000);
    await owner.recalculate(id);
    h = (await owner.watchHarvest(id).first)!;
    expect(h.costOverridden, isFalse);
    expect(h.costPaise, 2006000 + 750000);
  });

  test(
    'editing the teams works the cost out again unless edited by hand',
    () async {
      await costsSinceOctober();
      final teams = await specTeams();
      final (id, _) = await owner.save(
        input('2026-11-19', teams),
        canWriteMoney: true,
      );
      await owner.editTeams(
        id,
        input('2026-11-19', [teams[0], teams[2]]),
        canWriteMoney: true,
      );
      final h = (await owner.watchHarvest(id).first)!;
      expect(h.costPaise, 2006000 + 480000 + 100000);
      expect(h.teams, hasLength(2));
    },
  );

  test("a supervisor's harvest saves with the cost not yet worked out; an "
      "owner's phone works it out", () async {
    await costsSinceOctober();
    final (id, _) = await supervisor.save(
      input('2026-11-19', await specTeams()),
      canWriteMoney: false,
    );
    expect(await lotCostOf(id), isNull);
    expect((await owner.watchHarvest(id).first)!.costPaise, isNull);
    expect(await owner.settlePending(), 1);
    expect((await owner.watchHarvest(id).first)!.costPaise, 2856000);
    expect(await owner.settlePending(), 0);
    // the working out is a money entry in the history
    final events = await db
        .customSelect(
          "SELECT created_by FROM event_log WHERE entity = 'lot_costs' "
          "AND entity_id = '${(await owner.watchHarvest(id).first)!.lotId}'",
        )
        .get();
    expect(events.single.data['created_by'], testUser);
  });

  test("a supervisor's edit to the teams marks the cost not yet worked out "
      'again; a cost edited by hand is kept', () async {
    await costsSinceOctober();
    final teams = await specTeams();
    final (id, _) = await owner.save(
      input('2026-11-19', teams),
      canWriteMoney: true,
    );
    await supervisor.editTeams(
      id,
      input('2026-11-19', teams.sublist(0, 2)),
      canWriteMoney: false,
    );
    expect((await owner.watchHarvest(id).first)!.costPaise, isNull);
    await owner.settlePending();
    expect((await owner.watchHarvest(id).first)!.costPaise, 2006000 + 750000);

    final lotId = (await owner.watchHarvest(id).first)!.lotId;
    await owner.setCost(lotId, 3000000);
    await supervisor.editTeams(
      id,
      input('2026-11-19', teams),
      canWriteMoney: false,
    );
    await owner.settlePending();
    final h = (await owner.watchHarvest(id).first)!;
    expect(h.costPaise, 3000000);
    expect(h.costOverridden, isTrue);
  });

  test('a supervisor never reads the lot cost', () async {
    final (id, _) = await supervisor.save(
      input('2026-11-19', await specTeams()),
      canWriteMoney: false,
    );
    await owner.settlePending();
    final seen = (await supervisor.watchHarvest(id, withCost: false).first)!;
    expect(seen.costPaise, isNull);
  });

  test('"last time" shows the last harvest of the crop', () async {
    expect(await owner.lastHarvest(pepper), isNull);
    await owner.save(
      input('2026-11-19', await specTeams()),
      canWriteMoney: true,
    );
    final last = (await owner.lastHarvest(pepper))!;
    expect(last.quantity, 120000);
    expect(last.people, 10);
    expect(last.day, '2026-11-19');
  });

  test('undo takes back the harvest, its teams and its lot', () async {
    final (id, events) = await owner.save(
      input('2026-11-19', await specTeams()),
      canWriteMoney: true,
    );
    await owner.undo(events);
    expect(await owner.watchHarvest(id).first, isNull);
    final left = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM labour_entries WHERE deleted_at IS NULL',
        )
        .getSingle();
    expect(left.data['n'], 0);
  });

  test('a harvest of 30 teams saves within the 150 ms budget', () async {
    final dir = await Directory.systemTemp.createTemp('thottam_harvest');
    addTearDown(() => dir.delete(recursive: true));
    final fileDb = AppDatabase(
      NativeDatabase(File('${dir.path}/h.db'), setup: applyPragmas),
    );
    addTearDown(fileDb.close);
    var now = DateTime(2026, 11, 19, 10);
    final h = History(
      fileDb,
      userId: testUser,
      clock: () => now = now.add(const Duration(milliseconds: 10)),
      random: Random(9),
    );
    final repo = HarvestRepository(fileDb, h, farm);
    // the rows it touches need no farm set-up: the plan only needs ids
    final teams = [
      for (var i = 0; i < 30; i++)
        HarvestTeam(heads: 2, ratePaise: 80000, quantity: 10000),
    ];
    final times = <int>[];
    var statements = 0;
    for (var i = 0; i < 5; i++) {
      final w = Stopwatch()..start();
      await repo.save(
        HarvestInput(
          day: '2026-11-19',
          plotId: 'p',
          cycleId: 'c',
          unit: 'kg',
          teams: teams,
          perTeam: true,
        ),
        canWriteMoney: true,
      );
      times.add(w.elapsedMicroseconds);
    }
    final events = await fileDb
        .customSelect('SELECT COUNT(*) AS n FROM event_log')
        .getSingle();
    // per row: insert, read back, history, two uploads
    statements = (events.data['n']! as int) ~/ 5 * 5;
    times.sort();
    // ignore: avoid_print
    print(
      'harvest with 30 teams (${(events.data['n']! as int) ~/ 5} rows, about '
      '$statements statements): median ${(times[2] / 1000).toStringAsFixed(1)} '
      'ms, slowest ${(times.last / 1000).toStringAsFixed(1)} ms (budget 150)',
    );
    expect(times[2] / 1000, lessThan(150));
  });
}
