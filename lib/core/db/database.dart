import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:sqlite3/common.dart';

part 'database.g.dart';

/// The schema version this app writes. 2: inputs and stock (phase 7).
const currentSchemaVersion = 2;

/// The phone's database: the source of truth for every screen.
@DriftDatabase(include: {'tables.drift'})
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // Every later version adds a step here and a test in test/core/db/.
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        for (final t in <TableInfo<Table, Object?>>[
          inputItems,
          inputApplications,
          stockMovements,
          inputApplicationCosts,
          soilTests,
        ]) {
          await m.createTable(t);
        }
        for (final i in [
          inputItemsFarm,
          inputApplicationsFarmDay,
          inputApplicationsCycleDay,
          stockMovementsItemDay,
          stockMovementsFarmDay,
          stockMovementsExpense,
          stockMovementsApplication,
          soilTestsPlotDay,
        ]) {
          await m.createIndex(i);
        }
        await m.addColumn(harvests, harvests.waitingOverrideReason);
      }
    },
    beforeOpen: (details) async {
      // An upgraded file is checked before any screen reads it. The copy made
      // before the upgrade goes only on a later open that passes the check.
      final file = (await customSelect(
        'PRAGMA database_list',
      ).get()).first.read<String?>('file');
      final copy = file == null || file.isEmpty
          ? null
          : File('$file$preUpgradeSuffix');
      final hasCopy = copy != null && copy.existsSync();
      if (!details.hadUpgrade && !hasCopy) return;
      final check = await customSelect('PRAGMA integrity_check').get();
      if (check.length != 1 || check.single.data.values.single != 'ok') {
        throw StateError('database integrity check failed after upgrade');
      }
      if (!details.hadUpgrade && hasCopy) copy.deleteSync();
    },
  );
}

/// Opens the signed-in user's database on a background isolate, so queries
/// never block the interface. One file per user: signing in as someone else
/// on the same phone never shows the first user's data.
/// [directory] is for tests; the app uses the documents directory.
AppDatabase openAppDatabase(String userId, {String? directory}) => AppDatabase(
  driftDatabase(
    name: 'thottam_$userId',
    native: DriftNativeOptions(
      setup: applyPragmas,
      databaseDirectory: directory == null ? null : () async => directory,
      tempDirectoryPath: directory == null ? null : () async => directory,
    ),
  ),
);

/// Settings from implementation plan section 12, applied on every open.
void applyPragmas(CommonDatabase db) {
  db
    ..execute(r'PRAGMA journal_mode = WAL')
    ..execute(r'PRAGMA synchronous = NORMAL')
    ..execute(r'PRAGMA foreign_keys = ON')
    ..execute(r'PRAGMA busy_timeout = 5000')
    ..execute(r'PRAGMA cache_size = -8000'); // about 8 MB
  keepCopyBeforeUpgrade(db);
}

/// Suffix of the copy kept while a newer app upgrades the file.
const preUpgradeSuffix = '.pre-upgrade';

/// Implementation plan section 12: before a newer app upgrades the file, copy
/// it beside itself. A copy left by a failed upgrade is never overwritten.
void keepCopyBeforeUpgrade(CommonDatabase db) {
  final path = db.select('PRAGMA database_list').first['file'] as String?;
  if (path == null || path.isEmpty) return; // in memory
  final copy = File('$path$preUpgradeSuffix');
  final version = db.userVersion;
  if (version > 0 && version < currentSchemaVersion && !copy.existsSync()) {
    db.execute('VACUUM INTO ?', [copy.path]);
  }
}
