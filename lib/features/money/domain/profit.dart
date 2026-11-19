/// Profit and loss (screen 5; product spec, Money). Totals come from SQL
/// per crop cycle; this joins them by crop and adds them up exactly.
library;

/// One crop cycle's money for the period, as the database adds it up.
class CycleMoney {
  const CycleMoney(
    this.cycleId, {
    this.incomePaise = 0,
    this.expensePaise = 0,
    this.paidLabourPaise = 0,
    this.familyLabourPaise = 0,
  });

  /// Null for money on the farm or a plot but on no crop.
  final String? cycleId;
  final int incomePaise;
  final int expensePaise;
  final int paidLabourPaise;

  /// The value of the family's own work, left out unless asked for.
  final int familyLabourPaise;
}

/// A row of the report: one crop (or the money on no crop).
class ProfitRow {
  const ProfitRow(
    this.key, {
    required this.incomePaise,
    required this.expensePaise,
    required this.familyPaise,
  });

  /// The crop id, or null for money on no crop.
  final String? key;
  final int incomePaise;

  /// Expense as reported: with family labour when it is included.
  final int expensePaise;
  final int familyPaise;

  int get profitPaise => incomePaise - expensePaise;
}

class ProfitAndLoss {
  const ProfitAndLoss(this.rows, {required this.familyPaise});

  final List<ProfitRow> rows;

  /// The family's own work in the period, shown even when left out.
  final int familyPaise;

  int get incomePaise => rows.fold(0, (s, r) => s + r.incomePaise);
  int get expensePaise => rows.fold(0, (s, r) => s + r.expensePaise);
  int get profitPaise => incomePaise - expensePaise;
}

/// The report by crop: each crop cycle's money under its crop (from
/// [cropOf]), money on no crop on its own row, and family labour in the
/// expense only when [includeFamily]. The totals are always the sum of the
/// rows.
ProfitAndLoss profitByCrop(
  Iterable<CycleMoney> cycles,
  String? Function(String cycleId) cropOf, {
  required bool includeFamily,
}) {
  final income = <String?, int>{};
  final expense = <String?, int>{};
  final family = <String?, int>{};
  final order = <String?>[];
  for (final c in cycles) {
    final key = c.cycleId == null ? null : cropOf(c.cycleId!);
    if (!income.containsKey(key)) order.add(key);
    income[key] = (income[key] ?? 0) + c.incomePaise;
    expense[key] =
        (expense[key] ?? 0) +
        c.expensePaise +
        c.paidLabourPaise +
        (includeFamily ? c.familyLabourPaise : 0);
    family[key] = (family[key] ?? 0) + c.familyLabourPaise;
  }
  // crops first, by what they brought in; money on no crop last
  order.sort((a, b) {
    if (a == null) return 1;
    if (b == null) return -1;
    return income[b]!.compareTo(income[a]!);
  });
  return ProfitAndLoss([
    for (final k in order)
      if (income[k] != 0 || expense[k] != 0)
        ProfitRow(
          k,
          incomePaise: income[k]!,
          expensePaise: expense[k]!,
          familyPaise: family[k]!,
        ),
  ], familyPaise: family.values.fold(0, (s, v) => s + v));
}

/// The financial year (April to March) holding [day], as 'YYYY-MM-DD'.
(String, String) financialYear(DateTime day) {
  final start = day.month >= 4 ? day.year : day.year - 1;
  return ('$start-04-01', '${start + 1}-03-31');
}
