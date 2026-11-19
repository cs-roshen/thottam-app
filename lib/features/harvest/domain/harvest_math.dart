/// Harvest and lot cost (product spec, Harvest; rules 8 and 9). Quantities
/// are thousandths of the harvest unit, money is paise; per-person and
/// per-unit figures are worked out for display, never stored.
library;

import '../../../core/money/money.dart';

/// One team on a harvest: an unnamed group, a named group or a named
/// worker. A group has one common rate per head; a piece-rate team is paid
/// per unit harvested and always enters its own quantity.
class HarvestTeam {
  const HarvestTeam({
    required this.ratePaise,
    this.heads = 1,
    this.pieceRate = false,
    this.quantity,
    this.isFamily = false,
    this.workerId,
    this.groupId,
    this.label = '',
  });

  final int heads;

  /// Per head per day, or per unit for a piece-rate team.
  final int ratePaise;
  final bool pieceRate;

  /// Thousandths of the harvest unit, when the team logs its own.
  final int? quantity;

  /// A family member: their work is shown apart and left out of costs.
  final bool isFamily;
  final String? workerId;
  final String? groupId;
  final String label;

  bool get named => workerId != null;

  /// The team's wage: heads × rate, or quantity × rate for piece rate,
  /// rounded once.
  int get wagePaise => pieceRate
      ? amountForQuantity(quantity ?? 0, ratePaise)
      : heads * ratePaise;
}

/// What the harvest screen shows under the teams.
class HarvestSummary {
  const HarvestSummary({
    required this.quantity,
    required this.people,
    required this.paidWagesPaise,
    required this.familyWagesPaise,
  });

  /// Thousandths of the unit.
  final int quantity;
  final int people;

  /// Wages paid out: the harvest's labour cost.
  final int paidWagesPaise;

  /// Family work, on its own marked line and out of the cost.
  final int familyWagesPaise;

  /// Quantity per person per day, in thousandths, or null with nobody.
  int? get perPerson =>
      people == 0 ? null : divRound(BigInt.from(quantity), BigInt.from(people));

  /// Paid labour cost per whole unit, in paise, or null with no quantity.
  int? get labourCostPerUnit =>
      quantity == 0 ? null : mulDivRound(paidWagesPaise, 1000, quantity);
}

/// The harvest's total quantity: the teams' own when each logs it, else
/// the total entered (piece-rate teams still log theirs for their wage).
int harvestQuantity(
  List<HarvestTeam> teams, {
  required bool perTeam,
  int? total,
}) => perTeam ? teams.fold(0, (s, t) => s + (t.quantity ?? 0)) : (total ?? 0);

HarvestSummary summarise(
  List<HarvestTeam> teams, {
  required bool perTeam,
  int? total,
}) {
  var paid = 0;
  var family = 0;
  for (final t in teams) {
    t.isFamily ? family += t.wagePaise : paid += t.wagePaise;
  }
  return HarvestSummary(
    quantity: harvestQuantity(teams, perTeam: perTeam, total: total),
    people: teams.fold(0, (s, t) => s + t.heads),
    paidWagesPaise: paid,
    familyWagesPaise: family,
  );
}

/// One team's quantity per person and labour cost per unit, for its line.
(int?, int?) teamRates(HarvestTeam t) {
  final q = t.quantity;
  if (q == null || q == 0) return (null, null);
  return (
    divRound(BigInt.from(q), BigInt.from(t.heads)),
    mulDivRound(t.wagePaise, 1000, q),
  );
}

/// A lot's cost (rule 9): every cost posted to its crop cycle since the
/// previous harvest, plus this harvest's paid wages. Family labour is
/// already out of both.
int lotCost({required int costsSincePaise, required int paidWagesPaise}) =>
    costsSincePaise + paidWagesPaise;

/// Cost per whole unit of a lot, in paise, shown only.
int? costPerUnit(int costPaise, int quantity) =>
    quantity == 0 ? null : mulDivRound(costPaise, 1000, quantity);
