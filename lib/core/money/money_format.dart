import 'money.dart';

/// Formats integer paise as rupees with Indian grouping: ₹1,84,500.
/// Paise appear only when the amount is not whole: ₹463.60.
/// Digits are always Latin, in every language.
String formatPaise(int paise) {
  final sign = paise < 0 ? '−' : '';
  final abs = paise.abs();
  final rupees = (abs ~/ 100).toString();
  final rest = abs % 100;

  final grouped = indianGrouping(rupees);

  final fraction = rest == 0 ? '' : '.${rest.toString().padLeft(2, '0')}';
  return '$sign₹$grouped$fraction';
}

/// Inserts Indian digit grouping into a run of digits: 1234567 → 12,34,567.
String indianGrouping(String digits) {
  if (digits.length <= 3) return digits;
  final last3 = digits.substring(digits.length - 3);
  var head = digits.substring(0, digits.length - 3);
  final groups = <String>[];
  while (head.length > 2) {
    groups.insert(0, head.substring(head.length - 2));
    head = head.substring(0, head.length - 2);
  }
  if (head.isNotEmpty) groups.insert(0, head);
  return [...groups, last3].join(',');
}

/// Formats a quantity in thousandths of its unit for display: rounded to one
/// decimal, half away from zero, with Indian grouping; the decimal appears only
/// when it is not zero (12.5, 1,200). Digits are always Latin. A per-person or
/// per-unit figure passes the divisor as [per], so it is rounded only once.
String formatQuantity(int thousandths, [int per = 1]) {
  if (per <= 0) throw ArgumentError.value(per, 'per');
  final tenths = divRound(BigInt.from(thousandths), BigInt.from(100 * per));
  final sign = tenths < 0 ? '−' : '';
  final abs = tenths.abs();
  final whole = indianGrouping((abs ~/ 10).toString());
  return abs % 10 == 0 ? '$sign$whole' : '$sign$whole.${abs % 10}';
}
