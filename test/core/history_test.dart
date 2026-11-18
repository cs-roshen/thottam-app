import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/history/write_with_history.dart';

const farm = '0190f000-0000-7000-8000-00000000f001';
const plot = '0190f000-0000-7000-8000-00000000a001';
const user = '0190f000-0000-7000-8000-00000000u001';

void main() {
  late AppDatabase db;
  late History history;
  late DateTime now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 11, 18, 9);
    history = History(
      db,
      userId: user,
      clock: () => now = now.add(const Duration(seconds: 1)),
      random: Random(1),
    );
  });
  tearDown(() => db.close());

  Future<List<Map<String, Object?>>> rows(String sql) async => [
    for (final r in await db.customSelect(sql).get()) r.data,
  ];
  Map<String, Object?> json(Object? text) =>
      (jsonDecode(text! as String) as Map).cast<String, Object?>();

  Future<String> addExpense() async {
    await history.writeWithHistory([
      const CreateRow(
        'expenses',
        {
          'id': 'e1',
          'farm_id': farm,
          'spent_on': '2026-11-10',
          'category_code': 'fertiliser',
          'amount_paise': 360000,
          'plot_id': plot,
        },
        occurredOn: '2026-11-10',
        summary: {'amount_paise': 360000, 'plot': 'Plot 1'},
      ),
    ]);
    return 'e1';
  }

  test('create writes the row, a full history row and one upload', () async {
    final events = await history.writeWithHistory([
      const CreateRow('plots', {'farm_id': farm, 'name': 'Plot 1'}),
    ]);
    final plotRow = (await rows('SELECT * FROM plots')).single;
    expect(plotRow['version'], 1);
    expect(plotRow['created_by'], user);
    expect(plotRow['deleted_at'], isNull);

    final event = (await rows('SELECT * FROM event_log')).single;
    expect(event['id'], events.single);
    expect(event['action'], 'create');
    expect(event['entity'], 'plots');
    expect(event['entity_id'], plotRow['id']);
    expect(event['old_values'], isNull);
    expect(json(event['new_values'])['name'], 'Plot 1');
    expect(json(event['new_values'])['version'], 1);
    expect(event['occurred_on'], '2026-11-18');

    final outbox = await rows(
      'SELECT entity, row_id, base_version FROM outbox',
    );
    expect(outbox, [
      {'entity': 'plots', 'row_id': plotRow['id'], 'base_version': 0},
      {'entity': 'event_log', 'row_id': event['id'], 'base_version': 0},
    ]);
  });

  test(
    'an edit stores only the changed fields and bumps the version',
    () async {
      final id = await addExpense();
      await history.writeWithHistory([
        UpdateRow(
          'expenses',
          id,
          {
            'amount_paise': 380000,
            'category_code': 'fertiliser', // unchanged
          },
          summary: const {'amount_paise': 380000},
        ),
      ]);
      final expense = (await rows('SELECT * FROM expenses')).single;
      expect(expense['amount_paise'], 380000);
      expect(expense['version'], 2);

      final edit = (await rows(
        "SELECT * FROM event_log WHERE \"action\" = 'update'",
      )).single;
      expect(json(edit['old_values']), {'amount_paise': 360000});
      expect(json(edit['new_values']), {'amount_paise': 380000});
      expect(json(edit['summary']), {'amount_paise': 380000});
    },
  );

  test('an edit that changes nothing writes nothing', () async {
    final id = await addExpense();
    final events = await history.writeWithHistory([
      UpdateRow('expenses', id, const {'amount_paise': 360000}),
    ]);
    expect(events, isEmpty);
    expect((await rows('SELECT * FROM event_log')).length, 1);
    expect((await rows('SELECT * FROM expenses')).single['version'], 1);
  });

  test(
    'edits made offline fold into one upload keeping the base version',
    () async {
      final id = await addExpense();
      // as if the create reached the server: the queue is empty again
      await db.customStatement('DELETE FROM outbox');
      for (final amount in [370000, 380000, 390000]) {
        await history.writeWithHistory([
          UpdateRow('expenses', id, {'amount_paise': amount}),
        ]);
      }
      final pending = await rows(
        "SELECT row_id, base_version FROM outbox WHERE entity = 'expenses'",
      );
      expect(pending, [
        {'row_id': id, 'base_version': 1},
      ]);
      expect((await rows('SELECT * FROM expenses')).single['version'], 4);
      // the history still carries all three changes
      expect(
        (await rows("SELECT * FROM event_log WHERE \"action\" = 'update'"))
            .length,
        3,
      );
    },
  );

  test('delete only marks the row and keeps the full row in history', () async {
    final id = await addExpense();
    await history.writeWithHistory([DeleteRow('expenses', id)]);
    final expense = (await rows('SELECT * FROM expenses')).single;
    expect(expense['deleted_at'], isNotNull);
    final del = (await rows(
      "SELECT * FROM event_log WHERE \"action\" = 'delete'",
    )).single;
    expect(json(del['old_values'])['amount_paise'], 360000);
    expect(json(del['old_values'])['deleted_at'], isNull);
    // deleting again changes nothing
    expect(
      await history.writeWithHistory([DeleteRow('expenses', id)]),
      isEmpty,
    );
  });

  test(
    'restore of a delete brings the row back, and is itself logged',
    () async {
      final id = await addExpense();
      final del = await history.writeWithHistory([
        DeleteRow('expenses', id, occurredOn: '2026-11-10'),
      ]);
      final restored = await history.restore(del.single);
      expect(restored, isNotNull);
      final expense = (await rows('SELECT * FROM expenses')).single;
      expect(expense['deleted_at'], isNull);
      expect(expense['version'], 3);
      final r = (await rows(
        "SELECT * FROM event_log WHERE \"action\" = 'restore'",
      )).single;
      expect(json(r['new_values']), {'deleted_at': null});
      expect(r['occurred_on'], '2026-11-10'); // the day of the entry
    },
  );

  test('restore of an edit puts the old values back', () async {
    final id = await addExpense();
    final edit = await history.writeWithHistory([
      UpdateRow('expenses', id, const {'amount_paise': 1, 'notes': 'typo'}),
    ]);
    await history.restore(edit.single);
    final expense = (await rows('SELECT * FROM expenses')).single;
    expect(expense['amount_paise'], 360000);
    expect(expense['notes'], isNull);
  });

  test(
    'restore of a create is the undo of a save: the row is deleted',
    () async {
      await addExpense();
      final create = (await rows('SELECT id FROM event_log')).single['id']!;
      await history.restore(create as String);
      expect(
        (await rows('SELECT * FROM expenses')).single['deleted_at'],
        isNotNull,
      );
      // restoring that restore brings it back
      final undo = (await rows(
        "SELECT id FROM event_log WHERE \"action\" = 'restore'",
      )).single['id']!;
      await history.restore(undo as String);
      expect(
        (await rows('SELECT * FROM expenses')).single['deleted_at'],
        isNull,
      );
    },
  );

  test(
    'a failed write leaves nothing in the row, history or upload tables',
    () async {
      await expectLater(
        history.writeWithHistory([
          const CreateRow('plots', {'farm_id': farm, 'name': 'Plot 1'}),
          const UpdateRow('plots', 'missing', {'name': 'x'}),
        ]),
        throwsStateError,
      );
      expect(await rows('SELECT * FROM plots'), isEmpty);
      expect(await rows('SELECT * FROM event_log'), isEmpty);
      expect(await rows('SELECT * FROM outbox'), isEmpty);
    },
  );

  test('a write with several rows is one transaction', () async {
    final events = await history.writeWithHistory([
      const CreateRow('plots', {'id': 'p1', 'farm_id': farm, 'name': 'Plot 1'}),
      const CreateRow('crop_cycles', {
        'farm_id': farm,
        'plot_id': 'p1',
        'crop_id': 'coconut',
      }),
    ]);
    expect(events.length, 2);
    expect((await rows('SELECT * FROM outbox')).length, 4);
  });

  test('only synced tables and their own columns can be written', () async {
    expect(
      () => history.writeWithHistory([
        const CreateRow('outbox', {'farm_id': farm}),
      ]),
      throwsArgumentError,
    );
    expect(
      () => history.writeWithHistory([
        const CreateRow('event_log', {'farm_id': farm}),
      ]),
      throwsArgumentError,
    );
    expect(
      () => history.writeWithHistory([
        const CreateRow('plots', {'farm_id': farm, 'name': 'x', 'evil"': 1}),
      ]),
      throwsArgumentError,
    );
    expect(
      () => history.writeWithHistory([
        const CreateRow('plots', {'farm_id': farm, 'name': 'x', 'version': 9}),
      ]),
      throwsArgumentError,
    );
    expect(
      () => history.writeWithHistory([
        const CreateRow('plots', {'name': 'no farm'}),
      ]),
      throwsArgumentError,
    );
    final id = await addExpense();
    expect(
      () => history.writeWithHistory([
        UpdateRow('expenses', id, const {'farm_id': 'other'}),
      ]),
      throwsArgumentError,
    );
    expect(
      () => history.writeWithHistory([
        UpdateRow('expenses', id, const {'deleted_at': 1}),
      ]),
      throwsArgumentError,
    );
  });

  test('a new farm is its own farm', () async {
    await history.writeWithHistory([
      const CreateRow('farms', {'id': farm, 'name': 'Thottam'}),
    ]);
    final event = (await rows('SELECT farm_id FROM event_log')).single;
    expect(event['farm_id'], farm);
  });

  test(
    'JSON and true or false values are stored as the server expects',
    () async {
      await history.writeWithHistory([
        const CreateRow('workers', {
          'id': 'w1',
          'farm_id': farm,
          'name': 'Ravi',
          'is_family': true,
        }),
        const CreateRow('labour_groups', {
          'farm_id': farm,
          'label': 'Gang',
          'default_rates': {'general': 80000},
        }),
      ]);
      final w = (await rows('SELECT is_family FROM workers')).single;
      expect(w['is_family'], 1);
      final g = (await rows('SELECT default_rates FROM labour_groups')).single;
      expect(json(g['default_rates']), {'general': 80000});
    },
  );

  test('history rows are ordered by time for the diary', () async {
    await addExpense();
    await history.writeWithHistory([
      const UpdateRow('expenses', 'e1', {'amount_paise': 1}),
    ]);
    final events = await db
        .customSelect(
          'SELECT "action" FROM event_log WHERE farm_id = ? '
          'ORDER BY occurred_on DESC, created_at DESC, id DESC',
          variables: [Variable.withString(farm)],
        )
        .get();
    expect(events.map((e) => e.data['action']), ['update', 'create']);
  });
}
