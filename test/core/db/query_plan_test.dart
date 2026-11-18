import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/db/database.dart';

import 'list_queries.dart';

/// Section 12: every list and total query uses an index and never scans a
/// whole table; pages come out in index order.
void main() {
  late AppDatabase db;
  setUpAll(() => db = AppDatabase(NativeDatabase.memory()));
  tearDownAll(() => db.close());

  for (final q in listQueries) {
    test(q.name, () async {
      final (sql, args) = bindNamed(q.sql, const {});
      final plan = [
        for (final row
            in await db
                .customSelect('EXPLAIN QUERY PLAN $sql', variables: args)
                .get())
          row.read<String>('detail'),
      ];
      final scans = plan.where((d) => RegExp(r'^SCAN \w+').hasMatch(d));
      expect(scans, isEmpty, reason: plan.join('\n'));
      if (q.ordered) {
        expect(
          plan.where((d) => d.contains('TEMP B-TREE')),
          isEmpty,
          reason: plan.join('\n'),
        );
      }
    });
  }
}

/// Turns `:name` parameters into `?` with values from [values] (or a
/// placeholder when planning).
(String, List<Variable>) bindNamed(String sql, Map<String, Object> values) {
  final args = <Variable>[];
  final out = sql.replaceAllMapped(RegExp(r':(\w+)'), (m) {
    final v = values[m.group(1)] ?? 'x';
    args.add(v is int ? Variable.withInt(v) : Variable.withString('$v'));
    return '?';
  });
  return (out, args);
}
