import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The schema check gate (implementation plan section 16): the server
/// migrations and the phone's schema agree on every synced table's columns,
/// apart from the server-only server_seq.
void main() {
  const serverOnlyTables = {'sync_tables'};
  const phoneOnlyTables = {
    'outbox',
    'sync_state',
    'conflicts',
    'photo_uploads',
    'app_settings',
  };

  final server = <String, List<String>>{};
  for (final f in Directory('supabase/migrations').listSync()..sort(_byPath)) {
    if (f is File && f.path.endsWith('.sql')) {
      server.addAll(parseTables(f.readAsStringSync()));
    }
  }
  final phone = parseTables(
    File('lib/core/db/tables.drift').readAsStringSync(),
  );

  test('both sides were parsed', () {
    expect(server.length, greaterThan(25));
    expect(phone.length, greaterThan(25));
  });

  test('every server table is on the phone, and the other way round', () {
    expect(
      phone.keys.toSet().difference(phoneOnlyTables),
      server.keys.toSet().difference(serverOnlyTables),
    );
  });

  for (final table in server.keys.where((t) => !serverOnlyTables.contains(t))) {
    test('$table has the same columns on both sides', () {
      expect(
        phone[table],
        server[table]!.where((c) => c != 'server_seq').toList(),
      );
    });
  }
}

int _byPath(FileSystemEntity a, FileSystemEntity b) => a.path.compareTo(b.path);

final _create = RegExp(
  r'create table (?:public\.)?(\w+) \((.*?)\n\)',
  caseSensitive: false,
  dotAll: true,
);
final _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
const _notColumns = {'primary', 'unique', 'check', 'constraint', 'foreign'};

/// Table name to column names, in order, from `CREATE TABLE` statements
/// written one column per line.
Map<String, List<String>> parseTables(String sql) => {
  for (final m in _create.allMatches(sql))
    m.group(1)!.toLowerCase(): [
      for (final line in m.group(2)!.split('\n'))
        if (line.trim().split(RegExp(r'\s+')).first.replaceAll('"', '')
            case final name
            when _identifier.hasMatch(name) &&
                !_notColumns.contains(name.toLowerCase()))
          name.toLowerCase(),
    ],
};
