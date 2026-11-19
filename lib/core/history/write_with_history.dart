import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../db/database.dart';
import '../db/sql_value.dart';
import '../db/synced_tables.dart';
import '../ids/uuid_v7.dart';

/// One change to a synced row. Values are Dart values: text, int, bool, null,
/// DateTime, or maps and lists for JSON columns.
sealed class RowWrite {
  const RowWrite(this.table, {this.occurredOn, this.summary = const {}});

  final String table;

  /// The day the change belongs to ('YYYY-MM-DD'), for the farm diary; may be
  /// backdated. Defaults to today.
  final String? occurredOn;

  /// The few display fields the timeline needs (plot, crop, amount, quantity),
  /// so History never joins to draw a row.
  final Map<String, Object?> summary;
}

final class CreateRow extends RowWrite {
  const CreateRow(super.table, this.values, {super.occurredOn, super.summary});

  /// Every column except the common ones, which the history path sets. May
  /// carry an `id` made earlier (a lot's cost uses its lot's id).
  final Map<String, Object?> values;
}

final class UpdateRow extends RowWrite {
  const UpdateRow(
    super.table,
    this.id,
    this.changes, {
    super.occurredOn,
    super.summary,
  });

  final String id;
  final Map<String, Object?> changes;
}

final class DeleteRow extends RowWrite {
  const DeleteRow(super.table, this.id, {super.occurredOn, super.summary});

  final String id;
}

/// The one write path for synced tables (implementation plan section 6, B4).
/// Inside one local transaction it writes the row, an `event_log` row with
/// old and new values, and an `outbox` row. Nothing is hard-deleted.
class History {
  History(
    this.db, {
    required this.userId,
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final AppDatabase db;
  final String userId;
  final DateTime Function() _clock;
  final Random _random;

  static const _managed = {
    'created_at',
    'created_by',
    'updated_at',
    'updated_by',
    'version',
    'deleted_at',
  };
  static final _farmColumn = {for (final (t, c) in syncedTables) t: c};
  static const _notWritable = {'template_items', 'event_log'};

  /// Applies [writes] in order, all or nothing. Returns the ids of the
  /// history rows written, for undo; an update that changes nothing writes
  /// nothing.
  Future<List<String>> writeWithHistory(List<RowWrite> writes) =>
      _notifying({for (final w in writes) w.table}, () async {
        final events = <String>[];
        for (final w in writes) {
          final event = switch (w) {
            CreateRow() => await _create(w),
            UpdateRow() => await _update(w.table, w.id, w.changes, 'update', w),
            DeleteRow() => await _delete(w),
          };
          if (event != null) events.add(event);
        }
        return events;
      });

  /// Puts the row back as it was before history row [eventId]: an edit's old
  /// values, a deleted row back in place, a new row deleted (the undo of a
  /// save). The restore is itself a logged write. Returns its history id, or
  /// null when the row is already that way.
  // Restoring an event the row has changed since is allowed: the History
  // screen asks first (HistoryRepository.changedSince).
  Future<String?> restore(String eventId) async =>
      (await undo([eventId])).firstOrNull;

  /// The undo of one save: restores every history row [eventIds] it returned,
  /// newest first, all or nothing. Returns the new history ids.
  Future<List<String>> undo(List<String> eventIds) async {
    final entities = <String>{};
    for (final id in eventIds) {
      final e = await db
          .customSelect(
            'SELECT entity FROM event_log WHERE id = ?',
            variables: [Variable.withString(id)],
          )
          .getSingleOrNull();
      if (e == null) throw ArgumentError.value(id, 'eventIds');
      entities.add(e.read<String>('entity'));
    }
    return _notifying(entities, () async {
      final restored = <String>[];
      for (final id in eventIds.reversed) {
        if (await _restore(id) case final r?) restored.add(r);
      }
      return restored;
    });
  }

  Future<String?> _restore(String eventId) async {
    final event = await db
        .customSelect(
          'SELECT * FROM event_log WHERE id = ?',
          variables: [Variable.withString(eventId)],
        )
        .getSingleOrNull();
    if (event == null) throw ArgumentError.value(eventId, 'eventId');
    final e = event.data;
    final old = e['old_values'] == null
        ? <String, Object?>{}
        : (jsonDecode(e['old_values']! as String) as Map)
              .cast<String, Object?>();
    final target = switch (e['action']) {
      'create' => {'deleted_at': _clock().millisecondsSinceEpoch},
      'delete' => {'deleted_at': null},
      _ => old,
    };
    final summary = {
      for (final MapEntry(:key, :value) in (jsonDecode(
        e['summary']! as String,
      ) as Map).cast<String, Object?>().entries)
        key: target.containsKey(key) ? target[key] : value,
    };
    return _update(
      e['entity']! as String,
      e['entity_id']! as String,
      target,
      'restore',
      _Meta(e['occurred_on']! as String, summary),
    );
  }

  /// Runs [body] in one transaction, then tells every watching query that
  /// [tables], the history and the upload queue changed (raw statements do
  /// not do that on their own).
  Future<T> _notifying<T>(Set<String> tables, Future<T> Function() body) async {
    final result = await db.transaction(body);
    db.notifyUpdates({
      for (final t in db.allTables)
        if (tables.contains(t.actualTableName) ||
            t.actualTableName == 'event_log' ||
            t.actualTableName == 'outbox')
          TableUpdate.onTable(t),
    });
    return result;
  }

  Future<String> _create(CreateRow w) async {
    final columns = _columnsOf(w.table);
    for (final MapEntry(:key, :value) in w.values.entries) {
      if (!columns.containsKey(key) || _managed.contains(key)) {
        throw ArgumentError.value(key, 'values', 'not settable on ${w.table}');
      }
      _checkKind(columns[key]!, value, w.table);
    }
    final now = _clock().millisecondsSinceEpoch;
    final id = (w.values['id'] as String?) ?? newId();
    final row = <String, Object?>{
      for (final MapEntry(:key, :value) in w.values.entries)
        key: toSqlValue(value),
      'id': id,
      'created_at': now,
      'created_by': userId,
      'updated_at': now,
      'updated_by': userId,
      'version': 1,
      'deleted_at': null,
    };
    final farmId = _farmOf(w.table, row);
    final cols = row.keys.toList();
    await db.customStatement(
      'INSERT INTO ${w.table} (${cols.map((c) => '"$c"').join(', ')}) '
      'VALUES (${List.filled(cols.length, '?').join(', ')})',
      [for (final c in cols) row[c]],
    );
    await _enqueue(w.table, id, farmId, 0, now);
    // the row as stored, defaults included; the event row already carries
    // the id, farm, times, author and version
    final stored = await _current(w.table, id);
    final shown = {
      for (final MapEntry(:key, :value) in stored.entries)
        if (!commonColumns.contains(key) && key != _farmColumn[w.table])
          key: value,
    };
    return _log(w.table, id, farmId, 'create', null, shown, w, now);
  }

  Future<String?> _update(
    String table,
    String id,
    Map<String, Object?> changes,
    String action,
    Object meta,
  ) async {
    final columns = _columnsOf(table);
    final current = await _current(table, id);
    if (action == 'update' && current['deleted_at'] != null) {
      // another phone deleted it; saving onto a hidden row would lose the edit
      throw StateError('$table row $id is deleted');
    }
    final farmColumn = _farmColumn[table];
    final changed = <String, Object?>{};
    for (final MapEntry(:key, :value) in changes.entries) {
      final allowed =
          columns.containsKey(key) &&
          key != 'id' &&
          key != farmColumn &&
          (!_managed.contains(key) ||
              (action == 'restore' && key == 'deleted_at'));
      if (!allowed) {
        throw ArgumentError.value(key, 'changes', 'not settable on $table');
      }
      _checkKind(columns[key]!, value, table);
      final v = toSqlValue(value);
      final same = key == 'deleted_at'
          ? (current[key] == null) == (v == null)
          : current[key] == v;
      if (!same) changed[key] = v;
    }
    if (changed.isEmpty) return null;
    final now = _clock().millisecondsSinceEpoch;
    final version = current['version']! as int;
    final set = {
      ...changed,
      'updated_at': now,
      'updated_by': userId,
      'version': version + 1,
    };
    await db.customStatement(
      'UPDATE $table SET ${set.keys.map((c) => '"$c" = ?').join(', ')} '
      'WHERE id = ?',
      [...set.values, id],
    );
    final farmId = _farmOf(table, current);
    await _enqueue(table, id, farmId, version, now);
    return _log(
      table,
      id,
      farmId,
      action,
      {for (final k in changed.keys) k: current[k]},
      changed,
      meta,
      now,
    );
  }

  Future<String?> _delete(DeleteRow w) async {
    _columnsOf(w.table);
    final current = await _current(w.table, w.id);
    if (current['deleted_at'] != null) return null;
    final now = _clock().millisecondsSinceEpoch;
    final version = current['version']! as int;
    await db.customStatement(
      'UPDATE ${w.table} SET deleted_at = ?, updated_at = ?, updated_by = ?, '
      'version = ? WHERE id = ?',
      [now, now, userId, version + 1, w.id],
    );
    final farmId = _farmOf(w.table, current);
    await _enqueue(w.table, w.id, farmId, version, now);
    return _log(w.table, w.id, farmId, 'delete', current, null, w, now);
  }

  Future<String> _log(
    String table,
    String id,
    String farmId,
    String action,
    Map<String, Object?>? oldValues,
    Map<String, Object?>? newValues,
    Object meta,
    int now,
  ) async {
    final (occurredOn, summary) = switch (meta) {
      RowWrite w => (_dayOf(w.occurredOn) ?? _today(), w.summary),
      _Meta m => (m.occurredOn, m.summary),
      _ => throw StateError('meta'),
    };
    final eventId = newId();
    await db.customStatement(
      'INSERT INTO event_log (id, farm_id, entity, entity_id, "action", '
      'summary, old_values, new_values, occurred_on, created_at, created_by) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        eventId,
        farmId,
        table,
        id,
        action,
        jsonEncode(summary),
        oldValues == null ? null : jsonEncode(oldValues),
        newValues == null ? null : jsonEncode(newValues),
        occurredOn,
        now,
        userId,
      ],
    );
    await _enqueue('event_log', eventId, farmId, 0, now);
    return eventId;
  }

  /// One pending upload per row: a later edit folds into it and keeps its
  /// base version (the version the server last had). While an earlier upload
  /// of the row is in flight or was refused, the server never took the
  /// phone's newer versions, so the new upload keeps that upload's base.
  Future<void> _enqueue(
    String table,
    String id,
    String farmId,
    int baseVersion,
    int now,
  ) => db.customStatement(
    'INSERT INTO outbox (farm_id, entity, row_id, base_version, status, '
    'attempts, created_at, updated_at) VALUES (?, ?, ?, COALESCE((SELECT '
    'MIN(base_version) FROM outbox WHERE entity = ? AND row_id = ?), ?), '
    "'pending', 0, ?, ?) "
    "ON CONFLICT (entity, row_id) WHERE status = 'pending' "
    'DO UPDATE SET updated_at = excluded.updated_at',
    [farmId, table, id, table, id, baseVersion, now, now],
  );

  Future<Map<String, Object?>> _current(String table, String id) async {
    final row = await db
        .customSelect(
          'SELECT * FROM $table WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull();
    if (row == null) throw StateError('no $table row $id');
    return row.data;
  }

  Map<String, GeneratedColumn<Object>> _columnsOf(String table) {
    if (!_farmColumn.containsKey(table) || _notWritable.contains(table)) {
      throw ArgumentError.value(table, 'table', 'not written through history');
    }
    final info = db.allTables.firstWhere((t) => t.actualTableName == table);
    return {for (final c in info.$columns) c.name: c};
  }

  static final _day = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Refuses a value of the wrong kind for its column, which would otherwise
  /// be stored, never match on the next save, or never sync: text for text
  /// (or a map or list for JSON), whole numbers or times for integers, true
  /// or false for booleans, and 'YYYY-MM-DD' for days of work.
  static void _checkKind(GeneratedColumn<Object> c, Object? v, String table) {
    if (v == null) return;
    final ok = switch (c.type) {
      DriftSqlType.string =>
        v is Map ||
            v is List ||
            (v is String &&
                (!(c.name.endsWith('_on') || c.name == 'work_date') ||
                    _day.hasMatch(v))),
      DriftSqlType.int || DriftSqlType.bigInt => v is int || v is DateTime,
      // history keeps booleans as 0 and 1
      DriftSqlType.bool => v is bool || v == 0 || v == 1,
      _ => true,
    };
    if (!ok) {
      throw ArgumentError.value(v, c.name, 'not a value for $table.${c.name}');
    }
  }

  String _farmOf(String table, Map<String, Object?> row) {
    final farmId = row[_farmColumn[table]!];
    if (farmId is! String) {
      throw ArgumentError.value(row, 'row', 'has no farm');
    }
    return farmId;
  }

  /// A new time-ordered id, for a repository that must know a row's id
  /// before writing it (a plot under a new farm).
  String newId() => uuidV7(_clock(), _random);

  /// Today on this history's clock, 'YYYY-MM-DD'.
  String today() => _today();

  static String? _dayOf(String? day) {
    if (day != null && !_day.hasMatch(day)) {
      throw ArgumentError.value(day, 'occurredOn', 'not YYYY-MM-DD');
    }
    return day;
  }

  String _today() {
    final d = _clock();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}

class _Meta {
  const _Meta(this.occurredOn, this.summary);
  final String occurredOn;
  final Map<String, Object?> summary;
}
