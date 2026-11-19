/// Wage calculations (product spec, Labour; rule 8). Amounts are paise,
/// attendance and hours thousandths. Every stored amount is rounded once,
/// half away from zero.
library;

import '../../../core/money/money.dart';

/// A named worker's day. Half-day is an attendance value, not a wage type;
/// overtime is a full day plus extra hours.
enum Attendance {
  full(1000),
  half(500),
  absent(0),
  overtime(1000);

  const Attendance(this.thousandths);

  /// Stored in `labour_entries.attendance`.
  final int thousandths;

  /// The attendance a saved entry had.
  static Attendance of(int thousandths, int? overtimeHours) =>
      (overtimeHours ?? 0) > 0
      ? overtime
      : switch (thousandths) {
          1000 => full,
          500 => half,
          0 => absent,
          // another fraction, typed by hand elsewhere: closest of the three
          _ => thousandths >= 750 ? full : (thousandths >= 250 ? half : absent),
        };
}

/// One named worker's wage for a day: the daily rate times attendance, plus
/// overtime hours at the overtime rate. ₹900 full + 2 h at ₹150 → ₹1,200.
int attendanceWage(
  int ratePaise,
  Attendance attendance, {
  int overtimeHours = 0,
  int overtimeRatePaise = 0,
}) =>
    mulDivRound(ratePaise, attendance.thousandths, 1000) +
    (attendance == Attendance.overtime
        ? amountForQuantity(overtimeHours, overtimeRatePaise)
        : 0);

/// One rate class of a group: so many people at one rate per head.
class GroupLine {
  const GroupLine(this.rateClass, this.heads, this.ratePaise);
  final String rateClass;
  final int heads;
  final int ratePaise;

  int get paise => heads * ratePaise;
}

/// A group's wage: each rate class's head count times its rate.
/// 5 at ₹800 and 1 at ₹1,200 → ₹5,200.
int groupWage(Iterable<GroupLine> lines) =>
    lines.fold(0, (sum, l) => sum + l.paise);

/// Kinds of labour payment (product spec, Labour).
enum PaymentKind { advance, part, settlement, bonus, deduction }

/// What a worker or group is owed: wages earned, less money paid and
/// deductions. A bonus is money paid for something earned on top of wages,
/// so it leaves the balance as it is. Negative means they were paid ahead.
// shortcut: bonus and deduction follow the reading sent to the owner on
// 2026-11-19 (docs silent); change here if the owner decides otherwise.
int balance(int wagesPaise, Map<PaymentKind, int> payments) {
  int of(PaymentKind k) => payments[k] ?? 0;
  return wagesPaise -
      of(PaymentKind.advance) -
      of(PaymentKind.part) -
      of(PaymentKind.settlement) -
      of(PaymentKind.deduction);
}
