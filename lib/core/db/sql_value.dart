import 'dart:convert';

/// The phone's storage form of a value: milliseconds since the epoch for
/// times, JSON text for maps and lists, 0 or 1 for booleans.
Object? toSqlValue(Object? v) => switch (v) {
  DateTime d => d.millisecondsSinceEpoch,
  Map() || List() => jsonEncode(v),
  bool b => b ? 1 : 0,
  _ => v,
};
