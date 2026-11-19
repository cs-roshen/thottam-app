import 'dart:convert';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/access/access.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/history/write_with_history.dart';
import 'package:thottam/core/sync/sync_engine.dart';
import 'package:thottam/core/sync/sync_scheduler.dart';
import 'package:thottam/core/sync/sync_server.dart';

import 'fake_server.dart';

const farm = '0190f000-0000-7000-8000-0000000000f1';
const owner = 'user-owner';
const manager = 'user-manager';

/// A simulated phone: its own database, history, clock and sync engine.
class Phone {
  Phone(
    FakeServer server,
    this.user, {
    Duration skew = Duration.zero,
    int seed = 1,
  }) : db = AppDatabase(NativeDatabase.memory()),
       now = DateTime.utc(2026, 11, 18, 8).add(skew) {
    DateTime clock() => now = now.add(const Duration(milliseconds: 10));
    history = History(db, userId: user, clock: clock, random: Random(seed));
    engine = SyncEngine(
      db,
      server.as(user),
      userId: user,
      clock: clock,
      random: Random(seed + 100),
      pageSize: 7,
      batchRows: 5,
    );
  }

  final String user;
  final AppDatabase db;

  /// The phone's clock; tests move it to make it jump.
  DateTime now;
  late final History history;
  late final SyncEngine engine;

  Future<List<String>> write(List<RowWrite> w) => history.writeWithHistory(w);
  Future<void> sync() => engine.sync();

  Future<Map<String, Object?>?> row(String table, String id) async =>
      (await db
              .customSelect("SELECT * FROM $table WHERE id = '$id'")
              .getSingleOrNull())
          ?.data;

  Future<int> count(String sql) async =>
      (await db.customSelect(sql).getSingle()).data.values.first! as int;
}

void main() {
  late FakeServer server;
  late Phone a;
  late Phone b;

  /// The owner sets up the farm on phone A; the manager joins on phone B.
  Future<void> setUpFarm() async {
    await a.write([
      const CreateRow('farms', {'id': farm, 'name': 'Thottam'}),
      const CreateRow('farm_members', {
        'id': 'm-owner',
        'farm_id': farm,
        'user_id': owner,
        'role': 'owner',
      }),
      const CreateRow('plots', {'id': 'p1', 'farm_id': farm, 'name': 'Plot 1'}),
      const CreateRow('crop_cycles', {
        'id': 'c1',
        'farm_id': farm,
        'plot_id': 'p1',
        'crop_id': 'pepper',
      }),
      const CreateRow('expenses', {
        'id': 'e1',
        'farm_id': farm,
        'spent_on': '2026-11-17',
        'category_code': 'fertiliser',
        'amount_paise': 360000,
        'plot_id': 'p1',
      }),
    ]);
    await a.sync();
    // the manager accepted an invite on the server
    server.put('farm_members', {
      'id': 'm-manager',
      'farm_id': farm,
      'user_id': manager,
      'role': 'manager',
      'permissions': <String, Object?>{},
      'created_at': '2026-11-18T08:00:00.000Z',
      'updated_at': '2026-11-18T08:00:00.000Z',
      'version': 1,
      'deleted_at': null,
    });
    await b.sync();
  }

  setUp(() {
    server = FakeServer();
    a = Phone(server, owner);
    b = Phone(server, manager, seed: 2);
  });
  tearDown(() async {
    await a.db.close();
    await b.db.close();
  });

  test('a farm set up on one phone arrives whole on the other', () async {
    await setUpFarm();
    expect((await b.row('expenses', 'e1'))!['amount_paise'], 360000);
    expect((await b.row('farms', farm))!['name'], 'Thottam');
    expect(await b.count('SELECT COUNT(*) FROM event_log'), 5);
    expect(await a.count('SELECT COUNT(*) FROM outbox'), 0);
    // pages were small, so the cursor moved several times
    expect(
      await b.count(
        "SELECT \"cursor\" FROM sync_state WHERE entity = 'event_log'",
      ),
      greaterThan(0),
    );
  });

  test(
    'both phones offline, then both sync: nothing lost, nothing doubled',
    () async {
      await setUpFarm();
      await a.write([
        const CreateRow('notes', {
          'id': 'n-a',
          'farm_id': farm,
          'noted_on': '2026-11-18',
          'body': 'A',
        }),
      ]);
      await b.write([
        const CreateRow('notes', {
          'id': 'n-b',
          'farm_id': farm,
          'noted_on': '2026-11-18',
          'body': 'B',
        }),
      ]);
      await a.sync();
      await b.sync();
      await a.sync();
      for (final p in [a, b]) {
        expect(await p.count('SELECT COUNT(*) FROM notes'), 2);
        expect(await p.count('SELECT COUNT(*) FROM event_log'), 7);
        expect(await p.count('SELECT COUNT(*) FROM outbox'), 0);
      }
    },
  );

  test('the same row edited on both: different fields merge', () async {
    await setUpFarm();
    await a.write([
      const UpdateRow('expenses', 'e1', {'notes': 'neem cake'}),
    ]);
    await b.write([
      const UpdateRow('expenses', 'e1', {'category_code': 'plant_protection'}),
    ]);
    await a.sync();
    await b.sync();
    await a.sync();
    for (final p in [a, b]) {
      final e = (await p.row('expenses', 'e1'))!;
      expect(e['notes'], 'neem cake');
      expect(e['category_code'], 'plant_protection');
    }
    expect(await b.count('SELECT COUNT(*) FROM conflicts'), 0);
    expect(
      (await a.row('expenses', 'e1'))!['version'],
      (await b.row('expenses', 'e1'))!['version'],
    );
  });

  test('the same plain field on both: the upload that reaches the server later wins', () async {
    await setUpFarm();
    await a.write([
      const UpdateRow('expenses', 'e1', {'notes': 'from A'}),
    ]);
    await b.write([
      const UpdateRow('expenses', 'e1', {'notes': 'from B'}),
    ]);
    await a.sync();
    await b.sync();
    await a.sync();
    for (final p in [a, b]) {
      expect((await p.row('expenses', 'e1'))!['notes'], 'from B');
    }
  });

  test('the same money field on both goes to the farmer to choose', () async {
    await setUpFarm();
    await a.write([
      const UpdateRow('expenses', 'e1', {'amount_paise': 370000}),
    ]);
    await b.write([
      const UpdateRow('expenses', 'e1', {'amount_paise': 380000}),
    ]);
    await a.sync();
    await b.sync();
    final c =
        (await b.db.customSelect('SELECT * FROM conflicts').getSingle()).data;
    expect(c['kind'], 'same_field');
    expect(jsonDecode(c['fields']! as String), ['amount_paise']);
    expect((jsonDecode(c['mine']! as String) as Map)['amount_paise'], 380000);
    expect((jsonDecode(c['theirs']! as String) as Map)['amount_paise'], 370000);
    // until the farmer chooses, both phones show the server's amount
    expect((await b.row('expenses', 'e1'))!['amount_paise'], 370000);
    await a.sync();
    expect((await a.row('expenses', 'e1'))!['amount_paise'], 370000);
    expect(
      await b.count('SELECT COUNT(*) FROM outbox WHERE entity = \'expenses\''),
      0,
    );
  });

  test('two changes to the same value are not a conflict', () async {
    await setUpFarm();
    await a.write([
      const UpdateRow('expenses', 'e1', {'amount_paise': 370000}),
    ]);
    await b.write([
      const UpdateRow('expenses', 'e1', {'amount_paise': 370000}),
    ]);
    await a.sync();
    await b.sync();
    expect(await b.count('SELECT COUNT(*) FROM conflicts'), 0);
  });

  test(
    'a delete on one phone against an edit on the other goes to the farmer',
    () async {
      await setUpFarm();
      await a.write([const DeleteRow('expenses', 'e1')]);
      await b.write([
        const UpdateRow('expenses', 'e1', {'notes': 'still here'}),
      ]);
      await a.sync();
      await b.sync();
      final c =
          (await b.db.customSelect('SELECT * FROM conflicts').getSingle()).data;
      expect(c['kind'], 'delete_edit');
      expect((await b.row('expenses', 'e1'))!['deleted_at'], isNotNull);
      expect((jsonDecode(c['mine']! as String) as Map)['notes'], 'still here');

      // and the other way round: edit first, then the delete arrives
      await a.history.restore(
        (await a.db
                .customSelect(
                  "SELECT id FROM event_log WHERE \"action\" = 'delete'",
                )
                .getSingle())
            .read<String>('id'),
      );
      await a.sync();
      await b.sync();
      await a.write([
        const UpdateRow('expenses', 'e1', {'notes': 'edited on A'}),
      ]);
      await b.write([const DeleteRow('expenses', 'e1')]);
      await a.sync();
      await b.sync();
      expect(
        await b.count(
          "SELECT COUNT(*) FROM conflicts WHERE kind = 'delete_edit'",
        ),
        2,
      );
      expect((await b.row('expenses', 'e1'))!['deleted_at'], isNull);
    },
  );

  test(
    'an upload cut off after the server applied it is not applied twice',
    () async {
      await setUpFarm();
      await a.write([
        const CreateRow('notes', {
          'id': 'n1',
          'farm_id': farm,
          'noted_on': '2026-11-18',
          'body': 'x',
        }),
      ]);
      server.loseNextReply = true;
      await expectLater(a.sync(), throwsA(isA<SyncUnavailable>()));
      expect(
        await a.count("SELECT COUNT(*) FROM outbox WHERE status = 'sending'"),
        greaterThan(0),
      );
      final applied = server.tables['notes']!['n1']!['server_seq'];
      final pushesBefore = server.pushes.length;
      await a.sync();
      expect(
        server.tables['notes']!['n1']!['server_seq'],
        applied,
      ); // not written again
      expect(
        server.pushes.length,
        pushesBefore,
      ); // the retry got the stored answer
      expect(await a.count('SELECT COUNT(*) FROM outbox'), 0);
    },
  );

  test('the same batch sent twice changes nothing', () async {
    await setUpFarm();
    final session = server.as(owner);
    const row = PushRow(
      entity: 'notes',
      row: {
        'id': 'n2',
        'farm_id': farm,
        'noted_on': '2026-11-18',
        'body': 'twice',
        'version': 1,
        'created_at': '2026-11-18T08:00:00.000Z',
        'updated_at': '2026-11-18T08:00:00.000Z',
      },
      baseVersion: 0,
    );
    final first = await session.push('batch-1', farm, [row], userId: owner);
    final seq = server.tables['notes']!['n2']!['server_seq'];
    final second = await session.push('batch-1', farm, [row], userId: owner);
    expect(second.accepted, first.accepted);
    expect(server.tables['notes']!['n2']!['server_seq'], seq);
  });

  test(
    'a phone whose clock is a day wrong still merges in server order',
    () async {
      server = FakeServer();
      a = Phone(server, owner);
      b = Phone(server, manager, seed: 2, skew: const Duration(days: -1));
      await setUpFarm();
      await a.write([
        const UpdateRow('expenses', 'e1', {'notes': 'A, on time'}),
      ]);
      await b.write([
        const UpdateRow('expenses', 'e1', {'notes': 'B, clock a day behind'}),
      ]);
      await a.sync();
      await b.sync();
      await a.sync();
      expect(
        (await a.row('expenses', 'e1'))!['notes'],
        'B, clock a day behind',
      );
      expect(await a.count('SELECT COUNT(*) FROM outbox'), 0);
      expect(await b.count('SELECT COUNT(*) FROM outbox'), 0);
    },
  );

  test(
    'a new row under a parent deleted on the other phone goes to the farmer',
    () async {
      await setUpFarm();
      await a.write([const DeleteRow('crop_cycles', 'c1')]);
      await b.write([
        const CreateRow('workers', {
          'id': 'w1',
          'farm_id': farm,
          'name': 'Ravi',
        }),
        const CreateRow('labour_entries', {
          'id': 'l1',
          'farm_id': farm,
          'work_date': '2026-11-18',
          'worker_id': 'w1',
          'crop_cycle_id': 'c1',
          'rate_paise': 90000,
          'amount_paise': 90000,
        }),
      ]);
      await a.sync();
      await b.sync();
      final c =
          (await b.db.customSelect('SELECT * FROM conflicts').getSingle()).data;
      expect(c['kind'], 'orphan');
      expect(c['row_id'], 'l1');
      // the entry is kept, not lost
      expect(server.row('labour_entries', 'l1'), isNotNull);
    },
  );

  test('two phones selling more than a lot holds go to the farmer', () async {
    await setUpFarm();
    await a.write([
      const CreateRow('lots', {
        'id': 'lot1',
        'farm_id': farm,
        'crop_cycle_id': 'c1',
        'quantity': 50000,
      }),
    ]);
    await a.sync();
    await b.sync();
    for (final (p, n) in [(a, 'a'), (b, 'b')]) {
      await p.write([
        CreateRow('sales', {
          'id': 's-$n',
          'farm_id': farm,
          'sold_on': '2026-11-18',
          'quantity': 30000,
          'rate_paise': 70500,
          'net_paise': 2115000,
        }),
        CreateRow('sale_lots', {
          'id': 'sl-$n',
          'farm_id': farm,
          'sale_id': 's-$n',
          'lot_id': 'lot1',
          'quantity': 30000,
        }),
      ]);
    }
    await a.sync();
    await b.sync();
    expect(await a.count('SELECT COUNT(*) FROM conflicts'), 0);
    expect(
      await b.count("SELECT COUNT(*) FROM conflicts WHERE kind = 'oversell'"),
      1,
    );
  });

  test('five offline edits to one row go up as one', () async {
    await setUpFarm();
    for (var i = 1; i <= 5; i++) {
      await a.write([
        UpdateRow('expenses', 'e1', {'amount_paise': 360000 + i}),
      ]);
    }
    final before = server.pushes.length;
    await a.sync();
    final sent = server.pushes
        .skip(before)
        .expand((p) => p)
        .where((r) => r.entity == 'expenses');
    expect(sent.length, 1);
    expect(sent.single.baseVersion, 1);
    expect(sent.single.changes, {'amount_paise': 360000});
    expect(sent.single.row['amount_paise'], 360005);
    // the history still has all five
    expect(
      server.tables['event_log']!.values
          .where((e) => e['entity'] == 'expenses' && e['action'] == 'update')
          .length,
      5,
    );
  });

  test(
    'a row the server refuses leaves the queue and never blocks later rows',
    () async {
      await setUpFarm();
      server.denied[manager] = {'parties'};
      await b.write([
        const CreateRow('parties', {
          'id': 'v1',
          'farm_id': farm,
          'kind': 'vendor',
          'name': 'Shop',
        }),
        const CreateRow('notes', {
          'id': 'n3',
          'farm_id': farm,
          'noted_on': '2026-11-18',
          'body': 'ok',
        }),
      ]);
      await b.sync();
      expect(server.row('notes', 'n3'), isNotNull);
      expect(server.row('parties', 'v1'), isNull);
      final status = await b.engine.watchStatus().first;
      expect(status.rejected, 1);
      expect(status.waiting, 0);
      await b.sync(); // the refused row is not sent again
      expect(server.row('parties', 'v1'), isNull);
    },
  );

  test('a pull never overwrites a change still waiting to upload', () async {
    await setUpFarm();
    await a.write([
      const UpdateRow('expenses', 'e1', {'notes': 'A'}),
    ]);
    await a.sync();
    server.down = true;
    await b.write([
      const UpdateRow('expenses', 'e1', {'category_code': 'seeds'}),
    ]);
    server.down = false;
    await b.engine.pull(); // a pull alone, before B's upload
    expect((await b.row('expenses', 'e1'))!['category_code'], 'seeds');
    await b.sync();
    expect((await b.row('expenses', 'e1'))!['notes'], 'A');
    expect((await b.row('expenses', 'e1'))!['category_code'], 'seeds');
  });

  test(
    'offline, sync fails quietly and keeps everything for next time',
    () async {
      await setUpFarm();
      await a.write([
        const CreateRow('notes', {
          'id': 'n4',
          'farm_id': farm,
          'noted_on': '2026-11-18',
          'body': 'x',
        }),
      ]);
      server.down = true;
      await expectLater(a.sync(), throwsA(isA<SyncUnavailable>()));
      expect((await a.engine.watchStatus().first).waiting, 1);
      server.down = false;
      await a.sync();
      final status = await a.engine.watchStatus().first;
      expect(status.waiting, 0);
      expect(status.lastSyncedAt, isNotNull);
    },
  );

  test('a membership committed late in another farm is still found', () async {
    await setUpFarm();
    // B has already pulled memberships with higher server_seq values; a
    // membership in a second farm then lands with a lower one, as a late
    // commit from another farm's transaction would.
    await b.sync();
    server.tables['farm_members']!['m-late'] = {
      ...server.row('farm_members', 'm-manager')!,
      'id': 'm-late',
      'farm_id': 'farm-2',
      'server_seq': 1,
    };
    await b.sync();
    expect(await b.row('farm_members', 'm-late'), isNotNull);
  });

  test('a removed member stops receiving the farm', () async {
    await setUpFarm();
    server.put('farm_members', {
      ...server.row('farm_members', 'm-manager')!,
      'deleted_at': '2026-11-18T09:00:00.000Z',
      'version': 2,
    });
    await a.write([
      const CreateRow('notes', {
        'id': 'n5',
        'farm_id': farm,
        'noted_on': '2026-11-18',
        'body': 'private',
      }),
    ]);
    await a.sync();
    await b.sync();
    expect(await b.row('notes', 'n5'), isNull);
    // and the farm leaves that phone: money included
    expect(await b.row('expenses', 'e1'), isNull);
    expect(await b.row('farms', farm), isNull);
    expect(await b.count('SELECT COUNT(*) FROM event_log'), 0);
  });

  test('an edit made while an upload is in flight is not lost', () async {
    await setUpFarm();
    await a.write([
      const UpdateRow('expenses', 'e1', {'amount_paise': 370000}),
    ]);
    await a.sync();
    await b.write([
      const UpdateRow('expenses', 'e1', {'amount_paise': 380000}),
    ]);
    // the farmer saves a note while the conflicting upload is on its way
    server.duringPush = () => b.write([
      const UpdateRow('expenses', 'e1', {'notes': 'said while sending'}),
    ]);
    await b.engine.upload();
    expect(await b.count('SELECT COUNT(*) FROM conflicts'), 1);
    expect((await b.row('expenses', 'e1'))!['notes'], 'said while sending');
    await b.sync();
    await a.sync();
    expect((await a.row('expenses', 'e1'))!['notes'], 'said while sending');
  });

  test('a change undone before it synced is not a change', () async {
    await setUpFarm();
    final edit = await a.write([
      const UpdateRow('expenses', 'e1', {'amount_paise': 370000}),
    ]);
    await a.history.restore(edit.single); // back to 360000
    await b.write([
      const UpdateRow('expenses', 'e1', {'amount_paise': 380000}),
    ]);
    await b.sync();
    await a.sync();
    expect(await a.count('SELECT COUNT(*) FROM conflicts'), 0);
    expect((await a.row('expenses', 'e1'))!['amount_paise'], 380000);
    expect(server.row('expenses', 'e1')!['amount_paise'], 380000);
  });

  test(
    'a delete undone before it synced keeps the other phone edits',
    () async {
      await setUpFarm();
      final del = await a.write([const DeleteRow('expenses', 'e1')]);
      await a.history.restore(del.single);
      await b.write([
        const UpdateRow('expenses', 'e1', {'notes': 'from B'}),
      ]);
      await b.sync();
      await a.sync();
      expect(server.row('expenses', 'e1')!['notes'], 'from B');
      expect(server.row('expenses', 'e1')!['deleted_at'], isNull);
      expect(await a.count('SELECT COUNT(*) FROM conflicts'), 0);
    },
  );

  test(
    'two phones working out the same lot cost: a different amount is a choice',
    () async {
      await setUpFarm();
      await a.write([
        const CreateRow('lots', {
          'id': 'lot1',
          'farm_id': farm,
          'crop_cycle_id': 'c1',
          'quantity': 120000,
        }),
      ]);
      await a.sync();
      await b.sync();
      // both money phones work out the supervisor's lot while offline
      await a.write([
        const CreateRow('lot_costs', {
          'id': 'lot1',
          'farm_id': farm,
          'cost_paise': 2856000,
        }),
      ]);
      await b.write([
        const CreateRow('lot_costs', {
          'id': 'lot1',
          'farm_id': farm,
          'cost_paise': 3000000,
          'cost_overridden': true,
        }),
      ]);
      await a.sync();
      await b.sync();
      final c =
          (await b.db.customSelect('SELECT * FROM conflicts').getSingle()).data;
      expect(c['kind'], 'same_field');
      expect(c['row_id'], 'lot1');
    },
  );

  test(
    'two phones working out the same lot cost alike need no choice',
    () async {
      await setUpFarm();
      await a.write([
        const CreateRow('lots', {
          'id': 'lot2',
          'farm_id': farm,
          'crop_cycle_id': 'c1',
          'quantity': 1000,
        }),
      ]);
      await a.sync();
      await b.sync();
      for (final p in [a, b]) {
        await p.write([
          const CreateRow('lot_costs', {
            'id': 'lot2',
            'farm_id': farm,
            'cost_paise': 1000,
          }),
        ]);
      }
      await a.sync();
      await b.sync();
      expect(await b.count('SELECT COUNT(*) FROM conflicts'), 0);
    },
  );

  test(
    'a clock that jumps back does not drop an edit from the merge',
    () async {
      await setUpFarm();
      a.now = a.now.add(const Duration(hours: 5)); // a fast clock
      await a.write([
        const UpdateRow('expenses', 'e1', {'notes': 'first'}),
      ]);
      a.now = a.now.subtract(
        const Duration(hours: 5),
      ); // corrected by the network
      await a.write([
        const UpdateRow('expenses', 'e1', {'category_code': 'seeds'}),
      ]);
      await b.write([
        const UpdateRow('expenses', 'e1', {'mode': 'upi'}),
      ]);
      await b.sync();
      await a.sync();
      final e = server.row('expenses', 'e1')!;
      expect(e['category_code'], 'seeds');
      expect(e['notes'], 'first');
      expect(e['mode'], 'upi');
    },
  );

  test('a cut-off upload goes again parents first', () async {
    await setUpFarm();
    await b.write([
      const CreateRow('workers', {'id': 'w1', 'farm_id': farm, 'name': 'Ravi'}),
      const CreateRow('labour_entries', {
        'id': 'l1',
        'farm_id': farm,
        'work_date': '2026-11-18',
        'worker_id': 'w1',
        'rate_paise': 90000,
        'amount_paise': 90000,
      }),
    ]);
    await b.sync();
    // the entry is edited, then moved to a worker added after it
    await b.write([
      const UpdateRow('labour_entries', 'l1', {'task_code': 'weeding'}),
    ]);
    await b.write([
      const CreateRow('workers', {'id': 'w2', 'farm_id': farm, 'name': 'Sita'}),
    ]);
    await b.write([
      const UpdateRow('labour_entries', 'l1', {'worker_id': 'w2'}),
    ]);
    server.failNextPush = true;
    await expectLater(b.engine.upload(), throwsA(isA<SyncUnavailable>()));
    await b.sync();
    expect(server.row('labour_entries', 'l1')!['worker_id'], 'w2');
    expect((await b.engine.watchStatus().first).rejected, 0);
  });

  test('a row made offline and changed after a failed try is not a conflict '
      'with itself', () async {
    await setUpFarm();
    server.down = true;
    await a.write([
      const CreateRow('expenses', {
        'id': 'e2',
        'farm_id': farm,
        'spent_on': '2026-11-18',
        'category_code': 'seeds',
        'amount_paise': 1000,
      }),
      const CreateRow('expenses', {
        'id': 'e3',
        'farm_id': farm,
        'spent_on': '2026-11-18',
        'category_code': 'seeds',
        'amount_paise': 500,
      }),
    ]);
    await expectLater(a.sync(), throwsA(isA<SyncUnavailable>()));
    await a.write([
      const UpdateRow('expenses', 'e2', {'amount_paise': 2000}),
    ]);
    await a.write([const DeleteRow('expenses', 'e3')]);
    server.down = false;
    await a.sync();
    expect(await a.count('SELECT COUNT(*) FROM conflicts'), 0);
    expect(server.row('expenses', 'e2')!['amount_paise'], 2000);
    expect(server.row('expenses', 'e3')!['deleted_at'], isNotNull);
    expect(await a.count('SELECT COUNT(*) FROM outbox'), 0);
  });

  test('a split saved and undone before it synced needs no choice', () async {
    await setUpFarm();
    final saved = await a.write([
      const CreateRow('expenses', {
        'id': 'e4',
        'farm_id': farm,
        'spent_on': '2026-11-18',
        'category_code': 'seeds',
        'amount_paise': 1000,
      }),
      const CreateRow('expense_allocations', {
        'id': 'ea4',
        'farm_id': farm,
        'expense_id': 'e4',
        'crop_cycle_id': 'c1',
        'amount_paise': 1000,
      }),
    ]);
    await a.history.undo(saved);
    await a.sync();
    expect(await a.count('SELECT COUNT(*) FROM conflicts'), 0);
    expect(server.row('expense_allocations', 'ea4')!['deleted_at'], isNotNull);
  });

  test('a refused change gives way to the server row', () async {
    await setUpFarm();
    await a.write([
      const UpdateRow('expenses', 'e1', {'notes': 'owner note'}),
    ]);
    await a.sync();
    server.denied[manager] = {'expenses'};
    await b.write([
      const UpdateRow('expenses', 'e1', {'notes': 'refused note'}),
    ]);
    await b.sync();
    expect((await b.engine.watchStatus().first).rejected, 1);
    expect((await b.row('expenses', 'e1'))!['notes'], 'owner note');
  });

  test('wider access brings the history that was hidden before', () async {
    await setUpFarm();
    // a supervisor joins, and cannot see money history
    const sup = 'user-supervisor';
    server.put('farm_members', {
      ...server.row('farm_members', 'm-manager')!,
      'id': 'm-sup',
      'user_id': sup,
      'role': 'supervisor',
    });
    server.hidden = (user, table, row) =>
        user == sup &&
        server.row('farm_members', 'm-sup')!['role'] == 'supervisor' &&
        table == 'event_log' &&
        row['entity'] == 'expenses';
    await a.write([
      const CreateRow('notes', {
        'id': 'n9',
        'farm_id': farm,
        'noted_on': '2026-11-18',
        'body': 'daily',
      }),
    ]);
    await a.sync();
    final s = Phone(server, sup, seed: 3);
    addTearDown(s.db.close);
    await s.sync();
    const money = "SELECT COUNT(*) FROM event_log WHERE entity = 'expenses'";
    expect(await s.count(money), 0);
    expect(await s.row('notes', 'n9'), isNotNull);
    // the owner makes them accountant: the money history arrives
    server.put('farm_members', {
      ...server.row('farm_members', 'm-sup')!,
      'role': 'accountant',
      'version': 2,
    });
    await s.sync();
    expect(await s.count(money), greaterThan(0));
  });

  test('narrower access drops what can no longer be read', () async {
    await setUpFarm();
    await b.write([
      const CreateRow('notes', {
        'id': 'n11',
        'farm_id': farm,
        'noted_on': '2026-11-18',
        'body': 'daily',
      }),
    ]);
    await b.sync();
    expect(await b.row('expenses', 'e1'), isNotNull);
    expect(await b.row('farm_members', 'm-owner'), isNotNull);
    // the owner makes the manager a supervisor while their phone is offline,
    // with a money entry of theirs still waiting
    server.down = true;
    await b.write([
      const CreateRow('other_income', {
        'id': 'i1',
        'farm_id': farm,
        'received_on': '2026-11-18',
        'source_code': 'subsidy',
        'amount_paise': 100000,
      }),
    ]);
    server.down = false;
    server.put('farm_members', {
      ...server.row('farm_members', 'm-manager')!,
      'role': 'supervisor',
      'version': 2,
    });
    server.denied[manager] = {'other_income'};
    bool money(String t) => tableAccess[t] == AccessClass.money;
    server.hidden = (user, table, row) =>
        user == manager &&
        (money(table) ||
            (table == 'event_log' && money(row['entity']! as String)) ||
            (table == 'farm_members' && row['user_id'] != manager));
    await b.sync();
    // money, its history and the other members leave the phone
    expect(await b.row('expenses', 'e1'), isNull);
    expect(
      await b.count("SELECT COUNT(*) FROM event_log WHERE entity = 'expenses'"),
      0,
    );
    expect(await b.row('farm_members', 'm-owner'), isNull);
    // daily work, set-up, their own membership and its history stay
    expect(await b.row('notes', 'n11'), isNotNull);
    expect(await b.row('plots', 'p1'), isNotNull);
    expect((await b.row('farm_members', 'm-manager'))!['role'], 'supervisor');
    expect(
      await b.count("SELECT COUNT(*) FROM event_log WHERE entity = 'notes'"),
      greaterThan(0),
    );
    // the refused entry stays, shown as refused, not lost unseen
    expect(await b.row('other_income', 'i1'), isNotNull);
    expect((await b.engine.watchStatus().first).rejected, 1);
  });

  test('an upload for one person is never sent as another', () async {
    await setUpFarm();
    final wrong = SyncEngine(a.db, server.as(manager), userId: owner);
    await a.write([
      const CreateRow('notes', {
        'id': 'n10',
        'farm_id': farm,
        'noted_on': '2026-11-18',
        'body': 'x',
      }),
    ]);
    await expectLater(wrong.upload(), throwsA(isA<SyncUnavailable>()));
    expect(server.row('notes', 'n10'), isNull);
    await a.sync();
    expect(server.row('notes', 'n10')!['created_by'], owner);
  });

  test(
    'the scheduler syncs soon after a write and retries after a failure',
    () async {
      await setUpFarm();
      final scheduler = SyncScheduler(
        a.engine,
        debounce: const Duration(milliseconds: 20),
        backoff: (_) => const Duration(milliseconds: 30),
      )..start();
      addTearDown(scheduler.dispose);
      server.down = true;
      await a.write([
        const CreateRow('notes', {
          'id': 'n6',
          'farm_id': farm,
          'noted_on': '2026-11-18',
          'body': 'x',
        }),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(server.row('notes', 'n6'), isNull);
      server.down = false;
      for (var i = 0; i < 50 && server.row('notes', 'n6') == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(server.row('notes', 'n6'), isNotNull);
    },
  );

  test('retries wait longer each time, with jitter, up to ten minutes', () {
    final r = Random(3);
    for (var attempt = 0; attempt < 30; attempt++) {
      final d = retryDelay(attempt, r).inMilliseconds;
      final base = min(2000 * pow(2, min(attempt, 20)), 600000);
      expect(d, inInclusiveRange(base * 0.5, base * 1.5));
    }
  });
}
