import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../../../core/db/queries.dart';
import '../../../core/history/write_with_history.dart';

/// One row of the farm's history.
class HistoryEvent {
  const HistoryEvent({
    required this.id,
    required this.entity,
    required this.entityId,
    required this.action,
    required this.summary,
    required this.day,
    required this.createdAt,
    this.createdBy,
    this.oldValues,
    this.newValues,
  });

  factory HistoryEvent.of(QueryRow r) {
    Map<String, Object?>? json(String c) => switch (r.readNullable<String>(c)) {
      final s? => (jsonDecode(s) as Map).cast<String, Object?>(),
      null => null,
    };
    return HistoryEvent(
      id: r.read<String>('id'),
      entity: r.read<String>('entity'),
      entityId: r.read<String>('entity_id'),
      action: r.read<String>('action'),
      summary: json('summary') ?? const {},
      day: r.read<String>('occurred_on'),
      createdAt: r.read<int>('created_at'),
      createdBy: r.readNullable<String>('created_by'),
      oldValues: json('old_values'),
      newValues: json('new_values'),
    );
  }

  final String id;
  final String entity;
  final String entityId;
  final String action;
  final Map<String, Object?> summary;
  final String day;
  final int createdAt;
  final String? createdBy;
  final Map<String, Object?>? oldValues;
  final Map<String, Object?>? newValues;
}

/// The farm diary and each record's timeline, read only from `event_log`
/// (implementation plan, C7), and restore.
class HistoryRepository {
  HistoryRepository(this.db, this.history, this.farmId);

  final AppDatabase db;
  final History history;
  final String farmId;

  Stream<T> _watch<T>(Future<T> Function() load) async* {
    yield await load();
    await for (final _ in db.tableUpdates(
      TableUpdateQuery.onTable(db.eventLog),
    )) {
      yield await load();
    }
  }

  /// The newest [limit] diary rows of [entities] and [actions], optionally
  /// for one plot. Loading more asks for a larger [limit]; the query is a
  /// keyset page from the top, never an offset.
  Stream<List<HistoryEvent>> watchDiary({
    required String entities,
    required String actions,
    String plotId = '',
    int limit = 50,
  }) => _watch(
    () async => [
      for (final r in await select(db, qDiaryPage, {
        'farm': farmId,
        'day': '9999-12-31',
        'created': 1 << 53,
        'id': '',
        'entities': entities,
        'actions': actions,
        'onplot': plotId,
        'limit': limit,
      }))
        HistoryEvent.of(r),
    ],
  );

  /// How many diary rows fall between [from] and [to].
  Future<int> countBetween(String from, String to, String entities) async =>
      (await select(db, qDiaryRange, {
        'farm': farmId,
        'from': from,
        'to': to,
        'entities': entities,
      })).single.read<int>('n');

  Stream<List<HistoryEvent>> watchRecord(String entity, String id) => _watch(
    () async => [
      for (final r in await select(db, qRecordEvents, {
        'entity': entity,
        'row': id,
      }))
        HistoryEvent.of(r),
    ],
  );

  /// Whether the record of [e] was changed again after it: restoring it
  /// then asks first (review follow-up, C7).
  Future<bool> changedSince(HistoryEvent e) async =>
      (await select(db, qChangedSince, {
        'entity': e.entity,
        'row': e.entityId,
        'created': e.createdAt,
      })).single.read<int>('n') >
      0;

  /// Puts the record back as it was before [e]; returns the history ids for
  /// undo, empty when it already is.
  Future<List<String>> restore(HistoryEvent e) async => [
    ?await history.restore(e.id),
  ];

  Future<void> undo(List<String> events) => history.undo(events);
}
