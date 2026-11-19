import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/access/access.dart';
import '../core/auth/account.dart';
import '../core/db/database.dart';
import '../core/db/member_store.dart';
import '../core/db/override_store.dart';
import '../core/history/write_with_history.dart';
import '../core/overrides/overrides.dart';
import '../core/prefs/device_store.dart';
import '../core/sync/bundled_templates.dart';
import '../core/sync/sync_engine.dart';
import '../core/sync/sync_server.dart';
import '../core/units/units.dart';
import 'settings.dart';

/// Who is signed in, whether their first sync is done, and which farm they
/// have open. Kept in the phone's preferences so the app reopens where it was.
@immutable
class Session {
  const Session({this.account, this.firstSynced = false, this.farmId});

  final Account? account;

  /// The first sign-in on this phone pulled whatever the account already
  /// has (screens.md 1); until then set-up must not run, or a new phone
  /// would make a second farm.
  final bool firstSynced;
  final String? farmId;
}

/// Where the app must be: the order of the sign-in steps (screens.md 1, 17).
enum Gate { signedOut, firstSync, invites, setup, ready }

Gate gateOf(Session s, List<Invite> invites) => switch (s) {
  Session(account: null) => Gate.signedOut,
  Session(firstSynced: false) => Gate.firstSync,
  _ when invites.isNotEmpty => Gate.invites,
  Session(farmId: null) => Gate.setup,
  _ => Gate.ready,
};

class SessionNotifier extends Notifier<Session> {
  static const _account = 'session.account';
  static String _user(String id) => 'session.user.$id';

  DeviceStore get _store => ref.read(deviceStoreProvider);

  @override
  Session build() {
    final store = ref.watch(deviceStoreProvider);
    final account = store.get(_account);
    return account is Map
        ? _load(Account.fromJson(account.cast<String, Object?>()), store)
        : const Session();
  }

  Session _load(Account account, DeviceStore store) {
    final user = (store.get(_user(account.id)) as Map?) ?? const {};
    return Session(
      account: account,
      firstSynced: user['first_synced'] == true,
      farmId: user['farm'] as String?,
    );
  }

  Future<void> _save({bool? firstSynced, String? farmId}) async {
    final s = state;
    await _store.set(_user(s.account!.id), {
      'first_synced': firstSynced ?? s.firstSynced,
      'farm': farmId ?? s.farmId,
    });
    state = Session(
      account: s.account,
      firstSynced: firstSynced ?? s.firstSynced,
      farmId: farmId ?? s.farmId,
    );
  }

  Future<void> signIn(Account account) async {
    await _store.set(_account, account.toJson());
    state = _load(account, _store);
  }

  /// The first sync is done; [farmId] is the farm to open, if any.
  Future<void> firstSyncDone(String? farmId) =>
      _save(firstSynced: true, farmId: farmId);

  Future<void> openFarm(String farmId) => _save(farmId: farmId);

  /// The name and phone from set-up step 1.
  // shortcut: kept on this phone only; B6 saves them to the server profile.
  Future<void> updateProfile(String name, String? phone) async {
    final a = state.account!;
    final account = Account(id: a.id, email: a.email, name: name, phone: phone);
    await _store.set(_account, account.toJson());
    state = Session(
      account: account,
      firstSynced: state.firstSynced,
      farmId: state.farmId,
    );
  }

  Future<void> signOut() async {
    await _store.set(_account, null);
    state = const Session();
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, Session>(
  SessionNotifier.new,
);

final authGatewayProvider = Provider<AuthGateway>(
  (ref) => TestAccountAuth(ref.watch(deviceStoreProvider)),
);

/// The signed-in user's id; only read below the sign-in gate.
final userIdProvider = Provider<String>(
  (ref) => ref.watch(sessionProvider.select((s) => s.account?.id))!,
);

/// The open farm's id; only read past set-up.
final farmIdProvider = Provider<String>(
  (ref) => ref.watch(sessionProvider.select((s) => s.farmId))!,
);

/// The signed-in user's own database, closed when they sign out.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = openAppDatabase(ref.watch(userIdProvider));
  ref.onDispose(db.close);
  return db;
});

/// The bundled templates are on the phone (first run, offline set-up).
final templatesReadyProvider = FutureProvider<void>((ref) async {
  final db = ref.watch(databaseProvider);
  await installBundledTemplates(
    db,
    await rootBundle.loadString(bundledTemplatesAsset),
  );
});

/// The one clock: tests replace it so "today" stays put.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final historyProvider = Provider<History>(
  (ref) => History(
    ref.watch(databaseProvider),
    userId: ref.watch(userIdProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// The server, once there is a real sign-in to reach it with.
// shortcut: null until B6 signs in through Supabase; set-up then runs with
// no first sync and no invites.
final syncServerProvider = Provider<SyncServer?>((ref) => null);

final syncEngineProvider = Provider<SyncEngine?>((ref) {
  final server = ref.watch(syncServerProvider);
  if (server == null) return null;
  return SyncEngine(
    ref.watch(databaseProvider),
    server,
    userId: ref.watch(userIdProvider),
  );
});

/// Open invites found at sign-in, shown before anything else until each is
/// joined or declined.
class PendingInvites extends Notifier<List<Invite>> {
  @override
  List<Invite> build() {
    ref.watch(sessionProvider.select((s) => s.account?.id));
    return const [];
  }

  void set(List<Invite> invites) => state = invites;

  void remove(String inviteId) => state = [
    for (final i in state)
      if (i.id != inviteId) i,
  ];
}

final pendingInvitesProvider = NotifierProvider<PendingInvites, List<Invite>>(
  PendingInvites.new,
);

final gateProvider = Provider<Gate>(
  (ref) =>
      gateOf(ref.watch(sessionProvider), ref.watch(pendingInvitesProvider)),
);

/// The signed-in person's role and permissions on the open farm; none until
/// their membership is on the phone.
final accessProvider = StreamProvider<Access>(
  (ref) => watchAccess(
    ref.watch(databaseProvider),
    ref.watch(farmIdProvider),
    ref.watch(userIdProvider),
  ),
);

/// The open farm's templates and overrides, resolved from memory.
final overridesProvider = StreamProvider<Overrides>(
  (ref) =>
      watchOverrides(ref.watch(databaseProvider), ref.watch(farmIdProvider)),
);

/// Unit conversions from the templates.
final unitsProvider = Provider<Units?>((ref) {
  final overrides = ref.watch(overridesProvider).value;
  if (overrides == null) return null;
  return Units([
    for (final u in overrides.list('unit', const Scope()))
      Unit.fromTemplate(u.code, {
        for (final MapEntry(:key, :value) in u.data.entries) key: value.value,
      }),
  ]);
});
