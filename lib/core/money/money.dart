/// Money is integer paise; quantities are integer thousandths of their unit.
/// Rounding follows product spec rule 8.
library;

/// `a × b ÷ d`, exact, then rounded once to a whole number, half away from zero.
/// The rule for every stored amount (quantity × rate, half-day wage, commission)
/// and every stored converted quantity.
int mulDivRound(int a, int b, int d) =>
    divRound(BigInt.from(a) * BigInt.from(b), BigInt.from(d));

/// `n ÷ d` rounded to a whole number, half away from zero.
int divRound(BigInt n, BigInt d) {
  if (d == BigInt.zero) throw ArgumentError.value(d, 'd');
  final q = n ~/ d; // truncates toward zero
  if ((n - q * d).abs() * BigInt.two < d.abs()) return q.toInt();
  return (n.isNegative != d.isNegative ? q - BigInt.one : q + BigInt.one)
      .toInt();
}

/// Amount in paise for [quantity] thousandths of a unit at [ratePaise] per unit.
/// 12.5 kg at ₹64.33 → 80,412.5 paise → 80,413.
int amountForQuantity(int quantity, int ratePaise) =>
    mulDivRound(quantity, ratePaise, 1000);

/// Splits [paise] into parts by [weights] with the largest-remainder rule: each
/// part gets its rounded-down share, then the leftover paise go one at a time to
/// the parts with the largest fractional remainders; ties go to the part listed
/// first. The parts always sum to [paise].
///
/// Weights are non-negative integers in any scale (thousandths of a percent,
/// plant counts, area); equal shares are equal weights.
List<int> splitPaise(int paise, List<int> weights) {
  if (weights.isEmpty) throw ArgumentError.value(weights, 'weights');
  if (weights.any((w) => w < 0)) throw ArgumentError.value(weights, 'weights');
  final total = weights.fold<int>(0, (s, w) => s + w);
  if (total == 0) throw ArgumentError.value(weights, 'weights');
  if (paise < 0) return [for (final p in splitPaise(-paise, weights)) -p];

  final amount = BigInt.from(paise);
  final sum = BigInt.from(total);
  final parts = <int>[];
  final remainders = <BigInt>[];
  for (final w in weights) {
    final n = amount * BigInt.from(w);
    parts.add((n ~/ sum).toInt());
    remainders.add(n.remainder(sum));
  }
  var left = paise - parts.fold<int>(0, (s, p) => s + p);
  final order = List<int>.generate(weights.length, (i) => i)
    ..sort((a, b) {
      final c = remainders[b].compareTo(remainders[a]);
      return c != 0 ? c : a - b;
    });
  for (final i in order) {
    if (left == 0) break;
    parts[i]++;
    left--;
  }
  return parts;
}
