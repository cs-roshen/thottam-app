import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/dev/benchmark_seed.dart';

void main() {
  final seed = generateBenchmarkSeed();

  test('sizes match the plan (section 14)', () {
    int count(String table) => seed[table]!.length;
    expect(count('farms'), 1);
    expect(count('plots'), 8);
    expect(count('crop_cycles'), 20);
    expect(count('workers'), 40);
    expect(count('labour_groups'), 10);
    expect(count('labour_entries'), 15000);
    expect(count('expenses'), 6000);
    expect(count('harvests'), 1500);
    expect(count('lots'), 1500);
    expect(count('sales'), 1200);
    expect(count('event_log'), inInclusiveRange(45000, 55000));
  });

  test('the same seed gives the same rows', () {
    final again = generateBenchmarkSeed();
    expect(again['expenses']!.last, seed['expenses']!.last);
    expect(again['event_log']!.length, seed['event_log']!.length);
  });

  test('every expense split adds up to its amount', () {
    final byExpense = <Object?, int>{};
    for (final a in seed['expense_allocations']!) {
      byExpense.update(
        a['expense_id'],
        (v) => v + (a['amount_paise']! as int),
        ifAbsent: () => a['amount_paise']! as int,
      );
    }
    for (final e in seed['expenses']!) {
      expect(byExpense[e['id']], e['amount_paise'], reason: '${e['id']}');
    }
  });

  test('ids are unique and rows carry the common columns', () {
    final ids = <Object?>{};
    for (final MapEntry(key: table, value: rows) in seed.entries) {
      for (final row in rows) {
        expect(ids.add('$table/${row['id']}'), isTrue, reason: table);
        if (!const {'farms', 'event_log', 'crops'}.contains(table)) {
          expect(
            row.keys,
            containsAll(<String>[
              'farm_id',
              'created_at',
              'created_by',
              'updated_at',
              'updated_by',
              'version',
              'deleted_at',
            ]),
            reason: table,
          );
        }
      }
    }
  });

  test('entries span three years and never sell more than the lot', () {
    final dates = seed['labour_entries']!.map((e) => e['work_date']! as String);
    expect(dates.reduce((a, b) => a.compareTo(b) < 0 ? a : b), '2023-11-18');
    expect(
      dates.reduce((a, b) => a.compareTo(b) > 0 ? a : b),
      startsWith('2026-11'),
    );
    final sold = <Object?, int>{};
    for (final s in seed['sale_lots']!) {
      sold.update(
        s['lot_id'],
        (v) => v + (s['quantity']! as int),
        ifAbsent: () => s['quantity']! as int,
      );
    }
    for (final lot in seed['lots']!) {
      expect(sold[lot['id']] ?? 0, lessThanOrEqualTo(lot['quantity']! as int));
    }
  });
}
