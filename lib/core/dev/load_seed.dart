import '../db/database.dart';
import '../db/sql_value.dart';
import 'benchmark_seed.dart';

/// Inserts [seed] into [db] in one batch, for benchmarks and tests only.
/// It bypasses the event log on purpose: the seed already carries its own.
Future<void> loadSeed(AppDatabase db, SeedTables seed) => db.batch((b) {
  for (final MapEntry(key: table, value: rows) in seed.entries) {
    for (final row in rows) {
      final cols = row.keys.toList();
      b.customStatement(
        'INSERT INTO $table (${cols.map((c) => '"$c"').join(', ')}) '
        'VALUES (${List.filled(cols.length, '?').join(', ')})',
        [for (final c in cols) toSqlValue(row[c])],
      );
    }
  }
});
