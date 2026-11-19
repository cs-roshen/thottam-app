import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/database.dart';
import '../db/sql_value.dart';

/// Where the standard crops and template items ship inside the app, built by
/// `tool/build_templates.py` from the server migrations.
const bundledTemplatesAsset = 'assets/templates/standard.json';

/// Puts the bundled standard crops and template items on a phone that has
/// none yet, so set-up works offline on the first run (implementation plan,
/// C1). They are the server's own rows with the server's ids: the first sync
/// updates them in place. A phone that already has templates keeps them.
Future<void> installBundledTemplates(AppDatabase db, String json) async {
  final have = await db
      .customSelect('SELECT EXISTS (SELECT 1 FROM template_items) AS have')
      .getSingle();
  if (have.read<bool>('have')) return;
  final seed = (jsonDecode(json) as Map).cast<String, Object?>();
  await db.transaction(() async {
    for (final table in const ['crops', 'template_items']) {
      for (final r in seed[table]! as List) {
        final row = {
          ...(r as Map).cast<String, Object?>(),
          'created_at': 0,
          'updated_at': 0,
        };
        final cols = row.keys.toList();
        await db.customStatement(
          'INSERT INTO $table (${cols.map((c) => '"$c"').join(', ')}) '
          'VALUES (${List.filled(cols.length, '?').join(', ')}) '
          'ON CONFLICT (id) DO NOTHING',
          [for (final c in cols) toSqlValue(row[c])],
        );
      }
    }
  });
  db.notifyUpdates({
    TableUpdate.onTable(db.crops),
    TableUpdate.onTable(db.templateItems),
  });
}
