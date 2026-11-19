import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/db/database.dart';

import 'package:thottam/core/db/queries.dart';

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
      // a SELECT of sums with no table of its own reads one constant row
      final scans = plan.where(
        (d) => RegExp(r'^SCAN \w+').hasMatch(d) && d != 'SCAN CONSTANT ROW',
      );
      expect(scans, isEmpty, reason: plan.join('\n'));
      // an automatic index is built by scanning the table on every run
      expect(
        plan.where((d) => d.contains('AUTOMATIC')),
        isEmpty,
        reason: plan.join('\n'),
      );
      // reading every row of the farm is a scan in disguise, unless it is a
      // page taken in index order, or a set-up table that stays small (a
      // farm has tens of workers, groups, plots and crop cycles)
      if (!q.ordered) {
        const small = {
          'workers_farm',
          'labour_groups_farm',
          'plots_farm',
          'crop_cycles_farm',
        };
        expect(
          plan.where((d) {
            final m = RegExp(r'INDEX (\w+) \(farm_id=\?\)$').firstMatch(d);
            return m != null && !small.contains(m[1]);
          }),
          isEmpty,
          reason: plan.join('\n'),
        );
      }
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
