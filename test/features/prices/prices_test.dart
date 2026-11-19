import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/features/prices/domain/prices.dart';

void main() {
  final now = DateTime(2026, 11, 19, 12);
  PricePoint p(int rupees, DateTime at, {String market = 'Kochi'}) =>
      PricePoint(
        paise: rupees * 100,
        unit: 'kg',
        market: market,
        source: 'Spices Board',
        at: at,
      );

  test('latest price, its change from the one before in the same market, '
      'and every market', () {
    final s = summarize([
      p(690, DateTime(2026, 11, 17, 10)),
      p(700, DateTime(2026, 11, 18, 10)),
      p(698, DateTime(2026, 11, 18, 9), market: 'Kattappana'),
      p(705, DateTime(2026, 11, 19, 10)),
    ], now)!;
    expect(s.latest.paise, 70500);
    expect(s.changePaise, 500);
    expect(s.stale, isFalse);
    expect(s.markets.map((m) => (m.market, m.paise)), [
      ('Kochi', 70500),
      ('Kattappana', 69800),
    ]);
  });

  test('a price older than one day is stale', () {
    final s = summarize([p(705, DateTime(2026, 11, 18, 11))], now)!;
    expect(s.stale, isTrue);
    expect(s.changePaise, isNull);
    expect(
      summarize([p(705, DateTime(2026, 11, 18, 13))], now)!.stale,
      isFalse,
    );
  });

  test('the chart: the latest market, one price a day, oldest first, last '
      '30 days only', () {
    final s = summarize([
      p(600, DateTime(2026, 10, 1)),
      p(690, DateTime(2026, 11, 17, 8)),
      p(692, DateTime(2026, 11, 17, 18)),
      p(650, DateTime(2026, 11, 18), market: 'Kattappana'),
      p(705, DateTime(2026, 11, 19, 10)),
    ], now)!;
    expect(s.chart.map((c) => c.paise), [69200, 70500]);
    expect(s.low, 69200);
    expect(s.high, 70500);
  });

  test('no prices, no summary', () {
    expect(summarize(const [], now), isNull);
  });

  test('an alert is hit when the latest price is above its threshold', () {
    expect(alertHit(70000, 70500), isTrue);
    expect(alertHit(70500, 70500), isFalse);
    expect(alertHit(null, 70500), isFalse);
  });
}
