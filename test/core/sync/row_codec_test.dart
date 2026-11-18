import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/db/database.dart';
import 'package:thottam/core/sync/row_codec.dart';

void main() {
  final sql = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .map((f) => f.readAsStringSync())
      .join('\n');

  // Columns of the synced tables only (not function arguments, not the
  // server's own bookkeeping tables).
  final tables = RegExp(
    r'create table public\.(\w+) \((.*?)\n\)',
    dotAll: true,
  ).allMatches(sql).where((m) => !m.group(1)!.startsWith('sync_'));
  Set<String> columnsOfType(String type) => {
    for (final t in tables)
      for (final m in RegExp(
        '^\\s+(\\w+) $type\\b',
        multiLine: true,
      ).allMatches(t.group(2)!))
        m.group(1)!,
  };

  test('timestamp columns match the server\'s timestamptz columns', () {
    expect(timestampColumns, columnsOfType('timestamptz'));
  });

  test('JSON columns match the server\'s jsonb columns', () {
    expect(jsonColumns, columnsOfType('jsonb'));
  });

  test('a row survives the trip to the server form and back', () {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final local = <String, Object?>{
      'id': 'w1',
      'farm_id': 'f1',
      'name': 'Ravi',
      'phone': null,
      'skill': null,
      'wage_type': 'daily',
      'default_rate_paise': 90000,
      'is_family': 1,
      'created_at': 1763452800123,
      'created_by': 'u1',
      'updated_at': 1763452800123,
      'updated_by': 'u1',
      'version': 3,
      'deleted_at': null,
    };
    final server = toServerRow(db.workers, local);
    expect(server['is_family'], true);
    expect(server['created_at'], '2025-11-18T08:00:00.123Z');
    expect(toLocalRow(db.workers, {...server, 'server_seq': 9}), local);
  });

  test('the server\'s own time and JSON forms are read', () {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final local = toLocalRow(db.labourGroups, {
      'id': 'g1',
      'default_rates': {'general': 80000},
      'created_at': '2026-11-18T09:00:00.5+00:00',
      'is_named': false,
      'usual_size': 6.0,
    });
    expect(local['default_rates'], '{"general":80000}');
    expect(
      local['created_at'],
      DateTime.utc(2026, 11, 18, 9, 0, 0, 500).millisecondsSinceEpoch,
    );
    expect(local['is_named'], 0);
    expect(local['usual_size'], 6);
  });
}
