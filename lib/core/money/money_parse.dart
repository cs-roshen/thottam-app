final _rupees = RegExp(r'^(\d+)(?:\.(\d{0,2}))?$');

/// Parses what the farmer typed ("1,234.5") into paise (123450).
/// Returns null for empty input or more than two decimal places.
int? parseRupeesToPaise(String text) {
  final match = _rupees.firstMatch(text.replaceAll(',', '').trim());
  if (match == null) return null;
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  return int.parse(match.group(1)!) * 100 + int.parse(fraction);
}
