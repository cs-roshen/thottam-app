// Up to 12 digits before the point and three after: thousandths of a unit.
final _quantity = RegExp(r'^(\d{0,12})(?:\.(\d{0,3}))?$');

/// Parses what the farmer typed ("2.5", "1,200") into thousandths of the unit
/// (2500, 1200000), the way quantities and areas are stored. Returns null for
/// empty input, a negative number or more than three decimal places.
int? parseQuantity(String text) {
  final match = _quantity.firstMatch(text.replaceAll(',', '').trim());
  final whole = match?.group(1) ?? '';
  final fraction = match?.group(2) ?? '';
  if (match == null || whole.isEmpty && fraction.isEmpty) return null;
  return int.parse(whole.isEmpty ? '0' : whole) * 1000 +
      int.parse(fraction.padRight(3, '0'));
}
