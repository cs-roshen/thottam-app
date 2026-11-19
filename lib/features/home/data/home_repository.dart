import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../../../core/db/queries.dart';
import '../../../core/history/write_with_history.dart';

/// A task on Home: due today or before, open or ticked today.
class TaskView {
  const TaskView({
    required this.id,
    required this.title,
    required this.dueOn,
    required this.done,
    this.plotId,
    this.plot,
    this.cropMl,
    this.cropEn,
  });

  final String id;
  final String title;
  final String dueOn;
  final bool done;
  final String? plotId;
  final String? plot;
  final String? cropMl;
  final String? cropEn;
}

/// A note to save (quick add): text, day, and optionally a plot and crop.
class NoteInput {
  const NoteInput({
    required this.day,
    required this.text,
    this.plotId,
    this.plot,
    this.cycleId,
    this.cropMl,
    this.cropEn,
  });

  final String day;
  final String text;
  final String? plotId;
  final String? plot;
  final String? cycleId;
  final String? cropMl;
  final String? cropEn;
}

/// Home's tasks and quick add's notes (screens 2 and 3).
class HomeRepository {
  HomeRepository(this.db, this.history, this.farmId);

  final AppDatabase db;
  final History history;
  final String farmId;

  /// Tasks due on or before [day]; those ticked since [since] (milliseconds,
  /// the start of today) stay, ticked, so a tick can be taken back.
  Stream<List<TaskView>> watchTodayTasks(String day, int since) async* {
    Future<List<TaskView>> load() async => [
      for (final r in await select(db, qTodayTasks, {
        'farm': farmId,
        'day': day,
        'created': since,
      }))
        TaskView(
          id: r.read<String>('id'),
          title: r.read<String>('title'),
          dueOn: r.read<String>('due_on'),
          done: r.readNullable<int>('done_at') != null,
          plotId: r.readNullable<String>('plot_id'),
          plot: r.readNullable<String>('plot'),
          cropMl: r.readNullable<String>('crop_ml'),
          cropEn: r.readNullable<String>('crop_en'),
        ),
    ];
    yield await load();
    await for (final _ in db.tableUpdates(
      TableUpdateQuery.onAllTables([db.tasks, db.cropCycles, db.plots]),
    )) {
      yield await load();
    }
  }

  /// Ticks [task] done (or open again), recorded in history.
  Future<List<String>> setDone(TaskView task, bool done, int nowMs) =>
      history.writeWithHistory([
        UpdateRow(
          'tasks',
          task.id,
          {'done_at': done ? nowMs : null},
          summary: {
            'text': task.title,
            'plot_id': ?task.plotId,
            'plot': ?task.plot,
            'crop_ml': ?task.cropMl,
            'crop_en': ?task.cropEn,
          },
        ),
      ]);

  Future<List<String>> saveNote(NoteInput n) => history.writeWithHistory([
    CreateRow(
      'notes',
      {
        'id': history.newId(),
        'farm_id': farmId,
        'noted_on': n.day,
        'body': n.text.trim(),
        'plot_id': n.plotId,
        'crop_cycle_id': n.cycleId,
      },
      occurredOn: n.day,
      summary: {
        'text': n.text.trim(),
        'plot_id': ?n.plotId,
        'plot': ?n.plot,
        'crop_ml': ?n.cropMl,
        'crop_en': ?n.cropEn,
      },
    ),
  ]);

  Future<List<String>> undo(List<String> events) => history.undo(events);
}
