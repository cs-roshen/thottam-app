// At most 15 digits of rupees, so the paise always fit in an int.
final _rupees = RegExp(r'^(\d{1,15})(?:\.(\d{0,2}))?$');

/// Parses what the farmer typed ("1,234.5", or "₹1,234.50" as formatPaise
/// writes it) into paise (123450). Returns null for empty input, a negative
/// amount, more than two decimal places or more than 15 digits of rupees.
int? parseRupeesToPaise(String text) {
  final match = _rupees.firstMatch(
    text.replaceAll(',', '').replaceFirst('₹', '').trim(),
  );
  if (match == null) return null;
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  return int.parse(match.group(1)!) * 100 + int.parse(fraction);
}
