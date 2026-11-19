/// Plots and crop cycles as the land screens show them (screens.md 4, 18).
library;

/// One crop on a plot for one season or for the life of a perennial.
class CycleView {
  const CycleView({
    required this.id,
    required this.plotId,
    required this.cropId,
    required this.nameMl,
    required this.nameEn,
    required this.kind,
    this.variety,
    this.plantCount,
    this.areaShare,
    this.season,
    this.plantedOn,
    this.status = 'active',
  });

  final String id;
  final String plotId;
  final String cropId;
  final String nameMl;
  final String nameEn;

  /// seasonal, annual or perennial.
  final String kind;
  final String? variety;
  final int? plantCount;

  /// Thousandths of a percent of the plot.
  final int? areaShare;
  final String? season;
  final String? plantedOn;

  /// planned, active or closed. A closed season's entries are read-only.
  final String status;

  bool get closed => status == 'closed';
}

class PlotView {
  const PlotView({
    required this.id,
    required this.name,
    required this.areaUnit,
    required this.tenure,
    this.area,
    this.cycles = const [],
    this.nextTask,
  });

  final String id;
  final String name;

  /// Thousandths of [areaUnit], or null when not given.
  final int? area;
  final String areaUnit;

  /// owned, leased or shared.
  final String tenure;

  /// The crops growing now (closed seasons left out).
  final List<CycleView> cycles;

  /// The next open task on the plot: its title and due day.
  final (String, String?)? nextTask;

  bool get mixed => cycles.length > 1;
}

/// What one crop cycle has cost and yielded. Labour is paid labour only;
/// family labour stays out, as in profit and loss by default.
class CycleTotals {
  const CycleTotals(
    this.cycleId, {
    this.expensePaise = 0,
    this.labourPaise = 0,
    this.yields = const {},
  });

  final String cycleId;
  final int expensePaise;
  final int labourPaise;

  /// Quantity harvested, in thousandths, by unit.
  final Map<String, int> yields;

  int get costPaise => expensePaise + labourPaise;
}

/// A plot's totals: always the sum of its crop cycles (screens.md 18).
CycleTotals plotTotals(String plotId, Iterable<CycleTotals> cycles) {
  var expense = 0;
  var labour = 0;
  final yields = <String, int>{};
  for (final c in cycles) {
    expense += c.expensePaise;
    labour += c.labourPaise;
    for (final MapEntry(:key, :value) in c.yields.entries) {
      yields[key] = (yields[key] ?? 0) + value;
    }
  }
  return CycleTotals(
    plotId,
    expensePaise: expense,
    labourPaise: labour,
    yields: yields,
  );
}

/// The farm's land in one unit: the unit most plots use (the first listed on
/// a tie), the others converted into it with [convert]. Plots without an
/// area, or in a unit that does not convert, are left out.
(int, String)? totalArea(
  Iterable<PlotView> plots,
  int? Function(int quantity, String from, String to) convert,
) {
  final withArea = [
    for (final p in plots)
      if (p.area != null) p,
  ];
  if (withArea.isEmpty) return null;
  final counts = <String, int>{};
  for (final p in withArea) {
    counts[p.areaUnit] = (counts[p.areaUnit] ?? 0) + 1;
  }
  var unit = withArea.first.areaUnit;
  for (final MapEntry(:key, :value) in counts.entries) {
    if (value > counts[unit]!) unit = key;
  }
  var sum = 0;
  for (final p in withArea) {
    sum += convert(p.area!, p.areaUnit, unit) ?? 0;
  }
  return (sum, unit);
}

/// An area share typed as a percent ("60", "33.5") in thousandths of a
/// percent, or null when it is not a number from 0 to 100.
int? parsePercent(int? thousandths) =>
    thousandths != null && thousandths <= 100000 ? thousandths : null;

/// A planting year typed by the farmer, kept as the first day of that year;
/// the year is all a farmer usually knows of an old planting.
String? plantedOnForYear(String year, int thisYear) {
  final y = int.tryParse(year.trim());
  if (y == null || y < 1900 || y > thisYear) return null;
  return '$y-01-01';
}
