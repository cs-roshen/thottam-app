import 'package:intl/intl.dart';

import '../core/calendar/malayalam_calendar.dart';
import '../l10n/app_localizations.dart';

/// "Monday, 16 November · Vrischikam 1", in the app's language.
String formatHomeDate(DateTime date, AppLocalizations l10n) {
  final m = malayalamDateOf(date);
  return l10n.homeDate(
    DateFormat(
      // gate: not user-facing
      'EEEE, d MMMM',
      l10n.localeName,
    ).format(date),
    l10n.malayalamDate(l10n.malayalamMonth(m.month), m.day),
  );
}

/// A day of work ('YYYY-MM-DD') as a short label: today, yesterday, or
/// "12 Nov" in the app's language, with Latin digits.
String formatDay(String day, AppLocalizations l10n, DateTime today) {
  final d = DateTime.parse(day);
  final t = DateTime(today.year, today.month, today.day);
  final diff = t.difference(DateTime(d.year, d.month, d.day)).inDays;
  if (diff == 0) return l10n.dayToday;
  if (diff == 1) return l10n.dayYesterday;
  return DateFormat(
    // gate: not user-facing
    d.year == today.year ? 'd MMM' : 'd MMM y',
    l10n.localeName,
  ).format(d);
}
