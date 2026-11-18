import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/db/database.dart';

import 'generated/schema.dart';

void main() {
  test(
    'the app opens one file per user, with the section 12 settings',
    () async {
      final dir = await Directory.systemTemp.createTemp('thottam_db');
      final a = openAppDatabase('user-a', directory: dir.path);
      final b = openAppDatabase('user-b', directory: dir.path);
      Future<Object?> pragma(String name) async =>
          (await a.customSelect('PRAGMA $name').getSingle()).data.values.first;

      expect(await pragma('journal_mode'), 'wal');
      expect(await pragma('synchronous'), 1); // NORMAL
      expect(await pragma('foreign_keys'), 1);
      expect(await pragma('busy_timeout'), 5000);
      expect(await pragma('cache_size'), -8000);

      await a.customStatement(
        "INSERT INTO app_settings (\"key\", value) VALUES ('who', 'a')",
      );
      expect(await b.customSelect('SELECT * FROM app_settings').get(), isEmpty);
      await a.close();
      await b.close();
      expect(File('${dir.path}/thottam_user-a.sqlite').existsSync(), isTrue);
      expect(File('${dir.path}/thottam_user-b.sqlite').existsSync(), isTrue);
      await dir.delete(recursive: true);
    },
  );

  test('a row the server would always refuse is refused here too', () async {
    final db = AppDatabase(NativeDatabase.memory());
    Future<void> entry(String values) => db.customStatement(
      'INSERT INTO labour_entries (id, farm_id, work_date, worker_id, group_id, '
      'attendance, created_at, updated_at) VALUES ($values, 0, 0)',
    );
    await expectLater(
      entry("'l1', 'f', '2026-11-18', NULL, NULL, 1000"),
      throwsA(anything),
    );
    await expectLater(
      entry("'l2', 'f', '2026-11-18', 'w', NULL, 1500"),
      throwsA(anything),
    );
    await entry("'l3', 'f', '2026-11-18', 'w', NULL, 500");
    await db.close();
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
