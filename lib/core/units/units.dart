import '../money/money.dart';

/// A unit from the templates. [factor] is how many base units of its
/// [dimension] one unit holds (base: kg, cent, litre, piece), as a decimal
/// string so it stays exact ("247.105381"). Null means the farmer sets the ratio.
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
/// ("1 para of paddy is 7 kg"). It defines [from]: every conversion of [from]
/// goes through it, ahead of any template factor [from] has.
class UnitRatio {
  const UnitRatio(this.from, this.to, this.factor);
  final String from;
  final String to;
  final String factor;
}

typedef _Fraction = (BigInt, BigInt);

/// Converts quantities (thousandths of a unit) between units, from template
/// factors and the farmer's own ratios. A converted quantity is stored to
/// thousandths, half away from zero (product spec rule 8). A factor that is
/// not a positive number is ignored, so one bad entry cannot break the rest.
// shortcut: a path uses at most one farmer ratio at each end (para -> kg, or
// kg -> para); chains such as edangazhi -> para -> kg wait for the owner's
// answer on whether local units chain.
class Units {
  Units(Iterable<Unit> units, {Iterable<UnitRatio> ratios = const []}) {
    for (final u in units) {
      _dimension[u.code] = u.dimension;
      if (u.factor case final f? when _decimal(f) != null) {
        _factor[u.code] = _decimal(f)!;
      }
    }
    for (final r in ratios) {
      final f = _decimal(r.factor);
      if (f != null && r.from != r.to) (_ratios[r.from] ??= []).add((r.to, f));
    }
  }

  final _dimension = <String, String>{};
  final _factor = <String, _Fraction>{};
  final _ratios = <String, List<(String, _Fraction)>>{};

  /// [quantity] thousandths of [from] in thousandths of [to], or null when
  /// there is no known way between the two.
  int? convert(int quantity, String from, String to) {
    final r = _ratio(from, to);
    if (r == null) return null;
    return divRound(BigInt.from(quantity) * r.$1, r.$2);
  }

  /// How many [to] one [from] holds.
  _Fraction? _ratio(String from, String to) {
    if (from == to) return (BigInt.one, BigInt.one);
    // the farmer's definition of [from], then a template step to [to]
    for (final (unit, f) in _ratios[from] ?? const <(String, _Fraction)>[]) {
      final rest = unit == to ? (BigInt.one, BigInt.one) : _viaBase(unit, to);
      if (rest != null) return _times(f, rest);
    }
    // a template step from [from], then the farmer's definition of [to]
    for (final (unit, f) in _ratios[to] ?? const <(String, _Fraction)>[]) {
      final rest = unit == from
          ? (BigInt.one, BigInt.one)
          : _viaBase(from, unit);
      if (rest != null) return _times(rest, _invert(f));
    }
    return _viaBase(from, to);
  }

  _Fraction? _viaBase(String from, String to) {
    final a = _factor[from];
    final b = _factor[to];
    if (a == null || b == null || _dimension[from] != _dimension[to]) {
      return null;
    }
    return _times(a, _invert(b));
  }
}

final _plainDecimal = RegExp(r'^(\d+)(?:\.(\d+))?$');

/// A positive decimal ("7", "247.105381", or a double's "1e-7") as an exact
/// fraction, or null.
_Fraction? _decimal(String s) {
  final match = _plainDecimal.firstMatch(s.trim());
  if (match == null) {
    final v = double.tryParse(s.trim());
    if (v == null || !v.isFinite || v <= 0 || v >= 1e15) return null;
    return _decimal(v.toStringAsFixed(12));
  }
  final frac = match.group(2) ?? '';
  final n = BigInt.parse('${match.group(1)}$frac');
  if (n == BigInt.zero) return null;
  return (n, BigInt.from(10).pow(frac.length));
}

_Fraction _invert(_Fraction r) => (r.$2, r.$1);

_Fraction _times(_Fraction a, _Fraction b) => (a.$1 * b.$1, a.$2 * b.$2);
