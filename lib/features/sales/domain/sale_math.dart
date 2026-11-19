/// Selling (product spec, Selling and prices; rules 8 and 9). Quantities are
/// thousandths of their unit, money paise. Stored amounts (gross, net) are
/// rounded once; per-unit figures are worked out exactly and rounded only
/// for display.
library;

import '../../../core/money/money.dart';

/// Gross for [quantity] thousandths at [ratePaise] per unit: 50 kg at ₹705
/// → ₹35,250.
int gross(int quantity, int ratePaise) =>
    amountForQuantity(quantity, ratePaise);

/// Net after deductions: what the farmer receives.
int net(int grossPaise, Iterable<int> deductionsPaise) =>
    grossPaise - deductionsPaise.fold(0, (s, d) => s + d);

/// Per whole unit, for display: ₹35,080 over 50 kg → ₹701.60.
int? perUnit(int paise, int quantity) =>
    quantity == 0 ? null : mulDivRound(paise, 1000, quantity);

/// What is taken from one lot: [taken] of its [lotQuantity] (both in the
/// lot's unit), and the lot's stored cost.
class LotTake {
  const LotTake(this.taken, this.lotQuantity, this.lotCostPaise);
  final int taken;
  final int lotQuantity;
  final int lotCostPaise;
}

/// The cost of what is sold, exactly, as a fraction of paise: each lot's
/// cost in proportion to what is taken from it. A sale from several lots
/// thus carries the average cost per unit weighted by what each gives.
(BigInt, BigInt) _cost(List<LotTake> takes) {
  var n = BigInt.zero;
  var d = BigInt.one;
  for (final t in takes) {
    if (t.lotQuantity == 0) continue;
    // n/d + cost·taken/lotQuantity
    final tn = BigInt.from(t.lotCostPaise) * BigInt.from(t.taken);
    final td = BigInt.from(t.lotQuantity);
    n = n * td + tn * d;
    d = d * td;
  }
  return (n, d);
}

/// Lot cost per sale unit: the weighted cost of [takes] over [saleQuantity]
/// thousandths of the sale unit (converted already when units differ).
/// 30 kg at ₹238 and 20 kg at ₹250 → ₹242.80 per kg.
int? costPerSaleUnit(List<LotTake> takes, int saleQuantity) {
  if (saleQuantity == 0) return null;
  final (n, d) = _cost(takes);
  return divRound(n * BigInt.from(1000), d * BigInt.from(saleQuantity));
}

/// Profit per sale unit before saving (rule 9): net per unit minus lot cost
/// per unit, worked out from exact values and rounded once. 50 kg net
/// ₹35,080, lot at ₹238 a kg → ₹463.60 a kg.
int? profitPerSaleUnit(int netPaise, List<LotTake> takes, int saleQuantity) {
  if (saleQuantity == 0) return null;
  final (n, d) = _cost(takes);
  return divRound(
    (BigInt.from(netPaise) * d - n) * BigInt.from(1000),
    d * BigInt.from(saleQuantity),
  );
}

/// A lot with stock to sell from, oldest first.
class StockLot {
  const StockLot(this.id, this.stock);
  final String id;

  /// What is left, in the lot's unit.
  final int stock;
}

/// Takes [quantity] (in the lots' unit) from [lots] in the order given,
/// oldest first, each up to its stock. Null when they do not hold enough:
/// a sale never takes more than is in stock.
List<(String, int)>? takeFrom(List<StockLot> lots, int quantity) {
  final out = <(String, int)>[];
  var left = quantity;
  for (final l in lots) {
    if (left == 0) break;
    final t = left < l.stock ? left : l.stock;
    if (t > 0) out.add((l.id, t));
    left -= t;
  }
  return left == 0 ? out : null;
}

/// paid, part paid or due; what was received now.
enum PaymentStatus { paid, part, due }
