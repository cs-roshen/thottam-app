import '../money/money.dart';

/// A unit from the templates. [factor] is how many base units of its
/// [dimension] one unit holds (base: kg, cent, litre, piece), as a decimal
/// string so it stays exact ("247.105"). Null means the farmer sets the ratio.
class Unit {
  const Unit(this.code, this.dimension, this.factor);

  /// Reads a `template_items` row of list type `unit` (`data.dimension`,
  /// `data.factor`).
  factory Unit.fromTemplate(String code, Map<String, Object?> data) {
    final factor = data['factor'];
    return Unit(
      code,
      data['dimension']! as String,
      factor == null ? null : '$factor',
    );
  }

  final String code;
  final String dimension;
  final String? factor;
}

/// A farmer's own conversion: one [from] holds [factor] of [to]
/// ("1 para of paddy is 7 kg"). Overrides template factors for that pair.
class UnitRatio {
  const UnitRatio(this.from, this.to, this.factor);
  final String from;
  final String to;
  final String factor;
}

/// Converts quantities (thousandths of a unit) between units, from template
/// factors and the farmer's own ratios. A converted quantity is stored to
/// thousandths, half away from zero (product spec rule 8).
class Units {
  Units(Iterable<Unit> units, {Iterable<UnitRatio> ratios = const []})
    : _units = {for (final u in units) u.code: u},
      _ratios = ratios.toList();

  final Map<String, Unit> _units;
  final List<UnitRatio> _ratios;

  /// [quantity] thousandths of [from] in thousandths of [to], or null when
  /// there is no known way between the two.
  int? convert(int quantity, String from, String to) {
    final r = _ratio(from, to);
    if (r == null) return null;
    final (n, d) = r;
    if (n == BigInt.zero || d == BigInt.zero) return null;
    return divRound(BigInt.from(quantity) * n, d);
  }

  /// How many [to] one [from] holds, as numerator and denominator.
  (BigInt, BigInt)? _ratio(String from, String to) {
    if (from == to) return (BigInt.one, BigInt.one);
    final direct = _own(from, to);
    if (direct != null) return direct;
    final base = _viaBase(from, to);
    if (base != null) return base;
    // Through one of the farmer's ratios, with template steps on either side:
    // from → a (template), a → b (ratio), b → to (template).
    for (final r in _ratios) {
      final f = _decimal(r.factor);
      for (final (a, b, ab) in [
        (r.from, r.to, f),
        (r.to, r.from, _invert(f)),
      ]) {
        final left = from == a ? (BigInt.one, BigInt.one) : _viaBase(from, a);
        final right = b == to ? (BigInt.one, BigInt.one) : _viaBase(b, to);
        if (left != null && right != null) {
          return _times(_times(left, ab), right);
        }
      }
    }
    return null;
  }

  (BigInt, BigInt)? _own(String from, String to) {
    for (final r in _ratios) {
      if (r.from == from && r.to == to) return _decimal(r.factor);
      if (r.from == to && r.to == from) return _invert(_decimal(r.factor));
    }
    return null;
  }

  (BigInt, BigInt)? _viaBase(String from, String to) {
    final a = _units[from];
    final b = _units[to];
    if (a == null || b == null || a.dimension != b.dimension) return null;
    if (a.factor == null || b.factor == null) return null;
    return _times(_decimal(a.factor!), _invert(_decimal(b.factor!)));
  }
}

(BigInt, BigInt) _decimal(String s) {
  final match = RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(s.trim());
  if (match == null) throw FormatException(s);
  final frac = match.group(2) ?? '';
  return (
    BigInt.parse('${match.group(1)}$frac'),
    BigInt.from(10).pow(frac.length),
  );
}

(BigInt, BigInt) _invert((BigInt, BigInt) r) => (r.$2, r.$1);

(BigInt, BigInt) _times((BigInt, BigInt) a, (BigInt, BigInt) b) =>
    (a.$1 * b.$1, a.$2 * b.$2);
