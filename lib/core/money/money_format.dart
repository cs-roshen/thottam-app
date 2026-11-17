/// Formats integer paise as rupees with Indian grouping: ₹1,84,500.
/// Paise appear only when the amount is not whole: ₹463.60.
/// Digits are always Latin, in every language.
String formatPaise(int paise) {
  final sign = paise < 0 ? '−' : '';
  final abs = paise.abs();
  final rupees = (abs ~/ 100).toString();
  final rest = abs % 100;

  final last3 = rupees.length > 3
      ? rupees.substring(rupees.length - 3)
      : rupees;
  var head = rupees.length > 3 ? rupees.substring(0, rupees.length - 3) : '';
  final groups = <String>[];
  while (head.length > 2) {
    groups.insert(0, head.substring(head.length - 2));
    head = head.substring(0, head.length - 2);
  }
  if (head.isNotEmpty) groups.insert(0, head);
  final grouped = [...groups, last3].join(',');

  final fraction = rest == 0 ? '' : '.${rest.toString().padLeft(2, '0')}';
  return '$sign₹$grouped$fraction';
}
