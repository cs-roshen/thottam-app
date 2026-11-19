import 'dart:convert';

import 'package:thottam/core/db/synced_tables.dart';
import 'package:thottam/core/sync/sync_server.dart';

/// An in-memory server with the conflict rules of `sync_push` in
/// `supabase/migrations/0003_sync.sql`, for the two-device tests. Rows are
/// kept in the server's JSON form.
class FakeServer {
  final tables = <String, Map<String, Map<String, Object?>>>{};
  final _batches = <String, PushResult>{};
  var _seq = 0;

  /// The network is off: every call fails as a lost connection would.
  bool down = false;

  /// Apply the next batch, then lose the reply.
  bool loseNextReply = false;

  /// Tables a user may not write (a permission the server refuses); their
  /// history rows are refused too, as row-level security does.
  final denied = <String, Set<String>>{};

  /// Rows a user may not read, as row-level security would hide them.
  bool Function(String user, String table, Map<String, Object?> row)? hidden;

  /// Fail the next push before applying anything (the request never arrived).
  bool failNextPush = false;

  /// Runs after a push is applied and before its reply reaches the phone,
  /// as a farmer saving while the request is in flight.
  Future<void> Function()? duringPush;

  /// Pushes received, for checking what was sent.
  final pushes = <List<PushRow>>[];

  /// Open invites by the invited user, as `my_invites()` lists them.
  final invites = <String, List<Invite>>{};

  /// Which table each reference column points to, for orphan checks.
  static const parents = {
    'plot_id': 'plots',
    'crop_cycle_id': 'crop_cycles',
    'worker_id': 'workers',
    'group_id': 'labour_groups',
    'harvest_id': 'harvests',
    'expense_id': 'expenses',
    'sale_id': 'sales',
    'lot_id': 'lots',
    'labour_entry_id': 'labour_entries',
  };

  static bool moneyOrQuantity(String field) =>
      field.endsWith('_paise') ||
      const {
        'quantity',
        'piece_quantity',
        'head_count',
        'attendance',
        'hours',
        'overtime_hours',
        'area',
        'area_share',
        'deductions',
        'unit',
        'piece_unit',
        'area_unit',
      }.contains(field);

  /// jsonb equality: maps and lists compare by content.
  static bool same(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

  static const _managed = {
    'id',
    'farm_id',
    'created_at',
    'created_by',
    'updated_at',
    'updated_by',
    'version',
    'deleted_at',
  };

  SyncServer as(String userId) => _Session(this, userId);

  Map<String, Object?>? row(String table, String id) => tables[table]?[id];

  void put(String table, Map<String, Object?> row) {
    (tables[table] ??= {})[row['id']! as String] = {
      ...row,
      'server_seq': ++_seq,
    };
  }

  PushResult _push(
    String user,
    String batchId,
    String farmId,
    List<PushRow> rows,
  ) {
    if (_batches[batchId] case final done?) return done;
    pushes.add(rows);
    final accepted = <RowRef>[];
    final rejected = <Rejection>[];
    final conflicts = <ServerConflict>[];
    final lots = <String>{};

    for (final p in rows) {
      final ref = RowRef(p.entity, p.id);
      final deniedTable = p.entity == 'event_log'
          ? p.row['entity'] as String?
          : p.entity;
      if (denied[user]?.contains(deniedTable) ?? false) {
        rejected.add(Rejection(ref, '42501', 'permission'));
        continue;
      }
      // a reference to a row that does not exist fails that row (foreign key)
      final missing = [
        for (final MapEntry(:key, :value) in parents.entries)
          if (p.row[key] case final String id when row(value, id) == null) key,
      ];
      if (p.entity != 'event_log' && missing.isNotEmpty) {
        rejected.add(Rejection(ref, '23503', 'missing $missing'));
        continue;
      }
      final existing = row(p.entity, p.id);
      // like the server trigger: the signed-in user is stamped, the creator kept
      final up = {
        ...?existing,
        ...p.row,
        if (p.entity != 'event_log') ...{
          'created_by': existing == null ? user : existing['created_by'],
          'updated_by': user,
        },
      };
      if (p.entity == 'sale_lots') lots.add(up['lot_id']! as String);

      if (existing == null) {
        put(p.entity, up);
        if (p.entity == 'farms') {
          // create_farm: the creator's owner membership comes with the farm
          final member = rows
              .where(
                (r) => r.entity == 'farm_members' && r.row['user_id'] == user,
              )
              .firstOrNull;
          if (member != null) put('farm_members', member.row);
        }
        final orphanOf = [
          for (final MapEntry(:key, :value) in parents.entries)
            if (up[key] is String &&
                row(value, up[key]! as String)?['deleted_at'] != null)
              key,
        ];
        if (orphanOf.isNotEmpty) {
          conflicts.add(
            ServerConflict(ref, 'orphan', orphanOf, row(p.entity, p.id)),
          );
        } else {
          accepted.add(ref);
        }
        continue;
      }
      if (p.entity == 'event_log') {
        accepted.add(ref);
        continue;
      }
      final serverVersion = existing['version']! as int;
      if (p.baseVersion > 0 && serverVersion == p.baseVersion) {
        put(p.entity, up);
        accepted.add(ref);
        continue;
      }

      // Another phone changed the row since this one's base version, or made
      // the same row (a shared id) while this one was offline.
      final changes = p.baseVersion == 0
          ? {
              for (final k in p.row.keys)
                if (!_managed.contains(k)) k: null,
            }
          : p.changes;
      final iDelete =
          changes.containsKey('deleted_at') &&
          up['deleted_at'] != null &&
          changes['deleted_at'] == null;
      final theyDeleted = existing['deleted_at'] != null;
      final edits = {...changes}..remove('deleted_at');
      if (iDelete != theyDeleted && (iDelete || edits.isNotEmpty)) {
        conflicts.add(
          ServerConflict(ref, 'delete_edit', const ['deleted_at'], existing),
        );
        continue;
      }
      if (iDelete) {
        accepted.add(ref);
        continue;
      }
      final merged = {...existing};
      final clash = <String>[];
      var took = false;
      for (final MapEntry(key: f, value: base) in changes.entries) {
        if (const {
              'id',
              'created_at',
              'created_by',
              'updated_at',
            }.contains(f) ||
            f == 'version' ||
            f == 'updated_by' ||
            f == 'farm_id') {
          continue;
        }
        // changed and changed back on the phone: not a change at all
        if (p.baseVersion > 0 && same(up[f], base)) continue;
        if (same(existing[f], up[f])) {
          // the same value on both phones is not a conflict
        } else if (same(existing[f], base)) {
          merged[f] = up[f];
          took = true;
        } else if (moneyOrQuantity(f)) {
          clash.add(f);
        } else {
          merged[f] = up[f]; // the upload that reaches the server later wins
          took = true;
        }
      }
      if (took) {
        merged['version'] =
            (serverVersion > (up['version']! as int)
                ? serverVersion
                : up['version']! as int) +
            1;
        merged['updated_at'] = up['updated_at'];
        merged['updated_by'] = user;
        put(p.entity, merged);
      }
      if (clash.isEmpty) {
        accepted.add(ref);
      } else {
        conflicts.add(
          ServerConflict(ref, 'same_field', clash, row(p.entity, p.id)),
        );
      }
    }

    // Two phones selling from one lot while offline can sell more than it holds.
    for (final lot in lots) {
      final sold =
          (tables['sale_lots']?.values ?? const <Map<String, Object?>>[])
              .where((s) => s['lot_id'] == lot && s['deleted_at'] == null)
              .fold<int>(0, (sum, s) => sum + (s['quantity']! as int));
      final quantity = row('lots', lot)?['quantity'] as int? ?? 0;
      if (sold <= quantity) continue;
      for (final p in rows.where(
        (r) => r.entity == 'sale_lots' && r.row['lot_id'] == lot,
      )) {
        final ref = RowRef(p.entity, p.id);
        if (!accepted.remove(ref)) continue;
        conflicts.add(
          ServerConflict(ref, 'oversell', const [
            'quantity',
          ], row(p.entity, p.id)),
        );
      }
    }

    final result = PushResult(
      accepted: accepted,
      rejected: rejected,
      conflicts: conflicts,
    );
    _batches[batchId] = result;
    return result;
  }

  List<Map<String, Object?>> _pull(
    String user,
    String table, {
    required int after,
    required int limit,
    String? farmId,
    String? userId,
  }) {
    final farmColumn = {for (final (t, c) in syncedTables) t: c}[table];
    final rows =
        (tables[table]?.values ?? const <Map<String, Object?>>[])
            .where((r) => (r['server_seq']! as int) > after)
            .where((r) => hidden?.call(user, table, r) != true)
            .where(
              (r) => userId != null
                  ? r['user_id'] == userId
                  : farmColumn == null || r[farmColumn] == farmId,
            )
            .toList()
          ..sort(
            (a, b) =>
                (a['server_seq']! as int).compareTo(b['server_seq']! as int),
          );
    return rows.take(limit).toList();
  }
}

class _Session implements SyncServer {
  _Session(this.server, this.user);
  final FakeServer server;
  final String user;

  void _check() {
    if (server.down) throw const SyncUnavailable('offline');
  }

  @override
  Future<PushResult> push(
    String batchId,
    String farmId,
    List<PushRow> rows, {
    required String userId,
  }) async {
    _check();
    if (userId != user) throw const SyncUnavailable('signed in as another');
    if (server.failNextPush) {
      server.failNextPush = false;
      throw const SyncUnavailable('request lost');
    }
    final result = server._push(user, batchId, farmId, rows);
    if (server.duringPush case final during?) {
      server.duringPush = null;
      await during();
    }
    if (server.loseNextReply) {
      server.loseNextReply = false;
      throw const SyncUnavailable('reply lost');
    }
    return result;
  }

  @override
  Future<List<Map<String, Object?>>> pull(
    String table, {
    required int after,
    required int limit,
    String? farmId,
    String? userId,
  }) async {
    _check();
    return server._pull(
      user,
      table,
      after: after,
      limit: limit,
      farmId: farmId,
      userId: userId,
    );
  }

  // Like accept_invite and decline_invite: the invite leaves the list, and
  // only Join adds a membership.
  @override
  Future<List<Invite>> invites() async {
    _check();
    return [...?server.invites[user]];
  }

  Invite? _take(String inviteId) {
    final mine = server.invites[user] ?? [];
    final invite = mine.where((i) => i.id == inviteId).firstOrNull;
    mine.remove(invite);
    return invite;
  }

  @override
  Future<String?> acceptInvite(String inviteId) async {
    _check();
    final invite = _take(inviteId);
    if (invite == null) return null;
    server.put('farm_members', {
      'id': 'm-$inviteId',
      'farm_id': invite.farmId,
      'user_id': user,
      'role': invite.role,
      'permissions': <String, Object?>{},
      'created_at': '2026-11-19T00:00:00Z',
      'updated_at': '2026-11-19T00:00:00Z',
      'version': 1,
      'deleted_at': null,
    });
    return invite.farmId;
  }

  @override
  Future<String?> declineInvite(String inviteId) async {
    _check();
    return _take(inviteId)?.farmId;
  }
}
