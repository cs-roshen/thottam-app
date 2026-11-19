/// Prices (screen 14): a crop's latest price, its change, staleness, the
/// markets and a 30-day line. Official sources publish daily, so "live"
/// means the latest published. Pure Dart.
library;

/// One published price, official or entered on this farm.
class PricePoint {
  const PricePoint({
    required this.paise,
    required this.unit,
    required this.market,
    required this.source,
    required this.at,
    this.local = false,
  });

  final int paise;
  final String unit;
  final String market;
  final String source;
  final DateTime at;

  /// Entered on this farm (a shop's rate), shown apart from official ones.
  final bool local;
}

class PriceSummary {
  const PriceSummary({
    required this.latest,
    required this.changePaise,
    required this.stale,
    required this.markets,
    required this.chart,
  });

  final PricePoint latest;

  /// Against the price before it in the same market and unit; null when
  /// there is none.
  final int? changePaise;

  /// Older than one day.
  final bool stale;

  /// The latest price of each market, newest first.
  final List<PricePoint> markets;

  /// The latest market's last price of each day in the last 30 days,
  /// oldest first.
  final List<PricePoint> chart;

  int get low => chart.map((c) => c.paise).reduce((a, b) => a < b ? a : b);
  int get high => chart.map((c) => c.paise).reduce((a, b) => a > b ? a : b);
}

PriceSummary? summarize(Iterable<PricePoint> points, DateTime now) {
  final all = points.toList()..sort((a, b) => b.at.compareTo(a.at));
  if (all.isEmpty) return null;
  final latest = all.first;
  bool sameLine(PricePoint p) =>
      p.market == latest.market &&
      p.unit == latest.unit &&
      p.local == latest.local;
  final before = all.skip(1).where(sameLine).firstOrNull;
  final markets = <String, PricePoint>{};
  for (final p in all) {
    markets.putIfAbsent('${p.local}|${p.market}|${p.unit}', () => p);
  }
  final from = now.subtract(const Duration(days: 30));
  final byDay = <String, PricePoint>{};
  for (final p in all.where(sameLine)) {
    if (p.at.isBefore(from)) continue;
    // newest first, so the first of each day is its last price
    byDay.putIfAbsent('${p.at.year}-${p.at.month}-${p.at.day}', () => p);
  }
  return PriceSummary(
    latest: latest,
    changePaise: before == null ? null : latest.paise - before.paise,
    stale: now.difference(latest.at) > const Duration(days: 1),
    markets: markets.values.toList(),
    chart: byDay.values.toList().reversed.toList(),
  );
}

/// The farmer's alert ([thresholdPaise], null when off) is hit when the
/// latest price is above it.
bool alertHit(int? thresholdPaise, int latestPaise) =>
    thresholdPaise != null && latestPaise > thresholdPaise;
