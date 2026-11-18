import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/synced_tables.dart';
import 'sync_server.dart';

/// [SyncServer] on Supabase: `sync_push` for uploads, plain reads under
/// row-level security for pulls. Signing in is task B6; until then this is
/// exercised only by the server tests in `supabase/tests/`.
class SupabaseSyncServer implements SyncServer {
  SupabaseSyncServer(this.client);

  final SupabaseClient client;
  static final _farmColumn = {for (final (t, c) in syncedTables) t: c};

  @override
  Future<PushResult> push(String batchId, String farmId, List<PushRow> rows) =>
      _call(() async {
        final result = await client.rpc<Object?>(
          'sync_push',
          params: {
            'p_batch_id': batchId,
            'p_farm_id': farmId,
            'p_rows': [for (final r in rows) r.toJson()],
          },
        );
        return PushResult.fromJson((result! as Map).cast<String, Object?>());
      });

  @override
  Future<List<Map<String, Object?>>> pull(
    String table, {
    required int after,
    required int limit,
    String? farmId,
    String? userId,
  }) => _call(() async {
    var query = client.from(table).select().gt('server_seq', after);
    final farmColumn = _farmColumn[table];
    if (userId != null) {
      query = query.eq('user_id', userId);
    } else if (farmColumn != null) {
      query = farmId == null
          ? query.isFilter(farmColumn, null)
          : query.eq(farmColumn, farmId);
    }
    final rows = await query.order('server_seq').limit(limit);
    return [for (final r in rows) r.cast<String, Object?>()];
  });

  @override
  Future<void> acceptInvites() =>
      _call(() => client.rpc<Object?>('accept_invites'));

  /// Network trouble, a server error or an expired sign-in are worth
  /// retrying later; anything else is a bug and is thrown as it is.
  Future<T> _call<T>(Future<T> Function() body) async {
    try {
      return await body().timeout(const Duration(seconds: 30));
    } on SocketException catch (e) {
      throw SyncUnavailable(e);
    } on TimeoutException catch (e) {
      throw SyncUnavailable(e);
    } on AuthException catch (e) {
      throw SyncUnavailable(e);
    } on PostgrestException catch (e) {
      final status = int.tryParse(e.code ?? '');
      final retry =
          (status != null && status >= 500) ||
          e.code == '42501' ||
          e.code == 'PGRST301'; // an expired token
      if (retry) throw SyncUnavailable(e);
      rethrow;
    } on ClientException catch (e) {
      throw SyncUnavailable(e);
    }
  }
}
