import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/features/money/domain/profit.dart';

void main() {
  // the spec's example: income 92,000 + 68,500 + 24,000; expense 31,000 +
  // 44,200 + 21,000; family labour 5,000 + 4,000 + 3,000
  const cycles = [
    CycleMoney(
      'c-coconut',
      incomePaise: 9200000,
      expensePaise: 2000000,
      paidLabourPaise: 1100000,
      familyLabourPaise: 500000,
    ),
    CycleMoney(
      'c-pepper',
      incomePaise: 6850000,
      expensePaise: 4420000,
      familyLabourPaise: 400000,
    ),
    CycleMoney(
      'c-banana',
      incomePaise: 2400000,
      expensePaise: 1000000,
      paidLabourPaise: 1100000,
      familyLabourPaise: 300000,
    ),
  ];
  String? crop(String c) => c.substring(2);

  test('income ₹1,84,500, expense ₹96,200, profit ₹88,300', () {
    final p = profitByCrop(cycles, crop, includeFamily: false);
    expect(p.incomePaise, 18450000);
    expect(p.expensePaise, 9620000);
    expect(p.profitPaise, 8830000);
    expect(p.familyPaise, 1200000);
    expect(p.rows.map((r) => r.key), ['coconut', 'pepper', 'banana']);
  });

  test('with family labour: expense ₹1,08,200, profit ₹76,300', () {
    final p = profitByCrop(cycles, crop, includeFamily: true);
    expect(p.expensePaise, 10820000);
    expect(p.profitPaise, 7630000);
  });

  test('totals are the sum of the rows; two cycles of one crop make one row; '
      'money on no crop has its own row', () {
    final p = profitByCrop(
      [
        ...cycles,
        const CycleMoney('c-pepper2', incomePaise: 100000, expensePaise: 50000),
        const CycleMoney(null, expensePaise: 30000),
      ],
      (c) => c == 'c-pepper2' ? 'pepper' : crop(c),
      includeFamily: false,
    );
    expect(p.rows.map((r) => r.key), ['coconut', 'pepper', 'banana', null]);
    expect(p.incomePaise, p.rows.fold<int>(0, (s, r) => s + r.incomePaise));
    expect(p.rows[1].incomePaise, 6950000);
    expect(p.rows.last.expensePaise, 30000);
  });

  test('the financial year runs April to March', () {
    expect(financialYear(DateTime(2026, 11, 19)), ('2026-04-01', '2027-03-31'));
    expect(financialYear(DateTime(2027, 2, 1)), ('2026-04-01', '2027-03-31'));
    expect(financialYear(DateTime(2026, 4, 1)), ('2026-04-01', '2027-03-31'));
  });
}
