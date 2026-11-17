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
