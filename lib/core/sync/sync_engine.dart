import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../db/database.dart';
import '../db/synced_tables.dart';
import '../ids/uuid_v7.dart';
import 'row_codec.dart';
import 'sync_server.dart';
import 'sync_status.dart';

export 'sync_status.dart';

/// Uploads the outbox and pulls changes by cursor (implementation plan
/// section 13). Runs in the background only; screens never wait for it.
class SyncEngine {
  SyncEngine(
    this.db,
    this.server, {
    required this.userId,
    DateTime Function()? clock,
    Random? random,
    this.batchRows = 200,
    this.batchBytes = 256 * 1024,
    this.pageSize = 500,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final AppDatabase db;
  final SyncServer server;
  final String userId;
  final int batchRows;
  final int batchBytes;
  final int pageSize;
  final DateTime Function() _clock;
  final Random _random;

  static const masterFarm = '';
  static const myMemberships = '@me';
  static final _order = {for (final (i, (t, _)) in syncedTables.indexed) t: i};

  /// One full round: upload, then pull. Throws [SyncUnavailable] when the
  /// server cannot be reached; whatever was done before stays done. Invites
  /// are never accepted here: the person chooses (`SyncServer.acceptInvite`).
  Future<void> sync() async {
    await upload();
    await pull();
    await db.customStatement(
      'INSERT INTO app_settings ("key", value) VALUES (?, ?) '
      'ON CONFLICT ("key") DO UPDATE SET value = excluded.value',
      ['sync.last_synced_at', '${_clock().millisecondsSinceEpoch}'],
    );
    _notify({'app_settings'});
  }

  // ---------- upload ----------

  Future<void> upload() async {
    // A batch cut off by a lost connection goes again first, with its id, so
    // the server applies it once.
    final sending = await _outbox("status = 'sending'")
      ..sort(_byDependency);
    final byBatch = <String, List<Map<String, Object?>>>{};
    for (final o in sending) {
      (byBatch[o['batch_id']! as String] ??= []).add(o);
    }
    for (final MapEntry(key: batchId, value: rows) in byBatch.entries) {
      await _send(batchId, rows);
    }

    final pending = await _outbox("status = 'pending'")
      ..sort(_byDependency);
    var i = 0;
    while (i < pending.length) {
      final farm = pending[i]['farm_id'];
      final batch = <Map<String, Object?>>[];
      var bytes = 0;
      while (i < pending.length &&
          pending[i]['farm_id'] == farm &&
          batch.length < batchRows &&
          (batch.isEmpty || bytes < batchBytes)) {
        final o = pending[i++];
        bytes += await _rowBytes(o);
        batch.add(o);
      }
      final batchId = uuidV7(_clock(), _random);
      await db.transaction(() async {
        for (final o in batch) {
          await db.customStatement(
            "UPDATE outbox SET status = 'sending', batch_id = ? WHERE id = ?",
            [batchId, o['id']],
          );
        }
      });
      await _send(batchId, [
        for (final o in batch) {...o, 'batch_id': batchId},
      ]);
    }
  }

  static int _byDependency(Map<String, Object?> a, Map<String, Object?> b) {
    final f = (a['farm_id']! as String).compareTo(b['farm_id']! as String);
    if (f != 0) return f;
    final t = _order[a['entity']]!.compareTo(_order[b['entity']]!);
    return t != 0 ? t : (a['id']! as int).compareTo(b['id']! as int);
  }

  Future<void> _send(String batchId, List<Map<String, Object?>> outbox) async {
    final farmId = outbox.first['farm_id']! as String;
    final rows = <PushRow>[];
    final mine = <RowRef, Map<String, Object?>>{};
    for (final o in outbox) {
      final entity = o['entity']! as String;
      final id = o['row_id']! as String;
      final local = await _row(entity, id);
      if (local == null) continue;
      mine[RowRef(entity, id)] = local;
      final base = o['base_version']! as int;
      rows.add(
        PushRow(
          entity: entity,
          row: toServerRow(_table(entity), local),
          baseVersion: base,
          changes: base == 0
              ? const {}
              : await _changes(entity, id, o['id']! as int),
        ),
      );
    }

    final PushResult result;
    try {
      result = await server.push(batchId, farmId, rows, userId: userId);
    } on SyncUnavailable {
      await db.customStatement(
        'UPDATE outbox SET attempts = attempts + 1 WHERE batch_id = ?',
        [batchId],
      );
      rethrow;
    } on Object catch (e) {
      // The server will never take this batch as it is (a malformed row, a
      // limit). It leaves the queue and is shown, so it cannot stop every
      // later upload and pull.
      await db.customStatement(
        "UPDATE outbox SET status = 'rejected', last_error = ?, updated_at = ? "
        'WHERE batch_id = ?',
        ['$e', _clock().millisecondsSinceEpoch, batchId],
      );
      _notify({'outbox'});
      return;
    }

    final now = _clock().millisecondsSinceEpoch;
    final touched = <String>{'outbox', 'conflicts'};
    await db.transaction(() async {
      final settled = <RowRef>{};
      for (final r in result.rejected) {
        settled.add(r.ref);
        await db.customStatement(
          "UPDATE outbox SET status = 'rejected', last_error = ?, "
          'updated_at = ? WHERE batch_id = ? AND entity = ? AND row_id = ?',
          ['${r.code} ${r.message}', now, batchId, r.ref.entity, r.ref.id],
        );
        // The phone keeps a value the server will never take, and pulls
        // skipped this row while it waited. Read the table again, so the
        // server's row comes back (history is insert-only: nothing to undo).
        if (r.ref.entity != 'event_log') {
          await db.customStatement(
            'UPDATE sync_state SET "cursor" = 0 WHERE farm_id = ? AND entity = ?',
            [farmId, r.ref.entity],
          );
        }
      }
      for (final c in result.conflicts) {
        settled.add(c.ref);
        final table = _table(c.ref.entity);
        await db.customStatement(
          'INSERT INTO conflicts (id, farm_id, entity, row_id, kind, fields, '
          'mine, theirs, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            uuidV7(_clock(), _random),
            farmId,
            c.ref.entity,
            c.ref.id,
            c.kind,
            jsonEncode(c.fields),
            jsonEncode(mine[c.ref]),
            c.theirs == null ? null : jsonEncode(toLocalRow(table, c.theirs!)),
            now,
          ],
        );
        // The phone shows the server's row until the farmer chooses; their
        // own version waits in the conflict. Not when the farmer changed the
        // row again while this batch was out: that newer change is pending
        // and merges on its own. And never for orphan or oversell, where
        // "theirs" is this phone's own row.
        final waiting = await db
            .customSelect(
              'SELECT 1 FROM outbox WHERE entity = ? AND row_id = ? '
              "AND status = 'pending' LIMIT 1",
              variables: [
                Variable.withString(c.ref.entity),
                Variable.withString(c.ref.id),
              ],
            )
            .getSingleOrNull();
        if (c.theirs != null &&
            waiting == null &&
            (c.kind == 'same_field' || c.kind == 'delete_edit')) {
          await _upsert(c.ref.entity, toLocalRow(table, c.theirs!));
          touched.add(c.ref.entity);
        }
      }
      // Everything else in the batch was taken as sent.
      await db.customStatement(
        "DELETE FROM outbox WHERE batch_id = ? AND status = 'sending'",
        [batchId],
      );
    });
    _notify(touched);
  }

  /// The value each field had at the base version: the old values of this
  /// row's history queued after the row's upload, earliest first.
  Future<Map<String, Object?>> _changes(
    String entity,
    String id,
    int outboxId,
  ) async {
    // Only this phone's own history not yet uploaded (history pulled from
    // other phones describes their changes), and only what was queued after
    // this upload of the row, by queue order rather than by the clock, which
    // can jump.
    final events = await db
        .customSelect(
          'SELECT e.old_values FROM event_log e JOIN outbox o '
          "ON o.entity = 'event_log' AND o.row_id = e.id "
          "AND o.status IN ('pending', 'sending') "
          'WHERE e.entity = ? AND e.entity_id = ? AND o.id > ? '
          'AND e.old_values IS NOT NULL ORDER BY o.id',
          variables: [
            Variable.withString(entity),
            Variable.withString(id),
            Variable.withInt(outboxId),
          ],
        )
        .get();
    final bools = {
      for (final c in _table(entity).$columns)
        if (c.type == DriftSqlType.bool) c.name,
    };
    final base = <String, Object?>{};
    for (final e in events) {
      final old = jsonDecode(e.read<String>('old_values')) as Map;
      for (final MapEntry(:key, :value) in old.entries) {
        final k = key as String;
        if (commonColumns.contains(k) && k != 'deleted_at') continue;
        base.putIfAbsent(
          k,
          () => toServerValue(k, value, isBool: bools.contains(k)),
        );
      }
    }
    return base;
  }

  // ---------- pull ----------

  Future<void> pull() async {
    // This person's memberships span farms, and server_seq is in commit order
    // only within one farm (each farm's writes take that farm's lock), so a
    // cursor here could step over a late commit. They are a handful of rows:
    // read them all every time.
    final before = await _myMemberships();
    await _pullTable('farm_members', myMemberships, userId: userId, all: true);
    await _followMemberships(before, await _myMemberships());
    final farms = await db
        .customSelect(
          'SELECT farm_id FROM farm_members WHERE user_id = ? '
          'AND deleted_at IS NULL',
          variables: [Variable.withString(userId)],
        )
        .map((r) => r.read<String>('farm_id'))
        .get();
    for (final t in const ['template_items', 'crops', 'market_prices']) {
      await _pullTable(t, masterFarm);
    }
    for (final farm in farms) {
      for (final (t, _) in syncedTables) {
        if (t == 'template_items') continue;
        await _pullTable(t, farm, farmId: farm);
      }
    }
  }

  /// This person's memberships: farm to role, permissions and whether active.
  Future<Map<String, (String, String, bool)>> _myMemberships() async => {
    for (final r
        in await db
            .customSelect(
              'SELECT farm_id, role, permissions, deleted_at FROM farm_members '
              'WHERE user_id = ?',
              variables: [Variable.withString(userId)],
            )
            .get())
      r.read<String>('farm_id'): (
        r.read<String>('role'),
        r.read<String>('permissions'),
        r.readNullable<int>('deleted_at') == null,
      ),
  };

  /// A removed member's phone drops the farm; a member whose role or
  /// permissions changed pulls the farm again from the start, because rows
  /// they could not see before (money history, other members) lie behind
  /// their cursors.
  // shortcut: a narrower role keeps what it already pulled until removal;
  // dropping per access class waits for the role checks (D3).
  Future<void> _followMemberships(
    Map<String, (String, String, bool)> before,
    Map<String, (String, String, bool)> after,
  ) async {
    for (final MapEntry(key: farm, value: was) in before.entries) {
      final now = after[farm];
      if (!was.$3) continue;
      if (now == null || !now.$3) {
        await _dropFarm(farm);
      } else if (now.$1 != was.$1 || now.$2 != was.$2) {
        await db.customStatement('DELETE FROM sync_state WHERE farm_id = ?', [
          farm,
        ]);
      }
    }
  }

  /// Removes a farm this person no longer belongs to from the phone. Only
  /// this phone's copy goes; the farm stays whole on the server.
  Future<void> _dropFarm(String farm) async {
    await db.transaction(() async {
      for (final (table, column) in syncedTables) {
        if (column == null) continue;
        await db.customStatement('DELETE FROM $table WHERE "$column" = ?', [
          farm,
        ]);
      }
      for (final table in const [
        'outbox',
        'conflicts',
        'photo_uploads',
        'sync_state',
      ]) {
        await db.customStatement('DELETE FROM $table WHERE farm_id = ?', [
          farm,
        ]);
      }
    });
    _notify({for (final (t, _) in syncedTables) t, 'outbox', 'conflicts'});
  }

  Future<void> _pullTable(
    String table,
    String key, {
    String? farmId,
    String? userId,
    bool all = false,
  }) async {
    final info = _table(table);
    var cursor = all
        ? 0
        : (await db
                      .customSelect(
                        'SELECT "cursor" FROM sync_state WHERE farm_id = ? '
                        'AND entity = ?',
                        variables: [
                          Variable.withString(key),
                          Variable.withString(table),
                        ],
                      )
                      .getSingleOrNull())
                  ?.read<int>('cursor') ??
              0;
    while (true) {
      final rows = await server.pull(
        table,
        after: cursor,
        limit: pageSize,
        farmId: farmId,
        userId: userId,
      );
      if (rows.isEmpty) return;
      final last = (rows.last['server_seq']! as num).toInt();
      await db.transaction(() async {
        for (final r in rows) {
          final local = toLocalRow(info, r);
          // A row changed here and not yet uploaded keeps this phone's
          // version; the server merges it when it arrives.
          final waiting = await db
              .customSelect(
                'SELECT 1 FROM outbox WHERE entity = ? AND row_id = ? '
                "AND status IN ('pending', 'sending') LIMIT 1",
                variables: [
                  Variable.withString(table),
                  Variable.withString(local['id']! as String),
                ],
              )
              .getSingleOrNull();
          if (waiting == null) await _upsert(table, local);
        }
        await db.customStatement(
          'INSERT INTO sync_state (farm_id, entity, "cursor", pulled_at) '
          'VALUES (?, ?, ?, ?) ON CONFLICT (farm_id, entity) '
          'DO UPDATE SET "cursor" = excluded."cursor", '
          'pulled_at = excluded.pulled_at',
          [key, table, last, _clock().millisecondsSinceEpoch],
        );
      });
      _notify({table});
      cursor = last;
      if (rows.length < pageSize) return;
    }
  }

  // ---------- status ----------

  /// For the small sync line in Settings: last synced time, items waiting,
  /// items the server refused, and changes waiting for the farmer's choice.
  Stream<SyncStatus> watchStatus() => db
      .customSelect(
        'SELECT '
        "(SELECT COUNT(*) FROM outbox WHERE status IN ('pending', 'sending') "
        "AND entity <> 'event_log') AS waiting, "
        "(SELECT COUNT(*) FROM outbox WHERE status = 'rejected' "
        "AND entity <> 'event_log') AS rejected, "
        '(SELECT COUNT(*) FROM conflicts WHERE resolved_at IS NULL) AS open, '
        "(SELECT value FROM app_settings WHERE \"key\" = 'sync.last_synced_at') "
        'AS last',
        readsFrom: {db.outbox, db.conflicts, db.appSettings},
      )
      .watchSingle()
      .map(
        (r) => SyncStatus(
          waiting: r.read<int>('waiting'),
          rejected: r.read<int>('rejected'),
          conflicts: r.read<int>('open'),
          lastSyncedAt: switch (r.readNullable<String>('last')) {
            final v? => DateTime.fromMillisecondsSinceEpoch(int.parse(v)),
            null => null,
          },
        ),
      );

  // ---------- helpers ----------

  Future<List<Map<String, Object?>>> _outbox(String where) async => [
    for (final r
        in await db
            .customSelect('SELECT * FROM outbox WHERE $where ORDER BY id')
            .get())
      r.data,
  ];

  Future<Map<String, Object?>?> _row(String table, String id) async =>
      (await db
              .customSelect(
                'SELECT * FROM $table WHERE id = ?',
                variables: [Variable.withString(id)],
              )
              .getSingleOrNull())
          ?.data;

  Future<int> _rowBytes(Map<String, Object?> o) async {
    final row = await _row(o['entity']! as String, o['row_id']! as String);
    return row == null ? 0 : jsonEncode(row).length;
  }

  Future<void> _upsert(String table, Map<String, Object?> row) {
    final cols = row.keys.toList();
    final quoted = cols.map((c) => '"$c"');
    final conflict = table == 'event_log'
        ? 'DO NOTHING'
        : 'DO UPDATE SET ${cols.where((c) => c != 'id').map((c) => '"$c" = excluded."$c"').join(', ')}';
    return db.customStatement(
      'INSERT INTO $table (${quoted.join(', ')}) '
      'VALUES (${List.filled(cols.length, '?').join(', ')}) '
      'ON CONFLICT (id) $conflict',
      [for (final c in cols) row[c]],
    );
  }

  TableInfo<Table, Object?> _table(String name) =>
      db.allTables.firstWhere((t) => t.actualTableName == name);

  void _notify(Set<String> tables) => db.notifyUpdates({
    for (final t in db.allTables)
      if (tables.contains(t.actualTableName)) TableUpdate.onTable(t),
  });
}

/// How long to wait before retry number [attempt] (0 first): doubling from
/// two seconds, capped at ten minutes, with random jitter of ±50 %.
Duration retryDelay(int attempt, Random random) {
  final base = min(2000 * pow(2, min(attempt, 20)).toInt(), 600000);
  return Duration(milliseconds: (base * (0.5 + random.nextDouble())).round());
}
