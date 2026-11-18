import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:sqlite3/common.dart';

part 'database.g.dart';

/// The phone's database: the source of truth for every screen.
@DriftDatabase(include: {'tables.drift'})
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // Every later version adds a step here and a test in test/core/db/.
    onUpgrade: (m, from, to) async {},
  );
}

/// Opens the signed-in user's database on a background isolate, so queries
/// never block the interface. One file per user: signing in as someone else
/// on the same phone never shows the first user's data.
AppDatabase openAppDatabase(String userId) => AppDatabase(
  driftDatabase(
    name: 'thottam_$userId',
    native: const DriftNativeOptions(setup: applyPragmas),
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
}
