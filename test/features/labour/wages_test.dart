import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/features/labour/domain/wages.dart';

void main() {
  test('rates 900, 900, 700, 900 with full, full, half, absent → ₹2,150', () {
    final day = [
      attendanceWage(90000, Attendance.full),
      attendanceWage(90000, Attendance.full),
      attendanceWage(70000, Attendance.half),
      attendanceWage(90000, Attendance.absent),
    ];
    expect(day, [90000, 90000, 35000, 0]);
    expect(day.reduce((a, b) => a + b), 215000);
  });

  test('₹900 full day plus 2 hours at ₹150 per hour → ₹1,200', () {
    expect(
      attendanceWage(
        90000,
        Attendance.overtime,
        overtimeHours: 2000,
        overtimeRatePaise: 15000,
      ),
      120000,
    );
  });

  test('overtime hours count only on an overtime day', () {
    expect(
      attendanceWage(
        90000,
        Attendance.full,
        overtimeHours: 2000,
        overtimeRatePaise: 15000,
      ),
      90000,
    );
  });

  test('a half day of an odd rate rounds once, half away from zero', () {
    expect(attendanceWage(70001, Attendance.half), 35001);
  });

  test('5 at ₹800 and 1 at ₹1,200 → ₹5,200', () {
    expect(
      groupWage(const [
        GroupLine('general', 5, 80000),
        GroupLine('climber', 1, 120000),
      ]),
      520000,
    );
  });

  test('a saved entry reads back as its attendance', () {
    expect(Attendance.of(1000, null), Attendance.full);
    expect(Attendance.of(500, 0), Attendance.half);
    expect(Attendance.of(0, null), Attendance.absent);
    expect(Attendance.of(1000, 2000), Attendance.overtime);
  });

  test('balance: wages less money paid and deductions; a bonus leaves it', () {
    expect(
      balance(500000, {
        PaymentKind.advance: 100000,
        PaymentKind.part: 150000,
        PaymentKind.deduction: 20000,
        PaymentKind.bonus: 50000,
      }),
      230000,
    );
    expect(balance(0, {PaymentKind.advance: 100000}), -100000);
    expect(balance(230000, {PaymentKind.settlement: 230000}), 0);
  });
}
