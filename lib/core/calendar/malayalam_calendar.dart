/// A date in the Malayalam (Kollavarsham) calendar: month key and day.
typedef MalayalamDate = ({String month, int day});

// Gregorian month and day on which each Malayalam month usually begins.
// shortcut: fixed start dates, so a month can begin one day early or late in
// some years; compute the solar transit (sankranti) if exact dates are needed.
const _starts = <(String, int, int)>[
  ('makaram', 1, 14),
  ('kumbham', 2, 13),
  ('meenam', 3, 15),
  ('medam', 4, 14),
  ('edavam', 5, 15),
  ('mithunam', 6, 15),
  ('karkidakam', 7, 17),
  ('chingam', 8, 17),
  ('kanni', 9, 17),
  ('thulam', 10, 17),
  ('vrischikam', 11, 16),
  ('dhanu', 12, 16),
];

MalayalamDate malayalamDateOf(DateTime date) {
  // UTC days avoid daylight-saving and time-of-day effects on the count.
  final day = DateTime.utc(date.year, date.month, date.day);
  for (var year = date.year; year >= date.year - 1; year--) {
    for (final (month, m, d) in _starts.reversed) {
      final start = DateTime.utc(year, m, d);
      if (!start.isAfter(day)) {
        return (month: month, day: day.difference(start).inDays + 1);
      }
    }
  }
  // Dhanu of the previous year always matches, so this never runs.
  throw StateError('unreachable'); // gate: not user-facing
}
