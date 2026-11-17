import 'package:flutter_test/flutter_test.dart';
import 'package:thottam/core/calendar/malayalam_calendar.dart';

void main() {
  void expectDate(DateTime d, String month, int day) {
    final m = malayalamDateOf(d);
    expect((m.month, m.day), (month, day), reason: '$d');
  }

  test('month starts', () {
    expectDate(DateTime(2026, 11, 16), 'vrischikam', 1); // prototype example
    expectDate(DateTime(2026, 8, 17), 'chingam', 1);
    expectDate(DateTime(2026, 4, 14), 'medam', 1);
    expectDate(DateTime(2026, 1, 14), 'makaram', 1);
  });

  test('days count from the month start', () {
    expectDate(DateTime(2026, 11, 17), 'vrischikam', 2);
    expectDate(DateTime(2026, 8, 16), 'karkidakam', 31);
  });

  test('crosses the Gregorian year', () {
    expectDate(DateTime(2027, 1, 1), 'dhanu', 17);
    expectDate(DateTime(2027, 1, 13), 'dhanu', 29);
  });

  test('ignores the time of day', () {
    expectDate(DateTime(2026, 11, 16, 23, 59), 'vrischikam', 1);
  });
}
