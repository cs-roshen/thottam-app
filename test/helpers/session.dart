import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:thottam/app/session.dart';
import 'package:thottam/app/settings.dart';
import 'package:thottam/core/access/access.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/history/write_with_history.dart';
import 'package:thottam/core/prefs/device_store.dart';
import 'package:thottam/core/sync/bundled_templates.dart';
import 'package:thottam/core/sync/sync_server.dart';
import 'package:thottam/features/onboarding/data/onboarding_repository.dart';
import 'package:thottam/features/onboarding/domain/setup.dart';

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
  Access? access = const Access('owner'),
}) => [
  // the role on the open farm; null reads the membership from the database
  if (access != null)
    accessProvider.overrideWith((ref) => Stream.value(access)),
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

/// A phone where [testUser] set up "Riverside" with [crops] and opened it, as the
/// role [role]; [seed] adds rows before the app starts.
Future<(AppDatabase, String)> farmDatabase({
  List<String> crops = const [],
  String role = 'owner',
  Future<void> Function(AppDatabase db, History history, String farm)? seed,
}) async {
  final db = memoryDatabase();
  // a ticking clock and a fixed seed, so rows come out in one order each run
  var now = DateTime(2026, 11, 19, 9);
  final history = History(
    db,
    userId: testUser,
    clock: () => now = now.add(const Duration(milliseconds: 10)),
    random: Random(1),
  );
  await installBundledTemplates(
    db,
    File(bundledTemplatesAsset).readAsStringSync(),
  );
  final repo = OnboardingRepository(db, history);
  final ids = {for (final c in await repo.standardCrops()) c.nameEn: c.id};
  final farm = await repo.createFarm(
    testUser,
    SetupInput(
      name: 'Ravi',
      farmName: 'Riverside',
      area: 50000,
      areaUnit: 'cent',
      cropIds: [for (final c in crops) ids[c]!],
    ),
  );
  if (role != 'owner') {
    await db.customStatement(
      'UPDATE farm_members SET role = ? WHERE user_id = ?',
      [role, testUser],
    );
  }
  await seed?.call(db, history, farm);
  return (db, farm);
}

/// The overrides for an app opened on [farmDatabase]'s farm, in English
/// unless [prefs] say otherwise.
List<Override> farmOverrides(
  AppDatabase db,
  String farm, [
  Map<String, Object?> prefs = const {'settings.language': 'english'},
]) => [
  ...appOverrides(
    store: readyStore({
      'session.user.$testUser': {'first_synced': true, 'farm': farm},
      ...prefs,
    }),
    database: () => db,
    access: null,
  ),
  clockProvider.overrideWithValue(() => DateTime(2026, 11, 19, 9)),
];
