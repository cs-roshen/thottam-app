/// Splitting one amount across a plot's crop cycles (product spec, Expenses
/// and Labour; rule 8). Pure Dart: the screens and repositories of expenses
/// and labour share it.
library;

import '../money/money.dart';

/// How an amount is shared across crop cycles by default.
enum SplitMode {
  /// By each crop's default cost share from the templates (screens.md 9).
  templateShare,

  /// By each crop cycle's share of the plot's area.
  area,

  /// By each crop cycle's number of plants.
  plants,

  equal,
}

/// What a crop cycle brings to a split.
class SplitTarget {
  const SplitTarget(
    this.cycleId, {
    this.templateWeight,
    this.areaShare,
    this.plantCount,
  });

  final String cycleId;

  /// The crop's `split_weight` setting, as the override model resolves it.
  final num? templateWeight;
  final int? areaShare;
  final int? plantCount;
}

/// Whole-number weights for [targets] by [mode]. When any target lacks the
/// figure the mode needs, every target shares equally: a split never leaves
/// a crop out without the farmer saying so.
List<int> splitWeights(List<SplitTarget> targets, SplitMode mode) {
  int? figure(SplitTarget t) => switch (mode) {
    // template weights are percents, possibly with decimals
    SplitMode.templateShare =>
      t.templateWeight == null ? null : (t.templateWeight! * 1000).round(),
    SplitMode.area => t.areaShare,
    SplitMode.plants => t.plantCount,
    SplitMode.equal => 1,
  };
  final weights = [for (final t in targets) figure(t)];
  if (weights.any((w) => w == null || w < 0) || weights.every((w) => w == 0)) {
    return [for (final _ in targets) 1];
  }
  return weights.cast<int>();
}

/// [paise] split across [targets] by [mode], the parts summing to [paise]
/// by the largest-remainder rule.
List<int> splitAmount(int paise, List<SplitTarget> targets, SplitMode mode) =>
    targets.isEmpty ? const [] : splitPaise(paise, splitWeights(targets, mode));

/// The farmer typed [value] for part [index]. That part keeps it (never more
/// than [total] nor below zero); the parts in [fixed] keep theirs as far as
/// the total allows; the rest share what is left in their current
/// proportions, or equally when they are all zero. The parts always sum to
/// [total].
List<int> rebalance(
  int total,
  List<int> parts,
  int index,
  int value, {
  Set<int> fixed = const {},
}) {
  final out = [...parts];
  out[index] = value.clamp(0, total);
  var left = total - out[index];
  // parts the farmer set earlier keep their value while it still fits
  for (final i in fixed) {
    if (i == index || i >= out.length) continue;
    out[i] = out[i].clamp(0, left);
    left -= out[i];
  }
  final free = [
    for (var i = 0; i < out.length; i++)
      if (i != index && !fixed.contains(i)) i,
  ];
  if (free.isEmpty) {
    // nothing else may move: the edited part takes up the difference
    out[index] += left;
    return out;
  }
  final current = [for (final i in free) parts[i] < 0 ? 0 : parts[i]];
  final weights = current.every((w) => w == 0)
      ? [for (final _ in free) 1]
      : current;
  final shares = splitPaise(left, weights);
  for (var k = 0; k < free.length; k++) {
    out[free[k]] = shares[k];
  }
  return out;
}
