import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:thottam/app/session.dart';
import 'package:thottam/app/settings.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/prefs/device_store.dart';
import 'package:thottam/core/sync/bundled_templates.dart';
import 'package:thottam/core/sync/sync_server.dart';

const testUser = 'user-test';
const testFarm = 'farm-test';

/// A phone where [testUser] is signed in with [testFarm] open.
MemoryDeviceStore readyStore([Map<String, Object?> extra = const {}]) =>
    MemoryDeviceStore({
      'session.account': {'id': testUser, 'name': 'Ravi'},
      'session.user.$testUser': {'first_synced': true, 'farm': testFarm},
      ...extra,
    });

/// Each signed-in user gets a fresh in-memory database, as a new phone would.
AppDatabase memoryDatabase() => AppDatabase(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
);

/// Overrides for the whole app in a test: the phone's preferences, an
/// in-memory database, and optionally a server (as the signed-in user).
List<Override> appOverrides({
  DeviceStore? store,
  AppDatabase Function()? database,
  SyncServer Function(String userId)? server,
}) => [
  deviceStoreProvider.overrideWithValue(store ?? readyStore()),
  databaseProvider.overrideWith((ref) {
    ref.watch(userIdProvider);
    final db = (database ?? memoryDatabase)();
    ref.onDispose(db.close);
    return db;
  }),
  // the bundled templates, read from disk at once rather than through the
  // asset bundle, whose real-time loading fake test time never waits for
  templatesReadyProvider.overrideWith(
    (ref) => installBundledTemplates(
      ref.watch(databaseProvider),
      File(bundledTemplatesAsset).readAsStringSync(),
    ),
  ),
  if (server != null)
    syncServerProvider.overrideWith((ref) => server(ref.watch(userIdProvider))),
];
