/// What the sync engine needs from the server (implementation plan
/// section 13). The Supabase implementation is in `supabase_server.dart`;
/// tests use a fake with the same rules.
library;

/// One row to upload, in the server's JSON form.
class PushRow {
  const PushRow({
    required this.entity,
    required this.row,
    required this.baseVersion,
    this.changes = const {},
  });

  final String entity;
  final Map<String, Object?> row;

  /// The version this phone last received from the server; 0 for a new row.
  final int baseVersion;

  /// For an edited row: each field this phone changed since [baseVersion],
  /// with the value it had then. The server compares these with its own row
  /// to merge different fields and find same-field conflicts.
  final Map<String, Object?> changes;

  String get id => row['id']! as String;

  Map<String, Object?> toJson() => {
    'entity': entity,
    'row': row,
    'base_version': baseVersion,
    'changes': changes,
  };
}

class RowRef {
  const RowRef(this.entity, this.id);
  final String entity;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is RowRef && other.entity == entity && other.id == id;

  @override
  int get hashCode => Object.hash(entity, id);
}

/// A row the server will never accept (permission, validation). It leaves
/// the queue and is shown to the farmer; it never blocks later rows.
class Rejection {
  const Rejection(this.ref, this.code, this.message);
  final RowRef ref;
  final String code;
  final String message;
}

/// A change the server could not merge on its own.
class ServerConflict {
  const ServerConflict(this.ref, this.kind, this.fields, this.theirs);
  final RowRef ref;

  /// same_field (money or quantity), delete_edit, orphan or oversell.
  final String kind;
  final List<String> fields;

  /// The server's row as it stands, in server form.
  final Map<String, Object?>? theirs;
}

class PushResult {
  const PushResult({
    this.accepted = const [],
    this.rejected = const [],
    this.conflicts = const [],
  });

  factory PushResult.fromJson(Map<String, Object?> json) {
    RowRef ref(Map<String, Object?> m) =>
        RowRef(m['entity']! as String, m['id']! as String);
    List<Map<String, Object?>> list(String k) => [
      for (final e in (json[k] as List?) ?? const <Object?>[])
        (e! as Map).cast<String, Object?>(),
    ];
    return PushResult(
      accepted: [for (final m in list('accepted')) ref(m)],
      rejected: [
        for (final m in list('rejected'))
          Rejection(ref(m), m['code']! as String, '${m['message']}'),
      ],
      conflicts: [
        for (final m in list('conflicts'))
          ServerConflict(ref(m), m['kind']! as String, [
            for (final f in (m['fields'] as List?) ?? const []) '$f',
          ], (m['theirs'] as Map?)?.cast<String, Object?>()),
      ],
    );
  }

  final List<RowRef> accepted;
  final List<Rejection> rejected;
  final List<ServerConflict> conflicts;
}

/// The server could not be reached or failed for a reason worth retrying.
class SyncUnavailable implements Exception {
  const SyncUnavailable([this.cause]);
  final Object? cause;

  @override
  String toString() => 'SyncUnavailable($cause)'; // gate: not user-facing
}

abstract interface class SyncServer {
  /// Applies [rows] of one farm in one server transaction and returns what
  /// happened to each. Sending the same [batchId] again changes nothing and
  /// returns the first answer. [userId] is whose queue this is; the server
  /// refuses the batch, as worth retrying, when someone else is signed in.
  Future<PushResult> push(
    String batchId,
    String farmId,
    List<PushRow> rows, {
    required String userId,
  });

  /// Rows of [table] with server_seq above [after], in server_seq order:
  /// those of [farmId], or with [farmId] null the master rows (no farm), or
  /// with [userId] the user's own memberships.
  Future<List<Map<String, Object?>>> pull(
    String table, {
    required int after,
    required int limit,
    String? farmId,
    String? userId,
  });

  /// Turns the signed-in account's open invites into memberships.
  Future<void> acceptInvites();
}
