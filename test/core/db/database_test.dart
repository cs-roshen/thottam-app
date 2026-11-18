import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/db/database.dart';

import 'generated/schema.dart';

void main() {
  test('the settings from section 12 take effect on open', () async {
    final dir = await Directory.systemTemp.createTemp('thottam_db');
    final db = AppDatabase(
      NativeDatabase(File('${dir.path}/t.db'), setup: applyPragmas),
    );
    Future<Object?> pragma(String name) async =>
        (await db.customSelect('PRAGMA $name').getSingle()).data.values.first;

    expect(await pragma('journal_mode'), 'wal');
    expect(await pragma('synchronous'), 1); // NORMAL
    expect(await pragma('foreign_keys'), 1);
    expect(await pragma('busy_timeout'), 5000);
    expect(await pragma('cache_size'), -8000);
    await db.close();
    await dir.delete(recursive: true);
  });

  test('a new database matches the exported schema', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.validateDatabaseSchema();
    await db.close();
  });

  test('every earlier version upgrades to the current one', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    for (final from in GeneratedHelper.versions) {
      final connection = await verifier.startAt(from);
      final db = AppDatabase(connection);
      await verifier.migrateAndValidate(db, db.schemaVersion);
      await db.close();
    }
  });

  test('the current version has an exported schema', () {
    final db = AppDatabase(NativeDatabase.memory());
    expect(GeneratedHelper.versions.last, db.schemaVersion);
    db.close();
  });

  test('a failed transaction leaves nothing behind', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await expectLater(
      db.transaction(() async {
        await db.customStatement(
          "INSERT INTO app_settings (\"key\", value) VALUES ('a', '1')",
        );
        throw StateError('stop');
      }),
      throwsStateError,
    );
    final rows = await db.customSelect('SELECT * FROM app_settings').get();
    expect(rows, isEmpty);
    await db.close();
  });
}
