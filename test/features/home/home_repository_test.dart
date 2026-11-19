import 'dart:math';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/history/write_with_history.dart';
import 'package:thottam/features/history/data/history_repository.dart';
import 'package:thottam/features/home/data/home_repository.dart';
import 'package:thottam/features/land/data/land_repository.dart';

import '../../helpers/session.dart';
import 'home_test_farm.dart';

void main() {
  late AppDatabase db;
  late String farm;
  late History history;
  late HomeRepository home;
  final today = DateTime(2026, 11, 19).millisecondsSinceEpoch;

  setUp(() async {
    final (d, f) = await farmDatabase(
      crops: const ['Coconut', 'Pepper', 'Banana'],
      seed: homeFarm,
    );
    db = d;
    farm = f;
    var now = DateTime(2026, 11, 19, 12);
    history = History(
      db,
      userId: testUser,
      clock: () => now = now.add(const Duration(milliseconds: 10)),
      random: Random(9),
    );
    home = HomeRepository(db, history, farm);
  });
  tearDown(() => db.close());

  Future<List<TaskView>> tasks() =>
      home.watchTodayTasks('2026-11-19', today).first;

  test('today: tasks due today and overdue, oldest first; not tomorrow, '
      'not done before today', () async {
    final t = await tasks();
    expect(t.map((x) => x.title), ['Tie the vines', 'Spray Bordeaux']);
    expect(t.first.cropEn, 'Pepper');
    expect(t.first.plot, isNotNull);
  });

  test('ticking a task writes to history, stays on today ticked, and undo '
      'opens it again', () async {
    final task = (await tasks()).last;
    final events = await home.setDone(
      task,
      true,
      DateTime(2026, 11, 19, 12).millisecondsSinceEpoch,
    );
    expect((await tasks()).last.done, isTrue);
    final log = await db
        .customSelect(
          'SELECT action, summary FROM event_log WHERE id = ?',
          variables: [Variable.withString(events.single)],
        )
        .getSingle();
    expect(log.read<String>('action'), 'update');
    expect(log.read<String>('summary'), contains('Spray Bordeaux'));

    await home.undo(events);
    expect((await tasks()).last.done, isFalse);
  });

  test('a note saved offline shows in the diary under its day', () async {
    final plot = (await LandRepository(
      db,
      history,
      farm,
    ).watchPlots().first).single;
    final pepper = plot.cycles.firstWhere((c) => c.nameEn == 'Pepper');
    await home.saveNote(
      NoteInput(
        day: '2026-11-17',
        text: '  Leaves yellowing on the east side ',
        plotId: plot.id,
        plot: plot.name,
        cycleId: pepper.id,
        cropMl: pepper.nameMl,
        cropEn: pepper.nameEn,
      ),
    );
    final note = await db
        .customSelect('SELECT body, noted_on, crop_cycle_id FROM notes')
        .getSingle();
    expect(note.data, {
      'body': 'Leaves yellowing on the east side',
      'noted_on': '2026-11-17',
      'crop_cycle_id': pepper.id,
    });
    final diary = await HistoryRepository(
      db,
      history,
      farm,
    ).watchDiary(entities: ',notes,', actions: ',create,').first;
    expect(diary.single.day, '2026-11-17');
    expect(diary.single.summary['text'], 'Leaves yellowing on the east side');
    // nothing went to the server: it waits in the outbox
    final outbox = await db
        .customSelect("SELECT COUNT(*) AS n FROM outbox WHERE entity = 'notes'")
        .getSingle();
    expect(outbox.read<int>('n'), 1);
  });
}
