import 'dart:async';
import 'dart:convert';
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
  Future<PushResult> push(
    String batchId,
    String farmId,
    List<PushRow> rows, {
    required String userId,
  }) {
    final payload = [for (final r in rows) r.toJson()];
    // about 4 KB a second on a slow 2G link, and never less than 30 s
    final seconds = 30 + jsonEncode(payload).length ~/ 4096;
    return _call(() async {
      final result = await client.rpc<Object?>(
        'sync_push',
        params: {
          'p_batch_id': batchId,
          'p_farm_id': farmId,
          'p_rows': payload,
          'p_user': userId,
        },
      );
      return PushResult.fromJson((result! as Map).cast<String, Object?>());
    }, timeout: Duration(seconds: seconds));
  }

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
  /// retrying later; anything else the server will refuse every time, and
  /// is thrown as it is.
  Future<T> _call<T>(
    Future<T> Function() body, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      return await body().timeout(timeout);
    } on IOException catch (e) {
      // sockets, TLS handshakes, HTTP
      throw SyncUnavailable(e);
    } on TimeoutException catch (e) {
      throw SyncUnavailable(e);
    } on AuthException catch (e) {
      throw SyncUnavailable(e);
    } on ClientException catch (e) {
      throw SyncUnavailable(e);
    } on FormatException catch (e) {
      // a web page instead of an answer: a captive portal, an expired pack
      throw SyncUnavailable(e);
    } on PostgrestException catch (e) {
      if (worthRetrying(e.code)) throw SyncUnavailable(e);
      rethrow;
    }
  }

  /// Postgres error classes 08 (connection), 28 (signed in as someone else),
  /// 40 (a lost race), 53 (overload) and 57 (shutting down), an expired
  /// token, or a bare HTTP status of 500 and up.
  static bool worthRetrying(String? code) {
    if (code == null || code == 'PGRST301') return true;
    if (RegExp(r'^(08|28|40|53|57)[0-9A-Z]{3}$').hasMatch(code)) return true;
    final status = int.tryParse(code);
    return code.length == 3 && status != null && status >= 500;
  }
}
