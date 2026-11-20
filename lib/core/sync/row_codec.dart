import 'dart:convert';

import 'package:drift/drift.dart';

/// Columns that are `timestamptz` on the server and integer milliseconds
/// (UTC) on the phone. The codec test checks this against the migrations.
const timestampColumns = {
  'created_at',
  'updated_at',
  'deleted_at',
  'done_at',
  'accepted_at',
  'published_at',
};

/// Columns that are `jsonb` on the server and JSON text on the phone.
const jsonColumns = {
  'settings',
  'permissions',
  'data',
  'details',
  'default_rates',
  'deductions',
  'summary',
  'old_values',
  'new_values',
  'results',
};

/// Turns a phone row into the server's JSON form.
Map<String, Object?> toServerRow(
  TableInfo<Table, Object?> table,
  Map<String, Object?> row,
) {
  final bools = _boolColumns(table);
  return {
    for (final MapEntry(:key, :value) in row.entries)
      key: toServerValue(key, value, isBool: bools.contains(key)),
  };
}

Object? toServerValue(String column, Object? v, {bool isBool = false}) {
  if (v == null) return null;
  if (timestampColumns.contains(column)) {
    return DateTime.fromMillisecondsSinceEpoch(
      v as int,
      isUtc: true,
    ).toIso8601String();
  }
  if (jsonColumns.contains(column)) return jsonDecode(v as String);
  if (isBool) return v == 1 || v == true;
  return v;
}

/// Turns a server row into the phone's form, keeping only the phone's
/// columns (the server-only server_seq is dropped).
Map<String, Object?> toLocalRow(
  TableInfo<Table, Object?> table,
  Map<String, Object?> row,
) {
  final bools = _boolColumns(table);
  return {
    for (final c in table.$columns)
      if (row.containsKey(c.name))
        c.name: _toLocalValue(c.name, row[c.name], bools.contains(c.name)),
  };
}

Object? _toLocalValue(String column, Object? v, bool isBool) {
  if (v == null) return null;
  if (timestampColumns.contains(column)) {
    return DateTime.parse(v as String).millisecondsSinceEpoch;
  }
  if (jsonColumns.contains(column)) return jsonEncode(v);
  if (isBool) return v == true ? 1 : 0;
  if (v is double && v == v.roundToDouble()) return v.toInt();
  return v;
}

Set<String> _boolColumns(TableInfo<Table, Object?> table) => {
  for (final c in table.$columns)
    if (c.type == DriftSqlType.bool) c.name,
};
